import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var mirrorService = KoveMirrorService()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Dashboard & Controls
            MainDashboardView(mirrorService: mirrorService)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(0)
            
            // Tab 1: Live Navigation Mirror Canvas
            NavigationMirrorView(mirrorService: mirrorService)
                .tabItem {
                    Label("Live Mirror", systemImage: "map.fill")
                }
                .tag(1)
            
            // Tab 2: Settings
            SettingsView(mirrorService: mirrorService)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
            
            // Tab 3: Diagnostic Logs
            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "terminal.fill")
                }
                .tag(3)
        }
        .accentColor(.cyan)
        .preferredColorScheme(.dark)
    }
}

struct MainDashboardView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    @State private var isStealthModeActive = false
    @State private var previousBrightness: CGFloat = 0.5
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.11)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Master Action Card
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("KOVE MOTORCYCLE TFT")
                                        .font(.caption2)
                                        .fontWeight(.black)
                                        .foregroundColor(.cyan)
                                    
                                    Text("Screen Mirroring")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                
                                Image(systemName: "motorcycle")
                                    .font(.system(size: 36))
                                    .foregroundColor(.cyan)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // Master Toggle Button
                            Button(action: {
                                if mirrorService.isMirroringActive {
                                    mirrorService.stopMirroring()
                                } else {
                                    mirrorService.startMirroring()
                                }
                            }) {
                                HStack {
                                    Image(systemName: mirrorService.isMirroringActive ? "stop.fill" : "play.fill")
                                    Text(mirrorService.isMirroringActive ? "STOP MIRRORING" : "START MIRRORING")
                                        .fontWeight(.bold)
                                }
                                .font(.headline)
                                .foregroundColor(mirrorService.isMirroringActive ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(mirrorService.isMirroringActive ? Color.red : Color.cyan)
                                .cornerRadius(16)
                                .shadow(color: (mirrorService.isMirroringActive ? Color.red : Color.cyan).opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                        }
                        .padding(20)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // Full System Screen Casting Card (Google Maps, Waze, Scenic, OsmAnd)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tv.badge.wifi.fill")
                                            .foregroundColor(.green)
                                        Text("FULL SYSTEM SCREEN CASTING")
                                            .font(.caption)
                                            .fontWeight(.black)
                                            .foregroundColor(.green)
                                    }
                                    
                                    Text("Cast Google Maps, Waze, OsmAnd to TFT")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                Spacer()
                                
                                StatusBadge(
                                    isActive: mirrorService.screenCapture.isBroadcastIPCActive,
                                    activeTitle: "BROADCAST LIVE",
                                    inactiveTitle: "READY"
                                )
                            }
                            
                            Text("Tap the broadcast button on the right to start system screen recording. Your entire iPhone screen will be mirrored to the motorcycle display.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            HStack(spacing: 12) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.title3)
                                    .foregroundColor(.cyan)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TAP TO START SYSTEM BROADCAST")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("Select 'KoveMirror Broadcast' in system prompt")
                                        .font(.system(size: 10))
                                        .foregroundColor(.cyan)
                                }
                                
                                Spacer()
                                
                                MainDashboardBroadcastPickerRepresentable()
                                    .frame(width: 54, height: 54)
                                    .background(mirrorService.screenCapture.isBroadcastIPCActive ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2))
                                    .cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(mirrorService.screenCapture.isBroadcastIPCActive ? Color.green : Color.cyan, lineWidth: 1.5))
                            }
                        }
                        .padding(18)
                        .background(Color(red: 0.10, green: 0.14, blue: 0.16))
                        .cornerRadius(22)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(mirrorService.screenCapture.isBroadcastIPCActive ? Color.green.opacity(0.5) : Color.cyan.opacity(0.3), lineWidth: 1.5))

                        
                        // Pocket Stealth Mode Control Card
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "moon.stars.fill")
                                            .foregroundColor(.cyan)
                                        Text("POCKET STEALTH MODE")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                    }
                                    Text("OLED pitch black, 0% display power, 2s lock")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Toggle("", isOn: $isStealthModeActive)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                                    .onChange(of: isStealthModeActive) { active in
                                        #if canImport(UIKit)
                                        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                                            if active {
                                                previousBrightness = scene.screen.brightness
                                                scene.screen.brightness = 0.0
                                            } else {
                                                scene.screen.brightness = max(0.5, previousBrightness)
                                            }
                                        }
                                        #endif
                                    }
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // Status Matrix Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONNECTION STATUS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                StatusCard(
                                    title: "BLE GATT",
                                    subtitle: mirrorService.bleManager.peripheralName ?? "Scanning...",
                                    isActive: mirrorService.bleManager.isConnected,
                                    icon: "antenna.radiowaves.left.and.right"
                                )
                                
                                StatusCard(
                                    title: "Control Port 17818",
                                    subtitle: mirrorService.tcpManager.isControlConnected ? "Connected" : "Listening...",
                                    isActive: mirrorService.tcpManager.isControlConnected,
                                    icon: "network"
                                )
                                
                                StatusCard(
                                    title: "Video Port 15456",
                                    subtitle: mirrorService.tcpManager.isVideoConnected ? "Streaming H.264" : "Waiting...",
                                    isActive: mirrorService.tcpManager.isVideoConnected,
                                    icon: "video.fill"
                                )
                                
                                StatusCard(
                                    title: "Heartbeat Port 15457",
                                    subtitle: mirrorService.tcpManager.isHeartbeatConnected ? "200ms Active" : "Waiting...",
                                    isActive: mirrorService.tcpManager.isHeartbeatConnected,
                                    icon: "heart.fill"
                                )
                            }
                        }
                        
                        // Live Streaming Statistics Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("STREAMING PERFORMANCE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 12) {
                                StatRow(
                                    label: "Video Resolution",
                                    value: "\(mirrorService.width) × \(mirrorService.height) px"
                                )
                                StatRow(
                                    label: "Encoding Frame Rate",
                                    value: String(format: "%.1f FPS", mirrorService.encoder.currentFPS)
                                )
                                StatRow(
                                    label: "Total Encoded Frames",
                                    value: "\(mirrorService.encoder.encodedFrameCount) frames"
                                )
                                StatRow(
                                    label: "Data Transferred",
                                    value: String(format: "%.2f MB", Double(mirrorService.tcpManager.totalBytesSent) / 1024.0 / 1024.0)
                                )
                            }
                            .padding(16)
                            .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                            .cornerRadius(18)
                        }
                        
                        // Instructions Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundColor(.orange)
                                Text("QUICK CONNECTION GUIDE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cyan)
                            }
                            
                            InstructionStep(num: "1", text: "Turn on your Kove motorcycle TFT dashboard.")
                            InstructionStep(num: "2", text: "Connect iPhone to the motorcycle's Wi-Fi network (CQKY_XXXXXXXX). (Tip: Disable 5G Cellular Data if needed).")
                            InstructionStep(num: "3", text: "Ensure Bluetooth is ON on your iPhone.")
                            InstructionStep(num: "4", text: "Tap 'START MIRRORING' above to launch BLE & TCP servers.")
                            InstructionStep(
                                num: "5",
                                text: "CRITICAL: On motorcycle handlebar, LONG-PRESS the 'SET' key to open TFT menu and select 'Start Navigation'. The TFT will connect to Video Port 15456!",
                                isCrucial: true
                            )
                        }
                        .padding(16)
                        .background(Color(red: 0.10, green: 0.12, blue: 0.16))
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }
                    .padding()
                }
                
                // Full Screen Tap-to-Wake Stealth Overlay
                if isStealthModeActive {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.cyan.opacity(0.3))
                                
                                Text("POCKET STEALTH MODE ACTIVE")
                                    .font(.caption)
                                    .fontWeight(.black)
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Text("Double-tap screen when out of pocket to wake")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        )
                        .onTapGesture(count: 2) {
                            #if canImport(UIKit)
                            // Ignore touches if proximity sensor is covered inside pocket/bag
                            guard !UIDevice.current.proximityState else { return }
                            #endif
                            isStealthModeActive = false
                        }
                        .onAppear {
                            #if canImport(UIKit)
                            UIDevice.current.isProximityMonitoringEnabled = true
                            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                                previousBrightness = scene.screen.brightness
                                scene.screen.brightness = 0.0
                            }
                            #endif
                        }
                        .onDisappear {
                            #if canImport(UIKit)
                            UIDevice.current.isProximityMonitoringEnabled = false
                            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                                scene.screen.brightness = max(0.5, previousBrightness)
                            }
                            #endif
                        }
                }
            }
            .navigationTitle("KoveMirror")
        }
    }
}

struct StatusCard: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isActive ? .green : .gray)
                Spacer()
                Circle()
                    .fill(isActive ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(isActive ? .green : .gray)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isActive ? Color.green.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.cyan)
        }
    }
}

struct InstructionStep: View {
    let num: String
    let text: String
    var isCrucial: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 18, height: 18)
                .background(isCrucial ? Color.orange : Color.cyan)
                .clipShape(Circle())
            
            Text(text)
                .font(.caption)
                .fontWeight(isCrucial ? .semibold : .regular)
                .foregroundColor(isCrucial ? .orange : .gray)
            
            Spacer()
        }
    }
}

struct MainDashboardBroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
        picker.preferredExtension = "pl.cayco.kovemirror.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }
    
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct StatusBadge: View {
    let isActive: Bool
    let activeTitle: String
    let inactiveTitle: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(isActive ? activeTitle : inactiveTitle)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(isActive ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
        .cornerRadius(8)
    }
}
