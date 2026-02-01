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

## References

- [obmc-ikvm](https://github.com/openbmc/obmc-ikvm)
- [noVNC](https://novnc.com/)
- [USB HID Gadget](https://www.kernel.org/doc/html/latest/usb/gadget_hid.html)
- [ASPEED Video Engine](https://github.com/AspeedTech-BMC/linux)

---

{: .note }
**Tested on**: OpenBMC master, requires hardware with video capture support
