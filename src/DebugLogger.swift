import Foundation
import os.log

class DebugLogger {
    static let shared = DebugLogger()
    
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let logger = Logger(subsystem: "com.yourcompany.macdbg", category: "debug")
    
    private init() {
        // Create logs directory
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let logsDirectory = homeDirectory.appendingPathComponent("Desktop").appendingPathComponent("MacDBG_Debug_Logs")
        
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create logs directory: \(error)")
        }
        
        // Create timestamped log file
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyyMMdd_HHmmss"
        }.string(from: Date())
        
        self.logFileURL = logsDirectory.appendingPathComponent("macdbg_swift_debug_\(timestamp).log")
        
        // Create log file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        
        do {
            self.fileHandle = try FileHandle(forWritingTo: logFileURL)
        } catch {
            print("Failed to create file handle: \(error)")
            self.fileHandle = nil
        }
        
        log("=" * 80)
        log("MacDBG Swift Debug Logger Started")
        log("Log file: \(logFileURL.path)")
        log("Timestamp: \(Date())")
        log("=" * 80)
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    private func log(_ message: String, level: String = "INFO") {
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "HH:mm:ss.SSS"
        }.string(from: Date())
        
        let logEntry = "[\(timestamp)] [\(level)] \(message)"
        
        // Write to file
        if let data = (logEntry + "\n").data(using: .utf8) {
            fileHandle?.write(data)
        }
        
        // Write to console
        print(logEntry)
        
        // Write to system log
        logger.info("\(logEntry)")
    }
    
    func info(_ message: String) {
        log(message, level: "INFO")
    }
    
    func error(_ message: String) {
        log(message, level: "ERROR")
    }
    
    func warning(_ message: String) {
        log(message, level: "WARNING")
    }
    
    func crash(_ message: String) {
        log("=" * 50, level: "CRASH")
        log("CRASH DETECTED!", level: "CRASH")
        log(message, level: "CRASH")
        log("=" * 50, level: "CRASH")
    }
    
    func debug(_ message: String) {
        log(message, level: "DEBUG")
    }
}

// Extension to make DateFormatter easier to use
extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}

// Extension to repeat strings
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
