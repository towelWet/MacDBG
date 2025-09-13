#!/usr/bin/python
import os
import sys
import json
import lldb
import time
import shlex
import struct
import threading

###############################################################################

__DO_LOG__=False

def DBG_LOG(msg):
    if __DO_LOG__:
        with open(os.path.expanduser("~/Desktop/Hopper_lldb_output.txt"), "a") as _LOG_FILE:
            _LOG_FILE.write(msg)

###############################################################################

def get_registers(frame, kind):
    registerSet = frame.GetRegisters()
    for value in registerSet:
        if kind.lower() in value.GetName().lower():
            return value
    return None

def build_reg_value_string(reg):
    value = ""
    if reg.MightHaveChildren():
        c_count = reg.GetNumChildren()
        offset = 0
        i_value = 0
        for child in reg:
            err = lldb.SBError()
            i_value += child.GetValueAsUnsigned(err) << offset
            offset += child.GetByteSize() << 3
        fmt = "0x%%0%dx" % (reg.GetByteSize() << 1)
        value = fmt % i_value
    else:
        value = reg.GetValue()
    return value

def get_GPRs(frame):
    return get_registers(frame, "general purpose")

def get_FPRs(frame):
    return get_registers(frame, "floating point")

def get_ESRs(frame):
    return get_registers(frame, "exception state")

def findRegister(frame,name):
    registerSet = frame.GetRegisters()
    for regSet in registerSet:
        for value in regSet:
            if value.GetName() == name:
                return value
    return None

def stateToString(state):
    state_strings = ["eStateInvalid", "eStateUnloaded", "eStateConnected", "eStateAttaching", "eStateLaunching", "eStateStopped", "eStateRunning", "eStateStepping", "eStateCrashed", "eStateDetached", "eStateExited", "eStateSuspended"]
    if state >= 0 and state < len(state_strings):
        return state_strings[state]
    else:
        return "invalid state (%d)" % state

###############################################################################

class Handler(threading.Thread):
    def __init__(self,input_fd,output_fd,cmd_mode):
        threading.Thread.__init__(self)
        self.input_fd = input_fd
        self.output_fd = output_fd
        self.cmd_mode = cmd_mode
        self.target = None
        self.workingDirectory = None
        self.arguments = None
        self.executable = None
        self.is64Bits = True
        self.debugger = lldb.SBDebugger.Create()
        self.debugger.SetAsync(True)
        self.transport_lock = threading.Lock()
        
        class EventThread(threading.Thread):
            def __init__(self,handler):
                threading.Thread.__init__(self)
                self.handler = handler

            def getModulesFromEvents(self,lldb,event,target):
                lldb_modules = []
                if hasattr(lldb.SBTarget, "GetNumModulesFromEvent"):
                    cnt = lldb.SBTarget.GetNumModulesFromEvent(event)
                    for i in xrange(cnt):
                        module = lldb.SBTarget.GetModuleAtIndexFromEvent(i, event)
                        lldb_modules.append(module)
                else:
                    lldb_modules = target.modules
                hopper_modules = []
                for module in lldb_modules:
                    fileSpec = module.GetFileSpec()
                    section = module.GetSectionAtIndex(1)
                    fileAddr = section.GetFileAddress()
                    loadAddr = section.GetLoadAddress(target)
                    if loadAddr >= fileAddr:
                        slide = loadAddr - fileAddr
                        hopper_modules.append({
                            "directory": fileSpec.GetDirectory(),
                            "file": fileSpec.GetFilename(),
                            "loadAddress": loadAddr,
                            "fileAddress": fileAddr,
                            "slide": slide
                        })
                return hopper_modules

            def run(self):
                target = self.handler.target
                process = target.GetProcess()

                listener = lldb.SBListener("Hopper listener")

                processBroadcaster = process.GetBroadcaster()
                processBroadcaster.AddListener(listener, lldb.SBProcess.eBroadcastBitStateChanged | lldb.SBProcess.eBroadcastBitSTDOUT | lldb.SBProcess.eBroadcastBitSTDERR)

                targetBroadcaster = target.GetBroadcaster()
                targetBroadcaster.AddListener(listener, lldb.SBTarget.eBroadcastBitModulesLoaded | lldb.SBTarget.eBroadcastBitModulesUnloaded)

                self.stopRequest = False
                event = lldb.SBEvent()

                while not self.stopRequest:
                    if listener.WaitForEvent(1, event):
                        eBroadcaster = event.GetBroadcaster()
                        eType = event.GetType()
                        DBG_LOG("[EVENT] type %d (%s)\n" % (eType, str(event)))

                        if eBroadcaster == processBroadcaster:
                            if eType == lldb.SBProcess.eBroadcastBitStateChanged:
                                state = lldb.SBProcess.GetStateFromEvent(event)
                                resp = {"status":"event", "type":"state", "inferior_state":state, "state_desc": stateToString(state)}
                                if state == 10:
                                    resp["exit_status"] = process.GetExitStatus()
                                self.handler.sendJSON(resp)
                            elif eType == lldb.SBProcess.eBroadcastBitSTDOUT:
                                data=process.GetSTDOUT(256)
                                if data is not None and len(data) > 0:
                                    self.handler.sendJSON({"status":"event", "type":"stdout", "output": "".join(["%02x" % ord(c) for c in data])})
                            elif eType == lldb.SBProcess.eBroadcastBitSTDERR:
                                data=process.GetSTDERR(256)
                                if data is not None and len(data) > 0:
                                    self.handler.sendJSON({"status":"event", "type":"stderr", "output": "".join(["%02x" % ord(c) for c in data])})

                        elif eBroadcaster == targetBroadcaster:
                            if eType == lldb.SBTarget.eBroadcastBitModulesLoaded:
                                modules = self.getModulesFromEvents(lldb,event,target)
                                self.handler.sendJSON({"status":"event", "type":"moduleLoaded", "modules":modules})
                            elif eType == lldb.SBTarget.eBroadcastBitModulesUnloaded:
                                modules = []
                                self.handler.sendJSON({"status":"event", "type":"moduleUnloaded", "modules":modules})
                return
        
        self.eventThread = EventThread(self)

    def restartEventThread(self):
        self.eventThread.stopRequest = True
        self.eventThread.join()
        self.eventThread = EventThread(self)
        self.eventThread.start()

    def transportRead(self):
        try:
            if cmd_mode:
                s = self.input_fd.readline()
                if s == "":
                    return None
                print("--------\nINPUT:  %s" % s[:-1])
                return s
            else:
                length_str = self.input_fd.read(4)
                if len(length_str) < 4:
                    return None
                length = struct.unpack('i', length_str)[0]

                line = ""
                while len(line) != length:
                    rem = length - len(line)
                    part = self.input_fd.read(rem)
                    if part == None or len(part) == 0:
                        return None
                    line += part

                if len(line) < length:
                    return None

                DBG_LOG("[READ] " + line + "\n")
                return line
        except BaseException as e:
            raise
            return None

    def transportWrite(self,s):
        DBG_LOG("[WRITE] " + s + "\n")
        length = struct.pack('i', len(s))
        self.transport_lock.acquire()
        if self.cmd_mode:
            self.output_fd.write("OUTPUT: ")
        else:
            self.output_fd.write(length)
        self.output_fd.write(s)
        if self.cmd_mode:
            self.output_fd.write("\n")
        self.output_fd.flush()
        self.transport_lock.release()

    def buildError(self,msg):
        return {'status':'error', 'message':msg}

    def buildOK(self,msg=None):
        if msg == None:
            return {'status':'ok'}
        else:
            return {'status':'ok', 'message':msg}

    def sendJSON(self,j):
        s = json.dumps(j)
        self.transportWrite(s)

    def sendError(self,msg):
        self.sendJSON(self.buildError(msg))

    def sendOK(self,msg=None):
        self.sendJSON(self.buildOK(msg))

    def prepareExecutable(self,execPath,is64Bits,cwd,args):
        self.executable = execPath
        self.is64Bits = is64Bits
        self.workingDirectory = cwd
        self.arguments = shlex.split(args.encode("utf-8"))
        return self.buildOK()

    def createProcess(self):
        if self.target == None:
            err = lldb.SBError()
            self.target = self.debugger.CreateTargetWithFileAndArch(self.executable.encode("utf-8"), lldb.LLDB_ARCH_DEFAULT_64BIT if self.is64Bits else lldb.LLDB_ARCH_DEFAULT_32BIT)
            if self.target == None or not self.target.IsValid():
                return self.buildError("cannot build target")
            launchInfo = lldb.SBLaunchInfo(self.arguments if self.arguments != None else [])
            launchInfo.SetEnvironmentEntries(["" + k + "=" + os.environ[k] for k in os.environ], False)
            launchInfo.SetWorkingDirectory(self.workingDirectory.encode("utf-8") if self.workingDirectory != None else "")
            launchInfo.SetLaunchFlags(lldb.eLaunchFlagDisableASLR + lldb.eLaunchFlagStopAtEntry)
            process = self.target.Launch(launchInfo, err)
            if process != None:
                self.eventThread.start()
                while process.GetState() == lldb.eStateAttaching:
                    time.sleep(0.1)
                return self.buildOK()
            else:
                self.target = None
                return self.buildError("cannot create process")
        return self.buildError("process already exists")

    def attachToProcess(self,pid,executable,is64Bits):
        if self.target == None:
            err = lldb.SBError()
            self.is64Bits = is64Bits
            self.executable = executable
            self.target = self.debugger.CreateTargetWithFileAndArch(self.executable.encode("utf-8"), lldb.LLDB_ARCH_DEFAULT_64BIT if self.is64Bits else lldb.LLDB_ARCH_DEFAULT_32BIT)
            if self.target == None or not self.target.IsValid():
                self.target = self.debugger.CreateTarget("")
            if self.target == None or not self.target.IsValid():
                return self.buildError("cannot build target")
            process = self.target.AttachToProcessWithID(self.debugger.GetListener(),pid,err)
            if process != None:
                self.eventThread.start()
                while process.GetState() == lldb.eStateAttaching:
                    time.sleep(0.1)
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
                return result
            else:
                self.target = None
                return self.buildError("cannot attach to process")
        return self.buildError("process already exists")

    def moduleCount(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        result = self.buildOK()
        result['count'] = self.target.GetNumModules()
        return result

    def moduleDesc(self,module):
        desc = {}
        desc['uuid'] = module.GetUUIDString()
        fileSpec = module.GetFileSpec()
        if fileSpec != None:
            filename = fileSpec.GetFilename()
            desc['filename'] = filename
        sections = []
        gotBase = False
        for section in module.section_iter():
            loadAddr = section.GetLoadAddress(self.target)
            if loadAddr != lldb.LLDB_INVALID_ADDRESS:
                gotBase = True
            section_desc = {}
            section_desc['name'] = section.GetName()
            section_desc['fileAddr'] = section.GetFileAddress()
            section_desc['loadAddr'] = loadAddr
            section_desc['byteSize'] = section.GetByteSize()
            section_desc['fileByteSize'] = section.GetFileByteSize()
            sections.append(section_desc)
        desc['sections'] = sections
        return desc

    def moduleAtIndex(self,index):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        if index < 0 or index >= self.moduleCount():
            return self.buildError("index out of range")
        module = self.target.GetModuleAtIndex(index)
        if module == None:
            return self.buildError("cannot get module")
        result = self.buildOK()
        result['module'] = self.moduleDesc(module)
        return result

    def moduleForFile(self,filename):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        file_spec = lldb.SBFileSpec(filename.encode("utf-8"), True)
        module = self.target.FindModule(file_spec)
        if module == None:
            return self.buildError("can't find module")
        if not module.IsValid():
            return self.buildError("invalid module")
        result = self.buildOK()
        result['module'] = self.moduleDesc(module)
        return result

    def connectRemote(self,is64Bits,url,plugin,platform,filename):
        if self.target != None and self.target.GetProcess() != None:
            return self.buildError("already has a process")
        err = lldb.SBError()
        self.is64Bits = is64Bits
        self.executable = filename
        if plugin == "kdp-remote":
            ci = self.debugger.GetCommandInterpreter()

            cmd_result = lldb.SBCommandReturnObject()
            cmd = "target create \"%s\"" % (filename)
            DBG_LOG(cmd + "\n")
            ci.HandleCommand(cmd.encode("utf-8"), cmd_result)

            cmd_result = lldb.SBCommandReturnObject()
            cmd = "process connect --plugin %s \"%s\"" % (plugin, url)
            DBG_LOG(cmd + "\n")
            ci.HandleCommand(cmd.encode("utf-8"), cmd_result)

            self.target = self.debugger.GetSelectedTarget()
            process = self.target.GetProcess()
            # self.target = self.debugger.CreateTarget('')
            # process = self.target.ConnectRemote(self.debugger.GetListener(), url.encode("utf-8"), plugin.encode("utf-8"), err)
        else:
            self.target = self.debugger.CreateTargetWithFileAndArch(filename.encode("utf-8"), lldb.LLDB_ARCH_DEFAULT_64BIT if self.is64Bits else lldb.LLDB_ARCH_DEFAULT_32BIT)
            process = self.target.ConnectRemote(self.debugger.GetListener(), url.encode("utf-8"), plugin.encode("utf-8"), err)

        for i in xrange(10):
            DBG_LOG("step %d: %s\n" % (i, stateToString(process.GetState())))
            time.sleep(0.1)
        if process == None or not process.IsValid():
            return self.buildError("cannot connect to remote, invalid process")
        else:
            self.eventThread.start()
            return self.buildOK()

    def detach(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        self.target.GetProcess().Detach()
        return self.buildOK()

    def deleteProcess(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        if self.eventThread != None:
            self.eventThread.stopRequest = True
            self.eventThread.join()
            self.eventThread = None
        self.target.GetProcess().Destroy()
        self.target = None
        return self.buildOK()

    def hasProcess(self):
        if self.target != None and self.target.GetProcess() != None:
            return self.buildOK()
        else:
            return self.buildError("no process")

    def getProcessState(self):
        if self.target != None:
            process = self.target.GetProcess()
            if process != None:
                state = process.GetState()
                result = self.buildOK()
                result["state"] = state
                result["state-string"] = stateToString(state)
            else:
                result = self.buildError("no process")
        else:
            result = self.buildError("no process")
        return result

    def continueExecution(self):
        if self.target != None:
            process = self.target.GetProcess()
            if process != None:
                process.Continue()
                return self.buildOK()
        return self.buildError("no process")

    def stopReasonToString(self,reason):
        if reason == 0: return 'Invalid'
        if reason == 1: return 'None'
        if reason == 2: return 'Trace'
        if reason == 3: return 'Breakpoint'
        if reason == 4: return 'Watchpoint'
        if reason == 5: return 'Signal'
        if reason == 6: return 'Exception'
        if reason == 7: return 'Exec'
        if reason == 8: return 'Plan Complete'
        if reason == 9: return 'Thread Exiting'
        return 'Unknown Reason'

    def getThreadIDList(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        lst = [{"thread-id":thread.GetThreadID(), "state":self.stopReasonToString(thread.GetStopReason())} for thread in self.target.GetProcess()]
        result = self.buildOK()
        result["threads"] = lst
        return result

    def selectThreadID(self,tid):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        process = self.target.GetProcess()
        thread = process.GetThreadByID(tid)
        if thread == None:
            return self.buildError("no thread %d" % tid)
        process.SetSelectedThread(thread)
        return self.buildOK()

    def breakExecution(self):
        if self.target != None:
            process = self.target.GetProcess()
            if process != None:
                process.SendAsyncInterrupt()
                return self.buildOK()
        return self.buildError("no process")

    def stopExecution(self):
        if self.target != None:
            process = self.target.GetProcess()
            if process != None:
                process.Kill()
                return self.buildOK()
        return self.buildError("no process")
    
    def getRegisters(self):
        DBG_LOG("| Entering getRegisters\n")
        if self.target != None:
            process = self.target.GetProcess()
            DBG_LOG("|  process=%s\n" % process)
            if process != None:
                thread = process.GetSelectedThread()
                DBG_LOG("|   thread=%s\n" % thread)
                frame = thread.GetSelectedFrame()
                DBG_LOG("|   frame=%s\n" % frame)
                lst = {}
                r_gprs = get_GPRs(frame)
                r_fprs = get_FPRs(frame)
                r_esrs = get_ESRs(frame)
                DBG_LOG("|    r_gprs=%s\n" % r_gprs)
                DBG_LOG("|    r_fprs=%s\n" % r_fprs)
                DBG_LOG("|    r_esrs=%s\n" % r_esrs)
                if r_gprs != None:
                    for reg in r_gprs:
                        lst[reg.GetName()] = reg.GetValue()
                if r_fprs != None:
                    for reg in r_fprs:
                        lst[reg.GetName()] = build_reg_value_string(reg)
                if r_esrs != None:
                    for reg in r_esrs:
                        lst[reg.GetName()] = reg.GetValue()
                result = self.buildOK()
                DBG_LOG("|   done\n")
                result["registers"] = lst
                return result
        return self.buildError("no process")

    def setBreakpointAtVirtualAddress(self,addr):
        target = self.target
        if target == None:
            return self.buildError("no target")
        breakpoint = target.BreakpointCreateByAddress(addr)
        if breakpoint == None:
            return self.buildError("cannot create breakpoint")
        result = self.buildOK()
        result['bkpt_id'] = breakpoint.GetID()
        bli = 0
        for bl in breakpoint:
            result['bl%d' % bli] = "load addr: %s" % hex(bl.GetLoadAddress())
            bli = bli + 1
        return result

    def removeBreakpoint(self,bkpt_id):
        target = self.target
        if target == None:
            return self.buildError("no target")
        target.BreakpointDelete(bkpt_id)
        return self.buildOK()

    def removeAllBreakpoints(self):
        target = self.target
        if target == None:
            return self.buildError("no target")
        if target.DeleteAllBreakpoints():
            return self.buildOK()
        else:
            return self.buildError("cannot remove all breakpoints")

    def stepInstruction(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        thread.StepInstruction(False)

    def stepOver(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        thread.StepInstruction(True)

    def stepOut(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        thread.StepOut()

    def readMemory(self,addr,len):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        err = lldb.SBError()
        mem = self.target.GetProcess().ReadMemory(addr,len,err)
        if not err.Success():
            return self.buildError("unable to read memory")
        result = self.buildOK()
        result["memory"] = struct.unpack('B' * len, mem)
        return result

    def writeByte(self,addr,value):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        mem = struct.pack('B', value)
        err = lldb.SBError()
        self.target.GetProcess().WriteMemory(addr,mem,err)
        if not err.Success():
            return self.buildError("unable to write memory: " + err.GetCString() + ("(%d)" % self.target.GetProcess().GetState()))
        result = self.buildOK()
        return result

    def getFrameDesc(self,frame):
        module_name = None
        module_uuid = None
        module = frame.GetModule()
        if module != None:
            module_uuid = module.GetUUIDString()
            file = module.GetFileSpec()
            if file != None:
                module_name = file.GetFilename()
        return {"pc": frame.GetPC(), "function": frame.GetFunctionName(), "filename": module_name, "uuid": module_uuid}

    def getCallstack(self):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        callstack = [self.getFrameDesc(frame) for frame in thread]
        result = self.buildOK()
        result["callstack"] = callstack
        return result

    def selectFrame(self,index):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        thread.SetSelectedFrame(index)
        return self.buildOK()

    def setRegister(self,name,value):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        thread = self.target.GetProcess().GetSelectedThread()
        frame = thread.GetSelectedFrame()
        regValue = findRegister(frame, name)
        if regValue == None:
            return self.buildError("register not found")
        err = lldb.SBError()
        if not regValue.SetValueFromCString(value.encode("utf-8"), err):
            return self.buildError("cannot set the register value: %s" % err.GetCString())
        return self.buildOK()

    def executeCommand(self,cmd):
        ci = self.debugger.GetCommandInterpreter()
        cmd_result = lldb.SBCommandReturnObject()
        ci.HandleCommand(cmd.encode("utf-8"), cmd_result)
        result = self.buildOK()
        result['output'] = cmd_result.GetOutput()
        result['error'] = cmd_result.GetError()
        result['succeeded'] = cmd_result.Succeeded()
        return result

    def completeCommand(self,cmd,cur_pos):
        ci = self.debugger.GetCommandInterpreter()
        cmd_result = lldb.SBStringList()
        ci.HandleCompletion(cmd.encode("utf-8"), cur_pos, 0, -1, cmd_result)
        result = self.buildOK()
        result['completions'] = [s for s in cmd_result]
        return result

    def sendToApplication(self,data):
        if self.target == None or self.target.GetProcess() == None:
            return self.buildError("no process")
        result = self.buildOK()
        try:
            str = reduce(lambda x,y: x+y, map(lambda x: chr(x), data))
            self.target.GetProcess().PutSTDIN(str)
        except Exception as e:
            result = self.buildError("cannot build string to send")
        return result

    def handleRequest(self,req):
        command = req['command'];
        result = None
        if command == 'ping':
            result = self.buildOK()
        elif command == 'prepareExecutable':
            result = self.prepareExecutable(req['path'], req['is64Bits'], req['cwd'], req['args'])
        elif command == 'createProcess':
            result = self.createProcess()
        elif command == 'attachToProcess':
            result = self.attachToProcess(req['pid'], req['executable'], req['is64Bits'])
        elif command == 'detach':
            result = self.detach()
        elif command == 'deleteProcess':
            result = self.deleteProcess()
        elif command == 'hasProcess':
            result = self.hasProcess()
        elif command == 'getProcessState':
            result = self.getProcessState()
        elif command == 'continueExecution':
            result = self.continueExecution()
        elif command == 'stopExecution':
            result = self.stopExecution()
        elif command == 'breakExecution':
            result = self.breakExecution()
        elif command == 'getThreadIDList':
            result = self.getThreadIDList()
        elif command == 'selectThreadID':
            result = self.selectThreadID(req['tid'])
        elif command == 'getRegisters':
            result = self.getRegisters()
        elif command == 'setBreakpointAtVirtualAddress':
            result = self.setBreakpointAtVirtualAddress(req['address'])
        elif command == 'removeBreakpoint':
            result = self.removeBreakpoint(req['bkpt_id'])
        elif command == 'removeAllBreakpoints':
            result = self.removeAllBreakpoints()
        elif command == 'stepInstruction':
            result = self.stepInstruction()
        elif command == 'stepOver':
            result = self.stepOver()
        elif command == 'stepOut':
            result = self.stepOut()
        elif command == 'readMemory':
            result = self.readMemory(req['address'], req['length'])
        elif command == 'writeByte':
            result = self.writeByte(req['address'], req['value'])
        elif command == 'getCallstack':
            result = self.getCallstack()
        elif command == 'selectFrame':
            result = self.selectFrame(req['index'])
        elif command == 'setRegister':
            result = self.setRegister(req['register'], req['value'])
        elif command == 'executeCommand':
            result = self.executeCommand(req['cli'])
        elif command == 'completeCommand':
            result = self.completeCommand(req['cli'], req['pos'])
        elif command == 'sendToApplication':
            result = self.sendToApplication(req['data'])
        elif command == 'moduleCount':
            return self.moduleCount()
        elif command == 'moduleAtIndex':
            return self.moduleAtIndex(req['index'])
        elif command == 'moduleForFile':
            return self.moduleForFile(req['file'])
        elif command == 'connectRemote':
            return self.connectRemote(req['is64Bits'], req['url'], req['plugin'], req['platform'], req['file'])
        if result == None:
            result = self.buildError("unknown command '" + command + "'")
        return result

    def run(self):
        while True:
            try:
                # Get a command
                line = self.transportRead()
                if line == None:
                    break

                # Decode JSON
                try:
                    req = json.loads(line)
                except ValueError:
                    req = None

                if req == None:
                    self.sendError("cannot decode JSON")
                    continue

                result = None
                try:
                    result = self.handleRequest(req)
                except Exception as e:
                    result = self.buildError("bad request: " + str(e))

                if result == None:
                    result = self.buildError("empty response")

                if req.has_key("id"):
                    result["id"] = req["id"]
                self.sendJSON(result)

            except EOFError:
                self.sendOK("EOF")
                break
        self.stopRequest = True

if __name__ == "__main__":
    if len(sys.argv) == 1:
        input_fd = sys.stdin
        output_fd = sys.stdout
        cmd_mode = True
    else:
        fd_in = int(sys.argv[1])
        fd_out = int(sys.argv[2])
        input_fd = os.fdopen(fd_in, 'r')
        output_fd = os.fdopen(fd_out, 'w')
        cmd_mode = False

    print(dir(lldb.SBTarget))
    print(dir(lldb.SBProcess))
    print(dir(lldb.SBEvent))

    DBG_LOG("\n\n-------------- STARTING --------------\n")
    handler = Handler(input_fd, output_fd, cmd_mode)
    handler.start()
    handler.join()
