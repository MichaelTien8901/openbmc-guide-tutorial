---
layout: default
title: MCTP & PLDM Guide
parent: Advanced Topics
nav_order: 1
difficulty: advanced
prerequisites:
  - dbus-guide
  - openbmc-overview
---

# MCTP & PLDM Guide
{: .no_toc }

Configure and use MCTP and PLDM protocols on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**MCTP (Management Component Transport Protocol)** and **PLDM (Platform Level Data Model)** are DMTF standards for platform management communication. They provide a modern, scalable alternative to IPMI for device-to-device management in data center environments.

### Why MCTP/PLDM?

| Feature | IPMI | MCTP/PLDM |
|---------|------|-----------|
| Message size | 256 bytes max | 64KB+ |
| Transport | KCS, BT, IPMB | I2C, PCIe, SMBus, USB, Serial |
| Extensibility | OEM codes | Typed messages with PDR |
| Discovery | Manual | Automatic endpoint discovery |
| Sensors | SDR-based | PDR with rich metadata |
| Security | Limited | SPDM integration |

### Protocol Stack

```
+-------------------------------------------------------------------------+
|                    MCTP/PLDM Protocol Stack                             |
+-------------------------------------------------------------------------+
|                                                                         |
|   +------------------------------------------------------------------+  |
|   |                    Application Layer                             |  |
|   |                                                                  |  |
|   |   +----------+  +----------+  +----------+  +----------+         |  |
|   |   |  PLDM    |  |  SPDM    |  |  NCSI    |  |  NVMe-MI |         |  |
|   |   | Types    |  | Security |  | Network  |  | Storage  |         |  |
|   |   | 0,2,3,4,5|  |          |  | Control  |  | Mgmt     |         |  |
|   |   +----------+  +----------+  +----------+  +----------+         |  |
|   +------------------------------------------------------------------+  |
|                                    |                                    |
|   +------------------------------------------------------------------+  |
|   |                    MCTP Transport Layer                          |  |
|   |                                                                  |  |
|   |   +------------------+  +------------------+  +-----------------+|  |
|   |   | Message Assembly |  | Packet Routing   |  | EID Management  ||  |
|   |   | & Fragmentation  |  | & Forwarding     |  | & Discovery     ||  |
|   |   +------------------+  +------------------+  +-----------------+|  |
|   +------------------------------------------------------------------+  |
|                                    |                                    |
|   +------------------------------------------------------------------+  |
|   |                    Physical Transport Bindings                   |  |
|   |                                                                  |  |
|   |   +--------+  +--------+  +--------+  +--------+  +--------+     |  |
|   |   | I2C    |  | SMBus  |  | PCIe   |  | Serial |  | USB    |     |  |
|   |   | DSP0237|  | DSP0237|  | DSP0238|  | DSP0239|  | DSP0283|     |  |
|   |   +--------+  +--------+  +--------+  +--------+  +--------+     |  |
|   +------------------------------------------------------------------+  |
|                                                                         |
+-------------------------------------------------------------------------+
```

---

## MCTP Protocol Deep Dive

### MCTP Packet Format

Every MCTP packet follows this structure:

```
+-------+-------+-------+-------+-------+-------+-------+-------+
| Byte 0        | Byte 1        | Byte 2        | Byte 3        |
+---------------+---------------+---------------+---------------+
| Header Ver(4) | Dest EID (8)  | Source EID(8) | SOM|EOM|PktSeq|
| Rsvd (4)      |               |               | TO |Tag (3)   |
+---------------+---------------+---------------+---------------+
|                    Message Payload                            |
|                    (variable length)                          |
+---------------------------------------------------------------+
|                    Integrity Check (optional)                 |
+---------------------------------------------------------------+
```

#### Header Fields

| Field | Bits | Description |
|-------|------|-------------|
| Header Version | 4 | Always 0x1 for MCTP v1.x |
| Reserved | 4 | Must be 0 |
| Destination EID | 8 | Target endpoint ID (0x00-0xFF) |
| Source EID | 8 | Sender endpoint ID |
| SOM | 1 | Start of Message flag |
| EOM | 1 | End of Message flag |
| Packet Sequence | 2 | Sequence number for fragmentation |
| TO | 1 | Tag Owner (1=requester, 0=responder) |
| Message Tag | 3 | Unique tag per outstanding request |

#### Special Endpoint IDs

| EID | Name | Purpose |
|-----|------|---------|
| 0x00 | Null EID | Unassigned endpoint |
| 0x01-0x07 | Reserved | Reserved by DMTF |
| 0x08 | Default BMC | Common BMC address |
| 0x09-0xFE | General | Assignable to endpoints |
| 0xFF | Broadcast | All endpoints on network |

### MCTP Message Types

| Type | Value | Description | Specification |
|------|-------|-------------|---------------|
| MCTP Control | 0x00 | Endpoint management | DSP0236 |
| PLDM | 0x01 | Platform management | DSP0240 |
| NCSI | 0x02 | Network controller | DSP0222 |
| Ethernet | 0x03 | Ethernet frames | DSP0236 |
| NVMe-MI | 0x04 | NVMe management | NVM Express |
| SPDM | 0x05 | Security protocol | DSP0274 |
| Secure SPDM | 0x06 | Secured SPDM | DSP0277 |
| Vendor Defined (PCI) | 0x7E | PCI vendor ID | DSP0236 |
| Vendor Defined (IANA) | 0x7F | IANA enterprise | DSP0236 |

### MCTP Control Messages

MCTP Control (type 0x00) manages the MCTP network:

```
MCTP Control Message Format:
+-------+-------+-------+-------+
| IC|MsgType(7)| RqDI| Command |
| (1)          | (1) |Instance |
|              |     | ID (5)  |
+-------+-------+-------+-------+
|          Command Data         |
+-------------------------------+
```

#### Control Commands

| Command | Code | Description |
|---------|------|-------------|
| Set Endpoint ID | 0x01 | Assign EID to endpoint |
| Get Endpoint ID | 0x02 | Query endpoint's EID |
| Get Endpoint UUID | 0x03 | Get unique identifier |
| Get MCTP Version | 0x04 | Query MCTP version support |
| Get Message Type Support | 0x05 | Query supported message types |
| Get Vendor Defined Message Support | 0x06 | Query vendor extensions |
| Resolve Endpoint ID | 0x07 | Map EID to physical address |
| Allocate Endpoint IDs | 0x08 | Request EID pool |
| Routing Information Update | 0x09 | Update routing tables |
| Get Routing Table Entries | 0x0A | Query routing table |
| Prepare Endpoint Discovery | 0x0B | Reset discovery state |
| Endpoint Discovery | 0x0C | Discover endpoints |
| Discovery Notify | 0x0D | Notify discovery complete |

### Message Fragmentation

MCTP fragments large messages across multiple packets:

```
Large Message (> MTU):
+------------------+------------------+------------------+
|  Packet 1        |  Packet 2        |  Packet 3        |
|  SOM=1, EOM=0    |  SOM=0, EOM=0    |  SOM=0, EOM=1    |
|  Seq=0           |  Seq=1           |  Seq=2           |
|  [Payload 1]     |  [Payload 2]     |  [Payload 3]     |
+------------------+------------------+------------------+

Reassembled at receiver:
+----------------------------------------------------------+
|  Complete Message = Payload 1 + Payload 2 + Payload 3    |
+----------------------------------------------------------+
```

#### MTU by Transport

| Transport | Minimum MTU | Typical MTU |
|-----------|-------------|-------------|
| I2C/SMBus | 64 bytes | 64-256 bytes |
| PCIe VDM | 64 bytes | 64-4096 bytes |
| Serial | 64 bytes | 64-256 bytes |
| USB | 64 bytes | 512 bytes |

---

## MCTP Transport Bindings

### I2C/SMBus Binding (DSP0237)

```
I2C MCTP Packet Structure:
+-------+-------+-------+-------+-------+-------+-------+
| Slave | Cmd   | Byte  | Src   | Hdr   | MCTP Header   |
| Addr  | Code  | Count | Addr  | Ver   | + Payload     |
| (7+1) | 0x0F  | (8)   | (7+1) | (4+4) |               |
+-------+-------+-------+-------+-------+---------------+
|                    Payload Data                       |
+-------------------------------------------------------+
| PEC (optional)                                        |
+-------------------------------------------------------+
```

#### I2C Configuration

```bash
# Create MCTP I2C interface
mctp link add mctpi2c1 type i2c bus 1

# Set interface up
mctp link set mctpi2c1 up

# Set local address
mctp addr add 8 dev mctpi2c1

# Verify configuration
mctp link show
mctp addr show
```

#### Device Tree for I2C MCTP

```dts
&i2c1 {
    status = "okay";

    /* MCTP-capable device at address 0x50 */
    mctp_device@50 {
        compatible = "mctp-i2c-controller";
        reg = <0x50>;
    };
};
```

### PCIe VDM Binding (DSP0238)

PCIe Vendor Defined Messages carry MCTP over PCIe:

```
PCIe VDM TLP Format:
+-------+-------+-------+-------+
| Fmt   | Type  | TC    | Attr  |  <- TLP Header
| (3)   | (5)   | (3)   | (2)   |
+-------+-------+-------+-------+
| Length        | Requester ID  |
+---------------+---------------+
| Tag   | Message Code          |  <- VDM Header
| (8)   | Vendor ID (16)        |
+-------+-----------------------+
| MCTP Transport Header         |  <- MCTP Packet
+-------------------------------+
| MCTP Payload                  |
+-------------------------------+
```

#### PCIe VDM Configuration

```bash
# PCIe MCTP typically auto-discovered
# Check for PCIe MCTP devices
lspci -vvv | grep -i mctp

# MCTP over PCIe uses kernel MCTP stack
mctp link
```

### Serial Binding (DSP0239)

```
Serial MCTP Frame:
+-------+-------+-------+-------+-------+
| Sync  | Rev   | Byte  | MCTP Packet   |
| 0x7E  | (8)   | Count |               |
+-------+-------+-------+---------------+
| FCS (16-bit CRC)                      |
+---------------------------------------+
```

---

## PLDM Protocol Deep Dive

### PLDM Message Format

```
PLDM Message Structure:
+-------+-------+-------+-------+-------+-------+-------+
| MCTP  |PLDM Hdr       | PLDM Payload                  |
| Msg   |               |                               |
| Type  |               |                               |
| 0x01  |               |                               |
+-------+-------+-------+-------------------------------+

PLDM Header:
+-------+-------+-------+-------+
| Rq|D|IID(5)   | Hdr   | PLDM  |
| (1)(1)        | Ver(2)| Type  |
|               |       | (6)   |
+---------------+-------+-------+
| Command Code (8)              |
+-------------------------------+
```

#### Header Fields

| Field | Bits | Description |
|-------|------|-------------|
| Rq (Request) | 1 | 1=Request, 0=Response |
| D (Datagram) | 1 | 1=No response expected |
| Instance ID | 5 | Request/response correlation |
| Header Version | 2 | Always 0b00 |
| PLDM Type | 6 | Message type (0-63) |
| Command Code | 8 | Type-specific command |

### PLDM Types

| Type | Name | Specification | Description |
|------|------|---------------|-------------|
| 0 | Base | DSP0240 | Discovery, TID, versions |
| 1 | SMBIOS | DSP0246 | SMBIOS table transfer |
| 2 | Monitoring & Control | DSP0248 | Sensors, effecters, events |
| 3 | BIOS Control | DSP0247 | BIOS attributes |
| 4 | FRU Data | DSP0257 | Field Replaceable Unit data |
| 5 | Firmware Update | DSP0267 | Firmware update protocol |
| 6 | Redfish Device Enablement | DSP0218 | Redfish over PLDM |
| 63 | OEM | - | Vendor-specific |

### PLDM Type 0: Base Commands

| Command | Code | Description |
|---------|------|-------------|
| SetTID | 0x01 | Set Terminus ID |
| GetTID | 0x02 | Get Terminus ID |
| GetPLDMVersion | 0x03 | Query PLDM type versions |
| GetPLDMTypes | 0x04 | Query supported PLDM types |
| GetPLDMCommands | 0x05 | Query commands for a type |
| SelectPLDMVersion | 0x06 | Negotiate version |
| NegotiateTransferParameters | 0x07 | Set transfer sizes |
| MultipartSend | 0x08 | Send large data |
| MultipartReceive | 0x09 | Receive large data |

#### Example: Get TID

```bash
# Request GetTID (Command 0x02)
pldmtool raw -m 9 -d 0x80 0x00 0x02

# Response format:
# [0]: Completion Code (0x00 = success)
# [1]: TID value
```

### PLDM Type 2: Monitoring & Control

This type handles sensors, effecters, and events.

#### Sensor Commands

| Command | Code | Description |
|---------|------|-------------|
| GetSensorReading | 0x11 | Read numeric sensor |
| GetSensorThresholds | 0x12 | Get threshold values |
| SetSensorThresholds | 0x13 | Set threshold values |
| RestoreSensorThresholds | 0x14 | Restore defaults |
| GetSensorHysteresis | 0x15 | Get hysteresis value |
| SetSensorHysteresis | 0x16 | Set hysteresis value |
| InitNumericSensor | 0x17 | Initialize sensor |
| GetStateSensorReading | 0x21 | Read state sensor |

#### Effecter Commands

| Command | Code | Description |
|---------|------|-------------|
| SetNumericEffecterValue | 0x31 | Set numeric effecter |
| GetNumericEffecterValue | 0x32 | Get numeric effecter value |
| SetStateEffecterStates | 0x39 | Set state effecter |
| GetStateEffecterStates | 0x3A | Get state effecter |

#### Event Commands

| Command | Code | Description |
|---------|------|-------------|
| PlatformEventMessage | 0x0A | Send platform event |
| PollForPlatformEventMessage | 0x0B | Poll for events |
| EventMessageSupported | 0x0C | Query event support |
| EventMessageBufferSize | 0x0D | Query buffer size |

### PLDM Type 5: Firmware Update

| Command | Code | Description |
|---------|------|-------------|
| QueryDeviceIdentifiers | 0x01 | Get device IDs |
| GetFirmwareParameters | 0x02 | Get FW info |
| RequestUpdate | 0x10 | Start update |
| PassComponentTable | 0x13 | Send component list |
| UpdateComponent | 0x14 | Update single component |
| RequestFirmwareData | 0x15 | Request FW chunk |
| TransferComplete | 0x16 | Transfer done |
| VerifyComplete | 0x17 | Verification done |
| ApplyComplete | 0x18 | Application done |
| ActivateFirmware | 0x1A | Activate new FW |
| GetStatus | 0x1B | Query update status |
| CancelUpdateComponent | 0x1C | Cancel component update |
| CancelUpdate | 0x1D | Cancel entire update |

---

## Platform Data Records (PDR)

PDRs describe the platform's sensors, effecters, and associations.

### PDR Structure

```
PDR Header (common to all PDRs):
+-------+-------+-------+-------+-------+-------+-------+-------+
| Record Handle (32 bits)                                       |
+---------------+---------------+---------------+---------------+
| PDR Hdr Ver(8)| PDR Type (8)  | Record Change#| Data Len (16) |
+---------------+---------------+---------------+---------------+
|                    PDR-specific data                          |
+---------------------------------------------------------------+
```

### PDR Types

| Type | Name | Description |
|------|------|-------------|
| 1 | Terminus Locator | Maps TID to MCTP EID |
| 2 | Numeric Sensor | Numeric sensor definition |
| 3 | Numeric Sensor Initialization | Init parameters |
| 4 | State Sensor | State sensor definition |
| 5 | State Sensor Initialization | Init parameters |
| 6 | Sensor Auxiliary Names | Sensor name strings |
| 9 | OEM Device | Vendor-specific device |
| 10 | OEM | Vendor-specific PDR |
| 11 | Numeric Effecter | Numeric effecter definition |
| 12 | Numeric Effecter Initialization | Init parameters |
| 13 | State Effecter | State effecter definition |
| 14 | State Effecter Initialization | Init parameters |
| 15 | Effecter Auxiliary Names | Effecter name strings |
| 20 | Entity Association | Entity hierarchy |
| 21 | Entity Auxiliary Names | Entity name strings |
| 22 | OEM Entity ID | Vendor entity types |

### Numeric Sensor PDR Example

```
Numeric Sensor PDR (Type 2):
+-------+-------+-------+-------+-------+-------+-------+-------+
| Terminus Handle (16) | Sensor ID (16)                         |
+---------------+---------------+---------------+---------------+
| Entity Type(16)       | Entity Instance (16)                  |
+---------------+---------------+---------------+---------------+
| Container ID (16)     | Sensor Init | Auxiliary Names         |
+---------------+---------------+---------------+---------------+
| Base Unit (8)         | Unit Modifier (8) | Rate Unit (8)     |
+-----------------------+-----------------------+---------------+
| ... additional fields for ranges, thresholds, etc.            |
+---------------------------------------------------------------+
```

### State Sets

State sensors/effecters use predefined state sets:

| State Set ID | Name | Example States |
|--------------|------|----------------|
| 1 | Health State | Normal, Warning, Critical |
| 2 | Availability | Available, Unavailable |
| 3 | Operational Status | Enabled, Disabled |
| 4 | Configuration State | Valid, Invalid |
| 11 | Link State | Up, Down |
| 15 | Power Device | On, Off, Powering On, Powering Off |
| 192 | Boot Progress | Primary Processor Init, Memory Init, PCI Init |
| 196 | System Power State | Off, On, Standby |

### Querying PDRs

```bash
# Get all PDRs
pldmtool platform getpdr -t all -m 9

# Get specific PDR types
pldmtool platform getpdr -t numericSensorPDR -m 9
pldmtool platform getpdr -t stateSensorPDR -m 9
pldmtool platform getpdr -t numericEffecterPDR -m 9
pldmtool platform getpdr -t stateEffecterPDR -m 9
pldmtool platform getpdr -t terminusLocatorPDR -m 9
pldmtool platform getpdr -t entityAssociationPDR -m 9

# Get PDR by record handle
pldmtool platform getpdr -d 1 -m 9
pldmtool platform getpdr -d 2 -m 9
```

---

## OpenBMC Implementation

### Architecture

```
+-------------------------------------------------------------------------+
|                    OpenBMC MCTP/PLDM Architecture                       |
+-------------------------------------------------------------------------+
|                                                                         |
|   +------------------------------------------------------------------+  |
|   |                      D-Bus Services                              |  |
|   |                                                                  |  |
|   |   +---------------+  +---------------+  +------------------+     |  |
|   |   | Sensor Service|  | State Manager |  | Firmware Update  |     |  |
|   |   | (dbus-sensors)|  | (phosphor-    |  | (phosphor-bmc-   |     |  |
|   |   |               |  |  state-mgr)   |  |  code-mgmt)      |     |  |
|   |   +-------+-------+  +-------+-------+  +---------+--------+     |  |
|   +-----------|------------------|---------------------|-------------+  |
|               |                  |                     |                |
|   +-----------+------------------+---------------------+-------------+  |
|   |                         D-Bus                                    |  |
|   |    xyz.openbmc_project.PLDM    xyz.openbmc_project.MCTP          |  |
|   +----------------------------------+-------------------------------+  |
|                                      |                                  |
|   +----------------------------------+-------------------------------+  |
|   |                           pldmd                                  |  |
|   |                                                                  |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   |   | PLDM Requester |  | PLDM Responder|  | PDR Manager      |    |  |
|   |   | (host comms)   |  |(BMC as target)|  | (PDR repository) |    |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   |                                                                  |  |
|   |   +----------------------------------------------------------+   |  |
|   |   |                       libpldm                            |   |  |
|   |   |  (PLDM message encode/decode, PDR parsing)               |   |  |
|   |   +----------------------------------------------------------+   |  |
|   +----------------------------------+-------------------------------+  |
|                                      |                                  |
|   +----------------------------------+-------------------------------+  |
|   |                           mctpd                                  |  |
|   |                                                                  |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   |   | Route Manager  |  | EID Pool      |  | Link Management  |    |  |
|   |   |                |  | Manager       |  |                  |    |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   |                                                                  |  |
|   |   +----------------------------------------------------------+   |  |
|   |   |                       libmctp                            |   |  |
|   |   |  (MCTP packet handling, transport bindings)              |   |  |
|   |   +----------------------------------------------------------+   |  |
|   +----------------------------------+-------------------------------+  |
|                                      |                                  |
|   +----------------------------------+-------------------------------+  |
|   |                    Linux Kernel MCTP Stack                       |  |
|   |                                                                  |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   |   | AF_MCTP Socket |  | MCTP Network  |  | Transport Drivers|    |  |
|   |   |                |  | Device        |  | (i2c-mctp, etc.) |    |  |
|   |   +----------------+  +---------------+  +------------------+    |  |
|   +------------------------------------------------------------------+  |
|                                                                         |
+-------------------------------------------------------------------------+
```

### libmctp

Low-level MCTP packet handling:

```c
// Key libmctp structures
struct mctp;                    // MCTP context
struct mctp_binding;            // Transport binding
struct mctp_pktbuf;             // Packet buffer

// Transport bindings
struct mctp_binding_i2c;        // I2C/SMBus
struct mctp_binding_astlpc;     // ASPEED LPC
struct mctp_binding_serial;     // Serial

// Key functions
mctp_init();                    // Initialize context
mctp_set_rx_all();              // Set receive callback
mctp_message_tx();              // Transmit message
mctp_binding_set_tx_enabled();  // Enable transmission
```

### libpldm

PLDM message encoding and decoding:

```c
// Request encoding
encode_get_tid_req(instance_id, &request);
encode_get_sensor_reading_req(instance_id, sensor_id, &request);
encode_set_state_effecter_states_req(instance_id, effecter_id, ...);

// Response decoding
decode_get_tid_resp(response, &tid, &completion_code);
decode_get_sensor_reading_resp(response, &reading, &status);

// PDR handling
pldm_pdr_init();                    // Initialize PDR repository
pldm_pdr_add();                     // Add PDR record
pldm_pdr_find_record();             // Find PDR by handle
pldm_entity_association_tree_init();// Entity tree
```

### pldmd Configuration

```json
// /usr/share/pldm/host_eid
9

// /usr/share/pldm/pdr/pdr.json
{
    "entries": [
        {
            "type": "terminusLocator",
            "data": {
                "terminusHandle": 1,
                "validity": "valid",
                "tid": 1,
                "containerID": 0,
                "terminusLocatorType": "mctp_eid",
                "terminusLocatorValue": 8
            }
        }
    ]
}
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include MCTP/PLDM components
IMAGE_INSTALL:append = " \
    mctp \
    mctpd \
    libpldm \
    pldm \
"

# Configure MCTP transport options
EXTRA_OEMESON:pn-mctpd = " \
    -Di2c=enabled \
    -Dastlpc=enabled \
    -Dserial=disabled \
"

# Configure PLDM options
EXTRA_OEMESON:pn-pldm = " \
    -Dtransport-implementation=af-mctp \
    -Doem-ibm=disabled \
    -Dsoftoff=enabled \
    -Dhost-eid=9 \
    -Dlibpldmresponder=enabled \
"
```

### Meson Build Options (pldm)

| Option | Default | Description |
|--------|---------|-------------|
| `transport-implementation` | af-mctp | Transport (af-mctp or mctp-demux) |
| `oem-ibm` | disabled | IBM OEM PLDM extensions |
| `softoff` | enabled | Host soft power off via PLDM |
| `host-eid` | 9 | Default host endpoint ID |
| `libpldmresponder` | enabled | BMC as PLDM responder |
| `system-specific-bios-json` | disabled | Custom BIOS JSON location |

### Meson Build Options (mctpd)

| Option | Default | Description |
|--------|---------|-------------|
| `i2c` | enabled | I2C/SMBus transport |
| `astlpc` | enabled | ASPEED LPC transport |
| `serial` | disabled | Serial transport |
| `tests` | disabled | Build unit tests |

### Kernel Configuration

```kconfig
# Enable MCTP in kernel
CONFIG_MCTP=y
CONFIG_MCTP_FLOWS=y

# Transport drivers
CONFIG_I2C_MCTP=m
CONFIG_MCTP_SERIAL=m
```

### Runtime Configuration

```bash
# Check MCTP daemon status
systemctl status mctpd

# Check PLDM daemon status
systemctl status pldmd

# View logs
journalctl -u mctpd -f
journalctl -u pldmd -f

# Enable debug logging
systemctl edit pldmd
# Add: Environment="PLDM_VERBOSITY=debug"
```

---

## MCTP Configuration

### Managing MCTP Networks

```bash
# List all MCTP interfaces
mctp link

# Example output:
# dev        net  eid    up
# mctpi2c1   1    8      yes
# mctplpc0   2    8      yes

# Set interface up
mctp link set mctpi2c1 up

# Set interface down
mctp link set mctpi2c1 down

# View interface details
ip link show type mctp
```

### Endpoint Management

```bash
# List all endpoints
mctp endpoint

# Add local endpoint address
mctp addr add 8 dev mctpi2c1

# Remove endpoint address
mctp addr del 8 dev mctpi2c1

# View endpoint routing
mctp route
```

### Static Endpoint Configuration

Create `/etc/mctp/static-endpoints.json`:

```json
{
    "endpoints": [
        {
            "name": "host",
            "type": "static",
            "eid": 9,
            "transport": {
                "type": "i2c",
                "bus": 1,
                "address": "0x50"
            }
        },
        {
            "name": "gpu0",
            "type": "static",
            "eid": 10,
            "transport": {
                "type": "i2c",
                "bus": 3,
                "address": "0x51"
            }
        },
        {
            "name": "nvme0",
            "type": "static",
            "eid": 11,
            "transport": {
                "type": "i2c",
                "bus": 4,
                "address": "0x52"
            }
        }
    ]
}
```

### D-Bus Interface for MCTP

```bash
# List MCTP service
busctl tree xyz.openbmc_project.MCTP

# Get endpoint properties
busctl introspect xyz.openbmc_project.MCTP \
    /xyz/openbmc_project/mctp/1/9

# Watch for new endpoints
busctl monitor xyz.openbmc_project.MCTP
```

---

## PLDM Configuration

### PDR Repository

```bash
# List all PDRs
pldmtool platform getpdr -t all

# Count PDRs
pldmtool platform getpdr -t all | grep -c "recordHandle"

# Export PDRs to file
pldmtool platform getpdr -t all > /tmp/pdr_dump.txt
```

### Common PLDM Commands

```bash
# === Base Commands (Type 0) ===

# Get terminus ID
pldmtool base getTID -m 9

# Get PLDM version for type 0
pldmtool base getPLDMVersion -m 9 -t 0

# Get supported PLDM types
pldmtool base getPLDMTypes -m 9

# Get commands for a PLDM type
pldmtool base getPLDMCommands -m 9 -t 0
pldmtool base getPLDMCommands -m 9 -t 2

# === Platform Commands (Type 2) ===

# Get numeric sensor reading
pldmtool platform getSensorReading -m 9 -i 1

# Get state sensor reading
pldmtool platform getStateSensorReadings -m 9 -i 5

# Set state effecter
pldmtool platform setStateEffecterStates -m 9 -i 1 -c 1 -d 1

# Get PDR by type
pldmtool platform getPDR -m 9 -t sensorPDR
pldmtool platform getPDR -m 9 -t effecterPDR

# === Firmware Update Commands (Type 5) ===

# Get firmware parameters
pldmtool fw_update GetFirmwareParameters -m 9

# Query device identifiers
pldmtool fw_update QueryDeviceIdentifiers -m 9
```

### Raw PLDM Commands

```bash
# Send raw PLDM command
# Format: pldmtool raw -m <eid> -d <byte1> <byte2> ...
# Byte format: 0xRR 0xTT 0xCC [payload...]
#   RR = Request/Instance (0x80 for request, IID=0)
#   TT = PLDM Type
#   CC = Command Code

# GetTID (Type 0, Command 0x02)
pldmtool raw -m 9 -d 0x80 0x00 0x02

# GetPLDMTypes (Type 0, Command 0x04)
pldmtool raw -m 9 -d 0x80 0x00 0x04

# GetSensorReading (Type 2, Command 0x11) for sensor ID 1
pldmtool raw -m 9 -d 0x80 0x02 0x11 0x01 0x00 0x00
```

---

## Device Integration Examples

### NVMe over MCTP

NVMe-MI (Management Interface) uses MCTP for out-of-band management:

```bash
# Discover NVMe endpoints
mctp endpoint

# NVMe-MI over MCTP uses message type 0x04
# Query via pldmtool if device supports PLDM
pldmtool base getPLDMTypes -m 11

# For native NVMe-MI, use nvme-cli with MCTP transport
nvme list --mctp
```

### GPU Management

```bash
# Configure GPU endpoint (I2C bus 3, address 0x51)
mctp addr add 10 dev mctpi2c3

# Verify endpoint responds
pldmtool base getTID -m 10

# Query GPU sensors
pldmtool platform getSensorReading -m 10 -i 1   # Temperature
pldmtool platform getSensorReading -m 10 -i 2   # Power

# Query GPU capabilities
pldmtool base getPLDMTypes -m 10
```

### PSU Management

```bash
# Configure PSU endpoint
mctp addr add 11 dev mctpi2c4

# Read PSU telemetry via PLDM sensors
pldmtool platform getSensorReading -m 11 -i 1   # Input voltage
pldmtool platform getSensorReading -m 11 -i 2   # Output voltage
pldmtool platform getSensorReading -m 11 -i 3   # Output current
pldmtool platform getSensorReading -m 11 -i 4   # Temperature
```

### Host CPU/BIOS Communication

```bash
# Host typically at EID 9
# PLDM for BIOS attributes (Type 3)
pldmtool bios GetBIOSTable -m 9 -t StringTable
pldmtool bios GetBIOSTable -m 9 -t AttributeTable
pldmtool bios GetBIOSTable -m 9 -t AttributeValueTable

# Get specific BIOS attribute
pldmtool bios GetBIOSAttributeCurrentValueByHandle -m 9 -a "boot_order"
```

---

## PLDM Firmware Update

### Firmware Update Flow

```
BMC (Update Agent)                    Device (FD)
      |                                    |
      |  1. QueryDeviceIdentifiers         |
      |------------------------------------>|
      |  <------ Device IDs ---------------|
      |                                    |
      |  2. GetFirmwareParameters          |
      |------------------------------------>|
      |  <------ Component info ------------|
      |                                    |
      |  3. RequestUpdate                  |
      |------------------------------------>|
      |  <------ RequestUpdateResponse -----|
      |                                    |
      |  4. PassComponentTable             |
      |------------------------------------>|
      |  <------ PassComponentTableResp ----|
      |                                    |
      |  5. UpdateComponent (repeat)       |
      |------------------------------------>|
      |                                    |
      |  6. RequestFirmwareData            |
      |<------------------------------------|
      |  ------ Firmware chunk ------------>|
      |     (repeat until complete)        |
      |                                    |
      |  7. TransferComplete               |
      |<------------------------------------|
      |  ------ Acknowledgment ------------>|
      |                                    |
      |  8. VerifyComplete                 |
      |<------------------------------------|
      |  ------ Acknowledgment ------------>|
      |                                    |
      |  9. ApplyComplete                  |
      |<------------------------------------|
      |  ------ Acknowledgment ------------>|
      |                                    |
      |  10. ActivateFirmware              |
      |------------------------------------>|
      |  <------ ActivateResponse ---------|
      |                                    |
```

### Firmware Update Commands

```bash
# Query device capabilities
pldmtool fw_update QueryDeviceIdentifiers -m 9
pldmtool fw_update GetFirmwareParameters -m 9

# Start update process
pldmtool fw_update RequestUpdate -m 9 \
    -c 1000 \      # max_transfer_size
    -n 1 \         # number of components
    -m 0 \         # max_outstanding_requests
    -s 1           # package_data_length

# The actual update is typically handled by pldmd
# or a dedicated update agent
```

---

## Event Handling

### PLDM Event Types

| Event Class | ID | Description |
|-------------|----|-------------|
| Sensor Event | 0x00 | Sensor threshold/state changed |
| Effecter Event | 0x01 | Effecter state changed |
| Redfish Task Executed | 0x02 | Redfish task complete |
| Redfish Message | 0x03 | Redfish log message |
| PDR Repository Changed | 0x04 | PDR update |
| Message Poll | 0x05 | Async message waiting |
| Heartbeat | 0x06 | Keepalive |

### Sensor Event Format

```
Sensor Event Data:
+-------+-------+-------+-------+-------+-------+-------+
| Sensor ID (16)        | Sensor Event Class (8)        |
+-----------------------+-------------------------------+
| Event Data (variable based on class)                  |
+-------------------------------------------------------+
```

### Event Monitoring

```bash
# Subscribe to PLDM events via D-Bus
busctl monitor xyz.openbmc_project.PLDM

# Poll for platform events
pldmtool platform pollForPlatformEventMessage -m 9

# Check event message buffer size
pldmtool platform getEventMessageBufferSize -m 9
```

---

## D-Bus Interfaces

### MCTP D-Bus Objects

```bash
# Service: xyz.openbmc_project.MCTP
# Path: /xyz/openbmc_project/mctp/<network>/<eid>

busctl tree xyz.openbmc_project.MCTP

# Example output:
# └─/xyz/openbmc_project
#   └─/xyz/openbmc_project/mctp
#     └─/xyz/openbmc_project/mctp/1
#       ├─/xyz/openbmc_project/mctp/1/8
#       └─/xyz/openbmc_project/mctp/1/9

# Inspect endpoint
busctl introspect xyz.openbmc_project.MCTP \
    /xyz/openbmc_project/mctp/1/9

# Properties:
#   .Address          - Physical address
#   .NetworkId        - MCTP network ID
#   .EID              - Endpoint ID
#   .SupportedMessageTypes - Supported MCTP message types
```

### PLDM D-Bus Objects

```bash
# Service: xyz.openbmc_project.PLDM
# Paths:
#   /xyz/openbmc_project/pldm/terminus/<tid>
#   /xyz/openbmc_project/pldm/fru/<record_set_id>

busctl tree xyz.openbmc_project.PLDM

# Get terminus properties
busctl introspect xyz.openbmc_project.PLDM \
    /xyz/openbmc_project/pldm/terminus/1

# Get sensor value (exposed via standard sensor interface)
busctl get-property xyz.openbmc_project.PLDM \
    /xyz/openbmc_project/sensors/temperature/CPU0_Temp \
    xyz.openbmc_project.Sensor.Value Value
```

---

## Troubleshooting

### MCTP Connectivity Issues

```bash
# 1. Check kernel MCTP support
lsmod | grep mctp
modprobe mctp

# 2. Verify I2C bus
i2cdetect -l
i2cdetect -y 1   # Check bus 1

# 3. Check MCTP link status
mctp link
mctp addr

# 4. View mctpd logs
journalctl -u mctpd -f

# 5. Enable debug logging
systemctl edit mctpd
# Add: Environment="MCTP_LOG_LEVEL=debug"
systemctl restart mctpd

# 6. Check MCTP network device
ip link show type mctp
ip -d link show mctpi2c1
```

### PLDM Communication Issues

```bash
# 1. Verify endpoint responds
pldmtool base getTID -m 9

# 2. Check PLDM daemon status
systemctl status pldmd

# 3. View PLDM logs
journalctl -u pldmd -f

# 4. Test raw PLDM command
pldmtool raw -m 9 -d 0x80 0x00 0x04  # GetPLDMTypes

# 5. Increase timeout
pldmtool --timeout 30000 base getTID -m 9
```

### No Endpoints Discovered

```bash
# 1. Check static configuration
cat /etc/mctp/static-endpoints.json

# 2. Manually add endpoint
mctp addr add 9 dev mctpi2c1

# 3. Verify I2C device responds
i2cdetect -y 1
i2ctransfer -y 1 w1@0x50 0x00

# 4. Check discovery
mctp ctrl discover mctpi2c1
```

### Command Timeouts

```bash
# 1. Check endpoint health
mctp stats

# 2. Increase command timeout
pldmtool --timeout 60000 <command>

# 3. Check for I2C bus contention
dmesg | grep -i i2c

# 4. Verify clock speed
# Some devices need slower I2C clock
```

### PDR Issues

```bash
# 1. Check PDR repository
pldmtool platform getpdr -t all

# 2. Verify terminus locator
pldmtool platform getpdr -t terminusLocatorPDR

# 3. Check PDR JSON configuration
cat /usr/share/pldm/pdr/*.json

# 4. Rebuild PDR repository
systemctl restart pldmd
```

---

## Security Considerations

### Authentication with SPDM

MCTP/PLDM integrates with SPDM for device authentication:

```bash
# SPDM runs over MCTP (message type 0x05)
# See the SPDM Guide for details

# Verify device certificate
# Challenge device
# Establish secure session
```

### Access Control

```xml
<!-- /etc/dbus-1/system.d/pldm.conf -->
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
    <policy user="root">
        <allow own="xyz.openbmc_project.PLDM"/>
        <allow send_destination="xyz.openbmc_project.PLDM"/>
    </policy>
    <policy context="default">
        <allow send_destination="xyz.openbmc_project.PLDM"
               send_interface="org.freedesktop.DBus.Properties"
               send_member="Get"/>
        <allow send_destination="xyz.openbmc_project.PLDM"
               send_interface="org.freedesktop.DBus.Properties"
               send_member="GetAll"/>
    </policy>
</busconfig>
```

### Network Isolation

```bash
# MCTP networks are isolated by network ID
# EIDs are only unique within a network

# Use separate networks for different security domains
# Network 1: Host communication
# Network 2: Peripheral devices
```

---

## Enabling/Disabling

### Build-Time Disable

```bitbake
# Remove MCTP/PLDM packages
IMAGE_INSTALL:remove = "mctp mctpd pldm libpldm"
```

### Runtime Disable

```bash
# Stop PLDM daemon
systemctl stop pldmd
systemctl disable pldmd

# Stop MCTP daemon
systemctl stop mctpd
systemctl disable mctpd

# Verify stopped
systemctl status pldmd mctpd
```

---

## References

### DMTF Specifications

- [DSP0236 - MCTP Base Specification](https://www.dmtf.org/dsp/DSP0236) - Core MCTP protocol
- [DSP0237 - MCTP SMBus/I2C Transport](https://www.dmtf.org/dsp/DSP0237) - I2C binding
- [DSP0238 - MCTP PCIe VDM Transport](https://www.dmtf.org/dsp/DSP0238) - PCIe binding
- [DSP0239 - MCTP Serial Transport](https://www.dmtf.org/dsp/DSP0239) - Serial binding
- [DSP0240 - PLDM Base Specification](https://www.dmtf.org/dsp/DSP0240) - Core PLDM protocol
- [DSP0248 - PLDM for Platform Monitoring and Control](https://www.dmtf.org/dsp/DSP0248) - Type 2
- [DSP0267 - PLDM for Firmware Update](https://www.dmtf.org/dsp/DSP0267) - Type 5

### OpenBMC Repositories

- [libpldm (GitHub)](https://github.com/openbmc/libpldm) - PLDM library
- [pldm (GitHub)](https://github.com/openbmc/pldm) - PLDM daemon
- [libmctp (GitHub)](https://github.com/openbmc/libmctp) - MCTP library
- [mctp (GitHub)](https://github.com/openbmc/mctp) - MCTP userspace tools

### Linux Kernel

- [Linux MCTP Documentation](https://www.kernel.org/doc/html/latest/networking/mctp.html) - Kernel MCTP stack

---

{: .note }
**Tested on**: OpenBMC master, requires hardware with MCTP-capable endpoints. QEMU testing possible with mctp-serial loopback.
