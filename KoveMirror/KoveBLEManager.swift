import Foundation
import CoreBluetooth
import Combine

public final class KoveBLEManager: NSObject, ObservableObject {
    @Published public private(set) var isScanning = false
    @Published public private(set) var isConnected = false
    @Published public private(set) var peripheralName: String? = nil
    @Published public private(set) var discoveredPeripherals: [CBPeripheral] = []
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private var sendQueue: [Data] = []
    private var isProcessingQueue = false
    private var heartbeatTimer: Timer?
    
    public var onMirrorRequested: (() -> Void)?
    public var targetMacAddress: String?
    
    override public init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - Public Controls
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            Logger.shared.warning("Bluetooth is not powered on")
            return
        }
        
        discoveredPeripherals.removeAll()
        isScanning = true
        Logger.shared.info("🔵 Starting BLE scan for Kove motorcycle TFT...")
        
        // Scan for known Kove service UUIDs and open scan if needed
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    public func stopScanning() {
        isScanning = false
        centralManager.stopScan()
        Logger.shared.info("⏹️ BLE scan stopped")
    }
    
    public func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        Logger.shared.info("🔗 Connecting to BLE peripheral: \(peripheral.name ?? "Unknown Device") (\(peripheral.identifier.uuidString))...")
        centralManager.connect(peripheral, options: nil)
    }
    
    public func disconnect() {
        stopHeartbeat()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        isConnected = false
        peripheralName = nil
        Logger.shared.warning("🔴 BLE connection terminated")
    }
    
    public func sendJSON(_ dictionary: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            sendRaw(data)
        } catch {
            Logger.shared.error("Failed to serialize BLE JSON: \(error.localizedDescription)")
        }
    }
    
    public func sendRaw(_ data: Data) {
        sendQueue.append(data)
        if !isProcessingQueue {
            isProcessingQueue = true
            processNextQueueItem()
        }
    }
    
    private func processNextQueueItem() {
        guard !sendQueue.isEmpty else {
            isProcessingQueue = false
            return
        }
        
        let data = sendQueue.removeFirst()
        guard let peripheral = connectedPeripheral, let char = writeCharacteristic else {
            Logger.shared.warning("BLE write failed: Peripheral or characteristic not ready")
            isProcessingQueue = false
            return
        }
        
        peripheral.writeValue(data, for: char, type: .withoutResponse)
        
        // Pace writes by 120ms to prevent BLE throughput saturation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.processNextQueueItem()
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.sendJSON(KoveProtocol.makeBleHeartbeatJSON())
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    // MARK: - Handshake Sequence
    
    private func sendInitPackets() {
        Logger.shared.info("📤 Sending BLE initialization sequence...")
        
        // 1. Pair request
        sendJSON(KoveProtocol.makePairRequestJSON())
        
        // 2. Version request
        sendJSON(KoveProtocol.makeVersionQueryJSON())
        
        // 3. Language configuration
        sendJSON(KoveProtocol.makeLanguageSettingJSON())
        
        // 4. Clock sync
        sendJSON(KoveProtocol.makeClockSyncJSON())
    }
}

// MARK: - CBCentralManagerDelegate

extension KoveBLEManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            Logger.shared.success("Bluetooth is powered ON")
            startScanning()
        case .poweredOff:
            Logger.shared.error("Bluetooth is powered OFF")
            disconnect()
        case .unauthorized:
            Logger.shared.error("Bluetooth permission unauthorized")
        case .unsupported:
            Logger.shared.error("Bluetooth is unsupported on this device")
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
        
        // Auto connect if device name starts with CQKY or Kove or matches target MAC/UUID
        if name.contains("CQKY") || name.localizedCaseInsensitiveContains("kove") || name.localizedCaseInsensitiveContains("thinker") {
            Logger.shared.success("🎯 Found Kove TFT Device: \(name) [RSSI: \(RSSI) dBm]. Connecting automatically...")
            connect(to: peripheral)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheralName = peripheral.name ?? "Kove TFT"
        Logger.shared.success("🟢 Connected to BLE peripheral \(peripheralName!). Discovering GATT services...")
        
        peripheral.discoverServices([KoveProtocol.serviceUUID] + KoveProtocol.alternativeServiceUUIDs)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        Logger.shared.error("❌ Failed to connect to BLE peripheral: \(error?.localizedDescription ?? "Unknown error")")
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        stopHeartbeat()
        Logger.shared.warning("🔴 Disconnected from BLE peripheral: \(error?.localizedDescription ?? "Normal disconnect")")
    }
}

// MARK: - CBPeripheralDelegate

extension KoveBLEManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            Logger.shared.error("Error discovering GATT services: \(error?.localizedDescription ?? "None")")
            return
        }
        
        for service in services {
            Logger.shared.info("🔍 Discovered BLE Service: \(service.uuid)")
            peripheral.discoverCharacteristics([KoveProtocol.writeCharUUID, KoveProtocol.notifyCharUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            Logger.shared.error("Error discovering characteristics for service \(service.uuid): \(error?.localizedDescription ?? "")")
            return
        }
        
        for char in characteristics {
            Logger.shared.info("   -> Characteristic: \(char.uuid) (Properties: \(char.properties.rawValue))")
            
            if char.uuid == KoveProtocol.writeCharUUID {
                writeCharacteristic = char
            } else if char.uuid == KoveProtocol.notifyCharUUID {
                notifyCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                Logger.shared.success("🔓 Enabled notifications on GATT characteristic \(char.uuid)")
            }
        }
        
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            Logger.shared.success("✅ GATT handshake parameters acquired. Sending init sequence...")
            sendInitPackets()
            startHeartbeat()
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        
        if let text = String(data: data, encoding: .utf8) {
            Logger.shared.info("📥 TFT -> BLE: \(text)")
            
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let msgId = jsonObj["msg_id"] as? Int ?? 0
                let act = jsonObj["act"] as? String ?? ""
                let result = jsonObj["result"] as? Int ?? 0
                
                // Pair result handler
                if msgId == 27 && act == "send_pairresult" && result == 1 {
                    Logger.shared.success("✅ Pairing confirmed by TFT! Activating mirror status...")
                    onMirrorRequested?()
                    
                    sendJSON(KoveProtocol.makeMirrorStatusJSON(enabled: true))
                    sendJSON(KoveProtocol.makeRecordStatusJSON(enabled: true))
                    sendJSON(KoveProtocol.makeCarInfoQueryJSON())
                }
            }
        } else {
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            Logger.shared.data("📥 TFT -> BLE (Hex): \(hex)")
        }
    }
}
