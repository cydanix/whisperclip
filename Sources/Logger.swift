import Foundation
import os.log

/// A simple logging utility that adds source file and line information to log messages.
public enum Logger {
    // Create OSLog instances for different categories
    public static let hotkey = OSLog(subsystem: "com.whisperclip", category: "hotkey")
    public static let audio = OSLog(subsystem: "com.whisperclip", category: "audio")
    public static let settings = OSLog(subsystem: "com.whisperclip", category: "settings")
    public static let general = OSLog(subsystem: "com.whisperclip", category: "general")
    public static let updater = OSLog(subsystem: "com.whisperclip", category: "updater")


    /// Log a message with the specified log type
    /// - Parameters:
    ///   - message: The message to log
    ///   - log: The OSLog instance to use (defaults to general)
    ///   - type: The type of log message (defaults to .default)
    ///   - file: The file name where the log was called (automatically captured)
    ///   - function: The function name where the log was called (automatically captured)
    ///   - line: The line number where the log was called (automatically captured)
    public static func log(_ message: String,
                          log: OSLog = Logger.general,
                          type: OSLogType = .default,
                          file: String = #file,
                          function: String = #function,
                          line: Int = #line) {
        // Always log to system using os_log
        os_log("%{public}@", log: log, type: type, message)

        // Only print to console if running via swift run
        if GenericHelper.logToConsole() {
            let logMessage = formatLogMessage(message, log: log, type: type, file: file, function: function, line: line)
            Swift.print(logMessage)
        }

    }

    /// Log a debug message (only if debug logging is enabled in settings)
    /// - Parameters:
    ///   - message: The message to log
    ///   - log: The OSLog instance to use (defaults to general)
    ///   - type: The type of log message (defaults to .debug)
    ///   - file: The file name where the log was called (automatically captured)
    ///   - function: The function name where the log was called (automatically captured)
    ///   - line: The line number where the log was called (automatically captured)
    public static func debugLog(_ message: String,
                               log: OSLog = Logger.general,
                               type: OSLogType = .debug,
                               file: String = #file,
                               function: String = #function,
                               line: Int = #line) {
        // Only log if debug logging is enabled
        guard SettingsStore.shared.debugLogging else { return }

        // Use the regular log function
        self.log(message, log: log, type: type, file: file, function: function, line: line)
    }

    private static func formatLogMessage(_ message: String, log: OSLog, type: OSLogType, file: String, function: String, line: Int) -> String {
        let category: String
        switch log {
        case Logger.hotkey: category = "hotkey"
        case Logger.audio: category = "audio"
        case Logger.settings: category = "settings"
        case Logger.general: category = "general"
        case Logger.updater: category = "updater"
        default: category = "unknown"
        }

        let logType: String
        switch type {
        case .info: logType = "info"
        case .debug: logType = "debug"
        case .error: logType = "error"
        case .fault: logType = "fault"
        case .default: logType = "default"
        default: logType = "unknown"
        }

        let fileName = (file as NSString).lastPathComponent
        let unixTimestamp = Date().timeIntervalSince1970
        return "[com.whisperclip.\(category)] [\(unixTimestamp)] [\(logType)] [\(fileName):\(line) \(function)] \(message)"
    }
}
