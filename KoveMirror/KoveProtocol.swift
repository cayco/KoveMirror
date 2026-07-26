import Foundation
import CoreBluetooth

/// Protocol definitions and helper structures for Kove Motorcycle TFT Screen Mirroring
public enum KoveProtocol {
    
    // MARK: - Bluetooth LE UUIDs
    public static let serviceUUID = CBUUID(string: "0000E0FF-3C17-D293-8E48-14FE2E4DA212")
    public static let writeCharUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    public static let notifyCharUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
    public static let clientConfigUUID = CBUUID(string: "00002902-0000-1000-8000-00805F9B34FB")
    
    public static let alternativeServiceUUIDs = [
        CBUUID(string: "0000E0FF-3C17-D293-8E48-14FE2E4DA213"),
        CBUUID(string: "0000E0FF-3E17-D293-8E48-14FE2E4DA212"),
        CBUUID(string: "0000E0FF-4017-D293-8E48-14FE2E4DA212")
    ]
    
    // MARK: - TCP Server Ports
    public static let portControl: UInt16 = 17818
    public static let portVideo: UInt16 = 15456
    public static let portHeartbeat: UInt16 = 15457
    
    // MARK: - Packet Constants
    public static let magicHeader: [UInt8] = [0xEE, 0xFD]
    public static let packetFooter: UInt8 = 0xFF
    
    /// Standard 6-byte heartbeat packet used across Video & Dedicated Heartbeat sockets
    public static let heartbeatPacket: [UInt8] = [0x02, 0x01, 0x00, 0x00, 0x00, 0x00]
    
    // MARK: - BLE JSON Payloads
    
    public static func makePairRequestJSON() -> [String: Any] {
        return [
            "msg_id": 27,
            "func": "PAIR",
            "act": "get_pairinfo"
        ]
    }
    
    public static func makeVersionQueryJSON() -> [String: Any] {
        return [
            "msg_id": 13
        ]
    }
    
    public static func makeLanguageSettingJSON(language: Int = 2) -> [String: Any] {
        return [
            "msg_id": 25,
            "msg_type": 18,
            "msg_source": 2,
            "language": language
        ]
    }
    
    public static func makeClockSyncJSON(date: Date = Date(), tag: Int = -1) -> [String: Any] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: date)
        
        return [
            "msg_id": 11,
            "time": dateString,
            "tag": tag
        ]
    }
    
    public static func makeMirrorStatusJSON(enabled: Bool = true) -> [String: Any] {
        return [
            "msg_id": 25,
            "msg_type": 23,
            "msg_source": 2,
            "status": enabled ? 1 : 0
        ]
    }
    
    public static func makeRecordStatusJSON(enabled: Bool = true) -> [String: Any] {
        return [
            "msg_id": 25,
            "msg_type": 21,
            "msg_source": 2,
            "status": enabled ? 1 : 0
        ]
    }
    
    public static func makeBleHeartbeatJSON() -> [String: Any] {
        return [
            "msg_id": 25,
            "msg_type": 24,
            "msg_source": 2,
            "status": 1
        ]
    }
    
    public static func makeCarInfoQueryJSON() -> [String: Any] {
        return [
            "msg_id": 27,
            "func": "CAR_INFO",
            "act": "get_car_info"
        ]
    }
    
    public static func makeTucGetJSON() -> [String: Any] {
        return [
            "msg_id": 27,
            "func": "TUC",
            "act": "GET"
        ]
    }
    
    public static func makeInsideNaviQueryJSON(query: Int) -> [String: Any] {
        return [
            "msg_id": 27,
            "func": "INSIDENAVI",
            "query": query
        ]
    }
    
    // MARK: - Port 17818 Control Framing
    
    /// Encapsulates JSON string into Port 17818 custom framed format: [EE FD] [Length UInt32 Big-Endian] [Payload] [FF]
    public static func frameControlJSON(_ jsonString: String) -> Data {
        guard let payload = jsonString.data(using: .utf8) else { return Data() }
        let length = UInt32(payload.count)
        
        var packet = Data()
        packet.append(contentsOf: magicHeader)
        
        var bigEndianLength = length.bigEndian
        withUnsafeBytes(of: &bigEndianLength) { buffer in
            packet.append(contentsOf: buffer)
        }
        
        packet.append(payload)
        packet.append(packetFooter)
        return packet
    }
    
    /// Returns binary control handshake sequence sent on Port 17818 upon receiving TFT connection
    public static func makeBinaryControlHandshake() -> Data {
        var data = Data()
        
        // 1. Command 1 (6 bytes)
        data.append(contentsOf: [0x01, 0x01, 0x00, 0x00, 0x00, 0x00])
        
        // 2. Command 23 (10 bytes)
        data.append(contentsOf: [0x01, 0x17, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x02])
        
        // 3. Command 18 (262 bytes: 6 bytes header + 256 bytes email string padded with 0x00)
        data.append(contentsOf: [0x01, 0x12, 0x00, 0x00, 0x01, 0x00])
        var emailBytes = Array("apple@iphone.com".utf8)
        if emailBytes.count < 256 {
            emailBytes.append(contentsOf: Array(repeating: UInt8(0), count: 256 - emailBytes.count))
        } else {
            emailBytes = Array(emailBytes.prefix(256))
        }
        data.append(contentsOf: emailBytes)
        
        // 4. Command 14 (6 bytes)
        data.append(contentsOf: [0x01, 0x0E, 0x00, 0x00, 0x00, 0x00])
        
        // 5. Command 17 (6 bytes)
        data.append(contentsOf: [0x01, 0x11, 0x00, 0x00, 0x00, 0x00])
        
        return data
    }
    
    // MARK: - Port 15456 Video Header
    
    /// Generates 69-byte VideoSize header packet for Port 15456
    /// Bytes 0..64: Client name padded with 0x00 ("android")
    /// Bytes 65..66: Width in Big-Endian UInt16
    /// Bytes 67..68: Height in Big-Endian UInt16
    public static func makeVideoSizeHeader(width: UInt16, height: UInt16, clientName: String = "android") -> Data {
        var header = Data(count: 69)
        let nameBytes = Array(clientName.utf8)
        let copyLen = min(nameBytes.count, 64)
        
        // CRITICAL FIX: Byte 0 is 0x00. Client name ("android") starts at index 1
        header.replaceSubrange(1..<(1 + copyLen), with: nameBytes[0..<copyLen])
        
        let bigWidth = width.bigEndian
        let bigHeight = height.bigEndian
        
        withUnsafeBytes(of: bigWidth) { buf in
            header[65] = buf[0]
            header[66] = buf[1]
        }
        
        withUnsafeBytes(of: bigHeight) { buf in
            header[67] = buf[0]
            header[68] = buf[1]
        }
        
        return header
    }
}

