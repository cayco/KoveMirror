import SwiftUI

struct LogsView: View {
    @ObservedObject var logger = Logger.shared
    @State private var filterLevel: LogLevel? = nil
    
    var filteredEntries: [LogEntry] {
        if let filter = filterLevel {
            return logger.entries.filter { $0.level == filter }
        }
        return logger.entries
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "ALL", count: logger.entries.count, isSelected: filterLevel == nil) {
                                filterLevel = nil
                            }
                            FilterChip(title: "SUCCESS", count: logger.entries.filter { $0.level == .success }.count, isSelected: filterLevel == .success) {
                                filterLevel = .success
                            }
                            FilterChip(title: "INFO", count: logger.entries.filter { $0.level == .info }.count, isSelected: filterLevel == .info) {
                                filterLevel = .info
                            }
                            FilterChip(title: "DATA", count: logger.entries.filter { $0.level == .data }.count, isSelected: filterLevel == .data) {
                                filterLevel = .data
                            }
                            FilterChip(title: "HEARTBEAT", count: logger.entries.filter { $0.level == .heartbeat }.count, isSelected: filterLevel == .heartbeat) {
                                filterLevel = .heartbeat
                            }
                            FilterChip(title: "ERROR", count: logger.entries.filter { $0.level == .error }.count, isSelected: filterLevel == .error) {
                                filterLevel = .error
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .background(Color(red: 0.10, green: 0.12, blue: 0.16))
                    
                    // Log Scroll List
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(filteredEntries) { entry in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.formattedTimestamp)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.gray)
                                        
                                        Text(entry.level.icon)
                                            .font(.caption2)
                                        
                                        Text(entry.message)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(colorForLevel(entry.level))
                                            .textSelection(.enabled)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 10)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(6)
                                    .id(entry.id)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: logger.entries.count) { _ in
                            if let last = filteredEntries.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Diagnostic Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { logger.clear() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
    }
    
    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .white
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        case .data: return .cyan
        case .heartbeat: return .pink
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                Text("(\(count))")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(isSelected ? .black : .cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.cyan : Color.cyan.opacity(0.15))
            .cornerRadius(12)
        }
    }
}
