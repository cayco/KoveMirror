import Foundation
import Combine

public enum LogLevel: String {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"
    case data = "DATA"
    case heartbeat = "HEARTBEAT"
    
    public var icon: String {
        switch self {
        case .info: return "ℹ️"
        case .success: return "✅"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .data: return "📊"
        case .heartbeat: return "💓"
        }
    }
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
    
    @Published public private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    private let queue = DispatchQueue(label: "com.kove.mirror.logger", qos: .utility)
    
    private init() {}
    
    public func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        
        queue.async {
            DispatchQueue.main.async {
                self.entries.append(entry)
                if self.entries.count > self.maxEntries {
                    self.entries.removeFirst(self.entries.count - self.maxEntries)
                }
            }
        }
        
        #if DEBUG
        print("\(entry.formattedTimestamp) \(level.icon) [\(level.rawValue)] \(message)")
        #endif
    }
    
    public func info(_ message: String) { log(message, level: .info) }
    public func success(_ message: String) { log(message, level: .success) }
    public func warning(_ message: String) { log(message, level: .warning) }
    public func error(_ message: String) { log(message, level: .error) }
    public func data(_ message: String) { log(message, level: .data) }
    public func heartbeat(_ message: String) { log(message, level: .heartbeat) }
    
    public func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}
