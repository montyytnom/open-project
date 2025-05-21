import Foundation
import os.log

func consoleLog(_ message: String, type: OSLogType = .default) {
    os_log("%{public}@", log: OSLog.default, type: type, message)
}

// ConsoleLog struct with static methods for different log types
struct ConsoleLog {
    static func debug(_ message: String) {
        consoleLog("DEBUG: \(message)", type: .debug)
    }
    
    static func info(_ message: String) {
        consoleLog("INFO: \(message)", type: .info)
    }
    
    static func error(_ message: String) {
        consoleLog("ERROR: \(message)", type: .error)
    }
    
    static func fault(_ message: String) {
        consoleLog("FAULT: \(message)", type: .fault)
    }
} 