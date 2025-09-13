import lldb
import json
import sys
import os
import time
import threading
import signal
import struct

# Add the current directory to the Python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from debug_logger import init_logger, log, log_error, log_crash, log_communication, log_python_server, log_lldb

class EventThread(threading.Thread):
    def __init__(self, handler):
        super().__init__(daemon=True)
        self.handler = handler
        self.running = True

    def run(self):
        log_python_server("EventThread started")
        while self.running:
            try:
                if self.handler.target and self.handler.target.GetProcess():
                    process = self.handler.target.GetProcess()
                    if process.IsValid():
                        # Check for events
                        event = lldb.SBEvent()
                        if self.handler.debugger.GetListener().GetNextEvent(event):
                            log_python_server(f"Event received: {event.GetType()}")
                            if event.GetType() & lldb.SBProcess.eStateStopped:
                                log_python_server("Process stopped")
                                # Send stopped event to Swift
                                self.handler.sendEvent({"type": "stopped", "reason": "step"})
                time.sleep(0.1)
            except Exception as e:
                log_error(f"Error in EventThread: {str(e)}", e)
                break
        log_python_server("EventThread stopped")

class Handler:
    def __init__(self, input_fd, output_fd, cmd_mode):
        self.input_fd = input_fd
        self.output_fd = output_fd
        self.cmd_mode = cmd_mode
        self.debugger = lldb.SBDebugger.Create()
        self.target = None
        self.process = None
        self.eventThread = None
        self.logger = init_logger()
        self.is64Bits = True
        self.executable = None

    def buildOK(self):
        return {"status": "ok"}

    def buildError(self, message):
        return {"status": "error", "message": message}

    def sendEvent(self, event):
        try:
            data = json.dumps(event).encode('utf-8')
            length = struct.pack('<I', len(data))
            os.write(self.output_fd, length + data)
            log_communication("SENT", event)
        except Exception as e:
            log_error(f"Failed to send event: {str(e)}", e)

    def transportRead(self):
        try:
            log_python_server("Waiting for data from Swift...")
            # Read 4-byte length header
            length_data = os.read(self.input_fd, 4)
            log_python_server(f"Read length data: {length_data.hex()}")
            if len(length_data) != 4:
                log_python_server(f"Invalid length data length: {len(length_data)}")
                return None
            length = struct.unpack('<I', length_data)[0]
            log_python_server(f"Message length: {length}")
            
            # Read the actual data
            data = os.read(self.input_fd, length)
            log_python_server(f"Read data length: {len(data)}")
            if len(data) != length:
                log_python_server(f"Data length mismatch: expected {length}, got {len(data)}")
                return None
                
            message = data.decode('utf-8')
            log_communication("RECEIVED", message)
            return json.loads(message)
        except Exception as e:
            log_error(f"Error reading transport: {str(e)}", e)
            return None

    def transportWrite(self, s):
        try:
            data = s.encode('utf-8')
            length = struct.pack('<I', len(data))
            os.write(self.output_fd, length + data)
        except Exception as e:
            log_error(f"Error writing transport: {str(e)}", e)

    def attachToProcess(self, pid, executable, is64Bits):
        log_python_server(f"attachToProcess called: pid={pid}, executable={executable}, is64Bits={is64Bits}")
        
        try:
            if self.target == None:
                err = lldb.SBError()
                self.is64Bits = is64Bits
                self.executable = executable
                log_python_server(f"Creating target for executable: {executable}")
                self.target = self.debugger.CreateTargetWithFileAndArch(self.executable, lldb.LLDB_ARCH_DEFAULT_64BIT if self.is64Bits else lldb.LLDB_ARCH_DEFAULT_32BIT)
            
            if self.target == None or not self.target.IsValid():
                self.target = self.debugger.CreateTarget("")
            
            if self.target == None or not self.target.IsValid():
                return self.buildError("cannot build target")
            
            log_python_server(f"Attaching to process {pid}")
            process = self.target.AttachToProcessWithID(self.debugger.GetListener(), pid, err)
            
            if process != None:
                log_python_server(f"Attach successful, process state: {process.GetState()}")
                # Initialize event thread if not already done
                if self.eventThread is None:
                    log_python_server("Starting event thread")
                    self.eventThread = EventThread(self)
                self.eventThread.start()
                
                while process.GetState() == lldb.eStateAttaching:
                    time.sleep(0.1)
                
                log_python_server(f"Process state after attach: {process.GetState()}")
                result = self.buildOK()
                
                if self.target.GetNumModules() > 0:
                    executableFileSpec = self.target.GetExecutable()
                    module = self.target.FindModule(executableFileSpec)
                    if module != None and module.GetNumSections() > 1:
                        section = module.GetSectionAtIndex(1)
                        fileAddr = section.GetFileAddress()
                        loadAddr = section.GetLoadAddress(self.target)
                        aslrSlide = loadAddr - fileAddr
                        result['sectionName'] = section.GetName()
                        result['fileAddr'] = fileAddr
                        result['loadAddr'] = loadAddr
                        result['aslrSlide'] = aslrSlide
                
                log_python_server("attachToProcess completed successfully")
                return result
            else:
                log_error("Failed to attach to process - process is None")
                self.target = None
                return self.buildError("cannot attach to process")
        except Exception as e:
            log_error(f"Exception in attachToProcess: {str(e)}", e)
            log_crash(f"attachToProcess crashed: {str(e)}")
            return self.buildError(f"attachToProcess failed: {str(e)}")

    def getRegisters(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            frame = thread.GetFrameAtIndex(0)
            if not frame.IsValid():
                return self.buildError("no valid frame")
            
            registers = {}
            
            # Get register context from frame
            reg_context = frame.GetRegisters()
            
            # Iterate through register sets (general purpose, floating point, etc.)
            for reg_set_idx in range(reg_context.GetSize()):
                reg_set = reg_context.GetValueAtIndex(reg_set_idx)
                if reg_set.IsValid():
                    # Iterate through registers in this set
                    for reg_idx in range(reg_set.GetNumChildren()):
                        reg = reg_set.GetChildAtIndex(reg_idx)
                        if reg.IsValid():
                            reg_name = reg.GetName()
                            reg_value = reg.GetValue()
                            if reg_name and reg_value:
                                registers[reg_name] = reg_value
            
            log_lldb(f"Retrieved {len(registers)} registers")
            # Send as proper message format expected by Swift
            return {"type": "registers", "payload": {"registers": registers}}
        except Exception as e:
            log_error(f"Exception in getRegisters: {str(e)}", e)
            return self.buildError(f"getRegisters failed: {str(e)}")

    def disassembly(self, address, count):
        try:
            if self.target == None:
                return self.buildError("no target")
            
            # Handle address parameter - could be string or int
            if isinstance(address, str):
                if address.startswith("0x"):
                    address = int(address, 16)
                else:
                    address = int(address)
            
            log_lldb(f"Disassembling {count} instructions from 0x{address:x}")
            
            # Create address object
            sb_address = lldb.SBAddress(address, self.target)
            if not sb_address.IsValid():
                return self.buildError(f"invalid address: 0x{address:x}")
            
            # Use LLDB command interpreter for disassembly - more reliable
            process = self.target.GetProcess()
            if not process or not process.IsValid():
                return self.buildError("no valid process")
            
            # Use LLDB command interpreter to get disassembly
            command_interpreter = self.debugger.GetCommandInterpreter()
            command_result = lldb.SBCommandReturnObject()
            
            # Create disassembly command
            disasm_cmd = f"disassemble --count {count} --start-address 0x{address:x}"
            log_lldb(f"Executing LLDB command: {disasm_cmd}")
            
            # Execute the command
            command_interpreter.HandleCommand(disasm_cmd, command_result)
            
            if not command_result.Succeeded():
                return self.buildError(f"disassembly command failed: {command_result.GetError()}")
            
            # Parse the output
            output = command_result.GetOutput()
            if not output:
                return self.buildError("no disassembly output received")
            
            log_lldb(f"Disassembly output: {output[:200]}...")
            
            # Parse the disassembly output
            lines = []
            output_lines = output.strip().split('\n')
            
            for line in output_lines:
                line = line.strip()
                if not line or line.startswith('(') or line.startswith('Process') or line.endswith(':'):
                    continue
                
                # Handle LLDB format: "->  0x7ff8125dd93a <+10>: retq" or "    0x7ff8125dd93b <+11>: nop"
                # Remove arrow indicator and extra spaces
                line = line.replace('->', '').strip()
                
                # Parse line format: "0x7ff8125dd93a <+10>: retq" or "0x12345678: 48 89 e5    movq   %rsp, %rbp"
                parts = line.split(':', 1)
                if len(parts) != 2:
                    continue
                
                addr_part = parts[0].strip()
                
                # Extract address from formats like "0x7ff8125dd93a <+10>" or "0x7ff8125dd93a"
                if '<' in addr_part:
                    addr_part = addr_part.split('<')[0].strip()
                
                if not addr_part.startswith('0x'):
                    continue
                
                try:
                    addr = int(addr_part, 16)
                except ValueError:
                    continue
                
                # Parse instruction part
                inst_part = parts[1].strip()
                
                # Split instruction part - could be "retq" or "48 89 e5    movq   %rsp, %rbp"
                inst_parts = inst_part.split()
                
                if len(inst_parts) >= 1:
                    # Check if first part looks like hex bytes (contains only hex digits)
                    first_part = inst_parts[0]
                    if len(first_part) == 2 and all(c in '0123456789abcdefABCDEF' for c in first_part):
                        # Format with bytes: "48 89 e5    movq   %rsp, %rbp"
                        hex_bytes = ' '.join(inst_parts[0:3])  # Take first few parts as bytes
                        if len(inst_parts) > 3:
                            instruction = inst_parts[3]
                            operands = ' '.join(inst_parts[4:]) if len(inst_parts) > 4 else ""
                        else:
                            instruction = "???"
                            operands = ""
                    else:
                        # Format without bytes: "retq" or "movq %rsp, %rbp"
                        hex_bytes = ""
                        instruction = inst_parts[0]
                        operands = ' '.join(inst_parts[1:]) if len(inst_parts) > 1 else ""
                    
                    lines.append({
                        'address': addr,
                        'instruction': instruction,
                        'operands': operands,
                        'bytes': hex_bytes
                    })
            
            if not lines:
                return self.buildError("no valid disassembly lines found")
            
            log_lldb(f"Successfully disassembled {len(lines)} instructions")
            # Send as proper message format expected by Swift
            return {"type": "disassembly", "payload": {"lines": lines}}
        except Exception as e:
            log_error(f"Exception in disassembly: {str(e)}", e)
            return self.buildError(f"disassembly failed: {str(e)}")

    def stepInstruction(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            log_lldb("Stepping one instruction")
            
            # Step one instruction
            thread.StepInstruction(False)  # False = step over function calls
            
            # Wait for the process to stop
            timeout = 100  # 1 second timeout
            while process.GetState() == lldb.eStateRunning and timeout > 0:
                time.sleep(0.01)
                timeout -= 1
            
            if timeout <= 0:
                log_error("Step instruction timeout")
                return self.buildError("step timeout")
            
            # Get new PC after step
            frame = thread.GetFrameAtIndex(0)
            if frame.IsValid():
                pc = frame.GetPC()
                log_lldb(f"Step completed, new PC: 0x{pc:x}")
                
                # Send stopped event with new PC
                self.sendEvent({
                    "type": "stopped", 
                    "payload": {
                        "reason": "step",
                        "pc": pc,
                        "thread_id": thread.GetThreadID()
                    }
                })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepInstruction: {str(e)}", e)
            return self.buildError(f"stepInstruction failed: {str(e)}")
    
    def stepOver(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            log_lldb("Stepping over")
            
            # Step over (next line)
            thread.StepOver()
            
            # Wait for the process to stop
            timeout = 100
            while process.GetState() == lldb.eStateRunning and timeout > 0:
                time.sleep(0.01)
                timeout -= 1
            
            if timeout <= 0:
                return self.buildError("step over timeout")
            
            # Get new PC after step
            frame = thread.GetFrameAtIndex(0)
            if frame.IsValid():
                pc = frame.GetPC()
                log_lldb(f"Step over completed, new PC: 0x{pc:x}")
                
                self.sendEvent({
                    "type": "stopped", 
                    "payload": {
                        "reason": "step",
                        "pc": pc,
                        "thread_id": thread.GetThreadID()
                    }
                })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepOver: {str(e)}", e)
            return self.buildError(f"stepOver failed: {str(e)}")
    
    def stepOut(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            log_lldb("Stepping out")
            
            # Step out of current function
            thread.StepOut()
            
            # Wait for the process to stop
            timeout = 200  # Longer timeout for step out
            while process.GetState() == lldb.eStateRunning and timeout > 0:
                time.sleep(0.01)
                timeout -= 1
            
            if timeout <= 0:
                return self.buildError("step out timeout")
            
            # Get new PC after step
            frame = thread.GetFrameAtIndex(0)
            if frame.IsValid():
                pc = frame.GetPC()
                log_lldb(f"Step out completed, new PC: 0x{pc:x}")
                
                self.sendEvent({
                    "type": "stopped", 
                    "payload": {
                        "reason": "step",
                        "pc": pc,
                        "thread_id": thread.GetThreadID()
                    }
                })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepOut: {str(e)}", e)
            return self.buildError(f"stepOut failed: {str(e)}")
    
    def continueExecution(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            log_lldb("Continuing execution")
            
            # Continue execution
            process.Continue()
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in continueExecution: {str(e)}", e)
            return self.buildError(f"continueExecution failed: {str(e)}")
    
    def stopExecution(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            log_lldb("Stopping execution")
            
            # Stop/halt the process
            process.Stop()
            
            # Wait for it to actually stop
            timeout = 100
            while process.GetState() == lldb.eStateRunning and timeout > 0:
                time.sleep(0.01)
                timeout -= 1
            
            if process.GetState() == lldb.eStateStopped:
                # Get current PC
                thread = process.GetThreadAtIndex(0)
                if thread.IsValid():
                    frame = thread.GetFrameAtIndex(0)
                    if frame.IsValid():
                        pc = frame.GetPC()
                        log_lldb(f"Process stopped at PC: 0x{pc:x}")
                        
                        self.sendEvent({
                            "type": "stopped", 
                            "payload": {
                                "reason": "interrupted",
                                "pc": pc,
                                "thread_id": thread.GetThreadID()
                            }
                        })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stopExecution: {str(e)}", e)
            return self.buildError(f"stopExecution failed: {str(e)}")
    
    def detach(self):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            log_lldb("Detaching from process")
            
            # Detach from the process
            process.Detach()
            
            # Clean up
            self.target = None
            self.process = None
            
            # Stop event thread
            if self.eventThread:
                self.eventThread.running = False
                self.eventThread = None
            
            log_lldb("Successfully detached from process")
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in detach: {str(e)}", e)
            return self.buildError(f"detach failed: {str(e)}")

    def handleRequest(self, req):
        try:
            command = req.get("command")
            log_python_server(f"Handling request: {command}")
            
            if command == "attachToProcess":
                pid = req.get("pid")
                executable = req.get("executable")
                is64Bits = req.get("is64Bits", True)
                result = self.attachToProcess(pid, executable, is64Bits)
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "getRegisters":
                result = self.getRegisters()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "disassembly":
                address = req.get("address", 0)
                count = req.get("count", 10)
                result = self.disassembly(address, count)
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "stepInstruction":
                result = self.stepInstruction()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "stepOver":
                result = self.stepOver()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "stepOut":
                result = self.stepOut()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "continueExecution":
                result = self.continueExecution()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "stopExecution":
                result = self.stopExecution()
                log_python_server(f"Sending response: {result}")
                return result
            
            elif command == "detach":
                result = self.detach()
                log_python_server(f"Sending response: {result}")
                return result
            
            else:
                return self.buildError(f"Unknown command: {command}")
                
        except Exception as e:
            log_error(f"Exception in handleRequest: {str(e)}", e)
            return self.buildError(f"handleRequest failed: {str(e)}")

    def run(self):
        log_python_server("Python server started")
        
        while True:
            try:
                req = self.transportRead()
                if req is None:
                    break
                
                response = self.handleRequest(req)
                self.transportWrite(json.dumps(response))
                
            except KeyboardInterrupt:
                log_python_server("Received interrupt, shutting down")
                break
            except Exception as e:
                log_error(f"Error in main loop: {str(e)}", e)
                break
        
        log_python_server("Python server stopped")

if __name__ == "__main__":
    # Initialize logging
    logger = init_logger()
    log_python_server("Starting MacDBG Python server")
    
    # Get file descriptors from command line
    input_fd = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    output_fd = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    
    log_python_server(f"Using input_fd={input_fd}, output_fd={output_fd}")
    
    # Create and run handler
    handler = Handler(input_fd, output_fd, False)
    handler.run()
