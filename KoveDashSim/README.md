# KoveDashSim 🏍️🖥️

**KoveDashSim** is a native macOS application that simulates the **Kove Motorcycle TFT Dashboard** (Kove 800X Pro / 450 Rally / 510X display). It receives and displays the high-performance H.264 video stream broadcast by the [KoveMirror](file:///Users/krzysztofkajkowski/Downloads/Kove%20iPhone/README.md) iPhone app.

---

## 🛠️ Architecture

* **Hardware-Accelerated H.264 Video Decoder**: Decodes Annex-B NAL units via `AVSampleBufferDisplayLayer` and `VideoToolbox`.
* **Multi-Port TCP Client**: Connects to iPhone TCP ports `17818` (Control), `15456` (Video Stream), and `15457` (Dedicated Heartbeat).
* **BLE GATT Peripheral**: Advertises Kove TFT service `0000E0FF-3C17-D293-8E48-14FE2E4DA212` so KoveMirror on iPhone auto-detects and connects.

---

## 🚀 Building & Running

### Command Line
```bash
cd "/Users/krzysztofkajkowski/Downloads/Kove iPhone/KoveDashSim"
swift build --scratch-path ./build
./build/debug/KoveDashSim
```

### Xcode
Open `Package.swift` in Xcode and press `Cmd + R`.
