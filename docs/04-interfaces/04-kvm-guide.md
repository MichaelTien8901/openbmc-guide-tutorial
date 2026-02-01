---
layout: default
title: KVM Guide
parent: Interfaces
nav_order: 4
difficulty: advanced
prerequisites:
  - redfish-guide
  - webui-guide
---

# KVM Guide
{: .no_toc }

Configure remote keyboard, video, and mouse access on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**KVM (Keyboard, Video, Mouse)** provides remote graphical console access to the host system, allowing operators to interact with the system as if they were physically present. OpenBMC implements KVM through **obmc-ikvm**.

```
┌─────────────────────────────────────────────────────────────────┐
│                       KVM Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      Browser/Client                         ││
│  │                                                             ││
│  │   ┌──────────────────────────────────────────────────────┐  ││
│  │   │     noVNC (JavaScript VNC Client)                    │  ││
│  │   │                                                      │  ││
│  │   │   Video Display  │  Keyboard Input  │  Mouse Input   │  ││
│  │   └──────────────────────────────────────────────────────┘  ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│                     WebSocket / TCP:5900                        │
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                        bmcweb                               ││
│  │                  (WebSocket proxy)                          ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                       obmc-ikvm                             ││
│  │                                                             ││
│  │   ┌─────────────────┐  ┌─────────────────┐                  ││
│  │   │  Video Capture  │  │  USB HID Gadget │                  ││
│  │   │  (JPEG/ASTC)    │  │  (Keyboard/Mouse│                  ││
│  │   └────────┬────────┘  └────────┬────────┘                  ││
│  └────────────┼────────────────────┼───────────────────────────┘│
│               │                    │                            │
│  ┌────────────┴────────┐  ┌────────┴────────┐                   │
│  │  Video Capture HW   │  │   USB Device    │                   │
│  │  (ASPEED/Nuvoton)   │  │   Controller    │                   │
│  └─────────────────────┘  └─────────────────┘                   │
│               │                    │                            │
│               └────────┬───────────┘                            │
│                        │                                        │
│  ┌─────────────────────┴───────────────────────────────────────┐│
│  │                    Host System                              ││
│  │              (VGA output, USB ports)                        ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Hardware Requirements

### Video Capture

KVM requires hardware video capture capability:

| BMC SoC | Video Capture | Compression |
|---------|---------------|-------------|
| ASPEED AST2500/2600 | VGA capture engine | JPEG, ASPEED proprietary |
| Nuvoton NPCM7xx | GFX capture | JPEG |

### USB Device Controller

For keyboard/mouse input:

| BMC SoC | USB Controller | Gadget Support |
|---------|----------------|----------------|
| ASPEED AST2500/2600 | USB 2.0 device | HID gadget |
| Nuvoton NPCM7xx | USB device | HID gadget |

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include KVM support
IMAGE_INSTALL:append = " obmc-ikvm"

# Enable KVM in bmcweb
EXTRA_OEMESON:pn-bmcweb = " \
    -Dkvm=enabled \
"

# For ASPEED-based systems
PREFERRED_PROVIDER_virtual/obmc-host-ipmi-hw = "phosphor-ipmi-kcs"
MACHINE_FEATURES:append = " obmc-ikvm"
```

### bmcweb KVM Options

| Option | Default | Description |
|--------|---------|-------------|
| `kvm` | enabled | Enable KVM WebSocket support |
| `insecure-kvm-auth` | disabled | Allow unauthenticated KVM (testing only) |

### Device Tree Configuration

ASPEED systems require video capture configuration:

```dts
// Device tree snippet for AST2500/2600
&video {
    status = "okay";
    memory-region = <&video_memory>;
};

&gfx {
    status = "okay";
    memory-region = <&gfx_memory>;
};
```

### Runtime Configuration

```bash
# Check obmc-ikvm service
systemctl status obmc-ikvm

# View KVM logs
journalctl -u obmc-ikvm -f

# Restart KVM service
systemctl restart obmc-ikvm
```

---

## Accessing KVM

### Via WebUI

1. Login to WebUI at `https://<bmc-ip>/`
2. Navigate to **Operations** → **KVM Console**
3. Click **Open in new tab** or use embedded viewer
4. Interact with host display, keyboard, and mouse

### Via Direct noVNC

```bash
# Access noVNC directly (if exposed)
https://<bmc-ip>/kvm/0

# Or via Redfish link
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc
# Look for GraphicalConsole link
```

### Via VNC Client

For direct VNC client access (if enabled):

```bash
# Connect with VNC viewer
vncviewer bmc-ip:5900

# With password (if configured)
vncviewer -passwd ~/.vnc/passwd bmc-ip:5900
```

---

## Configuration Options

### Video Quality Settings

```bash
# Video quality is typically controlled via obmc-ikvm configuration
# Check available options
obmc-ikvm --help

# Common options:
# -f framerate    : Target frame rate
# -q quality      : JPEG quality (1-100)
# -r resolution   : Force resolution
```

### USB HID Configuration

```bash
# USB HID gadget is typically auto-configured
# Check USB gadget status
ls /sys/kernel/config/usb_gadget/

# Verify HID devices
ls /dev/hidg*
```

### Session Limits

Configure via bmcweb:

```cpp
// In bmcweb configuration
// Maximum concurrent KVM sessions (typically 1-2)
static constexpr size_t maxKvmSessions = 2;
```

---

## Power State Considerations

### KVM Availability by State

| Host Power State | Video Capture | KVM Available |
|------------------|---------------|---------------|
| Off | No output | Blank screen |
| On (POST) | BIOS output | Yes |
| On (OS) | OS display | Yes |
| Sleep | May blank | Limited |

### BIOS/UEFI Configuration

For best KVM experience, configure host BIOS:

1. **Set video output** to onboard/BMC VGA
2. **Disable** GPU priority if using external graphics
3. **Enable** legacy VGA for BIOS screens

---

## Input Handling

### Keyboard Mapping

```
Client Keyboard → noVNC → bmcweb WebSocket → obmc-ikvm → USB HID → Host
```

Common key mappings:

| Client Key | Host Key | Notes |
|------------|----------|-------|
| Ctrl+Alt+Del | Ctrl+Alt+Del | Captured by noVNC |
| F1-F12 | F1-F12 | Pass through |
| Alt+Tab | Alt+Tab | May be captured locally |
| Print Screen | Print Screen | Pass through |

### Special Key Combinations

Access via noVNC toolbar or keyboard shortcuts:

- **Ctrl+Alt+Delete**: Send to remote
- **Ctrl+Alt+F1-F6**: Virtual terminal switch (Linux)
- **Windows Key**: May need special handling

### Mouse Configuration

```bash
# Mouse is typically absolute positioning
# If relative mode needed, configure in obmc-ikvm

# Check mouse mode
cat /sys/class/usb_role/*/role
```

---

## Troubleshooting

### No Video Display

```bash
# Check video capture hardware
ls /dev/video*

# Check video capture service
systemctl status obmc-ikvm

# View video device info
v4l2-ctl --all

# Check memory regions
cat /proc/iomem | grep -i video
```

### Black Screen

```bash
# Verify host is powered on
obmcutil state

# Check if host is generating video
# May need to check VGA cable connection

# Try resetting video capture
systemctl restart obmc-ikvm
```

### Keyboard/Mouse Not Working

```bash
# Check USB HID gadget
ls /dev/hidg*

# Verify USB connection to host
# Check host BIOS for USB settings

# Reload USB gadget
modprobe -r g_hid
modprobe g_hid
```

### Connection Drops

```bash
# Check bmcweb WebSocket
journalctl -u bmcweb | grep -i kvm

# Check network connectivity
ping bmc-ip

# Verify KVM session count
# Too many sessions may cause issues
```

### Performance Issues

```bash
# Reduce quality for bandwidth
# Adjust frame rate
# Check network latency

# Monitor bandwidth usage
iftop -i eth0
```

---

## Security Considerations

### Authentication

KVM access requires Redfish authentication:

```bash
# KVM WebSocket is authenticated via session token
# Ensure strong passwords for KVM users

# Create operator account for KVM
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "UserName": "kvmuser",
        "Password": "SecurePass123!",
        "RoleId": "Operator"
    }' \
    https://localhost/redfish/v1/AccountService/Accounts
```

### Session Management

```bash
# View active sessions
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/SessionService/Sessions

# Terminate KVM session (close WebSocket)
# Sessions auto-terminate on browser close
```

### Encryption

All KVM traffic is encrypted via HTTPS/WSS:

```
Browser ←→ bmcweb: TLS 1.2/1.3
```

---

## Enabling/Disabling KVM

### Build-Time Disable

```bitbake
# Remove KVM from build
EXTRA_OEMESON:pn-bmcweb = " \
    -Dkvm=disabled \
"
IMAGE_INSTALL:remove = "obmc-ikvm"
```

### Runtime Disable

```bash
# Stop KVM service
systemctl stop obmc-ikvm
systemctl disable obmc-ikvm

# Re-enable
systemctl enable obmc-ikvm
systemctl start obmc-ikvm
```

---

## Deep Dive
{: .text-delta }

Advanced implementation details for KVM developers.

### Video Capture Pipeline

```
┌────────────────────────────────────────────────────────────────────────────┐
│                      Video Capture Processing Pipeline                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  HOST VGA OUTPUT                                                           │
│  ───────────────                                                           │
│        │                                                                   │
│        │ Analog VGA signals (R, G, B, HSync, VSync)                        │
│        v                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ASPEED Video Engine (AST2500/2600)                                 │   │
│  │                                                                     │   │
│  │  1. ADC Capture                                                     │   │
│  │     ─────────────                                                   │   │
│  │     VGA signals → 10-bit ADC sampling                               │   │
│  │     Sync detection → resolution/timing auto-detect                  │   │
│  │                                                                     │   │
│  │  2. Frame Buffer                                                    │   │
│  │     ────────────                                                    │   │
│  │     Raw pixels → Video memory (shared with ARM)                     │   │
│  │     Format: RGB565 or RGB888                                        │   │
│  │     Memory region: /dev/mem or videobuf2                            │   │
│  │                                                                     │   │
│  │  3. Hardware JPEG Encoder (Optional)                                │   │
│  │     ────────────────────────────────                                │   │
│  │     Full frame → DCT → Quantization → Huffman → JPEG stream         │   │
│  │     Or: Software compression via libjpeg-turbo                      │   │
│  └────────────────────────────────────────────────────────────────────-┘   │
│        │                                                                   │
│        │ /dev/video0 (V4L2 interface)                                      │
│        v                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  obmc-ikvm Video Processing                                         │   │
│  │                                                                     │   │
│  │  Frame Capture Loop:                                                │   │
│  │  ─────────────────────                                              │   │
│  │  while (running) {                                                  │   │
│  │      // 1. Dequeue buffer from V4L2                                 │   │
│  │      ioctl(fd, VIDIOC_DQBUF, &buf);                                 │   │
│  │                                                                     │   │
│  │      // 2. Check for frame changes (dirty detection)                │   │
│  │      if (memcmp(current_frame, last_frame, size) != 0) {            │   │
│  │          // 3. Compress changed regions                             │   │
│  │          jpeg_data = compress_jpeg(current_frame, quality);         │   │
│  │                                                                     │   │
│  │          // 4. Send via RFB protocol                                │   │
│  │          send_rfb_update(jpeg_data);                                │   │
│  │      }                                                              │   │
│  │                                                                     │   │
│  │      // 5. Requeue buffer                                           │   │
│  │      ioctl(fd, VIDIOC_QBUF, &buf);                                  │   │
│  │  }                                                                  │   │
│  │                                                                     │   │
│  │  Compression Options:                                               │   │
│  │    - JPEG (quality 10-100, typical 50-80)                           │   │
│  │    - Raw (no compression, high bandwidth)                           │   │
│  │    - Tight encoding with zlib                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### RFB (VNC) Protocol Frame Updates

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        RFB Protocol Frame Updates                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  VNC (RFB) PROTOCOL MESSAGE FLOW                                           │
│  ───────────────────────────────                                           │
│                                                                            │
│  Client (noVNC)                            Server (obmc-ikvm)              │
│       │                                           │                        │
│       │  FramebufferUpdateRequest                 │                        │
│       │  ┌─────────────────────────┐              │                        │
│       │  │ message-type: 3         │              │                        │
│       │  │ incremental: 1          │              │                        │
│       │  │ x: 0, y: 0              │              │                        │
│       │  │ width: 1920             │              │                        │
│       │  │ height: 1080            │              │                        │
│       │  └─────────────────────────┘              │                        │
│       │────────────────────────────────────────-->│                        │
│       │                                           │                        │
│       │                                           │ Capture frame          │
│       │                                           │ Detect changes         │
│       │                                           │ Compress regions       │
│       │                                           │                        │
│       │              FramebufferUpdate            │                        │
│       │  ┌─────────────────────────────────────┐  │                        │
│       │  │ message-type: 0                     │  │                        │
│       │  │ number-of-rectangles: 2             │  │                        │
│       │  │                                     │  │                        │
│       │  │ Rectangle 1 (changed region):       │  │                        │
│       │  │   x: 100, y: 200                    │  │                        │
│       │  │   width: 400, height: 300           │  │                        │
│       │  │   encoding: JPEG (21)               │  │                        │
│       │  │   data: [compressed JPEG bytes]     │  │                        │
│       │  │                                     │  │                        │
│       │  │ Rectangle 2 (cursor update):        │  │                        │
│       │  │   encoding: Cursor (-239)           │  │                        │
│       │  │   data: [cursor bitmap + mask]      │  │                        │
│       │  └─────────────────────────────────────┘  │                        │
│       │<──────────────────────────────────────────│                        │
│       │                                           │                        │
│                                                                            │
│  ENCODING TYPES SUPPORTED:                                                 │
│  ─────────────────────────                                                 │
│                                                                            │
│  │ Encoding    │ ID   │ Description                              │         │
│  │─────────────│──────│──────────────────────────────────────────│         │
│  │ Raw         │ 0    │ Uncompressed pixels (RGB888/RGB565)      │         │
│  │ CopyRect    │ 1    │ Copy from another screen region          │         │
│  │ RRE         │ 2    │ Rise and Run length Encoding             │         │
│  │ Hextile     │ 5    │ 16x16 tile-based compression             │         │
│  │ ZRLE        │ 16   │ Zlib Run-Length Encoding                 │         │
│  │ Tight       │ 7    │ Tight compression with JPEG option       │         │
│  │ JPEG        │ 21   │ JPEG-compressed rectangle                │         │
│  │ Cursor      │ -239 │ Client-side cursor rendering             │         │
│  │ DesktopSize │ -223 │ Desktop size change notification         │         │
│                                                                            │
│  TIGHT ENCODING WITH JPEG (commonly used):                                 │
│  ─────────────────────────────────────────                                 │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Tight Compression Control Byte:                                    │   │
│  │  ┌───┬───┬───┬───┬───┬───┬───┬───┐                                  │   │
│  │  │ 7 │ 6 │ 5 │ 4 │ 3 │ 2 │ 1 │ 0 │                                  │   │
│  │  └───┴───┴───┴───┴───┴───┴───┴───┘                                  │   │
│  │    │   │   │   │   │   └───┴───┴─── zlib stream reset flags         │   │
│  │    │   │   │   └───┴────────────── fill mode / filter               │   │
│  │    └───┴───┴────────────────────── compression type                 │   │
│  │         0x09 = JPEG compression                                     │   │
│  │         0x00-0x07 = Basic compression                               │   │
│  │                                                                     │   │
│  │  JPEG Quality Level:                                                │   │
│  │    -23 to -32 pseudo-encoding sets quality 0-9 (maps to 5-95%)      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### USB HID Gadget Protocol

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        USB HID Gadget Implementation                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  USB HID GADGET SETUP                                                      │
│  ────────────────────                                                      │
│                                                                            │
│  /sys/kernel/config/usb_gadget/kvm_gadget/                                 │
│  ├── idVendor              # 0x1d6b (Linux Foundation)                     │
│  ├── idProduct             # 0x0104 (Multifunction Composite Gadget)       │
│  ├── bcdDevice             # 0x0100                                        │
│  ├── bcdUSB                # 0x0200 (USB 2.0)                              │
│  ├── strings/0x409/                                                        │
│  │   ├── serialnumber      # BMC serial                                    │
│  │   ├── manufacturer      # OpenBMC                                       │
│  │   └── product           # Virtual KVM                                   │
│  ├── configs/c.1/                                                          │
│  │   ├── MaxPower          # 500 (mA)                                      │
│  │   ├── hid.keyboard -> functions/hid.keyboard                            │
│  │   └── hid.mouse -> functions/hid.mouse                                  │
│  └── functions/                                                            │
│      ├── hid.keyboard/                                                     │
│      │   ├── protocol      # 1 (Keyboard)                                  │
│      │   ├── subclass      # 1 (Boot Interface)                            │
│      │   ├── report_length # 8                                             │
│      │   └── report_desc   # HID Report Descriptor (binary)                │
│      └── hid.mouse/                                                        │
│          ├── protocol      # 2 (Mouse)                                     │
│          ├── subclass      # 1 (Boot Interface)                            │
│          ├── report_length # 6                                             │
│          └── report_desc   # HID Report Descriptor (binary)                │
│                                                                            │
│  KEYBOARD HID REPORT FORMAT (8 bytes):                                     │
│  ─────────────────────────────────────                                     │
│                                                                            │
│  ┌─────────┬─────────┬────────┬────────┬────────┬────────┬────────┬────────┐
│  │ Byte 0  │ Byte 1  │ Byte 2 │ Byte 3 │ Byte 4 │ Byte 5 │ Byte 6 │ Byte 7 │
│  ├─────────┼─────────┼────────┼────────┼────────┼────────┼────────┼────────┤
│  │Modifier │Reserved │ Key 1  │ Key 2  │ Key 3  │ Key 4  │ Key 5  │ Key 6  │
│  │ Flags   │  (0x00) │        │        │        │        │        │        │
│  └─────────┴─────────┴────────┴────────┴────────┴────────┴────────┴────────┘
│                                                                            │
│  Modifier Flags (Byte 0):                                                  │
│    Bit 0: Left Ctrl     Bit 4: Right Ctrl                                  │
│    Bit 1: Left Shift    Bit 5: Right Shift                                 │
│    Bit 2: Left Alt      Bit 6: Right Alt                                   │
│    Bit 3: Left GUI      Bit 7: Right GUI (Windows key)                     │
│                                                                            │
│  Example: Ctrl+Alt+Delete                                                  │
│    [0x05, 0x00, 0x4C, 0x00, 0x00, 0x00, 0x00, 0x00]                        │
│    0x05 = Left Ctrl (0x01) + Left Alt (0x04)                               │
│    0x4C = Delete key scancode                                              │
│                                                                            │
│  MOUSE HID REPORT FORMAT (6 bytes - Absolute):                             │
│  ────────────────────────────────────────────                              │
│                                                                            │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐             │
│  │ Byte 0  │ Byte 1  │ Byte 2  │ Byte 3  │ Byte 4  │ Byte 5  │             │
│  ├─────────┼─────────┼─────────┼─────────┼─────────┼─────────┤             │
│  │ Buttons │  X Low  │ X High  │  Y Low  │ Y High  │ Wheel   │             │
│  └─────────┴─────────┴─────────┴─────────┴─────────┴─────────┘             │
│                                                                            │
│  Buttons (Byte 0):                                                         │
│    Bit 0: Left button    Bit 2: Middle button                              │
│    Bit 1: Right button   Bits 3-7: Reserved                                │
│                                                                            │
│  X/Y: 16-bit absolute position (0-32767 maps to screen)                    │
│  Wheel: Signed 8-bit scroll delta                                          │
│                                                                            │
│  WRITING TO HID DEVICE:                                                    │
│  ──────────────────────                                                    │
│                                                                            │
│  // Send keyboard report                                                   │
│  int fd = open("/dev/hidg0", O_WRONLY);                                    │
│  uint8_t report[8] = {0x05, 0, 0x4C, 0, 0, 0, 0, 0};  // Ctrl+Alt+Del      │
│  write(fd, report, sizeof(report));                                        │
│                                                                            │
│  // Key release                                                            │
│  memset(report, 0, sizeof(report));                                        │
│  write(fd, report, sizeof(report));                                        │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### WebSocket to VNC Bridge

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    bmcweb KVM WebSocket Implementation                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  WEBSOCKET CONNECTION ESTABLISHMENT                                        │
│  ─────────────────────────────────                                         │
│                                                                            │
│  Browser                      bmcweb                      obmc-ikvm        │
│     │                           │                             │            │
│     │  GET /kvm/0               │                             │            │
│     │  Upgrade: websocket       │                             │            │
│     │  Sec-WebSocket-Protocol:  │                             │            │
│     │    binary                 │                             │            │
│     │──────────────────────────>│                             │            │
│     │                           │                             │            │
│     │  HTTP/1.1 101 Switching   │                             │            │
│     │  Connection: Upgrade      │                             │            │
│     │  Sec-WebSocket-Accept:    │                             │            │
│     │    [calculated hash]      │                             │            │
│     │<──────────────────────────│                             │            │
│     │                           │                             │            │
│     │  [WebSocket Binary Frame] │  Unix Socket                │            │
│     │  RFB Protocol Version     │  /var/run/obmc-ikvm.sock    │            │
│     │<─────────────────────────>│<───────────────────────────>│            │
│     │                           │                             │            │
│                                                                            │
│  BMCWEB KVM HANDLER (kvm.hpp):                                             │
│  ─────────────────────────────                                             │
│                                                                            │
│  void handleKvmWebSocket(crow::websocket::Connection& conn) {              │
│      // 1. Connect to obmc-ikvm Unix socket                                │
│      int sock = socket(AF_UNIX, SOCK_STREAM, 0);                           │
│      struct sockaddr_un addr;                                              │
│      addr.sun_family = AF_UNIX;                                            │
│      strncpy(addr.sun_path, "/var/run/obmc-ikvm.sock", sizeof(...));       │
│      connect(sock, (struct sockaddr*)&addr, sizeof(addr));                 │
│                                                                            │
│      // 2. Bidirectional forwarding                                        │
│      // WebSocket → Unix socket (client input)                             │
│      conn.onMessage([sock](const std::string& msg) {                       │
│          write(sock, msg.data(), msg.size());                              │
│      });                                                                   │
│                                                                            │
│      // Unix socket → WebSocket (video/responses)                          │
│      async_read(sock, buffer, [&conn](size_t bytes) {                      │
│          conn.sendBinary(buffer, bytes);                                   │
│      });                                                                   │
│  }                                                                         │
│                                                                            │
│  DATA FLOW:                                                                │
│  ─────────                                                                 │
│                                                                            │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐      ┌──────────┐        │
│  │  noVNC   │      │  bmcweb  │      │obmc-ikvm │      │   Host   │        │
│  │(browser) │      │          │      │          │      │          │        │
│  └────┬─────┘      └────┬─────┘      └────┬─────┘      └────┬─────┘        │
│       │                 │                 │                 │              │
│       │  KeyEvent       │                 │                 │              │
│       │  (RFB msg)      │                 │                 │              │
│       │────────────────>│────────────────>│                 │              │
│       │   WebSocket     │  Unix socket    │  write()        │              │
│       │   binary frame  │                 │  /dev/hidg0     │              │
│       │                 │                 │────────────────>│              │
│       │                 │                 │   USB HID       │              │
│       │                 │                 │   report        │              │
│       │                 │                 │                 │              │
│       │                 │                 │  Video capture  │              │
│       │                 │                 │<────────────────│              │
│       │                 │                 │   V4L2 frame    │              │
│       │  FramebufferUp  │                 │                 │              │
│       │<────────────────│<────────────────│                 │              │
│       │   WebSocket     │  Unix socket    │                 │              │
│       │   binary frame  │  (JPEG data)    │                 │              │
│       │                 │                 │                 │              │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files in [obmc-ikvm](https://github.com/openbmc/obmc-ikvm) and [bmcweb](https://github.com/openbmc/bmcweb):

| File | Description |
|------|-------------|
| `obmc-ikvm/ikvm_video.cpp` | V4L2 video capture and JPEG compression |
| `obmc-ikvm/ikvm_input.cpp` | USB HID gadget keyboard/mouse handling |
| `obmc-ikvm/ikvm_server.cpp` | RFB/VNC protocol server implementation |
| `bmcweb/include/kvm_websocket.hpp` | WebSocket to Unix socket bridge |
| `bmcweb/redfish-core/lib/managers.hpp` | GraphicalConsole Redfish resource |

---

## References

- [obmc-ikvm](https://github.com/openbmc/obmc-ikvm)
- [noVNC](https://novnc.com/)
- [USB HID Gadget](https://www.kernel.org/doc/html/latest/usb/gadget_hid.html)
- [ASPEED Video Engine](https://github.com/AspeedTech-BMC/linux)

---

{: .note }
**Tested on**: OpenBMC master, requires hardware with video capture support
