---
layout: default
title: Firmware Update Guide
parent: Advanced Topics
nav_order: 3
difficulty: advanced
prerequisites:
  - redfish-guide
  - openbmc-overview
---

# Firmware Update Guide
{: .no_toc }

Configure and perform BMC and host firmware updates on OpenBMC - comprehensive deep dive into update mechanisms, image formats, and flash management.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC supports firmware updates for BMC, BIOS/UEFI, and other platform components through multiple interfaces including Redfish, IPMI, PLDM, and command-line tools. This guide provides a deep dive into the update architecture, image formats, flash layouts, and troubleshooting procedures.

### Update Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      Firmware Update Architecture                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         Update Interfaces                               │ │
│  │                                                                         │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │ │
│  │  │ Redfish  │ │   IPMI   │ │  PLDM    │ │  WebUI   │ │   USB    │       │ │
│  │  │UpdateSvc │ │OEM Flash │ │FW Update │ │ Upload   │ │ Storage  │       │ │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘       │ │
│  └───────┼────────────┼────────────┼────────────┼────────────┼─────────────┘ │
│          │            │            │            │            │               │
│          └────────────┴─────┬──────┴────────────┴────────────┘               │
│                             │                                                │
│  ┌──────────────────────────┴────────────────────────────────────────────┐   │
│  │              phosphor-bmc-code-mgmt (Software Manager)                │   │
│  │                                                                       │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │ ItemUpdater  │  │ImageManager  │  │  Activation  │  │  Version   │ │   │
│  │  │(BMC/Host/PSU)│  │(tar extract) │  │  (flash ops) │  │  (D-Bus)   │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘ │   │
│  │                                                                       │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │   │
│  │  │ Signature    │  │ MANIFEST     │  │ Priority     │                 │   │
│  │  │ Verification │  │ Parsing      │  │ Management   │                 │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘                 │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
│                             │                                                │
│  ┌──────────────────────────┴────────────────────────────────────────────┐   │
│  │                        Flash Storage Layer                            │   │
│  │                                                                       │   │
│  │  ┌────────────────────────────┐  ┌────────────────────────────────┐   │   │
│  │  │      BMC Flash (SPI)       │  │      Host Flash (LPC/SPI)      │   │   │
│  │  │                            │  │                                │   │   │
│  │  │  ┌──────┐  ┌──────┐        │  │  ┌──────┐  ┌──────┐            │   │   │
│  │  │  │ UBI  │  │Static│        │  │  │ PNOR │  │ BIOS │            │   │   │
│  │  │  │Volumes│ │ MTD  │        │  │  │      │  │      │            │   │   │
│  │  │  └──────┘  └──────┘        │  │  └──────┘  └──────┘            │   │   │
│  │  └────────────────────────────┘  └────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Repository | Description |
|-----------|------------|-------------|
| phosphor-bmc-code-mgmt | [openbmc/phosphor-bmc-code-mgmt](https://github.com/openbmc/phosphor-bmc-code-mgmt) | Core BMC firmware management |
| phosphor-software-manager | Part of code-mgmt | D-Bus service for update operations |
| phosphor-ipmi-flash | [openbmc/phosphor-ipmi-flash](https://github.com/openbmc/phosphor-ipmi-flash) | IPMI OEM firmware update |
| pldmd | [openbmc/pldm](https://github.com/openbmc/pldm) | PLDM Type 5 firmware update |
| phosphor-image-signing | Part of code-mgmt | Signature generation and verification |

---

## Firmware Image Format

### Tarball Structure

OpenBMC firmware images are packaged as tarballs with a specific structure:

```
obmc-phosphor-image-<machine>.tar
├── MANIFEST                    # Metadata about the image
├── publickey                   # Public key for verification (optional)
├── image-kernel                # Linux kernel (FIT image or uImage)
├── image-rofs                  # Read-only root filesystem (squashfs)
├── image-rwfs                  # Read-write filesystem (ext4/ubifs)
├── image-u-boot                # U-Boot bootloader
├── image-bmc                   # Combined flash image (static.mtd)
└── *.sig                       # Signatures for each component
```

### MANIFEST File Format

The MANIFEST file contains critical metadata parsed during update:

```ini
# Example MANIFEST file
purpose=xyz.openbmc_project.Software.Version.VersionPurpose.BMC
version=2.12.0-dev-123-gabcdef
KeyType=OpenBMC
HashType=RSA-SHA256
MachineName=romulus

# Extended version information (optional)
extended_version=OpenBMC for Romulus - master branch build 123
```

#### MANIFEST Fields

| Field | Required | Description |
|-------|----------|-------------|
| `purpose` | Yes | `BMC`, `Host`, `System`, or custom |
| `version` | Yes | Semantic version string |
| `MachineName` | Recommended | Target machine (prevents wrong-machine updates) |
| `KeyType` | If signed | Signing key type (OpenBMC, ProductionKey, etc.) |
| `HashType` | If signed | Hash algorithm (RSA-SHA256, RSA-SHA512) |
| `extended_version` | No | Additional version details |

### Image File Types

| File | Format | Description |
|------|--------|-------------|
| `image-kernel` | FIT/uImage | Linux kernel, often with DTB |
| `image-rofs` | SquashFS | Compressed read-only root filesystem |
| `image-rwfs` | ext4/UBIFS | Persistent writable data |
| `image-u-boot` | Binary | U-Boot bootloader image |
| `image-bmc` | static.mtd | Complete flash image for recovery |

### Creating Firmware Images

```bash
# Build produces images in deploy directory
bitbake obmc-phosphor-image

# Find images
ls tmp/deploy/images/<machine>/
# obmc-phosphor-image-<machine>.tar
# obmc-phosphor-image-<machine>.static.mtd
# obmc-phosphor-image-<machine>.ubi.mtd

# Manual tarball creation (for testing)
cd tmp/deploy/images/<machine>/
tar -cvf custom-image.tar \
    MANIFEST \
    image-kernel \
    image-rofs \
    image-rwfs \
    image-u-boot
```

### Signing Images

```bash
# Generate signing keys (one-time setup)
openssl genrsa -out private.pem 4096
openssl rsa -in private.pem -pubout -out publickey

# Sign each component
for file in image-kernel image-rofs image-rwfs image-u-boot MANIFEST; do
    openssl dgst -sha256 -sign private.pem -out ${file}.sig ${file}
done

# Create signed tarball
tar -cvf obmc-phosphor-image-signed.tar \
    MANIFEST MANIFEST.sig \
    publickey \
    image-kernel image-kernel.sig \
    image-rofs image-rofs.sig \
    image-rwfs image-rwfs.sig \
    image-u-boot image-u-boot.sig
```

---

## Flash Layout & Storage

Understanding flash layout is essential for firmware update operations.

### BMC Flash Layout (ASPEED)

Typical ASPEED AST2500/AST2600 flash layout:

```
┌──────────────────────────────────────────────────────────────────┐
│                    BMC SPI Flash (32MB/64MB)                     │
├──────────────────────────────────────────────────────────────────┤
│ Offset      │ Size    │ Name          │ Description              │
├─────────────┼─────────┼───────────────┼──────────────────────────┤
│ 0x00000000  │ 512KB   │ u-boot        │ Bootloader               │
│ 0x00080000  │ 64KB    │ u-boot-env    │ Environment variables    │
│ 0x00090000  │ 448KB   │ <reserved>    │ Future use               │
│ 0x00100000  │ 4MB     │ kernel-a      │ Kernel image A           │
│ 0x00500000  │ 20MB    │ rofs-a        │ Read-only rootfs A       │
│ 0x01900000  │ 4MB     │ kernel-b      │ Kernel image B           │
│ 0x01D00000  │ 20MB    │ rofs-b        │ Read-only rootfs B       │
│ 0x03100000  │ 4MB     │ rwfs          │ Persistent data          │
│ 0x03500000  │ 11MB    │ <reserved>    │ Future use               │
└─────────────┴─────────┴───────────────┴──────────────────────────┘
```

### Static MTD vs UBI Layout

OpenBMC supports two flash management strategies:

#### Static MTD Layout

Traditional fixed-partition layout:

```bitbake
# In machine .conf
FLASH_SIZE = "32768"  # 32MB in KB

# Partition sizes (KB)
FLASH_UBOOT_OFFSET = "0"
FLASH_UBOOT_ENV_OFFSET = "512"
FLASH_KERNEL_OFFSET = "1024"
FLASH_ROFS_OFFSET = "5120"
FLASH_RWFS_OFFSET = "28160"
```

```bash
# View MTD partitions on target
cat /proc/mtd
# dev:    size   erasesize  name
# mtd0: 00080000 00001000 "u-boot"
# mtd1: 00010000 00001000 "u-boot-env"
# mtd2: 00400000 00001000 "kernel"
# mtd3: 01400000 00001000 "rofs"
# mtd4: 00400000 00001000 "rwfs"
```

#### UBI (Unsorted Block Images) Layout

Dynamic volume management with wear leveling:

```bitbake
# Enable UBI
IMAGE_FSTYPES += "ubi.mtd"
FLASH_UBI_OVERLAY_SIZE = "4096"  # KB
FLASH_UBI_RWFS_SIZE = "6144"     # KB
```

```bash
# View UBI volumes
ubinfo -a
# UBI version:                    1
# Volumes count:                  4
# Volume 0: kernel-a
# Volume 1: kernel-b
# Volume 2: rofs-a
# Volume 3: rofs-b

# Detailed volume info
ubinfo /dev/ubi0 -N rofs-a
```

### Host Flash Layout (Intel/AMD BIOS)

```
┌──────────────────────────────────────────────────────────────────┐
│                    Host SPI Flash (16MB/32MB)                    │
├──────────────────────────────────────────────────────────────────┤
│ Region      │ Size    │ Description                              │
├─────────────┼─────────┼──────────────────────────────────────────┤
│ Descriptor  │ 4KB     │ Flash descriptor (regions, permissions)  │
│ BIOS        │ 8-16MB  │ UEFI firmware                            │
│ ME/PSP      │ 2-4MB   │ Intel ME / AMD PSP firmware              │
│ GbE         │ 8KB     │ Ethernet controller config               │
│ Platform    │ Varies  │ Platform-specific data                   │
└─────────────┴─────────┴──────────────────────────────────────────┘
```

### OpenPOWER PNOR Layout

```
┌──────────────────────────────────────────────────────────────────┐
│                    PNOR Flash (64MB/128MB)                       │
├──────────────────────────────────────────────────────────────────┤
│ Partition   │ Size    │ Description                              │
├─────────────┼─────────┼──────────────────────────────────────────┤
│ TOC         │ 32KB    │ Table of Contents                        │
│ HBB         │ 1MB     │ Hostboot Base                            │
│ HBI         │ 16MB    │ Hostboot Extended Image                  │
│ HBRT        │ 4MB     │ Hostboot Runtime                         │
│ PAYLOAD     │ 1MB     │ OPAL Skiboot                             │
│ BOOTKERNEL  │ 32MB    │ Linux kernel + initramfs                 │
│ NVRAM       │ 576KB   │ Non-volatile settings                    │
│ GUARD       │ 16KB    │ Hardware guard records                   │
│ RINGOVD     │ 256KB   │ Ring override partition                  │
└─────────────┴─────────┴──────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include software management
IMAGE_INSTALL:append = " \
    phosphor-software-manager \
    phosphor-image-signing \
"

# Configure update options
EXTRA_OEMESON:pn-phosphor-bmc-code-mgmt = " \
    -Dfwupd-script=enabled \
    -Dsync-bmc-files=enabled \
    -Dverify-signature=enabled \
    -Dhost-bios-upgrade=enabled \
    -Dusb-code-update=enabled \
"

# Enable image signing
INHERIT += "image_types_phosphor"
IMAGE_TYPES += "static.mtd ubi.mtd"

# Configure flash layout
FLASH_SIZE = "32768"
FLASH_UBOOT_ENV_OFFSET_KB = "512"
FLASH_KERNEL_OFFSET_KB = "1024"

# Dual image support
OBMC_PHOSPHOR_IMAGE_DUAL = "1"
```

### phosphor-bmc-code-mgmt Meson Options

| Option | Default | Description |
|--------|---------|-------------|
| `verify-signature` | enabled | Require signed firmware |
| `sync-bmc-files` | enabled | Sync critical files between images |
| `fwupd-script` | disabled | Use external update script |
| `host-bios-upgrade` | disabled | Enable BIOS/UEFI updates |
| `usb-code-update` | disabled | Enable USB firmware update |
| `side-switch-on-boot` | disabled | Auto-switch on boot failure |
| `software-update-dbus-interface` | enabled | Expose D-Bus update interface |
| `delete-images` | enabled | Allow image deletion |

### Runtime Configuration

```bash
# Check software manager status
systemctl status phosphor-software-manager@bmc
systemctl status phosphor-version-software-manager

# View update logs
journalctl -u phosphor-software-manager@bmc -f

# Check current firmware versions
busctl tree xyz.openbmc_project.Software.BMC.Updater

# List all software objects
busctl call xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/object_mapper \
    xyz.openbmc_project.ObjectMapper \
    GetSubTree sias "/xyz/openbmc_project/software" 0 1 \
    "xyz.openbmc_project.Software.Version"
```

### D-Bus Software Interfaces

```bash
# Key interfaces exposed by phosphor-software-manager:

# Software.Version - Version information
busctl introspect xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.Version

# Software.Activation - Activation state
busctl introspect xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.Activation

# Software.RedundancyPriority - Boot priority
busctl introspect xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.RedundancyPriority
```

---

## Firmware Inventory

### View Current Versions

```bash
# Via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory

# Get specific firmware info
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/bmc_active

# Via D-Bus
busctl tree xyz.openbmc_project.Software.BMC.Updater
```

### Firmware Response

```json
{
    "@odata.id": "/redfish/v1/UpdateService/FirmwareInventory/bmc_active",
    "Id": "bmc_active",
    "Name": "BMC Firmware",
    "Version": "2.12.0",
    "Status": {
        "Health": "OK",
        "State": "Enabled"
    },
    "Updateable": true
}
```

---

## Update Methods

OpenBMC supports multiple update interfaces, each with specific use cases.

### Redfish Update Service

The primary update method for modern deployments:

```bash
# Upload firmware image via HttpPushUri
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @obmc-phosphor-image.tar \
    https://localhost/redfish/v1/UpdateService

# Check UpdateService status
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService

# Response shows update capabilities
{
    "@odata.id": "/redfish/v1/UpdateService",
    "HttpPushUri": "/redfish/v1/UpdateService",
    "HttpPushUriOptions": {
        "HttpPushUriApplyTime": {
            "ApplyTime": "OnReset"
        }
    },
    "MaxImageSizeBytes": 33554432,
    "ServiceEnabled": true
}
```

### SimpleUpdate Action

For network-based updates:

```bash
# Update from TFTP server
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "TransferProtocol": "TFTP",
        "ImageURI": "tftp://192.168.1.100/firmware.tar"
    }' \
    https://localhost/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate

# Update from HTTPS server
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "TransferProtocol": "HTTPS",
        "ImageURI": "https://server.example.com/firmware.tar"
    }' \
    https://localhost/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate

# Update from SCP (requires credentials)
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "TransferProtocol": "SCP",
        "ImageURI": "scp://user@server.example.com/path/to/firmware.tar",
        "UserName": "user",
        "Password": "password"
    }' \
    https://localhost/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate
```

### IPMI OEM Firmware Update

Using phosphor-ipmi-flash for IPMI-based updates:

```bash
# IPMI OEM firmware update commands (host-side)
# Uses OEM commands to transfer firmware via IPMI

# Start firmware transfer session
ipmitool raw 0x2e 0x00 0x00 0x00 0x01  # OEM start

# Transfer data in chunks (simplified)
ipmitool raw 0x2e 0x01 <offset> <data>  # OEM data

# Finalize and verify
ipmitool raw 0x2e 0x02  # OEM verify

# Activate firmware
ipmitool raw 0x2e 0x03  # OEM activate
```

#### phosphor-ipmi-flash Configuration

```bitbake
# Enable IPMI flash support
IMAGE_INSTALL:append = " phosphor-ipmi-flash"

# Configure supported transports
EXTRA_OEMESON:pn-phosphor-ipmi-flash = " \
    -Dlpc-type=nuvoton-lpc \
    -Dpci-bridge=true \
"
```

```json
// /usr/share/ipmi-flash/config/config.json
{
    "handlers": [
        {
            "handler": "static",
            "path": "/run/initramfs/image-bmc"
        }
    ],
    "actions": [
        {
            "type": "systemd",
            "unit": "phosphor-ipmi-flash-bmc-update.target"
        }
    ]
}
```

### PLDM Firmware Update (Type 5)

PLDM Type 5 firmware update for component updates:

```bash
# Query firmware devices
pldmtool fw_update GetFwParams -m <eid>

# Request firmware update
pldmtool fw_update RequestUpdate -m <eid> \
    --max_transfer_size 4096 \
    --num_comps 1 \
    --max_outstanding_transfer_req 2 \
    --pkg_data_len 0 \
    --comp_image_set_ver "1.0.0"

# Pass component table
pldmtool fw_update PassComponentTable -m <eid> \
    --transfer_flag 0x05 \
    --comp_classification 0x0A \
    --comp_identifier 0x0001 \
    --comp_classification_index 0 \
    --comp_comparison_stamp 0 \
    --comp_ver "1.0.0" \
    --comp_ver_str_type 1 \
    --comp_ver_str_len 5

# Update component
pldmtool fw_update UpdateComponent -m <eid> \
    --comp_classification 0x0A \
    --comp_identifier 0x0001 \
    --comp_classification_index 0
```

#### PLDM Update Flow

```
┌────────────┐                    ┌────────────────┐
│    BMC     │                    │  Update Agent  │
│  (pldmd)   │                    │    (Host)      │
└─────┬──────┘                    └───────┬────────┘
      │                                   │
      │      QueryDeviceIdentifiers       │
      │<──────────────────────────────────│
      │      DeviceIdentifiers            │
      │──────────────────────────────────>│
      │                                   │
      │      GetFirmwareParameters        │
      │<──────────────────────────────────│
      │      FirmwareParameters           │
      │──────────────────────────────────>│
      │                                   │
      │      RequestUpdate                │
      │<──────────────────────────────────│
      │      RequestUpdateResp (ACK)      │
      │──────────────────────────────────>│
      │                                   │
      │      PassComponentTable           │
      │<──────────────────────────────────│
      │      PassComponentTableResp       │
      │──────────────────────────────────>│
      │                                   │
      │      UpdateComponent              │
      │<──────────────────────────────────│
      │      UpdateComponentResp          │
      │──────────────────────────────────>│
      │                                   │
      │      RequestFirmwareData (loop)   │
      │──────────────────────────────────>│
      │      FirmwareData                 │
      │<──────────────────────────────────│
      │                                   │
      │      TransferComplete             │
      │──────────────────────────────────>│
      │      TransferCompleteResp         │
      │<──────────────────────────────────│
      │                                   │
      │      VerifyComplete               │
      │──────────────────────────────────>│
      │      VerifyCompleteResp           │
      │<──────────────────────────────────│
      │                                   │
      │      ApplyComplete                │
      │──────────────────────────────────>│
      │      ApplyCompleteResp            │
      │<──────────────────────────────────│
      │                                   │
      │      ActivateFirmware             │
      │<──────────────────────────────────│
      │      ActivateFirmwareResp         │
      │──────────────────────────────────>│
```

### WebUI Update

1. Login to WebUI at `https://<bmc-ip>/`
2. Navigate to **Operations** → **Firmware**
3. Click **Upload firmware**
4. Select firmware file (`.tar` format)
5. Wait for upload and verification
6. Click **Activate** when ready
7. Optionally select **Reboot BMC after activation**

### USB Code Update

```bash
# USB code update directory structure:
# /mnt/usb/<usb-device>/
# └── firmware/
#     └── image-bmc               # Firmware tarball (renamed)

# BMC-side: Check for USB device
lsblk
# NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# sda      8:0    1  7.5G  0 disk
# └─sda1   8:1    1  7.5G  0 part /media/usb

# Configuration in Yocto
EXTRA_OEMESON:pn-phosphor-bmc-code-mgmt:append = " -Dusb-code-update=enabled"

# USB monitor service watches for:
# - USB insertion events
# - Files matching firmware pattern
# - Triggers automatic update if policy allows
```

### Command-Line Update Tools

```bash
# Direct flash update (recovery only)
# WARNING: Use only for recovery, bypasses safety checks

# Backup current image first
dd if=/dev/mtd0 of=/tmp/backup-kernel.bin
dd if=/dev/mtd1 of=/tmp/backup-rofs.bin

# Flash new image
flashcp -v /tmp/image-kernel /dev/mtd0
flashcp -v /tmp/image-rofs /dev/mtd1

# For UBI volumes
ubiupdatevol /dev/ubi0_0 /tmp/image-kernel
ubiupdatevol /dev/ubi0_1 /tmp/image-rofs
```

---

## Dual Image Support

OpenBMC implements A/B redundant boot for high availability.

### Dual Image Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BMC SPI Flash                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                           Shared                                    │    │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐         │    │
│  │  │    U-Boot      │  │   U-Boot Env   │  │  Persistent    │         │    │
│  │  │   (shared)     │  │   (shared)     │  │     Data       │         │    │
│  │  │                │  │                │  │    (rwfs)      │         │    │
│  │  └────────────────┘  └────────────────┘  └────────────────┘         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│  ┌──────────────────────────┐  ┌──────────────────────────┐                 │
│  │       Image A            │  │       Image B            │                 │
│  │      (Active)            │  │      (Standby)           │                 │
│  │                          │  │                          │                 │
│  │  ┌──────────────────┐    │  │  ┌──────────────────┐    │                 │
│  │  │  kernel-a        │    │  │  │  kernel-b        │    │                 │
│  │  │  (FIT image)     │    │  │  │  (FIT image)     │    │                 │
│  │  └──────────────────┘    │  │  └──────────────────┘    │                 │
│  │                          │  │                          │                 │
│  │  ┌──────────────────┐    │  │  ┌──────────────────┐    │                 │
│  │  │  rofs-a          │    │  │  │  rofs-b          │    │                 │
│  │  │  (SquashFS)      │    │  │  │  (SquashFS)      │    │                 │
│  │  └──────────────────┘    │  │  └──────────────────┘    │                 │
│  │                          │  │                          │                 │
│  │  Version: 2.12.0         │  │  Version: 2.11.0         │                 │
│  │  Priority: 0 (boot)      │  │  Priority: 1 (standby)   │                 │
│  └──────────────────────────┘  └──────────────────────────┘                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### View Images via Redfish

```bash
# List all firmware
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory

# Response
{
    "Members": [
        {"@odata.id": "/redfish/v1/UpdateService/FirmwareInventory/bmc_active"},
        {"@odata.id": "/redfish/v1/UpdateService/FirmwareInventory/abc12345"}
    ]
}

# Get active image details
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/bmc_active
```

### View Images via D-Bus

```bash
# List software versions
busctl tree xyz.openbmc_project.Software.BMC.Updater
# /xyz/openbmc_project/software
# ├─ /xyz/openbmc_project/software/abc12345  (active)
# └─ /xyz/openbmc_project/software/def67890  (standby)

# Get version info
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/abc12345 \
    xyz.openbmc_project.Software.Version Version
# s "2.12.0"

# Get activation state
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/abc12345 \
    xyz.openbmc_project.Software.Activation Activation
# s "xyz.openbmc_project.Software.Activation.Activations.Active"

# Get boot priority (0 = primary, higher = lower priority)
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/abc12345 \
    xyz.openbmc_project.Software.RedundancyPriority Priority
# u 0
```

### Set Boot Priority

```bash
# Set image as primary (priority 0)
busctl set-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/def67890 \
    xyz.openbmc_project.Software.RedundancyPriority \
    Priority u 0

# Via Redfish - activate backup firmware
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{}' \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/def67890/Actions/SoftwareInventory.Activate
```

---

## U-Boot Environment & Boot Control

### Key U-Boot Environment Variables

```bash
# View all U-Boot environment variables
fw_printenv

# Key variables for firmware update:

# bootside - Which image to boot (a or b)
fw_printenv bootside
# bootside=a

# bootcount - Boot attempt counter
fw_printenv bootcount
# bootcount=0

# bootlimit - Max boot attempts before fallback
fw_printenv bootlimit
# bootlimit=3

# kernelname - Kernel partition name
fw_printenv kernelname
# kernelname=kernel-a

# rofsname - Root filesystem partition
fw_printenv rofsname
# rofsname=rofs-a
```

### U-Boot Boot Logic

```
┌───────────────────────────────────────────────────────────────┐
│                    U-Boot Boot Flow                           │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Read bootside (a or b)                                    │
│           │                                                   │
│           ▼                                                   │
│  2. Increment bootcount                                       │
│           │                                                   │
│           ▼                                                   │
│  3. bootcount > bootlimit?  ───Yes──► Switch bootside         │
│           │                           Reset bootcount         │
│          No                           Retry boot              │
│           │                                                   │
│           ▼                                                   │
│  4. Load kernel from bootside                                 │
│           │                                                   │
│           ▼                                                   │
│  5. Boot Linux                                                │
│           │                                                   │
│           ▼                                                   │
│  6. User-space resets bootcount to 0                          │
│           (via init script or systemd service)                │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### Manual Boot Control

```bash
# Force boot from specific side
fw_setenv bootside b
reboot

# Reset boot counter (call after successful boot)
fw_setenv bootcount 0

# Increase boot limit for debugging
fw_setenv bootlimit 5

# One-time boot override (doesn't change bootside)
fw_setenv bootonce b
reboot

# View boot arguments
fw_printenv bootargs
# bootargs=console=ttyS4,115200 root=/dev/mtdblock3 rootfstype=squashfs
```

### Recovery via Serial Console

If boot fails and you have serial access:

```bash
# At U-Boot prompt (interrupt boot with key press)
=> printenv bootside
bootside=a

# Switch to other image
=> setenv bootside b
=> saveenv
=> reset

# Or boot directly without saving
=> setenv bootside b
=> run bootcmd
```

---

## Failsafe Behavior

### Automatic Boot Fallback

```
┌────────────────────────────────────────────────────────────────┐
│                  Boot Failure Recovery                         │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Boot Attempt 1 (Image A)                                      │
│     ├─ Success → bootcount = 0, run normally                   │
│     └─ Fail → bootcount++                                      │
│                                                                │
│  Boot Attempt 2 (Image A)                                      │
│     ├─ Success → bootcount = 0                                 │
│     └─ Fail → bootcount++ (now 2)                              │
│                                                                │
│  Boot Attempt 3 (Image A)                                      │
│     ├─ Success → bootcount = 0                                 │
│     └─ Fail → bootcount++ (now 3, equals bootlimit)            │
│               Switch bootside to B                             │
│               Reset bootcount to 0                             │
│                                                                │
│  Boot Attempt 4 (Image B)                                      │
│     ├─ Success → bootcount = 0, run from backup                │
│     └─ Fail → bootcount++                                      │
│                                                                │
│  ... continues alternating ...                                 │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Boot Health Check Service

```bash
# phosphor-software-manager runs boot health check
# On successful boot, clears boot counter

# Check service status
systemctl status obmc-flash-bmc-setenv@bootcount

# Manual reset
fw_setenv bootcount 0

# View boot health log
journalctl -u obmc-flash-bmc-setenv@bootcount
```

### Recovery Mode

```bash
# Force recovery to backup image
fw_setenv bootside b
reboot

# Emergency: Use U-Boot to load recovery image from TFTP
# At U-Boot prompt:
=> setenv serverip 192.168.1.100
=> setenv ipaddr 192.168.1.50
=> tftp 0x83000000 recovery-image.bin
=> bootm 0x83000000

# Full factory recovery via static.mtd image
# At U-Boot prompt:
=> sf probe
=> tftp 0x83000000 obmc-phosphor-image.static.mtd
=> sf update 0x83000000 0x0 ${filesize}
=> reset
```

---

## Firmware Signing & Verification

### Signing Infrastructure Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    Firmware Signing Infrastructure                        │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Build Server                           BMC Target                        │
│  ┌───────────────────────────┐        ┌────────────────────────────┐      │
│  │                           │        │                            │      │
│  │  ┌──────────────────────┐ │        │  ┌──────────────────────┐  │      │
│  │  │   Private Key        │ │        │  │   Public Key         │  │      │
│  │  │   (kept secure)      │ │        │  │   (/etc/activation   │  │      │
│  │  └──────────┬───────────┘ │        │  │    data/)            │  │      │
│  │             │             │        │  └──────────┬───────────┘  │      │
│  │             ▼             │        │             │              │      │
│  │  ┌──────────────────────┐ │        │             ▼              │      │
│  │  │  Sign Components     │ │        │  ┌──────────────────────┐  │      │
│  │  │  - MANIFEST          │ │        │  │  Verify Signatures   │  │      │
│  │  │  - image-kernel      │ │  ───►  │  │  - Compare hashes    │  │      │
│  │  │  - image-rofs        │ │        │  │  - Validate chain    │  │      │
│  │  │  - image-u-boot      │ │        │  │  - Check key type    │  │      │
│  │  └──────────┬───────────┘ │        │  └──────────┬───────────┘  │      │
│  │             │             │        │             │              │      │
│  │             ▼             │        │             ▼              │      │
│  │  ┌──────────────────────┐ │        │  ┌──────────────────────┐  │      │
│  │  │  Create Tarball      │ │        │  │  Accept/Reject       │  │      │
│  │  │  with signatures     │ │        │  │  Update              │  │      │
│  │  └──────────────────────┘ │        │  └──────────────────────┘  │      │
│  │                           │        │                            │      │
│  └───────────────────────────┘        └────────────────────────────┘      │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Generate Signing Keys

```bash
# Create 4096-bit RSA keypair for production
openssl genrsa -out private.pem 4096
openssl rsa -in private.pem -pubout -out publickey

# Create self-signed certificate (for key identification)
openssl req -new -x509 -key private.pem -out cert.pem -days 3650 \
    -subj "/CN=OpenBMC Firmware Signing/O=My Organization"

# View key information
openssl rsa -in publickey -pubin -text -noout

# For development/testing (weaker key)
openssl genrsa -out dev-private.pem 2048
openssl rsa -in dev-private.pem -pubout -out dev-publickey
```

### Sign Firmware Components

```bash
# Sign each component with SHA-256 RSA signature
for file in MANIFEST image-kernel image-rofs image-rwfs image-u-boot; do
    if [ -f "$file" ]; then
        openssl dgst -sha256 -sign private.pem -out ${file}.sig ${file}
        echo "Signed: $file"
    fi
done

# Create MANIFEST with signature metadata
cat > MANIFEST << 'EOF'
purpose=xyz.openbmc_project.Software.Version.VersionPurpose.BMC
version=2.12.0
MachineName=romulus
KeyType=OpenBMC
HashType=RSA-SHA256
EOF

# Sign the MANIFEST itself
openssl dgst -sha256 -sign private.pem -out MANIFEST.sig MANIFEST

# Create signed tarball
tar -cvf obmc-phosphor-image-signed.tar \
    MANIFEST MANIFEST.sig \
    publickey \
    image-kernel image-kernel.sig \
    image-rofs image-rofs.sig \
    image-rwfs image-rwfs.sig \
    image-u-boot image-u-boot.sig
```

### Configure Verification in Yocto

```bitbake
# In your distro or local.conf

# Enable signature verification
EXTRA_OEMESON:pn-phosphor-bmc-code-mgmt:append = " -Dverify-signature=enabled"

# Configure public key provider
PREFERRED_PROVIDER_virtual/phosphor-software-manager-system-public-key = \
    "phosphor-software-manager-public-key-${MACHINE}"

# Key installation location
# Keys installed to: /etc/activationdata/

# Custom key type name
SIGNING_KEY_TYPE = "OpenBMC"
```

Create a recipe for your public key:

```bitbake
# meta-mymachine/recipes-phosphor/software/phosphor-software-manager-public-key-mymachine.bb

SUMMARY = "Public key for firmware verification"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=..."

inherit allarch

SRC_URI = "file://publickey"

do_install() {
    install -d ${D}${sysconfdir}/activationdata
    install -m 0644 ${WORKDIR}/publickey \
        ${D}${sysconfdir}/activationdata/key-OpenBMC
}

FILES:${PN} = "${sysconfdir}/activationdata"

RPROVIDES:${PN} = "virtual/phosphor-software-manager-system-public-key"
```

### Verification Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│                   Signature Verification Flow                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. Upload firmware tarball                                              │
│           │                                                              │
│           ▼                                                              │
│  2. Extract to /tmp/images/<random-id>/                                  │
│           │                                                              │
│           ▼                                                              │
│  3. Parse MANIFEST                                                       │
│     ├─ Read KeyType → "OpenBMC"                                          │
│     ├─ Read HashType → "RSA-SHA256"                                      │
│     └─ Read MachineName → validate against current machine               │
│           │                                                              │
│           ▼                                                              │
│  4. Load public key from /etc/activationdata/key-<KeyType>               │
│     └─ If key not found → REJECT (unless verify-signature=disabled)      │
│           │                                                              │
│           ▼                                                              │
│  5. Verify MANIFEST signature                                            │
│     └─ openssl dgst -sha256 -verify <pubkey> -signature MANIFEST.sig     │
│           │                                                              │
│           ▼                                                              │
│  6. Verify each component signature                                      │
│     ├─ image-kernel.sig vs image-kernel                                  │
│     ├─ image-rofs.sig vs image-rofs                                      │
│     ├─ image-rwfs.sig vs image-rwfs                                      │
│     └─ image-u-boot.sig vs image-u-boot                                  │
│           │                                                              │
│           ▼                                                              │
│  7. All signatures valid?                                                │
│     ├─ Yes → Proceed with activation                                     │
│     └─ No → REJECT, log error, delete extracted files                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Manual Signature Verification

```bash
# On the BMC, manually verify an image

# Extract tarball
mkdir -p /tmp/verify-test
cd /tmp/verify-test
tar -xvf /tmp/firmware.tar

# Check MANIFEST
cat MANIFEST

# Verify MANIFEST signature
openssl dgst -sha256 -verify /etc/activationdata/key-OpenBMC \
    -signature MANIFEST.sig MANIFEST

# Verify component signatures
for file in image-kernel image-rofs image-rwfs image-u-boot; do
    if [ -f "$file" ] && [ -f "${file}.sig" ]; then
        echo -n "Verifying $file: "
        openssl dgst -sha256 -verify /etc/activationdata/key-OpenBMC \
            -signature ${file}.sig ${file}
    fi
done
```

### Signature Verification Logs

```bash
# Check verification results
journalctl -u phosphor-software-manager | grep -i -E "(signature|verify|key)"

# Example output for successful verification:
# phosphor-software-manager[1234]: Signature verification passed for image abc12345
# phosphor-software-manager[1234]: Image abc12345 is valid

# Example output for failed verification:
# phosphor-software-manager[1234]: Signature verification failed for MANIFEST
# phosphor-software-manager[1234]: Error: Invalid signature
# phosphor-software-manager[1234]: Rejecting image def67890
```

### Key Type Configuration

Support multiple key types for different environments:

```bash
# /etc/activationdata/ structure
/etc/activationdata/
├── key-OpenBMC           # Development keys
├── key-ProductionKey     # Production keys
└── key-TestKey           # Test/staging keys

# MANIFEST selects which key to use:
# KeyType=ProductionKey → uses /etc/activationdata/key-ProductionKey
```

---

## Host Firmware Update

### BIOS/UEFI Update (Intel/AMD)

```bash
# Upload BIOS image via Redfish
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @bios.bin \
    https://localhost/redfish/v1/UpdateService

# Check BIOS firmware inventory
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/bios

# Response
{
    "@odata.id": "/redfish/v1/UpdateService/FirmwareInventory/bios",
    "Id": "bios",
    "Name": "BIOS Firmware",
    "Version": "1.23.0",
    "Updateable": true,
    "Status": {
        "State": "Enabled",
        "Health": "OK"
    }
}
```

#### Intel SPS/ME Firmware

```bash
# Query ME firmware version
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/me

# ME update typically requires specific tools
# Coordinated with BIOS update
```

### PNOR Update (OpenPOWER)

```bash
# Upload PNOR tarball
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @pnor.tar \
    https://localhost/redfish/v1/UpdateService

# PNOR image structure
pnor.tar
├── MANIFEST           # purpose=Host, version, MachineName
├── HOST_FIRMWARE/
│   ├── HBB            # Hostboot Base
│   ├── HBI            # Hostboot Image
│   ├── HBRT           # Hostboot Runtime
│   ├── PAYLOAD        # Skiboot (OPAL)
│   └── BOOTKERNEL     # Linux kernel
└── *.sig              # Signatures
```

#### openpower-pnor-code-mgmt

```bash
# View PNOR partitions
pflash -i

# Read specific partition
pflash -P HBB -r /tmp/hbb.bin

# Services involved
systemctl status openpower-update-bios@0.service
```

### PSU Firmware Update

```bash
# List PSU firmware
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory \
    | jq '.Members[] | select(.["@odata.id"] | contains("psu"))'

# PSU update via PMBUS or I2C
# Requires specific PSU support in OpenBMC
```

### Component-Level Update (PLDM)

```bash
# Use pldmtool for component updates (VR, CPLD, etc.)
# Get supported components
pldmtool fw_update GetFwParams -m <eid>

# Component classifications:
# 0x00 - Unknown
# 0x01 - Other
# 0x02 - Driver
# 0x03 - Configuration
# 0x04 - Application
# 0x05 - Instrumentation
# 0x06 - Firmware/BIOS
# 0x07 - Diagnostic
# 0x0A - Firmware
# 0x0B - CPLD/FPGA
# 0x0C - VR
```

---

## Update Workflow Deep Dive

### Complete Update Sequence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Firmware Update Workflow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. UPLOAD                                                                  │
│     ├─ Receive via Redfish/IPMI/PLDM                                        │
│     ├─ Store in /tmp/images/<random-id>/                                    │
│     └─ Create Software.Version D-Bus object                                 │
│                                                                             │
│  2. EXTRACT & PARSE                                                         │
│     ├─ Extract tarball contents                                             │
│     ├─ Parse MANIFEST file                                                  │
│     ├─ Validate MachineName against current machine                         │
│     └─ Check version purpose (BMC/Host/System)                              │
│                                                                             │
│  3. VERIFY (if signature verification enabled)                              │
│     ├─ Load public key from /etc/activationdata/key-<KeyType>               │
│     ├─ Verify MANIFEST signature                                            │
│     ├─ Verify each component signature                                      │
│     └─ REJECT if any verification fails                                     │
│                                                                             │
│  4. READY                                                                   │
│     ├─ Set Activation = Ready                                               │
│     ├─ Create RedundancyPriority interface                                  │
│     └─ Wait for activation request                                          │
│                                                                             │
│  5. ACTIVATING                                                              │
│     ├─ Set Activation = Activating                                          │
│     ├─ Lock flash access                                                    │
│     ├─ Erase standby partition                                              │
│     ├─ Write image-kernel to kernel partition                               │
│     ├─ Write image-rofs to rofs partition                                   │
│     ├─ Write image-rwfs to rwfs partition (if present)                      │
│     └─ Update U-Boot variables                                              │
│                                                                             │
│  6. ACTIVE                                                                  │
│     ├─ Set Activation = Active                                              │
│     ├─ Set Priority = 0 (primary)                                           │
│     ├─ Demote previous image priority                                       │
│     └─ Optional: trigger reboot                                             │
│                                                                             │
│  7. VERIFY (post-reboot)                                                    │
│     ├─ Boot new image                                                       │
│     ├─ Reset bootcount to 0                                                 │
│     └─ Log successful update                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Activation States

| State | Description |
|-------|-------------|
| `NotReady` | Image uploaded but not yet processed |
| `Invalid` | Image validation failed |
| `Ready` | Image verified, waiting for activation |
| `Activating` | Write in progress to flash |
| `Active` | Image is installed and bootable |
| `Failed` | Activation failed |

### Monitor Update Progress

```bash
# Via Redfish Task Service
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/TaskService/Tasks

# Get specific task
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/TaskService/Tasks/1

# Task states: New, Starting, Running, Completed, Exception

# Via D-Bus monitoring
busctl monitor xyz.openbmc_project.Software.BMC.Updater

# Watch activation progress
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.Activation Activation

# Watch for ActivationProgress (percentage)
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.ActivationProgress Progress
```

### Progress Indication

```bash
# ActivationProgress interface shows percentage
# 0-10%: Extracting
# 10-20%: Verifying signatures
# 20-40%: Erasing flash
# 40-90%: Writing flash
# 90-100%: Finalizing

# Via journald
journalctl -u phosphor-software-manager@bmc -f
# [date] Progress: 25%
# [date] Writing kernel partition...
# [date] Progress: 50%
# [date] Writing rootfs partition...
# [date] Progress: 90%
# [date] Activation complete
```

---

## Configuration Options

### Update Settings

```bash
# Configure via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "HttpPushUriOptions": {
            "HttpPushUriApplyTime": {
                "ApplyTime": "Immediate"
            }
        }
    }' \
    https://localhost/redfish/v1/UpdateService
```

### Apply Time Options

| Option | Description |
|--------|-------------|
| Immediate | Apply and reboot immediately |
| OnReset | Apply on next BMC reboot |
| AtMaintenanceWindowStart | Schedule for maintenance window |

---

## Troubleshooting

### Upload Fails

```bash
# Check available space in /tmp
df -h /tmp
# Minimum required: image size + extraction overhead (~2x image size)

# Check bmcweb body size limit
# Default is typically 30MB, configurable in bmcweb
cat /etc/bmcweb_persistent_data.json | jq .http_body_limit

# Verify tarball integrity
file firmware.tar
# firmware.tar: POSIX tar archive (GNU)

tar -tvf firmware.tar
# -rw-r--r-- 0/0     123 2024-01-15 10:00 MANIFEST
# -rw-r--r-- 0/0 4194304 2024-01-15 10:00 image-kernel
# -rw-r--r-- 0/0 20971520 2024-01-15 10:00 image-rofs

# Check for required files
tar -tf firmware.tar | grep -E "^(MANIFEST|image-)"

# Common upload errors:
# - "413 Request Entity Too Large" → Image too big
# - "503 Service Unavailable" → Service overloaded
# - Connection reset → Timeout or memory issue
```

### Signature Verification Failed

```bash
# Check installed public keys
ls -la /etc/activationdata/
# -rw-r--r-- 1 root root 800 Jan 15 10:00 key-OpenBMC

# Check MANIFEST KeyType matches installed key
tar -xOf firmware.tar MANIFEST | grep KeyType
# KeyType=OpenBMC
# → Needs /etc/activationdata/key-OpenBMC

# Verify signature manually
cd /tmp
tar -xf firmware.tar
openssl dgst -sha256 -verify /etc/activationdata/key-OpenBMC \
    -signature MANIFEST.sig MANIFEST
# Verified OK  or  Verification Failure

# Common signature errors:
# - "Public key not found" → Missing key file
# - "Verification Failure" → Wrong key or corrupted signature
# - "HashType mismatch" → MANIFEST HashType doesn't match key
```

### Machine Name Mismatch

```bash
# Check current machine name
cat /etc/os-release | grep OPENBMC_TARGET_MACHINE
# OPENBMC_TARGET_MACHINE=romulus

# Check MANIFEST MachineName
tar -xOf firmware.tar MANIFEST | grep MachineName
# MachineName=romulus

# If mismatch, image is rejected
# Error: "Machine name doesn't match"
```

### Boot Fails After Update

```bash
# Via serial console, check for:
# - Kernel panic
# - Filesystem mount failure
# - Init system failure

# Check U-Boot boot counter
fw_printenv bootcount
# If > 0, boot had issues

# Force boot to backup image
fw_setenv bootside b
fw_setenv bootcount 0
reboot

# Or at U-Boot prompt:
=> setenv bootside b
=> saveenv
=> reset

# If both images fail, use TFTP recovery:
=> setenv serverip 192.168.1.100
=> setenv ipaddr 192.168.1.50
=> tftp 0x80000000 obmc-phosphor-image.static.mtd
=> sf probe
=> sf update 0x80000000 0 ${filesize}
=> reset
```

### Image Not Activating

```bash
# Check activation state
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.Activation Activation

# States:
# NotReady - Still processing
# Invalid - Validation failed
# Ready - Can be activated
# Activating - In progress
# Active - Successfully activated
# Failed - Activation failed

# Check for activation blockers
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.Activation RequestedActivation

# View detailed logs
journalctl -u phosphor-software-manager@bmc --since "5 minutes ago"

# Common activation issues:
# - Flash busy/locked
# - Insufficient space
# - Filesystem corruption
# - Service crash during write
```

### Flash Write Errors

```bash
# Check MTD device status
cat /proc/mtd
mtd_debug info /dev/mtd0

# Check for bad blocks (UBI)
ubinfo -a
cat /sys/class/ubi/ubi0/bad_peb_count

# Manual flash test (DESTRUCTIVE)
# flashcp -v /dev/zero /dev/mtd0  # DO NOT RUN in production

# Check for flash busy
flock -n /run/lock/bmc_flash.lock echo "Flash not locked"
# If no output, flash is locked by another process

# View flash operations
journalctl | grep -i "mtd\|flash\|ubi"
```

### Activation Progress Stuck

```bash
# Check if activation is stuck at specific percentage
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Software.ActivationProgress Progress

# Stuck at 0%: MANIFEST parsing or signature verification
# Stuck at 20%: Flash erase
# Stuck at 50%: Flash write
# Stuck at 90%: Finalization

# Check for service crash
systemctl status phosphor-software-manager@bmc
# If failed, restart and retry

# Force cleanup and retry
rm -rf /tmp/images/*
systemctl restart phosphor-software-manager@bmc
```

### Delete Failed/Stale Images

```bash
# List all software objects
busctl tree xyz.openbmc_project.Software.BMC.Updater

# Delete specific image via D-Bus
busctl call xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<id> \
    xyz.openbmc_project.Object.Delete Delete

# Or via Redfish
curl -k -u root:0penBmc -X DELETE \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/<id>

# Clean up /tmp/images manually if needed
rm -rf /tmp/images/<id>
```

### Network Update Issues

```bash
# TFTP update fails
# Check network connectivity
ping <tftp-server>

# Check TFTP server is running
tftp <tftp-server>
tftp> get firmware.tar
tftp> quit

# Check firewall
# TFTP uses UDP port 69

# HTTPS update fails
# Check certificate trust
curl -v https://<server>/firmware.tar

# Check proxy settings
echo $http_proxy $https_proxy
```

---

## Rollback

### Rollback via D-Bus

```bash
# List all images to find backup ID
busctl tree xyz.openbmc_project.Software.BMC.Updater

# Get version info for each image
for obj in $(busctl tree xyz.openbmc_project.Software.BMC.Updater --list | grep software/); do
    echo "=== $obj ==="
    busctl get-property xyz.openbmc_project.Software.BMC.Updater \
        "$obj" xyz.openbmc_project.Software.Version Version 2>/dev/null
    busctl get-property xyz.openbmc_project.Software.BMC.Updater \
        "$obj" xyz.openbmc_project.Software.RedundancyPriority Priority 2>/dev/null
done

# Activate backup image (set as primary)
busctl call xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<backup_id> \
    xyz.openbmc_project.Software.Activation \
    RequestedActivation s \
    "xyz.openbmc_project.Software.Activation.RequestedActivations.Active"

# Or set priority directly (0 = primary)
busctl set-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/<backup_id> \
    xyz.openbmc_project.Software.RedundancyPriority \
    Priority u 0

# Reboot BMC to activate
obmcutil bmcreboot
```

### Rollback via Redfish

```bash
# List all firmware inventory
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory | jq

# Find backup image (non-active BMC image)
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/<backup_id>

# Activate backup (method varies by implementation)
# Some implementations use PATCH:
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Status": {"State": "Enabled"}}' \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/<backup_id>

# Others use Actions:
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/<backup_id>/Actions/SoftwareInventory.Activate

# Reboot via Redfish
curl -k -u root:0penBmc -X POST \
    -d '{"ResetType": "GracefulRestart"}' \
    https://localhost/redfish/v1/Managers/bmc/Actions/Manager.Reset
```

### Rollback via U-Boot

```bash
# If Linux is accessible, use fw_setenv
fw_setenv bootside b
reboot

# At U-Boot prompt (serial console)
=> printenv bootside
bootside=a
=> setenv bootside b
=> saveenv
=> reset
```

---

## Factory Reset

### Reset BMC Configuration

```bash
# Via Redfish - reset to factory defaults
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"ResetType": "ResetAll"}' \
    https://localhost/redfish/v1/Managers/bmc/Actions/Manager.ResetToDefaults

# Reset types:
# - ResetAll: Reset all settings to factory defaults
# - PreserveNetworkAndUsers: Keep network and user settings
# - PreserveNetwork: Keep only network settings
```

### Clear Persistent Data

```bash
# Clear read-write filesystem (preserves firmware)
# WARNING: Loses all BMC configuration

# Method 1: Via systemd
systemctl start obmc-factory-reset.target

# Method 2: Manual (requires reboot)
rm -rf /var/lib/*
rm -rf /etc/machine-id
reboot

# Method 3: Via U-Boot (most thorough)
# At U-Boot prompt:
=> setenv openbmconce factory-reset
=> saveenv
=> reset
# BMC will clear rwfs on next boot
```

### Full Flash Recovery

```bash
# Complete flash re-image (via TFTP and U-Boot)
# WARNING: Erases EVERYTHING

# At U-Boot prompt:
=> setenv serverip 192.168.1.100
=> setenv ipaddr 192.168.1.50
=> setenv netmask 255.255.255.0

# Download full image
=> tftp 0x80000000 obmc-phosphor-image.static.mtd

# Probe SPI flash
=> sf probe

# Erase and write entire flash
=> sf erase 0 0x2000000  # Adjust size for your flash
=> sf write 0x80000000 0 ${filesize}

# Reset
=> reset
```

---

## Security Considerations

### Secure Boot Chain

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        Secure Boot Chain                                   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  1. Hardware Root of Trust                                                 │
│     └─ SoC verifies U-Boot signature using OTP-fused key                   │
│                                                                            │
│  2. U-Boot (Verified Boot)                                                 │
│     └─ Verifies FIT image signature (kernel + DTB + initramfs)             │
│                                                                            │
│  3. Linux Kernel                                                           │
│     └─ dm-verity protects read-only rootfs                                 │
│                                                                            │
│  4. User Space                                                             │
│     └─ phosphor-software-manager verifies update signatures                │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### U-Boot Verified Boot Configuration

```bash
# In U-Boot config (defconfig)
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_RSA=y

# FIT image with signature node
/dts-v1/;

/ {
    images {
        kernel {
            data = /incbin/("Image");
            type = "kernel";
            arch = "arm";
            compression = "none";
            hash {
                algo = "sha256";
            };
        };
    };
    configurations {
        default = "conf";
        conf {
            kernel = "kernel";
            signature {
                algo = "sha256,rsa4096";
                key-name-hint = "dev-key";
                sign-images = "kernel", "fdt";
            };
        };
    };
};
```

### Update Authentication

```bash
# Redfish authentication requirements
# - All update endpoints require authentication
# - Use HTTPS only (port 443)
# - Implement rate limiting to prevent brute force

# Enable mTLS for automated updates
# In bmcweb configuration:
# ssl_verify_mode = SSL_VERIFY_PEER

# RBAC for firmware updates
# Only Administrator role can perform updates
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/AccountService/Accounts/root | jq .RoleId
# "Administrator"
```

### Audit Logging

```bash
# Firmware update events are logged
journalctl -u phosphor-software-manager | grep -i "activat"

# Redfish audit log
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/LogServices/CELog/Entries

# Key events to monitor:
# - Firmware upload
# - Signature verification result
# - Activation start/complete
# - Boot failures
# - Factory reset
```

---

## Best Practices

### Pre-Update Checklist

1. **Verify backup image** - Ensure standby image is known-good
2. **Check storage space** - Minimum 2x image size in /tmp
3. **Verify network connectivity** - For network-based updates
4. **Document current version** - For rollback reference
5. **Schedule maintenance window** - BMC reboot affects management

### Update Procedure

```bash
# 1. Record current version
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/bmc_active \
    | jq .Version > /tmp/before_version.txt

# 2. Verify backup image is bootable
fw_printenv bootside
# Ensure alternate side has valid image

# 3. Upload new image
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @firmware.tar \
    https://localhost/redfish/v1/UpdateService

# 4. Monitor activation
watch -n 5 'curl -sk -u root:0penBmc \
    https://localhost/redfish/v1/TaskService/Tasks | jq'

# 5. Verify after reboot
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/UpdateService/FirmwareInventory/bmc_active \
    | jq .Version
```

### Post-Update Verification

```bash
# Verify boot success
fw_printenv bootcount
# Should be 0

# Check system health
obmcutil state
# Should show Ready

# Verify all services running
systemctl --failed
# Should be empty

# Test critical functionality
curl -k -u root:0penBmc https://localhost/redfish/v1/Systems/system
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc chassis status
```

---

## References

### OpenBMC Repositories

- [phosphor-bmc-code-mgmt](https://github.com/openbmc/phosphor-bmc-code-mgmt) - BMC code version management
- [phosphor-ipmi-flash](https://github.com/openbmc/phosphor-ipmi-flash) - IPMI-based firmware update
- [openpower-pnor-code-mgmt](https://github.com/openbmc/openpower-pnor-code-mgmt) - OpenPOWER PNOR management
- [pldm](https://github.com/openbmc/pldm) - PLDM Type 5 firmware update

### OpenBMC Documentation

- [Code Update Architecture](https://github.com/openbmc/docs/blob/master/architecture/code-update/code-update.md)
- [Software Update Design](https://github.com/openbmc/docs/blob/master/designs/software-update.md)
- [Secure Boot](https://github.com/openbmc/docs/blob/master/architecture/code-update/secure-boot.md)

### Standards

- [DMTF Redfish UpdateService Schema](https://redfish.dmtf.org/schemas/UpdateService.v1_11_0.json)
- [DMTF PLDM Firmware Update Spec (DSP0267)](https://www.dmtf.org/dsp/DSP0267)
- [IPMI Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)

### U-Boot

- [U-Boot Verified Boot](https://u-boot.readthedocs.io/en/latest/usage/fit/verified-boot.html)
- [U-Boot Environment Variables](https://u-boot.readthedocs.io/en/latest/usage/environment.html)

---

## Deep Dive
{: .text-delta }

Advanced implementation details for firmware update developers.

### Flash Layout and MTD Partitions

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Typical BMC Flash Layout (32MB)                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Offset     Size        Partition        Description                   │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ 0x0000000│ 512KB     │ u-boot        │ Bootloader               │   │
│   ├──────────┼───────────┼───────────────┼──────────────────────────┤   │
│   │ 0x0080000│ 128KB     │ u-boot-env    │ U-Boot environment       │   │
│   ├──────────┼───────────┼───────────────┼──────────────────────────┤   │
│   │ 0x00A0000│ 4.5MB     │ kernel        │ FIT image (kernel+dtb)   │   │
│   ├──────────┼───────────┼───────────────┼──────────────────────────┤   │
│   │ 0x0520000│ 25MB      │ rofs          │ Read-only rootfs         │   │
│   ├──────────┼───────────┼───────────────┼──────────────────────────┤   │
│   │ 0x1DC0000│ 2MB       │ rwfs          │ Persistent read-write    │   │
│   └──────────┴───────────┴───────────────┴──────────────────────────┘   │
│                                                                         │
│   Dual-Flash Configuration (A/B):                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ Flash 0 (Current)     │ Flash 1 (Alternate)                     │   │
│   ├───────────────────────┼─────────────────────────────────────────┤   │
│   │ u-boot (shared)       │ (reserved)                              │   │
│   │ u-boot-env            │                                         │   │
│   │ kernel-a (active)     │ kernel-b                                │   │
│   │ rofs-a (active)       │ rofs-b                                  │   │
│   │ rwfs (shared)         │                                         │   │
│   └───────────────────────┴─────────────────────────────────────────┘   │
│                                                                         │
│   Linux MTD Devices:                                                    │
│   /dev/mtd0 = u-boot                                                    │
│   /dev/mtd1 = u-boot-env                                                │
│   /dev/mtd2 = kernel                                                    │
│   /dev/mtd3 = rofs                                                      │
│   /dev/mtd4 = rwfs                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Update Image Verification

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Image Verification Process                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Update Image Structure:                                               │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ MANIFEST (text)        │ Version info, purpose, sha256 hashes   │   │
│   ├─────────────────────────────────────────────────────────────────┤   │
│   │ publickey (optional)   │ Public key for signature verification  │   │
│   ├─────────────────────────────────────────────────────────────────┤   │
│   │ image-kernel           │ FIT image with kernel and DTB          │   │
│   ├─────────────────────────────────────────────────────────────────┤   │
│   │ image-rofs             │ Read-only root filesystem (squashfs)   │   │
│   ├─────────────────────────────────────────────────────────────────┤   │
│   │ image-u-boot           │ U-Boot binary (optional)               │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   MANIFEST File Example:                                                │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ purpose=xyz.openbmc_project.Software.Version.VersionPurpose.BMC │   │
│   │ version=2.12.0                                                  │   │
│   │ MachineName=romulus                                             │   │
│   │ KeyType=OpenBMC                                                 │   │
│   │ HashType=RSA-SHA256                                             │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Verification Flow:                                                    │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│   │ Receive  │───▶│ Verify   │───▶│ Verify   │───▶│ Verify   │          │
│   │ Image    │    │ MANIFEST │    │ Signature│    │ Hashes   │          │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                        │              │               │                 │
│                        ▼              ▼               ▼                 │
│                   Check          RSA verify      SHA256 each            │
│                   required       against        component vs            │
│                   fields         pubkey         MANIFEST                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Flash Programming Internals

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Flash Write Process                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   MTD Write Operation:                                                  │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ 1. Erase sector (typically 64KB)                                │   │
│   │    ioctl(mtd_fd, MEMERASE, &erase_info)                         │   │
│   │    └─ Sector erased to 0xFF                                     │   │
│   │                                                                 │   │
│   │ 2. Write data (page-aligned, typically 256 bytes)               │   │
│   │    write(mtd_fd, data, page_size)                               │   │
│   │    └─ Data written to erased sector                             │   │
│   │                                                                 │   │
│   │ 3. Verify (optional, MEMVERIFY ioctl)                           │   │
│   │    read-back and compare                                        │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Update Daemon (phosphor-bmc-code-mgmt) Flow:                          │
│   ┌────────────────────────────────────────────────────────────────┐    │
│   │ 1. Image uploaded to /tmp/images/                              │    │
│   │ 2. Item Updater detects new image via inotify                  │    │
│   │ 3. Verify signature and hashes                                 │    │
│   │ 4. Create D-Bus Version object (Ready)                         │    │
│   │ 5. User activates: RequestedActivation = Active                │    │
│   │ 6. Write image components to alternate flash                   │    │
│   │ 7. Update U-Boot env to boot from new image                    │    │
│   │ 8. Set Activation = Activating, then Active                    │    │
│   │ 9. Reboot (if requested)                                       │    │
│   └────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│   U-Boot Environment (dual-boot):                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ bootside=a           # Currently running: a or b                │   │
│   │ bootcount=0          # Failed boot attempts                     │   │
│   │ bootlimit=3          # Max failures before fallback             │   │
│   │ bootcmd=             # Selects kernel-a or kernel-b             │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Recovery Mechanism

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Boot Failure Recovery                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Recovery Flow:                                                        │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                                                                  │  │
│   │  U-Boot Power On                                                 │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  bootcount++                                                     │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  bootcount > bootlimit? ───Yes──▶ Switch to alternate image      │  │
│   │       │                           Reset bootcount                │  │
│   │       No                          Boot alternate                 │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  Boot current image                                              │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  Linux boots successfully?                                       │  │
│   │       │                                                          │  │
│   │      Yes                                                         │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  systemd reaches multi-user.target                               │  │
│   │       │                                                          │  │
│   │       ▼                                                          │  │
│   │  obmc-flash-bmc-setenv@bootcount=0.service                       │  │
│   │  (Reset bootcount to indicate successful boot)                   │  │
│   │                                                                  │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   Manual Recovery Commands:                                             │
│   # From U-Boot prompt (serial console):                                │
│   => setenv bootside b        # Switch to alternate                     │
│   => saveenv                                                            │
│   => reset                                                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files:

| Repository | File/Directory | Description |
|------------|----------------|-------------|
| phosphor-bmc-code-mgmt | `item_updater.cpp` | Main update logic |
| phosphor-bmc-code-mgmt | `activation.cpp` | Activation state machine |
| phosphor-bmc-code-mgmt | `image_verify.cpp` | Signature verification |
| phosphor-bmc-code-mgmt | `flash.cpp` | Flash write operations |
| openbmc/meta-phosphor | `recipes-phosphor/flash/` | Flash recipes |
| u-boot | `board/aspeed/` | ASPEED board support |

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus (limited dual-flash functionality), ASPEED AST2500/AST2600 EVB
