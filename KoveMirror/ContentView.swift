import SwiftUI
import ReplayKit
import Combine

struct ContentView: View {
    @StateObject private var mirrorService = KoveMirrorService()
    @StateObject private var stealthManager = PocketStealthManager()
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Tab 0: Dashboard & Controls
                MainDashboardView(mirrorService: mirrorService, stealthManager: stealthManager)
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
            
            if stealthManager.isStealthActive {
                PocketStealthOverlayView(stealthManager: stealthManager)
            }
        }
    }
}

struct MainDashboardView: View {
    @ObservedObject var mirrorService: KoveMirrorService
    @State private var isStealthModeActive = false
    @State private var previousBrightness: CGFloat = 0.5
    @ObservedObject var stealthManager: PocketStealthManager
    
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
                            
                            // Master Toggle Button with Programmatic Broadcast Picker Trigger
                            Button(action: {
                                if !mirrorService.isMirroringActive {
                                    mirrorService.startMirroring()
                                }
                                BroadcastTrigger.shared.trigger()
                            }) {
                                let isBroadcastActive = mirrorService.screenCapture.isBroadcastIPCActive
                                HStack {
                                    Image(systemName: isBroadcastActive ? "stop.fill" : "play.fill")
                                    Text(isBroadcastActive ? "STOP MIRRORING" : "START MIRRORING")
                                        .fontWeight(.bold)
                                }
                                .font(.headline)
                                .foregroundColor(isBroadcastActive ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isBroadcastActive ? Color.red : Color.cyan)
                                .cornerRadius(16)
                                .shadow(color: (isBroadcastActive ? Color.red : Color.cyan).opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                            .background(BroadcastTriggerView().frame(width: 0, height: 0))
                        }
                        .padding(20)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))

                        
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
                        
                        // Pocket Stealth Mode Card
                        VStack(spacing: 12) {
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
                                
                                Toggle("", isOn: $stealthManager.isStealthActive)
                                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.18))
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
                        
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

class BroadcastTrigger {
    static let shared = BroadcastTrigger()
    var picker: RPSystemBroadcastPickerView?
    
    func setup() -> UIView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.preferredExtension = "pl.cayco.kovemirror.ios.broadcasts"
        picker.showsMicrophoneButton = false
        picker.alpha = 0.0
        self.picker = picker
        return picker
    }
    
    func trigger() {
        guard let picker = picker else { return }
        if let button = picker.subviews.first(where: { $0 is UIButton }) as? UIButton {
            button.sendActions(for: .touchUpInside)
        }
    }
}

struct BroadcastTriggerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        return BroadcastTrigger.shared.setup()
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
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

// MARK: - Pocket Stealth Mode Manager & Overlay

public final class PocketStealthManager: ObservableObject {
    @Published public var isStealthActive: Bool = false {
        didSet {
            updateStealthState()
        }
    }
    @Published public private(set) var isProximityCovered: Bool = false
    @Published public private(set) var originalBrightness: CGFloat = 0.5
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        UIDevice.current.isProximityMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.isProximityCovered = UIDevice.current.proximityState
                if self?.isStealthActive == true {
                    self?.updateStealthState()
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        UIDevice.current.isProximityMonitoringEnabled = false
        setSystemBrightness(originalBrightness > 0 ? originalBrightness : 0.5)
    }
    
    private func getCurrentBrightness() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            return windowScene.screen.brightness
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.screen.brightness
        }
        return UIScreen.main.brightness
    }
    
    private func setSystemBrightness(_ val: CGFloat) {
        let clamped = max(0.0, min(1.0, val))
        let apply = {
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                windowScene.screen.brightness = clamped
            } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.screen.brightness = clamped
            }
            UIScreen.main.brightness = clamped
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
    
    private func updateStealthState() {
        let apply = {
            if self.isStealthActive {
                let current = self.getCurrentBrightness()
                if current > 0.05 {
                    self.originalBrightness = current
                }
                self.setSystemBrightness(0.0)
                UIApplication.shared.isIdleTimerDisabled = true
                UIDevice.current.isProximityMonitoringEnabled = true
                Logger.shared.info("🌙 Pocket Stealth Mode ENABLED (OLED Pitch Black, Proximity Sensor Active, 2s Long-Press Lock)")
            } else {
                self.setSystemBrightness(self.originalBrightness > 0 ? self.originalBrightness : 0.5)
                UIDevice.current.isProximityMonitoringEnabled = false
                Logger.shared.info("☀️ Pocket Stealth Mode DISABLED")
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
    
    public func exitStealth() {
        isStealthActive = false
    }
}

public struct PocketStealthOverlayView: View {
    @ObservedObject var stealthManager: PocketStealthManager
    @State private var isHolding = false
    
    public init(stealthManager: PocketStealthManager) {
        self.stealthManager = stealthManager
    }
    
    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all, edges: .all)
            
            if !stealthManager.isProximityCovered {
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.cyan.opacity(isHolding ? 0.9 : 0.4))
                        .scaleEffect(isHolding ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHolding)
                    
                    Text("POCKET STEALTH MODE ACTIVE")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text(isHolding ? "Keep holding to unlock..." : "Press and hold screen for 2s to unlock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
        .statusBar(hidden: stealthManager.isStealthActive)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 2.0, perform: {
            stealthManager.exitStealth()
        }, onPressingChanged: { pressing in
            isHolding = pressing
        })
    }
}
