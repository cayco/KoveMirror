# KoveMirror 🏍️📱

**KoveMirror** is an open-source iOS application designed for **Kove motorcycle TFT dashboards** (Kove 800X Pro / 450 Rally / 510X / etc.). It enables high-performance wireless screen mirroring of navigation apps (Google Maps, Waze, Scenic, OsmAnd) onto the motorcycle's dashboard display.

---

## 🌟 Key Features

* **H.264 Baseline 3.1 Video Streaming**: Tailored specifically for low-latency embedded Linux TFT decoders (Carbit Link / EasyConnection protocol).
* **System-Wide Screen Broadcasting**: Uses an iOS ReplayKit Broadcast Upload Extension to stream any active app on your iPhone directly to the dashboard.
* **BLE GATT Handshake**: Automatically pairs with the motorcycle display over Bluetooth Low Energy to initiate connection and WiFi AP setup.
* **Multi-Port TCP Socket Server**: Implements control (`17818`), video (`15456`), and heartbeat (`15457`) servers to maintain a stable, non-disconnecting stream.
* **Telemetry & Diagnostic Logging**: Real-time stats for encoding frame rate (FPS), total MB transferred, BLE status, and port connectivity.

---

## 🚀 Quick Setup & Usage Guide

1. **Start Connection in App**:
   * Turn on your Kove motorcycle TFT display.
   * Connect your iPhone to the motorcycle's Wi-Fi network (`CQKY_XXXXXXXX`).
   * Launch **KoveMirror** and tap **START MIRRORING**.
   * On the motorcycle handlebar, **long-press the SET button** -> select **Start Navigation**. The TFT display will connect to Video Port `15456`.

2. **Launch Google Maps / Waze Screen Broadcast**:
   * Swipe down from the top right corner of your iPhone to open **Control Center**.
   * Long-press the **Screen Recording** button (🔴).
   * Select **KoveMirror Broadcast** and tap **Start Broadcast**.
   * Open **Google Maps**, **Waze**, **Scenic**, or **OsmAnd** — your navigation map will now project live onto the TFT display!

---

## 🛠️ Architecture & Protocol Specifications

* **BLE GATT Service**: `0000E0FF-3C17-D293-8E48-14FE2E4DA212`
* **TCP Control Server**: Port `17818` (Framed JSON & Binary Handshake)
* **TCP Video Server**: Port `15456` (69-byte `android` VideoSize Header + Annex-B H.264 stream)
* **TCP Heartbeat Server**: Port `15457` (200ms periodic keep-alive)

---

## 📄 License

MIT License. Free to use and modify for motorcycle enthusiasts.
