---
layout: default
title: Virtual Media Guide
parent: Interfaces
nav_order: 5
difficulty: advanced
prerequisites:
  - redfish-guide
---

# Virtual Media Guide
{: .no_toc }

Configure remote ISO and image mounting on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**Virtual Media** allows mounting remote disk images (ISO, IMG) to the host system over the network, appearing as local USB storage devices. This enables remote OS installation and recovery without physical media.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Virtual Media Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   Remote Image Source                       ││
│  │                                                             ││
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    ││
│  │   │  HTTPS   │  │  CIFS    │  │   NFS    │  │  Upload  │    ││
│  │   │  Server  │  │  Share   │  │  Export  │  │ (WebUI)  │    ││
│  │   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘    ││
│  └────────┼─────────────┼─────────────┼─────────────┼──────────┘│
│           └─────────────┴─────────────┴─────────────┘           │
│                                   │                             │
│                              Network                            │
│                                   │                             │
│  ┌────────────────────────────────┴────────────────────────────┐│
│  │                          bmcweb                             ││
│  │                   (WebSocket / Redfish)                     ││
│  └────────────────────────────────┬────────────────────────────┘│
│                                   │                             │
│           ┌───────────────────────┼──────────────────────┐      │
│           │                       │                      │      │
│  ┌────────┴────────┐    ┌─────────┴─────────┐   ┌────────┴────┐ │
│  │   Proxy Mode    │    │   Legacy Mode     │   │  NBD Proxy  │ │
│  │ (preferred)     │    │ (USB Mass Storage)│   │             │ │
│  └────────┬────────┘    └─────────┬─────────┘   └───────┬─────┘ │
│           │                       │                     │       │
│  ┌────────┴───────────────────────┴─────────────────────┴──────┐│
│  │                      USB Gadget                             ││
│  │                  (Mass Storage Class)                       ││
│  └────────────────────────────┬────────────────────────────────┘│
│                               │                                 │
│  ┌────────────────────────────┴────────────────────────────────┐│
│  │                      Host System                            ││
│  │                  (USB disk device)                          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Modes of Operation

### Proxy Mode (Recommended)

- Image streams from remote server through BMC
- No local storage required on BMC
- Supports HTTPS, NFS, CIFS sources
- Lower latency for network-accessible images

### Legacy Mode

- Image stored locally on BMC filesystem
- Presented via USB mass storage
- Works offline once mounted
- Limited by BMC storage capacity

### NBD Proxy

- Network Block Device protocol
- Efficient streaming protocol
- Used with WebSocket connections

---

## Hardware Requirements

Virtual Media requires USB device controller:

| BMC SoC | USB Controller | Mass Storage |
|---------|----------------|--------------|
| ASPEED AST2500/2600 | USB 2.0 device | Supported |
| Nuvoton NPCM7xx | USB 2.0 device | Supported |

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include virtual media support
IMAGE_INSTALL:append = " virtual-media"

# Enable in bmcweb
EXTRA_OEMESON:pn-bmcweb = " \
    -Dvm-websocket=enabled \
    -Dvm-nbdproxy=enabled \
"

# Include NBD client (for proxy mode)
IMAGE_INSTALL:append = " nbd-client"
```

### bmcweb Virtual Media Options

| Option | Default | Description |
|--------|---------|-------------|
| `vm-websocket` | enabled | Virtual Media WebSocket support |
| `vm-nbdproxy` | enabled | NBD proxy for streaming |
| `insecure-vm-auth` | disabled | Unauthenticated VM (testing) |

### Runtime Configuration

```bash
# Check virtual media service
systemctl status virtual-media

# View logs
journalctl -u virtual-media -f

# Check USB gadget configuration
ls /sys/kernel/config/usb_gadget/
```

---

## Mounting Images

### Via WebUI

1. Login to WebUI at `https://<bmc-ip>/`
2. Navigate to **Operations** → **Virtual Media**
3. Select device type: **CD/DVD** or **USB**
4. Choose mount method:
   - **From URL**: Enter HTTP/HTTPS/NFS/CIFS path
   - **Upload**: Upload local file
5. Click **Mount**

### Via Redfish API

#### List Virtual Media Devices

```bash
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia
```

#### Mount from URL

```bash
# Mount ISO from HTTPS server
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Image": "https://example.com/images/ubuntu-22.04.iso",
        "TransferProtocolType": "HTTPS",
        "UserName": "",
        "Password": "",
        "WriteProtected": true,
        "Inserted": true
    }' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0

# Mount from NFS
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Image": "nfs://192.168.1.100/exports/images/boot.iso",
        "Inserted": true
    }' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0

# Mount from CIFS/SMB
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Image": "smb://192.168.1.100/share/images/install.iso",
        "UserName": "user",
        "Password": "password",
        "Inserted": true
    }' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0
```

#### Check Mount Status

```bash
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0
```

Response:
```json
{
    "@odata.id": "/redfish/v1/Managers/bmc/VirtualMedia/Slot_0",
    "Id": "Slot_0",
    "Name": "VirtualMedia",
    "MediaTypes": ["CD", "DVD"],
    "Image": "https://example.com/images/ubuntu.iso",
    "ImageName": "ubuntu.iso",
    "Inserted": true,
    "WriteProtected": true,
    "ConnectedVia": "URI",
    "TransferProtocolType": "HTTPS"
}
```

#### Unmount Image

```bash
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Inserted": false}' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0
```

#### Eject Action

```bash
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0/Actions/VirtualMedia.EjectMedia
```

---

## Configuration Options

### Virtual Media Slots

```bash
# Default slots (varies by implementation)
Slot_0  - CD/DVD (read-only)
Slot_1  - USB storage (read-write)

# Check available slots
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia | jq '.Members'
```

### Transfer Protocol Support

| Protocol | Port | Use Case |
|----------|------|----------|
| HTTPS | 443 | Secure download, most common |
| HTTP | 80 | Testing only |
| NFS | 2049 | Network file system |
| CIFS/SMB | 445 | Windows shares |

### USB Gadget Configuration

```bash
# USB mass storage gadget setup
# Typically auto-configured by virtual-media service

# View gadget configuration
cat /sys/kernel/config/usb_gadget/virtual_media/UDC

# Check backing file
ls -l /sys/kernel/config/usb_gadget/virtual_media/functions/mass_storage.usb0/lun.0/
```

---

## Boot from Virtual Media

### Configure Boot Order

```bash
# Set boot source override to CD
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Boot": {
            "BootSourceOverrideTarget": "Cd",
            "BootSourceOverrideEnabled": "Once"
        }
    }' \
    https://localhost/redfish/v1/Systems/system
```

### One-Time Boot Sequence

1. Mount installation ISO
2. Set boot override to CD
3. Reset/power on system
4. System boots from virtual CD

```bash
# Complete workflow
# 1. Mount ISO
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Image": "https://server/ubuntu.iso", "Inserted": true}' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0

# 2. Set boot source
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Boot": {"BootSourceOverrideTarget": "Cd", "BootSourceOverrideEnabled": "Once"}}' \
    https://localhost/redfish/v1/Systems/system

# 3. Power cycle
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"ResetType": "ForceRestart"}' \
    https://localhost/redfish/v1/Systems/system/Actions/ComputerSystem.Reset
```

---

## WebSocket Mode

### Connecting via WebSocket

For direct file streaming:

```javascript
// JavaScript example
const ws = new WebSocket('wss://bmc-ip/nbd/0');

// Handle binary data streaming
ws.binaryType = 'arraybuffer';

ws.onmessage = function(event) {
    // Handle NBD protocol messages
};
```

### NBD Protocol

Network Block Device protocol for efficient streaming:

```bash
# Check NBD devices
ls /dev/nbd*

# NBD proxy handles protocol translation
# WebSocket → NBD → USB mass storage
```

---

## Troubleshooting

### Image Not Mounting

```bash
# Check virtual media service
systemctl status virtual-media
journalctl -u virtual-media -f

# Verify URL is accessible from BMC
curl -k https://example.com/image.iso -o /dev/null

# Check USB gadget
ls /sys/kernel/config/usb_gadget/
```

### Host Not Seeing USB Device

```bash
# Check USB connection
lsusb -t   # On host if possible

# Verify USB gadget is bound
cat /sys/kernel/config/usb_gadget/*/UDC

# Check USB device controller
ls /sys/class/udc/

# Rebind gadget
echo "" > /sys/kernel/config/usb_gadget/virtual_media/UDC
echo "1e6a0000.usb-vhub:p1" > /sys/kernel/config/usb_gadget/virtual_media/UDC
```

### Slow Transfer Speed

```bash
# Check network connection
iftop -i eth0

# Monitor image streaming
journalctl -u virtual-media -f

# For large images, consider:
# - Local caching
# - Faster network link
# - Proximity of image server
```

### Boot Fails

```bash
# Verify boot order in BIOS
# USB boot may need to be enabled

# Check image integrity
curl https://server/image.iso | sha256sum

# Verify image is bootable
# May need to test image locally first
```

### Authentication Errors

```bash
# For CIFS/SMB shares
# Verify credentials
smbclient //server/share -U username

# For HTTPS with client cert
# Check certificate configuration
```

---

## Security Considerations

### Image Source Authentication

```bash
# Prefer HTTPS for image sources
# Verify SSL certificates

# For self-signed certs, may need:
EXTRA_OEMESON:pn-bmcweb = " \
    -Dinsecure-ignore-cert-errors=enabled \
"
# NOT recommended for production
```

### Access Control

```bash
# Virtual media access requires authentication
# Recommended: Operator role or higher

# Check role permissions
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/AccountService/Roles
```

### Write Protection

```bash
# Always mount OS images as write-protected
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Image": "https://server/image.iso",
        "WriteProtected": true,
        "Inserted": true
    }' \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0
```

---

## Enabling/Disabling Virtual Media

### Build-Time Disable

```bitbake
# Disable virtual media
EXTRA_OEMESON:pn-bmcweb = " \
    -Dvm-websocket=disabled \
    -Dvm-nbdproxy=disabled \
"
IMAGE_INSTALL:remove = "virtual-media"
```

### Runtime Disable

```bash
# Stop virtual media service
systemctl stop virtual-media
systemctl disable virtual-media

# Unmount any mounted images first
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/Managers/bmc/VirtualMedia/Slot_0/Actions/VirtualMedia.EjectMedia
```

---

## References

- [OpenBMC Virtual Media](https://github.com/openbmc/virtual-media)
- [Redfish VirtualMedia Schema](https://redfish.dmtf.org/schemas/VirtualMedia.v1_6_0.json)
- [NBD Protocol](https://nbd.sourceforge.io/)
- [USB Mass Storage Class](https://www.usb.org/document-library/mass-storage-class-specification-overview-14)

---

{: .note }
**Tested on**: OpenBMC master, requires hardware with USB device controller
