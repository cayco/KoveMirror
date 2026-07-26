import Foundation
import Combine

public enum LogLevel: String {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARN"
    case error = "ERROR"
    case data = "DATA"
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

public final class Logger: ObservableObject {
    public static let shared = Logger()
    
    @Published public private(set) var logs: [LogEntry] = []
    private let maxLogs = 300
    
    private init() {}
    
    public func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst(self.logs.count - self.maxLogs)
            }
        }
        print("[\(entry.formattedTimestamp)] [\(level.rawValue)] \(message)")
    }
    
    public func info(_ message: String) { log(message, level: .info) }
    public func success(_ message: String) { log(message, level: .success) }
    public func warning(_ message: String) { log(message, level: .warning) }
    public func error(_ message: String) { log(message, level: .error) }
    public func data(_ message: String) { log(message, level: .data) }
    
    public func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
