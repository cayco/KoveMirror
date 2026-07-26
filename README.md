# KoveMirror 🏍️📱

**KoveMirror** is an open-source iOS application designed for **Kove motorcycle TFT dashboards** (Kove 800X Pro / 450 Rally / 510X / etc.). It enables high-performance, low-latency wireless screen mirroring of navigation apps (Google Maps, Waze, Scenic, OsmAnd) directly onto the motorcycle's TFT display.

---

## 🌟 Key Features & Updates

* **H.264 Baseline 3.1 CAVLC Hardware Video Encoding**: Custom-tuned for low-latency embedded Linux TFT decoders (Carbit Link / EasyConnection motorcycle protocol).
* **System-Wide Screen Broadcasting**: Uses a high-performance iOS ReplayKit Broadcast Upload Extension to capture and stream any navigation app on your iPhone.
* **GPU Hardware Downscaling**: Downscales full-resolution iPhone screen buffers to the target TFT display resolution (480×800) using `VTPixelTransferSession` before IPC transfer, keeping extension memory footprint under iOS 50 MB limits.
* **Pocket Stealth Mode & OLED Power Dimming**: Reduces OLED display brightness to 0% with proximity sensor lockout, preventing accidental pocket touches while saving battery and lowering thermal load.
* **BLE GATT & Multi-Port TCP Handshake**: Automatically pairs with the motorcycle over Bluetooth Low Energy, syncing clocks and starting control (`17818`), video (`15456`), and heartbeat (`15457`) TCP servers.
* **macOS Dashboard Simulator (`KoveDashSim`)**: Includes a native macOS TFT simulator for testing screen casting without needing the physical motorcycle.

---

## 📺 How Screen Casting Works

Screen projection follows a multi-stage hardware and network pipeline:

```
+------------------------------------+        +-----------------------------------+        +-----------------------------------+
|  iPhone Screen (Maps / Waze)       | -----> | ReplayKit Broadcast Extension     | -----> | KoveMirror Host App               |
|  Native Resolution (e.g. 1179x2556)|        | VTPixelTransferSession (480x800)  | IPC    | VideoToolbox H.264 Encoder        |
+------------------------------------+        +-----------------------------------+        +-----------------------------------+
                                                                                                             | TCP Port 15456
                                                                                                             v
                                                                                           +-----------------------------------+
                                                                                           | Motorcycle TFT Display (Carbit)   |
                                                                                           | Embedded Linux H.264 Decoder      |
                                                                                           +-----------------------------------+
```

1. **ReplayKit Capture & GPU Scaling**: When system broadcast is started from Control Center, `SampleHandler` captures native screen sample buffers. A `VTPixelTransferSession` hardware-downscales frames to 480×800 (1.53 MB per frame) using GPU hardware acceleration.
2. **Loopback IPC Transfer**: Scaled frames are sent over a local TCP loopback IPC socket (`127.0.0.1:19890`) to the host app. `ScreenCaptureManager` receives payload buffers using a chunked 64 KB accumulator loop to prevent network buffer drops.
3. **VideoToolbox Hardware Encoding**: The host app compresses frames into raw Annex-B H.264 NAL units using `VTCompressionSession` configured for **H.264 Baseline Profile Level 3.1** and **CAVLC entropy mode** (embedded motorcycle SoCs do not support CABAC). SPS and PPS parameters are prepended to every IDR keyframe.
4. **TCP Port 15456 Handshake**: When the TFT connects to Video Port 15456, the phone transmits a **69-byte `VideoSize` header** (byte `0` = `0x00`, `"android"` starting at byte index `1`, followed by big-endian width and height). H.264 video data is then streamed continuously to the TFT display.

---

## 🌙 Pocket Stealth Mode & Display Dimming

When riding with your iPhone stored in your pocket or tank bag, **Pocket Stealth Mode** protects battery life and prevents device overheating:

* **0% OLED Display Brightness**: Dims the iPhone screen pitch black while the TFT display continues streaming navigation video uninterrupted.
* **Pocket Proximity Lockout**: Integrates iOS `UIDevice.current.proximityState`. While inside a pocket or bag (proximity sensor covered), **all touch events are strictly ignored**, preventing fabric rubs or accidental bumps from waking the screen.
* **Double-Tap to Wake**: Once removed from your pocket or bag (proximity sensor clear), a deliberate **Double-Tap** anywhere on the black screen immediately deactivates Stealth Mode and restores display brightness.

---

## 🖥️ macOS TFT Dashboard Simulator (`KoveDashSim`)

If you want to test screen mirroring without going to your motorcycle, use the included **`KoveDashSim`** macOS application:

```
                  +-----------------------+
                  |  macOS KoveDashSim    |
                  |  TFT Dashboard View   |
                  +-----------------------+
                    ^         ^         ^
       BLE GATT     |         |         | Dedicated Heartbeat (15457)
    Advertisement   |         | Video   | 
  (0000E0FF-...)    |         | (15456) |
                    |         |         |
                  +-----------------------+
                  |    iPhone KoveMirror  |
                  +-----------------------+
```

### Features of `KoveDashSim`:
* Advertises the official Kove BLE GATT Service (`0000E0FF-3C17-D293-8E48-14FE2E4DA212`) over your Mac's Bluetooth.
* Connects to iPhone TCP ports `17818`, `15456`, and `15457`.
* Decodes incoming H.264 Annex-B NAL streams in real-time using `AVSampleBufferDisplayLayer` and displays a live 480×800 motorcycle dashboard interface.

### How to Run `KoveDashSim`:

#### Option A: Quick Script (Terminal)
```bash
cd KoveDashSim
./run.sh
```

#### Option B: Swift Package Manager
```bash
cd KoveDashSim
swift run
```

#### Option C: Xcode
Open `KoveDashSim/Package.swift` in Xcode and press `Cmd + R` to run.

---

## 🚀 Quick Setup & Usage Guide for iPhone

1. **Launch App & Start Mirroring**:
   * Turn on your Kove motorcycle TFT display (or launch `KoveDashSim` on your Mac).
   * Connect iPhone to the motorcycle's Wi-Fi network (`CQKY_XXXXXXXX`).
   * Launch **KoveMirror** on your iPhone and tap **START MIRRORING**.
   * On the motorcycle handlebar, **long-press the SET button** -> select **Start Navigation**. The TFT display will connect to Video Port `15456`.

2. **Launch Navigation Broadcast**:
   * Swipe down from the top right corner of your iPhone to open **Control Center**.
   * Long-press the **Screen Recording** button (🔴).
   * Select **KoveMirror Broadcast** and tap **Start Broadcast**.
   * Open **Google Maps**, **Waze**, **Scenic**, or **OsmAnd** — your live map will project directly onto the motorcycle display!

---

## 🛠️ Architecture & Protocol Specifications

* **BLE GATT Service**: `0000E0FF-3C17-D293-8E48-14FE2E4DA212`
* **TCP Control Server**: Port `17818` (Framed JSON & Binary Handshake)
* **TCP Video Server**: Port `15456` (69-byte `VideoSize` Header + Annex-B H.264 CAVLC stream)
* **TCP Dedicated Heartbeat Server**: Port `15457` (200ms periodic keep-alive)

---

## 📄 License

MIT License. Free to use and modify for motorcycle enthusiasts.
