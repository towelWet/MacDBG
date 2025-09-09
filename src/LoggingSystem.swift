import Foundation
import os.log

/// Comprehensive logging system for MacDBG that exports logs to files
class LoggingSystem {
    static let shared = LoggingSystem()
    
    private let logger = Logger(subsystem: "com.macdbg.app", category: "main")
    private let fileLogger: FileHandle?
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.macdbg.logging", qos: .utility)
    
    init() {
        // Create logs directory in user's Documents
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logsDir = documentsPath.appendingPathComponent("MacDBG_Logs")
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Create timestamped log file
        let timestamp = DateFormatter.fileTimestamp.string(from: Date())
        logFileURL = logsDir.appendingPathComponent("macdbg_\(timestamp).log")
        
        // Create file and get handle
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileLogger = try? FileHandle(forWritingTo: logFileURL)
        
        // Log system startup
        log("📋 MacDBG Logging System Started", category: .system)
        log("📁 Log file: \(logFileURL.path)", category: .system)
    }
    
    deinit {
        fileLogger?.closeFile()
    }
    
    enum LogCategory: String, CaseIterable {
        case system = "SYSTEM"
        case lldb = "LLDB"
        case ui = "UI"
        case crash = "CRASH"
        case launch = "LAUNCH"
        case debug = "DEBUG"
        case error = "ERROR"
        case network = "NETWORK"
        case threading = "THREADING"
        case performance = "PERF"
    }
    
    func log(_ message: String, category: LogCategory = .debug, file: String = #file, line: Int = #line, function: String = #function) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logEntry = "[\(timestamp)] [\(category.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        
        // Log to system logger
        logger.info("\(logEntry)")
        
        // Log to file asynchronously
        queue.async { [weak self] in
            guard let self = self,
                  let data = (logEntry + "\n").data(using: .utf8) else { return }
            self.fileLogger?.write(data)
        }
        
        // Also print to console for debugging
        print(logEntry)
    }
    
    func logCrash(_ error: Error, context: String = "") {
        let crashInfo = """
        🚨 CRASH DETECTED 🚨
        Context: \(context)
        Error: \(error.localizedDescription)
        Stack Trace: \(Thread.callStackSymbols.joined(separator: "\n"))
        """
        log(crashInfo, category: .crash)
    }
    
    func logLaunchAttempt(_ binaryPath: String) {
        log("🚀 LAUNCH ATTEMPT: \(binaryPath)", category: .launch)
    }
    
    func logThreadingViolation(_ message: String) {
        log("⚠️ THREADING VIOLATION: \(message)", category: .threading)
    }
    
    func exportLogs() -> URL {
        // Force flush
        queue.sync {
            fileLogger?.synchronizeFile()
        }
        return logFileURL
    }
    
    func getLogSummary() -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8) else {
            return "Unable to read log file"
        }
        
        let lines = content.components(separatedBy: .newlines)
        let crashLines = lines.filter { $0.contains("[CRASH]") }
        let errorLines = lines.filter { $0.contains("[ERROR]") }
        let launchLines = lines.filter { $0.contains("[LAUNCH]") }
        let threadingLines = lines.filter { $0.contains("[THREADING]") }
        
        return """
        📊 MacDBG Log Summary
        =====================
        Total log entries: \(lines.count)
        Crashes detected: \(crashLines.count)
        Errors logged: \(errorLines.count)
        Launch attempts: \(launchLines.count)
        Threading violations: \(threadingLines.count)
        
        Log file: \(logFileURL.path)
        """
    }
}

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

/// Global logging functions for easy use
func macdbgLog(_ message: String, category: LoggingSystem.LogCategory = .debug, file: String = #file, line: Int = #line, function: String = #function) {
    LoggingSystem.shared.log(message, category: category, file: file, line: line, function: function)
}

func macdbgLogCrash(_ error: Error, context: String = "", file: String = #file, line: Int = #line, function: String = #function) {
    LoggingSystem.shared.logCrash(error, context: context)
    LoggingSystem.shared.log("Crash logged from \(URL(fileURLWithPath: file).lastPathComponent):\(line)", category: .crash, file: file, line: line, function: function)
}
