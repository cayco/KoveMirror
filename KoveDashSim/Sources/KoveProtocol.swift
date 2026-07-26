import Foundation
import CoreBluetooth

public enum KoveProtocol {
    // MARK: - Bluetooth LE UUIDs
    public static let serviceUUID = CBUUID(string: "0000E0FF-3C17-D293-8E48-14FE2E4DA212")
    public static let writeCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    public static let notifyCharUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
    
    // MARK: - TCP Server Ports
    public static let portControl: UInt16 = 17818
    public static let portVideo: UInt16 = 15456
    public static let portHeartbeat: UInt16 = 15457
    
    // MARK: - Packet Constants
    public static let heartbeatPacket: [UInt8] = [0x02, 0x01, 0x00, 0x00, 0x00, 0x00]
    
    public static func makePairResultJSON(success: Bool = true) -> [String: Any] {
        return [
            "msg_id": 27,
            "act": "send_pairresult",
            "result": success ? 1 : 0
        ]
    }
}
