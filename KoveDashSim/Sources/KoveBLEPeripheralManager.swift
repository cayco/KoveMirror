import Foundation
import CoreBluetooth
import Combine

public final class KoveBLEPeripheralManager: NSObject, ObservableObject {
    @Published public private(set) var isAdvertising = false
    @Published public private(set) var isCentralConnected = false
    @Published public private(set) var lastReceivedJSON: String = ""
    
    private var peripheralManager: CBPeripheralManager!
    private var writeCharacteristic: CBMutableCharacteristic?
    private var notifyCharacteristic: CBMutableCharacteristic?
    
    public var onPairRequested: (() -> Void)?
    
    override public init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }
    
    public func startAdvertising(deviceName: String = "CQKY_TFT_Dash") {
        guard peripheralManager.state == .poweredOn else {
            Logger.shared.warning("Bluetooth Peripheral Manager is not powered on")
            return
        }
        
        setupGATTService()
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: deviceName,
            CBAdvertisementDataServiceUUIDsKey: [KoveProtocol.serviceUUID]
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        Logger.shared.success("📡 BLE Peripheral Advertising Started: '\(deviceName)' [Service: \(KoveProtocol.serviceUUID)]")
    }
    
    public func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        isCentralConnected = false
        Logger.shared.info("⏹️ BLE Peripheral Advertising Stopped")
    }
    
    private func setupGATTService() {
        peripheralManager.removeAllServices()
        
        writeCharacteristic = CBMutableCharacteristic(
            type: KoveProtocol.writeCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        
        notifyCharacteristic = CBMutableCharacteristic(
            type: KoveProtocol.notifyCharUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        let service = CBMutableService(type: KoveProtocol.serviceUUID, primary: true)
        service.characteristics = [writeCharacteristic!, notifyCharacteristic!]
        
        peripheralManager.add(service)
    }
    
    public func sendPairResultNotification() {
        guard let notifyChar = notifyCharacteristic else { return }
        let dictionary = KoveProtocol.makePairResultJSON(success: true)
        
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) {
            let success = peripheralManager.updateValue(data, for: notifyChar, onSubscribedCentrals: nil)
            if success {
                Logger.shared.success("📤 BLE Notification Sent: Pair Confirm (send_pairresult)")
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension KoveBLEPeripheralManager: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.shared.info("🔵 Bluetooth LE Peripheral powered ON")
            startAdvertising()
        case .poweredOff:
            Logger.shared.error("Bluetooth LE powered OFF")
            stopAdvertising()
        default:
            break
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == KoveProtocol.notifyCharUUID {
            isCentralConnected = true
            Logger.shared.success("🔗 iPhone subscribed to GATT notifications! Ready for pairing sequence...")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == KoveProtocol.notifyCharUUID {
            isCentralConnected = false
            Logger.shared.warning("🔴 iPhone unsubscribed from GATT notifications")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                if let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.lastReceivedJSON = text
                    }
                    Logger.shared.info("📥 iPhone -> BLE: \(text)")
                    
                    if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let msgId = jsonObj["msg_id"] as? Int ?? 0
                        let funcName = jsonObj["func"] as? String ?? ""
                        let act = jsonObj["act"] as? String ?? ""
                        
                        // If iPhone sends PAIR get_pairinfo
                        if msgId == 27 && funcName == "PAIR" && act == "get_pairinfo" {
                            Logger.shared.success("🎯 Received PAIR request from iPhone! Sending pair confirm notification...")
                            sendPairResultNotification()
                            onPairRequested?()
                        }
                    }
                }
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
