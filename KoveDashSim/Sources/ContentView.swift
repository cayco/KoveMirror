import SwiftUI
import AVFoundation

public struct ContentView: View {
    @StateObject private var client = KoveDashClient()
    @StateObject private var bleManager = KoveBLEPeripheralManager()
    @StateObject private var logger = Logger.shared
    
    @FocusState private var isIPFieldFocused: Bool
    @State private var inputIP: String = "192.168.1.100"
    @State private var showLogs: Bool = false
    @State private var simulatedSpeed: Int = 85
    @State private var simulatedRPM: Int = 5400
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Panel: Kove TFT Dashboard Screen Sim
            VStack(spacing: 16) {
                // Dashboard Outer Frame / Bezel
                VStack(spacing: 0) {
                    // TFT Top Header Bar
                    topHeaderBar
                    
                    // Main Canvas Area (Video Mirror or Standby View)
                    ZStack {
                        Color(red: 0.05, green: 0.06, blue: 0.09)
                        
                        if client.isVideoConnected {
                            SampleBufferVideoView(decoder: client.decoder)
                                .clipShape(Rectangle())
                        } else {
                            standbyView
                        }
                    }
                    .frame(width: 480, height: 720)
                    
                    // TFT Bottom Telemetry Bar
                    bottomTelemetryBar
                }
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.3), lineWidth: 2))
                .shadow(color: Color.cyan.opacity(0.15), radius: 25, x: 0, y: 10)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().background(Color.white.opacity(0.15))
            
            // MARK: - Right Panel: Controls & Telemetry Stats
            controlSidebar
        }
        .onReceive(timer) { _ in
            simulatedSpeed = Int(80 + 10 * sin(Date().timeIntervalSince1970 * 0.5))
            simulatedRPM = Int(5000 + 600 * sin(Date().timeIntervalSince1970 * 0.5))
        }
        .onAppear {
            bleManager.onPairRequested = {
                Logger.shared.success("🎯 BLE Pair handshake complete!")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var topHeaderBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(client.isVideoConnected ? Color.green : (client.isConnected ? Color.orange : Color.red))
                    .frame(width: 10, height: 10)
                
                Text(client.isVideoConnected ? "STREAM ACTIVE" : (client.isConnected ? "CONNECTED" : "DISCONNECTED"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(client.isVideoConnected ? .green : (client.isConnected ? .orange : .red))
            }
            
            Spacer()
            
            Text("KOVE 800X PRO TFT")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.cyan)
            
            Spacer()
            
            Text(Date(), style: .time)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
    }
    
    private var bottomTelemetryBar: some View {
        HStack {
            HStack(spacing: 12) {
                Label("2.4 BAR", systemImage: "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cyan)
                Label("2.5 BAR", systemImage: "gauge.open.with.lines.needle.33percent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cyan)
            }
            Spacer()
            Label("78% FUEL", systemImage: "fuelpump.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
    }
    
    private var standbyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.cyan)
                .shadow(color: .cyan.opacity(0.4), radius: 10)
            
            VStack(spacing: 6) {
                Text("KOVE DASHBOARD SIMULATOR")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                
                Text("Awaiting iPhone Screen Mirror Stream...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "1.circle.fill").foregroundColor(.cyan)
                    Text("Connect iPhone to same Wi-Fi network").foregroundColor(.white).font(.caption)
                }
                HStack(spacing: 8) {
                    Image(systemName: "2.circle.fill").foregroundColor(.cyan)
                    Text("Enter iPhone IP in control panel on right").foregroundColor(.white).font(.caption)
                }
                HStack(spacing: 8) {
                    Image(systemName: "3.circle.fill").foregroundColor(.cyan)
                    Text("Click CONNECT or let BLE auto-pair").foregroundColor(.white).font(.caption)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            HStack(spacing: 24) {
                VStatView(title: "SPEED", value: "\(simulatedSpeed) KM/H", icon: "speedometer")
                VStatView(title: "ENGINE", value: "\(simulatedRPM) RPM", icon: "engine.combustion.fill")
                VStatView(title: "GEAR", value: "4TH", icon: "gearshape.fill")
            }
            .padding(.horizontal)
        }
        .padding(24)
    }
    
    private var controlSidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("DASH SIMULATOR CONTROLS")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
                Text("Kove Motorcycle Screen Mirroring Receiver")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            
            // IP Connection Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("IP CONNECTION SETUP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.cyan)
                    Spacer()
                    Button(action: {
                        client.startAutoDiscovery()
                    }) {
                        HStack(spacing: 4) {
                            if client.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(client.isSearching ? "SCANNING..." : "AUTO-DISCOVER IPHONE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(client.isSearching)
                }
                
                HStack {
                    TextField("iPhone IP Address (e.g. 192.168.1.100)", text: $inputIP)
                        .focused($isIPFieldFocused)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button(action: {
                        if client.isConnected {
                            client.disconnect()
                        } else {
                            client.connect(to: inputIP.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }) {
                        Text(client.isConnected ? "DISCONNECT" : "CONNECT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(client.isConnected ? Color.red : Color.cyan)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .cornerRadius(12)
            
            // BLE Peripheral Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLE GATTS PERIPHERAL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.cyan)
                        Text("Advertises as Kove TFT display (CQKY_TFT_Dash)")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { bleManager.isAdvertising },
                        set: { newValue in
                            if newValue {
                                bleManager.startAdvertising()
                            } else {
                                bleManager.stopAdvertising()
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                }
                
                HStack(spacing: 12) {
                    StatusChip(title: "BLE ADVERTISING", isActive: bleManager.isAdvertising)
                    StatusChip(title: "IPHONE BLE PAIRED", isActive: bleManager.isCentralConnected)
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .cornerRadius(12)
            
            // Connection Ports Status
            VStack(alignment: .leading, spacing: 10) {
                Text("TCP SOCKETS STATUS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                
                VStack(spacing: 8) {
                    SocketRowView(portName: "Control Port 17818", isConnected: client.isControlConnected)
                    SocketRowView(portName: "Video Stream Port 15456", isConnected: client.isVideoConnected)
                    SocketRowView(portName: "Heartbeat Port 15457", isConnected: client.isHeartbeatConnected)
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .cornerRadius(12)
            
            // Stream Performance Telemetry
            VStack(alignment: .leading, spacing: 10) {
                Text("STREAM TELEMETRY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Decoder Resolution:").font(.caption).foregroundColor(.gray)
                        Text("\(client.decoder.streamWidth) x \(client.decoder.streamHeight)")
                            .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    }
                    GridRow {
                        Text("Frame Rate (FPS):").font(.caption).foregroundColor(.gray)
                        Text(String(format: "%.1f FPS", client.decoder.currentFPS))
                            .font(.caption).fontWeight(.bold).foregroundColor(.green)
                    }
                    GridRow {
                        Text("Decoded Frames:").font(.caption).foregroundColor(.gray)
                        Text("\(client.decoder.decodedFrameCount)")
                            .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    }
                    GridRow {
                        Text("Total Data Received:").font(.caption).foregroundColor(.gray)
                        Text(formatBytes(client.totalBytesReceived))
                            .font(.caption).fontWeight(.bold).foregroundColor(.cyan)
                    }
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
            .cornerRadius(12)
            
            // Logs Toggle & Clear
            HStack {
                Button(action: { showLogs.toggle() }) {
                    Label(showLogs ? "Hide Console Logs" : "Show Console Logs", systemImage: "terminal.fill")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("Clear Logs") {
                    logger.clear()
                }
                .font(.caption)
                .foregroundColor(.gray)
                .buttonStyle(PlainButtonStyle())
            }
            
            // Console Logs Box
            if showLogs {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(logger.logs) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(entry.formattedTimestamp)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    Text("[\(entry.level.rawValue)]")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(colorForLevel(entry.level))
                                    
                                    Text(entry.message)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 180)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .onChange(of: logger.logs.count) { _ in
                        if let last = logger.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(red: 0.07, green: 0.08, blue: 0.11))
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .cyan
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .data: return .purple
        }
    }
}

struct SocketRowView: View {
    let portName: String
    let isConnected: Bool
    
    var body: some View {
        HStack {
            Text(portName)
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isConnected ? .green : .red)
            }
        }
    }
}

struct StatusChip: View {
    let title: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isActive ? .green : .gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
    }
}

struct VStatView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.cyan)
            
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 8))
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }
}
