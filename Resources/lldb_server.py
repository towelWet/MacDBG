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
            for i in range(frame.GetNumRegisters()):
                reg = frame.GetRegisterAtIndex(i)
                if reg.IsValid():
                    registers[reg.GetName()] = {
                        'value': reg.GetValue(),
                        'type': reg.GetType().GetName()
                    }
            
            return {"registers": registers}
        except Exception as e:
            log_error(f"Exception in getRegisters: {str(e)}", e)
            return self.buildError(f"getRegisters failed: {str(e)}")

    def disassembly(self, address, count):
        try:
            if self.target == None:
                return self.buildError("no target")
            
            # Get instructions at the address
            instructions = self.target.GetInstructions(lldb.SBAddress(address, self.target), count)
            lines = []
            
            for i in range(instructions.GetSize()):
                inst = instructions.GetInstructionAtIndex(i)
                if inst.IsValid():
                    addr = inst.GetAddress().GetLoadAddress(self.target)
                    mnemonic = inst.GetMnemonic(self.target)
                    operands = inst.GetOperands(self.target)
                    bytes = inst.GetBytes(self.target)
                    
                    # Convert bytes to hex string
                    hex_bytes = ' '.join([f'{b:02x}' for b in bytes])
                    
                    lines.append({
                        'address': addr,
                        'instruction': f"{mnemonic} {operands}".strip(),
                        'bytes': hex_bytes
                    })
            
            return {"lines": lines}
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
            
            # Step one instruction
            thread.StepInstruction(False)
            
            # Wait for the process to stop
            while process.GetState() == lldb.eStateRunning:
                time.sleep(0.01)
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepInstruction: {str(e)}", e)
            return self.buildError(f"stepInstruction failed: {str(e)}")

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
