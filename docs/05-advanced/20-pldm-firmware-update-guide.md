---
layout: default
title: PLDM Firmware Update
parent: Advanced Topics
nav_order: 20
difficulty: advanced
prerequisites:
  - mctp-pldm-guide
  - firmware-update-guide
last_modified_date: 2026-02-07
---

# PLDM Firmware Update (Type 5)
{: .no_toc }

Update device firmware using PLDM Type 5 (DSP0267) — package creation, update agent workflow, component transfer, activation, and integration with OpenBMC's update infrastructure.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**PLDM for Firmware Update** (DMTF [DSP0267](https://www.dmtf.org/sites/default/files/standards/documents/DSP0267_1.2.0WIP99.pdf)) provides a standardized protocol for updating firmware on any PLDM-capable device — GPUs, NICs, NVMe drives, power supplies, Bridge ICs (OpenBIC), FPGAs, and more. It eliminates the need for vendor-specific update tools by defining a common update flow.

In OpenBMC, the `pldmd` daemon acts as the **Update Agent (UA)** — the entity that initiates and drives the firmware update process. The device being updated is the **Firmware Device (FD)**. The UA sends the firmware package, the FD pulls data from the UA, verifies the image, applies it, and optionally activates the new firmware.

**Key concepts covered:**
- PLDM firmware update package format (component images + metadata)
- Update Agent (UA) / Firmware Device (FD) roles and state machines
- The complete update flow: request → component transfer → verify → apply → activate
- Package creation with `pldm_fwup_pkg_creator.py`
- Integration with Redfish UpdateService
- Multi-component and multi-device update patterns

{: .note }
This guide covers PLDM-based firmware update for platform devices. For host BIOS flash update via SPI/GPIO mux, see the [BIOS Firmware Management Guide]({% link docs/05-advanced/16-bios-firmware-management-guide.md %}). For the general OpenBMC firmware update framework, see the [Firmware Update Guide]({% link docs/05-advanced/03-firmware-update-guide.md %}).

---

## Architecture

### Roles

| Role | Entity | Description |
|------|--------|-------------|
| **Update Agent (UA)** | BMC (`pldmd`) | Initiates updates, serves firmware data to the FD |
| **Firmware Device (FD)** | Target device (GPU, NIC, BIC, etc.) | Receives firmware, verifies, applies, and activates |

The key design principle: the **FD pulls data from the UA**. The UA does not push firmware directly — instead, the FD requests specific byte ranges of the component image from the UA via `RequestFirmwareData` commands.

### Update Flow Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│            PLDM Firmware Update Architecture                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                         BMC                                  │   │
│  │                                                              │   │
│  │  Redfish UpdateService                                       │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  phosphor-software-manager                                   │   │
│  │       │                                                      │   │
│  │       ▼                                                      │   │
│  │  pldmd (Update Agent)                                        │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │ 1. Parse PLDM FW package                            │     │   │
│  │  │ 2. Match package to target FD (device descriptors)  │     │   │
│  │  │ 3. RequestUpdate → FD                               │     │   │
│  │  │ 4. PassComponentTable → FD                          │     │   │
│  │  │ 5. UpdateComponent → FD                             │     │   │
│  │  │ 6. Serve RequestFirmwareData from FD                │     │   │
│  │  │ 7. Wait for TransferComplete / VerifyComplete       │     │   │
│  │  │ 8. Wait for ApplyComplete                           │     │   │
│  │  │ 9. ActivateFirmware → FD                            │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  └──────────────────────────────┬───────────────────────────────┘   │
│                                 │  PLDM over MCTP                   │
│                                 │                                   │
│  ┌──────────────────────────────┴───────────────────────────────┐   │
│  │                    Firmware Device (FD)                      │   │
│  │                                                              │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │ 1. Accept RequestUpdate                             │     │   │
│  │  │ 2. Review component table (compatible?)             │     │   │
│  │  │ 3. RequestFirmwareData → UA (pull image chunks)     │     │   │
│  │  │ 4. TransferComplete → UA                            │     │   │
│  │  │ 5. Verify image (signature, CRC)                    │     │   │
│  │  │ 6. VerifyComplete → UA                              │     │   │
│  │  │ 7. Apply image (write to flash)                     │     │   │
│  │  │ 8. ApplyComplete → UA                               │     │   │
│  │  │ 9. Activate on next reset (or self-activate)        │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### State Machine

The Firmware Device progresses through these states during an update:

```
┌───────────┐
│   IDLE    │ ◀──────────────────────────────────────────────┐
└─────┬─────┘                                                │
      │ RequestUpdate                                        │
      ▼                                                      │
┌───────────┐                                                │
│   LEARN   │  UA sends PassComponentTable                   │
└─────┬─────┘                                                │
      │ All components passed                                │
      ▼                                                      │
┌───────────┐                                                │
│   READY   │  UA sends UpdateComponent                      │
└─────┬─────┘                                                │
      │ FD starts pulling data                               │
      ▼                                                      │
┌───────────┐                                                │
│ DOWNLOAD  │  FD sends RequestFirmwareData (loop)           │
│           │  FD sends TransferComplete                     │
└─────┬─────┘                                                │
      │                                                      │
      ▼                                                      │
┌───────────┐                                                │
│  VERIFY   │  FD validates image                            │
│           │  FD sends VerifyComplete                       │
└─────┬─────┘                                                │
      │                                                      │
      ▼                                                      │
┌───────────┐                                                │
│   APPLY   │  FD writes image to flash                      │
│           │  FD sends ApplyComplete                        │
└─────┬─────┘                                                │
      │ More components? → back to READY                     │
      │ All done?                                            │
      ▼                                                      │
┌───────────┐                                                │
│ ACTIVATE  │  UA sends ActivateFirmware                     │
│           │  FD activates new image (may require reset)    │
└───────────┘──────────────────────────────── back to IDLE ──┘
```

---

## PLDM Commands

### UA → FD Commands (BMC sends to device)

| Command | Code | Description |
|---------|------|-------------|
| `RequestUpdate` | 0x10 | Initiate update, specify max transfer size |
| `PassComponentTable` | 0x13 | Send component metadata for FD to review |
| `UpdateComponent` | 0x14 | Start transferring a specific component |
| `ActivateFirmware` | 0x1A | Activate new firmware (self-contained or pending reset) |
| `GetStatus` | 0x1B | Query FD's current update state |
| `CancelUpdateComponent` | 0x1C | Cancel current component transfer |
| `CancelUpdate` | 0x1D | Cancel entire update process |

### FD → UA Commands (Device sends to BMC)

| Command | Code | Description |
|---------|------|-------------|
| `RequestFirmwareData` | 0x15 | Pull a chunk of component image from the UA |
| `TransferComplete` | 0x16 | All data received for current component |
| `VerifyComplete` | 0x17 | Image verification succeeded or failed |
| `ApplyComplete` | 0x18 | Image applied to storage |

### Inventory Commands (pre-update discovery)

| Command | Code | Description |
|---------|------|-------------|
| `QueryDeviceIdentifiers` | 0x01 | Get device descriptors (vendor, model, serial) |
| `GetFirmwareParameters` | 0x02 | Get current firmware versions and component info |

---

## Firmware Update Package

### Package Structure

A PLDM firmware update package bundles one or more component images with metadata:

```
┌──────────────────────────────────────────────────────────┐
│               PLDM Firmware Update Package               │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Package Header Information                        │  │
│  │  - PackageHeaderIdentifier (UUID)                  │  │
│  │  - PackageHeaderFormatRevision                     │  │
│  │  - PackageReleaseDateTime                          │  │
│  │  - ComponentBitmapBitLength                        │  │
│  │  - PackageVersionString                            │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Firmware Device Identification Area               │  │
│  │  - DeviceIDRecordCount                             │  │
│  │  - For each device:                                │  │
│  │    - Descriptors (vendor, device, subsystem IDs)   │  │
│  │    - ApplicableComponents bitmask                  │  │
│  │    - ComponentImageSetVersionString                │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Component Image Information Area                  │  │
│  │  - ComponentImageCount                             │  │
│  │  - For each component:                             │  │
│  │    - ComponentClassification                       │  │
│  │    - ComponentIdentifier                           │  │
│  │    - ComponentComparisonStamp                      │  │
│  │    - ComponentOptions                              │  │
│  │    - RequestedComponentActivationMethod            │  │
│  │    - ComponentLocationOffset (into package)        │  │
│  │    - ComponentSize                                 │  │
│  │    - ComponentVersionString                        │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Package Header Checksum (CRC-32)                  │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Component Image 0 (raw firmware binary)           │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  Component Image 1 (raw firmware binary)           │  │
│  ├────────────────────────────────────────────────────┤  │
│  │  Component Image N ...                             │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Component Classifications

| Classification | ID | Description |
|---------------|-----|-------------|
| Unknown | 0x0000 | Unspecified |
| Other | 0x0001 | Vendor-defined |
| Firmware | 0x000A | Device firmware |
| BIOS/UEFI | 0x000C | Host BIOS image |
| CPLD | 0x0010 | CPLD bitstream |
| Diagnostic | 0x000D | Diagnostic software |
| Operating System | 0x000E | OS image |
| Middleware | 0x000F | Middleware software |

### Activation Methods

| Method | Bit | Description |
|--------|-----|-------------|
| Automatic | 0 | FD activates immediately after apply |
| Self-Contained | 1 | FD can activate without external trigger |
| Medium-Specific Reset | 2 | Requires bus reset (PCIe, I2C) |
| System Reboot | 3 | Requires full system reboot |
| DC Power Cycle | 4 | Requires power cycle |
| AC Power Cycle | 5 | Requires AC power cycle |
| Pending Image | 6 | FD holds image; UA sends ActivateFirmware later |

---

## Creating Firmware Update Packages

### Using pldm_fwup_pkg_creator.py

OpenBMC provides a Python script to create PLDM firmware update packages from raw component images and a metadata JSON file.

```bash
# Location in the pldm repository
# tools/fw-update/pldm_fwup_pkg_creator.py

# Usage
python3 pldm_fwup_pkg_creator.py \
    <output_package_name> \
    <metadata_json> \
    <component_image_1> [component_image_2] ...
```

### Metadata JSON Format

```json
{
    "PackageHeaderInformation": {
        "PackageHeaderIdentifier": "f018878c-cb7d-4943-9800-a02f059aca02",
        "PackageHeaderFormatRevision": 1,
        "PackageReleaseDateTime": "2026-02-07T00:00:00Z",
        "ComponentBitmapBitLength": 8,
        "PackageVersionString": "1.0.0"
    },
    "FirmwareDeviceIdentificationArea": [
        {
            "DeviceUpdateOptionFlags": 0,
            "ApplicableComponents": [0],
            "ComponentImageSetVersionString": "2.1.0",
            "FirmwareDevicePackageDataLength": 0,
            "Descriptors": [
                {
                    "DescriptorType": 0,
                    "DescriptorData": "0x10DE"
                },
                {
                    "DescriptorType": 1,
                    "DescriptorData": "0x1234"
                }
            ]
        }
    ],
    "ComponentImageInformationArea": [
        {
            "ComponentClassification": 10,
            "ComponentIdentifier": 1,
            "ComponentComparisonStamp": 0,
            "ComponentOptions": 0,
            "RequestedComponentActivationMethod": 6,
            "ComponentVersionString": "2.1.0"
        }
    ]
}
```

### Example: Package a GPU Firmware Update

```bash
# Create a single-component package for a GPU firmware
python3 pldm_fwup_pkg_creator.py \
    gpu_firmware_v2.1.0.pldm \
    gpu_metadata.json \
    gpu_firmware.bin

# Create a multi-component package (firmware + CPLD)
python3 pldm_fwup_pkg_creator.py \
    gpu_full_update_v2.1.0.pldm \
    gpu_multi_metadata.json \
    gpu_firmware.bin \
    gpu_cpld.bin
```

### Device Descriptor Types

Descriptors in the metadata identify which device the package targets:

| Type | ID | Description | Example |
|------|-----|-------------|---------|
| PCI Vendor ID | 0 | PCIe vendor | `0x10DE` (NVIDIA) |
| PCI Device ID | 1 | PCIe device | `0x1234` |
| PCI Subsystem Vendor ID | 2 | Subsystem vendor | `0x10DE` |
| PCI Subsystem ID | 3 | Subsystem device | `0x5678` |
| PCI Revision ID | 4 | Revision | `0x01` |
| IANA Enterprise ID | 5 | IANA enterprise number | `0x00A015` |
| UUID | 6 | Device UUID | RFC 4122 format |
| Vendor Defined | 0xFFFF | OEM-specific | Arbitrary |

---

## Complete Update Flow

### Step-by-Step Protocol Exchange

```
UA (BMC pldmd)                               FD (Device)
      │                                           │
      │  ══════ PRE-UPDATE DISCOVERY ══════       │
      │                                           │
      │  QueryDeviceIdentifiers                   │
      │──────────────────────────────────────────▶│
      │  Descriptors: VendorID=0x10DE,            │
      │◀──────────────────────────────────────────│
      │    DeviceID=0x1234                        │
      │                                           │
      │  GetFirmwareParameters                    │
      │──────────────────────────────────────────▶│
      │  ActiveFW: "2.0.0", PendingFW: none       │
      │◀──────────────────────────────────────────│
      │  Components: [FW (id=1), CPLD (id=2)]     │
      │                                           │
      │  ══════ UPDATE INITIATION ══════          │
      │                                           │
      │  RequestUpdate                            │
      │──────────────────────────────────────────▶│
      │  MaxTransferSize=4096                     │
      │  NumComponents=1                          │
      │                                           │
      │  RequestUpdate response: OK               │
      │◀──────────────────────────────────────────│
      │                                           │
      │  PassComponentTable (comp 1 of 1)         │
      │──────────────────────────────────────────▶│
      │  CompID=1, CompVersion="2.1.0"            │
      │                                           │
      │  PassComponentTable response:             │
      │◀──────────────────────────────────────────│
      │  ComponentResponse=CanBeUpdated            │
      │                                           │
      │  ══════ DATA TRANSFER ══════              │
      │                                           │
      │  UpdateComponent                          │
      │──────────────────────────────────────────▶│
      │  CompID=1, CompSize=2097152 (2MB)         │
      │                                           │
      │  UpdateComponent response: OK             │
      │◀──────────────────────────────────────────│
      │                                           │
      │          RequestFirmwareData              │
      │◀──────────────────────────────────────────│
      │          Offset=0, Length=4096            │
      │                                           │
      │          RequestFirmwareData response     │
      │──────────────────────────────────────────▶│
      │          (4096 bytes of image data)       │
      │                                           │
      │          ... (repeats until all data sent)│
      │                                           │
      │          RequestFirmwareData              │
      │◀──────────────────────────────────────────│
      │          Offset=2093056, Length=4096      │
      │          (final chunk)                    │
      │                                           │
      │  ══════ VERIFY & APPLY ══════             │
      │                                           │
      │          TransferComplete                 │
      │◀──────────────────────────────────────────│
      │          TransferResult=Success           │
      │                                           │
      │          TransferComplete response: OK    │
      │──────────────────────────────────────────▶│
      │                                           │
      │          VerifyComplete                   │
      │◀──────────────────────────────────────────│
      │          VerifyResult=Success             │
      │                                           │
      │          VerifyComplete response: OK      │
      │──────────────────────────────────────────▶│
      │                                           │
      │          ApplyComplete                    │
      │◀──────────────────────────────────────────│
      │          ApplyResult=Success              │
      │          ActivationMethod=PendingImage    │
      │                                           │
      │          ApplyComplete response: OK       │
      │──────────────────────────────────────────▶│
      │                                           │
      │  ══════ ACTIVATION ══════                 │
      │                                           │
      │  ActivateFirmware                         │
      │──────────────────────────────────────────▶│
      │  SelfContainedActivation=true             │
      │                                           │
      │  ActivateFirmware response: OK            │
      │◀──────────────────────────────────────────│
      │  EstimatedTimeForActivation=30s           │
      │                                           │
      │  (Device resets and boots new firmware)   │
      │                                           │
```

### Transfer Size and Chunking

The `MaxTransferSize` negotiated in `RequestUpdate` determines the maximum bytes per `RequestFirmwareData` exchange. Typical values:

| Transport | Typical MaxTransferSize | Notes |
|-----------|------------------------|-------|
| MCTP over I2C/SMBus | 256 bytes | Limited by I2C transaction size |
| MCTP over PCIe VDM | 4096 bytes | PCIe allows larger payloads |
| MCTP over I3C | 1024 bytes | I3C higher bandwidth than I2C |

{: .tip }
Larger transfer sizes significantly reduce update time. A 2 MB firmware image with 256-byte chunks requires ~8000 round-trips, while 4096-byte chunks need only ~500.

---

## Redfish Integration

### Upload via Redfish UpdateService

```bash
# Upload a PLDM firmware update package via Redfish
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @gpu_firmware_v2.1.0.pldm \
    https://${BMC_IP}/redfish/v1/UpdateService

# Multipart upload targeting a specific device
curl -k -u root:0penBmc \
    -X POST \
    -F 'UpdateParameters={"Targets":["/redfish/v1/Chassis/GPU_0"]};type=application/json' \
    -F 'UpdateFile=@gpu_firmware_v2.1.0.pldm;type=application/octet-stream' \
    https://${BMC_IP}/redfish/v1/UpdateService/update
```

### Monitor Update Progress

```bash
# Check update task progress
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/TaskService/Tasks/0

# Example response:
# {
#     "TaskState": "Running",
#     "PercentComplete": 65,
#     "Messages": [
#         {"Message": "Transferring component 1 of 1"},
#         {"Message": "Downloaded 1.3 MB of 2.0 MB"}
#     ]
# }

# Check firmware inventory after update
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/UpdateService/FirmwareInventory
```

### Query Device Firmware Versions

```bash
# Query current firmware versions via PLDM inventory
pldmtool fw_update GetFirmwareParameters -m <eid>

# Example output:
# {
#     "ActiveComponentImageSetVersionString": "2.0.0",
#     "PendingComponentImageSetVersionString": "2.1.0",
#     "ComponentParameterEntries": [
#         {
#             "ComponentClassification": "Firmware",
#             "ComponentIdentifier": 1,
#             "ActiveComponentVersionString": "2.0.0",
#             "PendingComponentVersionString": "2.1.0"
#         }
#     ]
# }
```

---

## Multi-Component Updates

A single PLDM firmware package can contain multiple component images — for example, main firmware + CPLD bitstream + configuration data. The UA updates each component sequentially:

```
UA                                         FD
 │  RequestUpdate (NumComponents=3)         │
 │──────────────────────────────────────▶   │
 │  PassComponentTable (comp 1: FW)         │
 │──────────────────────────────────────▶   │
 │  PassComponentTable (comp 2: CPLD)       │
 │──────────────────────────────────────▶   │
 │  PassComponentTable (comp 3: Config)     │
 │──────────────────────────────────────▶   │
 │                                          │
 │  UpdateComponent (comp 1: FW)            │
 │──────────────────────────────────────▶   │
 │  ... transfer, verify, apply comp 1 ...  │
 │                                          │
 │  UpdateComponent (comp 2: CPLD)          │
 │──────────────────────────────────────▶   │
 │  ... transfer, verify, apply comp 2 ...  │
 │                                          │
 │  UpdateComponent (comp 3: Config)        │
 │──────────────────────────────────────▶   │
 │  ... transfer, verify, apply comp 3 ...  │
 │                                          │
 │  ActivateFirmware (all components)       │
 │──────────────────────────────────────▶   │
```

{: .warning }
Image signature verification is performed by the Firmware Device, not the BMC. The UA performs only compatibility checks (matching device descriptors). The FD is responsible for cryptographic validation of the image before applying it.

---

## Build Configuration

### Enable PLDM Firmware Update in OpenBMC

```bitbake
# In your machine .conf or local.conf
EXTRA_OEMESON:pn-pldm += " \
    -Dfirmware-update=enabled \
"

# Include pldm in the image
IMAGE_INSTALL:append = " pldm"

# Optional: include the package creator tool for development
IMAGE_INSTALL:append = " pldm-tools"
```

### pldmd Firmware Update Meson Options

| Option | Default | Description |
|--------|---------|-------------|
| `firmware-update` | `enabled` | Enable PLDM Type 5 firmware update |
| `maximum-transfer-size` | `4096` | Max bytes per RequestFirmwareData |

---

## Troubleshooting

### Issue: Package Not Accepted by Device

**Symptom**: `RequestUpdate` or `PassComponentTable` returns an error.

**Cause**: Device descriptor mismatch — the package targets a different device.

**Solution**:
```bash
# Query what the device reports as its identifiers
pldmtool fw_update QueryDeviceIdentifiers -m <eid>

# Compare with your package metadata JSON
# Vendor ID, Device ID, and descriptors must match exactly

# Check if the device supports the requested activation method
pldmtool fw_update GetFirmwareParameters -m <eid>
```

### Issue: Transfer Stalls

**Symptom**: Update progress stops at a certain percentage.

**Cause**: MCTP transport timeout, I2C bus error, or FD internal error.

**Solution**:
```bash
# Check PLDM update status
pldmtool fw_update GetStatus -m <eid>

# Check pldmd logs for transfer errors
journalctl -u pldmd -f | grep -i "fw_update\|firmware\|transfer"

# Check MCTP connectivity
pldmtool base GetTID -m <eid>

# Check for I2C/bus errors
dmesg | grep -i "i2c\|mctp"
```

### Issue: Verify or Apply Fails

**Symptom**: `VerifyComplete` or `ApplyComplete` returns a failure result.

**Cause**: Image signature invalid, incompatible firmware version, or flash write error on the FD.

**Solution**:
```bash
# Check the completion code in pldmd logs
journalctl -u pldmd --no-pager | grep -i "verify\|apply"

# VerifyResult codes:
#   0 = Success
#   1 = GeneralError
#   2 = VersionMismatch
#   3 = SecurityCheckFail
#   4 = IncompleteUpdate

# If signature fails, verify the image is correctly signed
# for the target device's trust chain
```

### Issue: Activation Requires Manual Reset

**Symptom**: New firmware is applied but device still runs old version.

**Cause**: The FD's `RequestedComponentActivationMethod` requires a reset that hasn't occurred.

**Solution**:
```bash
# Check what activation method the device requires
pldmtool fw_update GetFirmwareParameters -m <eid>
# Look for ActivationMethod field

# If "Medium-Specific Reset" — reset the bus
# If "DC Power Cycle" — power cycle the device
# If "System Reboot" — reboot the host

# After reset, verify new firmware is active
pldmtool fw_update GetFirmwareParameters -m <eid>
# ActiveComponentVersionString should show new version
```

### Debug Commands Summary

```bash
# Pre-update discovery
pldmtool fw_update QueryDeviceIdentifiers -m <eid>
pldmtool fw_update GetFirmwareParameters -m <eid>

# During update
pldmtool fw_update GetStatus -m <eid>

# Monitor pldmd update progress
journalctl -u pldmd -f | grep -i fw_update

# Cancel a stuck update
pldmtool fw_update CancelUpdate -m <eid>
```

---

## References

### DMTF Specifications
- [DSP0267 — PLDM for Firmware Update](https://www.dmtf.org/sites/default/files/standards/documents/DSP0267_1.2.0WIP99.pdf) — Core firmware update specification
- [DSP0240 — PLDM Base Specification](https://www.dmtf.org/dsp/DSP0240) — Message format and base commands
- [DSP0245 — PLDM IDs and Codes](https://www.dmtf.org/sites/default/files/standards/documents/DSP0245_1.4.0.pdf) — Descriptor types, component classifications

### OpenBMC Repositories
- [openbmc/pldm](https://github.com/openbmc/pldm) — PLDM daemon (fw-update module)
- [openbmc/pldm/tools/fw-update](https://github.com/openbmc/pldm/tree/master/tools/fw-update) — Package creator script
- [NVIDIA/PLDM-unpack](https://github.com/NVIDIA/PLDM-unpack) — Tool to inspect/unpack PLDM firmware packages

### Related Guides
- [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) — MCTP transport and general PLDM concepts
- [PLDM Platform Monitoring Guide]({% link docs/05-advanced/19-pldm-platform-monitoring-guide.md %}) — PLDM Type 2 sensors and effecters
- [Firmware Update Guide]({% link docs/05-advanced/03-firmware-update-guide.md %}) — General OpenBMC firmware update framework
- [BIOS Firmware Management Guide]({% link docs/05-advanced/16-bios-firmware-management-guide.md %}) — SPI-based BIOS flash and PLDM BIOS config

### OCP Standards
- [OCP GPU Firmware Update Specification](https://www.opencompute.org/documents/external-ocp-gpu-fw-update-specification-v1-0-1-pdf) — GPU-specific PLDM firmware update guidance

---

{: .note }
**Tested on**: OpenBMC master branch. PLDM firmware update requires real hardware with PLDM-capable firmware devices. Use `pldm_fwup_pkg_creator.py` to create test packages for development.
