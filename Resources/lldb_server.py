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
                            # Don't send generic stopped events - let the stepping methods handle their own events
                            # This prevents interference with proper stepping events that include PC information
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
        """Step one instruction (step over calls)"""
        return self._stepInstruction(False)
    
    def stepInto(self):
        """Step one instruction (step into calls)"""
        return self._stepInstruction(True)
    
    def _stepInstruction(self, step_into_calls=False):
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            # Check if process is already running
            state = process.GetState()
            if state == lldb.eStateRunning:
                log_lldb("Process is running, stopping first...")
                process.Stop()
                # Wait for it to stop
                timeout = 50
                while process.GetState() == lldb.eStateRunning and timeout > 0:
                    time.sleep(0.01)
                    timeout -= 1
            
            # Check if we're in a valid state for stepping
            if process.GetState() not in [lldb.eStateStopped, lldb.eStateSuspended]:
                log_error(f"Process not in stoppable state: {process.GetState()}")
                return self.buildError(f"process state invalid for stepping: {process.GetState()}")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            step_type = "into" if step_into_calls else "over"
            log_lldb(f"Stepping one instruction ({step_type})")
            
            # Get current PC before stepping
            frame = thread.GetFrameAtIndex(0)
            old_pc = frame.GetPC() if frame.IsValid() else 0
            log_lldb(f"Current PC before step: 0x{old_pc:x}")
            
            # Check if we're in system library code
            in_system_lib = False
            if frame.IsValid():
                module = frame.GetModule()
                if module.IsValid():
                    module_name = module.GetFileSpec().GetFilename()
                    if module_name and ("libsystem" in module_name or "dylib" in module_name):
                        in_system_lib = True
                        log_lldb(f"Stepping in system library: {module_name}")
            
            # Step one instruction
            try:
                thread.StepInstruction(step_into_calls)
            except Exception as step_e:
                log_error(f"StepInstruction failed: {str(step_e)}", step_e)
                # Try alternative stepping method
                try:
                    if step_into_calls:
                        thread.StepInto()
                    else:
                        thread.StepOver()
                    log_lldb("Used alternative stepping method")
                except Exception as alt_e:
                    log_error(f"Alternative stepping also failed: {str(alt_e)}", alt_e)
                    return self.buildError(f"stepping failed: {str(step_e)}")
            
            # Wait for the process to stop
            timeout = 100  # 1 second timeout
            while process.GetState() == lldb.eStateRunning and timeout > 0:
                time.sleep(0.01)
                timeout -= 1
            
            # Check final state
            final_state = process.GetState()
            log_lldb(f"Process state after step: {final_state}")
            
            if timeout <= 0:
                log_error(f"Step instruction ({step_type}) timeout, final state: {final_state}")
                # Don't return error immediately, try to get PC anyway
                log_lldb("Attempting to get PC despite timeout...")
            elif final_state not in [lldb.eStateStopped, lldb.eStateSuspended]:
                log_lldb(f"Process not stopped after step, state: {final_state}")
                # Continue anyway, might still be able to get PC
            
            # Get new PC after step - try multiple methods
            frame = thread.GetFrameAtIndex(0)
            pc = 0
            
            if frame.IsValid():
                pc = frame.GetPC()
                log_lldb(f"Step ({step_type}) completed, new PC: 0x{pc:x}")
            else:
                # Frame might be invalid, try getting PC directly from thread
                log_lldb("Frame invalid after step, trying to get PC from thread...")
                try:
                    # Try to get PC from registers using a different approach
                    if thread.GetNumFrames() > 0:
                        try:
                            frame_0 = thread.GetFrameAtIndex(0)
                            if frame_0:
                                registers = frame_0.GetRegisters()
                                if registers:
                                    for reg_set in registers:
                                        for reg in reg_set:
                                            reg_name = reg.GetName().lower()
                                            if reg_name in ['pc', 'rip', 'eip']:
                                                reg_value = reg.GetValue()
                                                if reg_value:
                                                    pc = int(reg_value, 16)
                                                    log_lldb(f"Got PC from register {reg_name}: 0x{pc:x}")
                                                    break
                                        if pc != 0:
                                            break
                        except Exception as reg_e:
                            log_lldb(f"Error accessing registers: {str(reg_e)}")
                    
                    # Alternative method: use LLDB command to get PC
                    if pc == 0:
                        try:
                            result = lldb.SBCommandReturnObject()
                            self.target.GetDebugger().GetCommandInterpreter().HandleCommand("register read pc", result)
                            if result.Succeeded():
                                output = result.GetOutput()
                                # Parse PC from output like "pc = 0x7ff8125dd93b"
                                import re
                                match = re.search(r'pc\s*=\s*0x([0-9a-fA-F]+)', output)
                                if match:
                                    pc = int(match.group(1), 16)
                                    log_lldb(f"Got PC from command: 0x{pc:x}")
                        except Exception as cmd_e:
                            log_lldb(f"Error using register command: {str(cmd_e)}")
                    
                    # If still no PC, try alternative method
                    if pc == 0:
                        # Get thread info
                        thread_info = thread.GetStopDescription(256)
                        log_lldb(f"Thread stop description: {thread_info}")
                        
                        # Try to refresh thread state
                        process.GetThreadAtIndex(0).GetFrameAtIndex(0)
                        new_frame = thread.GetFrameAtIndex(0)
                        if new_frame.IsValid():
                            pc = new_frame.GetPC()
                            log_lldb(f"Got PC after refresh: 0x{pc:x}")
                        else:
                            # Last resort - use old PC and log warning
                            pc = old_pc
                            log_lldb(f"Warning: Could not get new PC, using old PC: 0x{pc:x}")
                            
                except Exception as e:
                    log_error(f"Error getting PC after step: {str(e)}", e)
                    pc = old_pc
                    log_lldb(f"Using old PC due to error: 0x{pc:x}")
            
            # Check if PC actually changed
            if pc == old_pc:
                log_lldb(f"Warning: PC did not change after step (0x{pc:x})")
                
                # If we're stuck on the same instruction, try a different approach
                if in_system_lib:
                    log_lldb("Attempting to step out of system library...")
                    try:
                        # First try step out
                        thread.StepOut()
                        
                        # Wait a bit for step out to complete
                        step_out_timeout = 50
                        while process.GetState() == lldb.eStateRunning and step_out_timeout > 0:
                            time.sleep(0.01)
                            step_out_timeout -= 1
                        
                        # Try to get new PC after step out
                        new_frame = thread.GetFrameAtIndex(0)
                        if new_frame.IsValid():
                            new_pc = new_frame.GetPC()
                            if new_pc != pc:
                                pc = new_pc
                                log_lldb(f"Step out successful, new PC: 0x{pc:x}")
                            else:
                                log_lldb("Step out didn't change PC, trying continue...")
                                # If step out didn't work, try continue briefly
                                process.Continue()
                                time.sleep(0.01)  # Very brief continue
                                process.Stop()
                                
                                # Wait for stop
                                stop_timeout = 30
                                while process.GetState() == lldb.eStateRunning and stop_timeout > 0:
                                    time.sleep(0.01)
                                    stop_timeout -= 1
                                
                                # Get PC after continue/stop
                                final_frame = thread.GetFrameAtIndex(0)
                                if final_frame.IsValid():
                                    pc = final_frame.GetPC()
                                    log_lldb(f"Continue/stop resulted in PC: 0x{pc:x}")
                        else:
                            log_lldb("Step out completed but frame still invalid")
                            
                    except Exception as step_out_e:
                        log_lldb(f"Step out failed: {str(step_out_e)}")
                else:
                    # Not in system library but PC didn't change - might be a different issue
                    log_lldb("PC didn't change in user code - this might indicate a problem")
            
            # Always send event, even if PC didn't change or we had issues
            log_lldb(f"Step ({step_type}) completed, PC: 0x{pc:x} (was: 0x{old_pc:x})")
            
            # Send stopped event with specific reason
            reason = "step_into" if step_into_calls else "step_over"
            self.sendEvent({
                "type": "stopped", 
                "payload": {
                    "reason": reason,
                    "pc": pc,
                    "thread_id": thread.GetThreadID()
                }
            })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in _stepInstruction: {str(e)}", e)
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
                        "reason": "step_over",
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
                        "reason": "step_out",
                        "pc": pc,
                        "thread_id": thread.GetThreadID()
                    }
                })
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepOut: {str(e)}", e)
            return self.buildError(f"stepOut failed: {str(e)}")
    
    def stepUntilUserCode(self):
        """Step until we're out of system library code"""
        try:
            if self.target == None or self.target.GetProcess() == None:
                return self.buildError("no process")
            
            process = self.target.GetProcess()
            if not process.IsValid():
                return self.buildError("process not valid")
            
            thread = process.GetThreadAtIndex(0)
            if not thread.IsValid():
                return self.buildError("no valid thread")
            
            log_lldb("Stepping until user code...")
            
            max_attempts = 20  # Prevent infinite loops
            attempts = 0
            
            while attempts < max_attempts:
                frame = thread.GetFrameAtIndex(0)
                if not frame.IsValid():
                    break
                
                # Check if we're in system library
                module = frame.GetModule()
                in_system_lib = False
                if module.IsValid():
                    module_name = module.GetFileSpec().GetFilename()
                    if module_name and ("libsystem" in module_name or "dylib" in module_name):
                        in_system_lib = True
                
                if not in_system_lib:
                    log_lldb("Reached user code!")
                    break
                
                log_lldb(f"Still in system code (attempt {attempts + 1}), stepping out...")
                
                # Try step out
                thread.StepOut()
                
                # Wait for completion
                timeout = 100
                while process.GetState() == lldb.eStateRunning and timeout > 0:
                    time.sleep(0.01)
                    timeout -= 1
                
                if timeout <= 0:
                    log_lldb("Timeout during step out, trying continue...")
                    # Try continue briefly as fallback
                    process.Continue()
                    time.sleep(0.05)
                    process.Stop()
                    
                    # Wait for stop
                    stop_timeout = 50
                    while process.GetState() == lldb.eStateRunning and stop_timeout > 0:
                        time.sleep(0.01)
                        stop_timeout -= 1
                
                attempts += 1
            
            # Get final PC
            frame = thread.GetFrameAtIndex(0)
            if frame.IsValid():
                pc = frame.GetPC()
                log_lldb(f"Step until user code completed, PC: 0x{pc:x}")
                
                self.sendEvent({
                    "type": "stopped", 
                    "payload": {
                        "reason": "step_until_user_code",
                        "pc": pc,
                        "thread_id": thread.GetThreadID()
                    }
                })
            else:
                log_error("Invalid frame after step until user code")
                return self.buildError("invalid frame after step until user code")
            
            return self.buildOK()
        except Exception as e:
            log_error(f"Exception in stepUntilUserCode: {str(e)}", e)
            return self.buildError(f"stepUntilUserCode failed: {str(e)}")
    
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
            
            elif command == "stepInto":
                result = self.stepInto()
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
            
            elif command == "stepUntilUserCode":
                result = self.stepUntilUserCode()
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
