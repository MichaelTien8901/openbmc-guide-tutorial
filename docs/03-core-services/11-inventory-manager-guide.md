---
layout: default
title: Inventory Manager Guide
parent: Core Services
nav_order: 11
difficulty: intermediate
prerequisites:
  - dbus-guide
  - entity-manager-guide
---

# Inventory Manager Guide
{: .no_toc }

Manage FRU data and hardware inventory on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-inventory-manager** tracks hardware components, FRU (Field Replaceable Unit) data, and component associations.

```
+-------------------------------------------------------------------+
|                  Inventory Manager Architecture                   |
+-------------------------------------------------------------------+
|                                                                   |
|  +----------------------------+  +----------------------------+   |
|  |      FRU EEPROMs           |  |     Entity Manager         |   |
|  |    (I2C devices)           |  |   (JSON configurations)    |   |
|  +-------------+--------------+  +-------------+--------------+   |
|                |                               |                  |
|                v                               v                  |
|  +------------------------------------------------------------+   |
|  |              phosphor-inventory-manager                    |   |
|  |                                                            |   |
|  |   +----------------+  +----------------+  +-------------+  |   |
|  |   | Inventory Tree |  |  Associations  |  | FRU Parser  |  |   |
|  |   | /xyz/openbmc_  |  | (links items)  |  | (IPMI FRU)  |  |   |
|  |   | project/inven- |  |                |  |             |  |   |
|  |   | tory/system/   |  |                |  |             |  |   |
|  |   +----------------+  +----------------+  +-------------+  |   |
|  |                                                            |   |
|  +----------------------------+-------------------------------+   |
|                               |                                   |
|           +-------------------+-------------------+               |
|           |                   |                   |               |
|           v                   v                   v               |
|  +---------------+   +---------------+   +---------------+        |
|  |    Redfish    |   |     IPMI      |   |    D-Bus      |        |
|  |   /Chassis/   |   |   fru print   |   |   busctl      |        |
|  +---------------+   +---------------+   +---------------+        |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Setup & Configuration

### Build-Time Configuration

```bitbake
# Include inventory manager
IMAGE_INSTALL:append = " \
    phosphor-inventory-manager \
    phosphor-fru-fault-monitor \
"
```

---

## Viewing Inventory

### Via D-Bus

```bash
# List inventory items
busctl tree xyz.openbmc_project.Inventory.Manager

# Get item details
busctl introspect xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/motherboard
```

### Via Redfish

```bash
# Get chassis inventory
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis

# Get system inventory
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system
```

---

## FRU Data

### FRU Structure

| Field | Description |
|-------|-------------|
| BOARD_MFG | Board manufacturer |
| BOARD_PRODUCT | Product name |
| BOARD_SERIAL | Serial number |
| BOARD_PART_NUMBER | Part number |

### Read FRU via IPMI

```bash
# List FRU devices
ipmitool fru list

# Read FRU data
ipmitool fru print 0
```

### FRU EEPROM Configuration

```json
{
    "Name": "Baseboard FRU",
    "Type": "EEPROM",
    "Bus": 1,
    "Address": "0x50"
}
```

---

## Associations

Associations link related inventory items:

```bash
# View associations
busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis \
    xyz.openbmc_project.Association.Definitions \
    Associations
```

---

## Deep Dive
{: .text-delta }

Advanced implementation details for inventory management developers.

### IPMI FRU Data Format

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         IPMI FRU Data Structure                            │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  FRU EEPROM LAYOUT (IPMI Platform Management FRU Specification)            │
│  ─────────────────────────────────────────────────────────────             │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Common Header Area (8 bytes, offset 0)                             │   │
│  │                                                                     │   │
│  │  ┌──────────┬──────────┬──────────┬──────────┬──────────┐           │   │
│  │  │ Version  │Internal  │ Chassis  │  Board   │ Product  │           │   │
│  │  │ (0x01)   │Info Ofs  │ Info Ofs │ Info Ofs │ Info Ofs │           │   │
│  │  │ 1 byte   │ 1 byte   │ 1 byte   │ 1 byte   │ 1 byte   │           │   │
│  │  └──────────┴──────────┴──────────┴──────────┴──────────┘           │   │
│  │  ┌──────────┬──────────┬──────────┐                                 │   │
│  │  │MultiRec  │  PAD     │ Checksum │                                 │   │
│  │  │ Offset   │ (0x00)   │ (zero-   │                                 │   │
│  │  │ 1 byte   │ 1 byte   │  sum)    │                                 │   │
│  │  └──────────┴──────────┴──────────┘                                 │   │
│  │                                                                     │   │
│  │  Note: Offsets are in 8-byte multiples (offset × 8 = byte address)  │   │
│  │  Value 0x00 = area not present                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Board Info Area (variable length)                                  │   │
│  │                                                                     │   │
│  │  ┌──────────┬──────────┬──────────────────────────────────────────┐ │   │
│  │  │ Version  │  Length  │ Language Code                            │ │   │
│  │  │ (0x01)   │ (×8 bytes│ (0x00 = English)                         │ │   │
│  │  └──────────┴──────────┴──────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Mfg Date/Time (3 bytes, minutes since 1996-01-01 00:00)        │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Board Manufacturer (type/length, then string)                  │ │   │
│  │  │   Type/Length byte: [7:6]=type, [5:0]=length                   │ │   │
│  │  │   Type: 00=binary, 01=BCD+, 10=6-bit ASCII, 11=8-bit ASCII     │ │   │
│  │  │   Example: 0xC5 = ASCII, 5 chars → "ACME"                      │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Board Product Name                                             │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Board Serial Number                                            │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ Board Part Number                                              │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ FRU File ID                                                    │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  │  ┌────────────────────────────────────────────────────────────────┐ │   │
│  │  │ End marker (0xC1) + Padding (0x00s) + Checksum                 │ │   │
│  │  └────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Product Info Area (similar structure)                              │   │
│  │                                                                     │   │
│  │  - Product Manufacturer                                             │   │
│  │  - Product Name                                                     │   │
│  │  - Product Part/Model Number                                        │   │
│  │  - Product Version                                                  │   │
│  │  - Product Serial Number                                            │   │
│  │  - Asset Tag                                                        │   │
│  │  - FRU File ID                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### D-Bus Inventory Object Model

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Inventory D-Bus Object Hierarchy                        │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  D-BUS OBJECT TREE                                                         │
│  ─────────────────                                                         │
│                                                                            │
│  /xyz/openbmc_project/inventory                                            │
│  └── system                                                                │
│      ├── chassis                                                           │
│      │   ├── motherboard                                                   │
│      │   │   ├── cpu0                                                      │
│      │   │   │   └── core0                                                 │
│      │   │   │   └── core1                                                 │
│      │   │   ├── dimm0                                                     │
│      │   │   ├── dimm1                                                     │
│      │   │   └── pcie_slot0                                                │
│      │   │       └── gpu0                                                  │
│      │   ├── powersupply0                                                  │
│      │   └── fan0                                                          │
│      └── bmc                                                               │
│                                                                            │
│  INTERFACES PER OBJECT                                                     │
│  ────────────────────                                                      │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  /xyz/openbmc_project/inventory/system/chassis/motherboard          │   │
│  │                                                                     │   │
│  │  xyz.openbmc_project.Inventory.Item                                 │   │
│  │    ├── Present: true                                                │   │
│  │    └── PrettyName: "System Board"                                   │   │
│  │                                                                     │   │
│  │  xyz.openbmc_project.Inventory.Decorator.Asset                      │   │
│  │    ├── Manufacturer: "ACME Corp"                                    │   │
│  │    ├── Model: "SuperServer X100"                                    │   │
│  │    ├── PartNumber: "P/N-12345"                                      │   │
│  │    ├── SerialNumber: "SN-ABCDEF123456"                              │   │
│  │    └── BuildDate: "2024-01-15"                                      │   │
│  │                                                                     │   │
│  │  xyz.openbmc_project.Inventory.Decorator.Revision                   │   │
│  │    └── Version: "Rev A01"                                           │   │
│  │                                                                     │   │
│  │  xyz.openbmc_project.Inventory.Item.Board                           │   │
│  │    (marker interface - identifies as board type)                    │   │
│  │                                                                     │   │
│  │  xyz.openbmc_project.Association.Definitions                        │   │
│  │    └── Associations: [                                              │   │
│  │          ("chassis", "containing", ".../chassis"),                  │   │
│  │          ("contained_by", "containing", ".../system"),              │   │
│  │          ("sensors", "all_sensors", ".../sensors/temperature/mb_*") │   │
│  │        ]                                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ITEM TYPE INTERFACES                                                      │
│  ────────────────────                                                      │
│                                                                            │
│  │ Interface                                 │ Used For               │    │
│  │───────────────────────────────────────────│────────────────────────│    │
│  │ xyz.openbmc_project.Inventory.Item.Board  │ Motherboards, cards    │    │
│  │ xyz.openbmc_project.Inventory.Item.Cpu    │ Processors             │    │
│  │ xyz.openbmc_project.Inventory.Item.Dimm   │ Memory modules         │    │
│  │ xyz.openbmc_project.Inventory.Item.Fan    │ Cooling fans           │    │
│  │ xyz.openbmc_project.Inventory.Item.Psu    │ Power supplies         │    │
│  │ xyz.openbmc_project.Inventory.Item.Chassis│ Enclosures             │    │
│  │ xyz.openbmc_project.Inventory.Item.Drive  │ Storage drives         │    │
│  │ xyz.openbmc_project.Inventory.Item.Bmc    │ BMC itself             │    │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Association Definitions

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    Inventory Association Relationships                     │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ASSOCIATION MODEL                                                         │
│  ─────────────────                                                         │
│                                                                            │
│  Associations are bidirectional relationships between inventory items.     │
│  Each association has three parts: (forward, reverse, endpoint)            │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Containment Example:                                               │   │
│  │                                                                     │   │
│  │  Chassis                     Motherboard                            │   │
│  │  ┌──────────────┐            ┌──────────────┐                       │   │
│  │  │ /inventory/  │            │ /inventory/  │                       │   │
│  │  │ system/      │            │ system/      │                       │   │
│  │  │ chassis      │            │ chassis/     │                       │   │
│  │  │              │            │ motherboard  │                       │   │
│  │  │ Associations:│            │              │                       │   │
│  │  │ ("containing"│ ─────────> │ Associations:│                       │   │
│  │  │  "contained" │            │ ("contained" │                       │   │
│  │  │  ".../mb")   │ <───────── │  "containing"│                       │   │
│  │  └──────────────┘            │  ".../chass")│                       │   │
│  │                              └──────────────┘                       │   │
│  │                                                                     │   │
│  │  D-Bus property on chassis:                                         │   │
│  │    Associations = [("containing", "contained_by",                   │   │
│  │                     "/xyz/.../chassis/motherboard")]                │   │
│  │                                                                     │   │
│  │  Creates automatic endpoints:                                       │   │
│  │    /xyz/.../chassis/containing → points to motherboard              │   │
│  │    /xyz/.../chassis/motherboard/contained_by → points to chassis    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  COMMON ASSOCIATION PATTERNS                                               │
│  ───────────────────────────                                               │
│                                                                            │
│  │ Forward      │ Reverse      │ Meaning                              │    │
│  │──────────────│──────────────│──────────────────────────────────────│    │
│  │ containing   │ contained_by │ Physical containment                 │    │
│  │ powered_by   │ powering     │ Power supply relationship            │    │
│  │ cooled_by    │ cooling      │ Fan/cooling relationship             │    │
│  │ sensors      │ inventory    │ Sensor to FRU mapping                │    │
│  │ led          │ identify     │ LED to component mapping             │    │
│  │ error_log    │ related_item │ Error log to failed component        │    │
│                                                                            │
│  SENSOR-TO-INVENTORY ASSOCIATION:                                          │
│  ────────────────────────────────                                          │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  CPU Temperature Sensor                                             │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │ /xyz/openbmc_project/sensors/temperature/cpu0_temp           │   │   │
│  │  │                                                              │   │   │
│  │  │ Associations = [                                             │   │   │
│  │  │   ("inventory", "all_sensors",                               │   │   │
│  │  │    "/xyz/openbmc_project/inventory/system/.../cpu0")         │   │   │
│  │  │ ]                                                            │   │   │
│  │  └──────────────────────────────────────────────────────────────┘   │   │
│  │                                                                     │   │
│  │  This allows:                                                       │   │
│  │    - Finding all sensors for a component                            │   │
│  │    - Redfish Chassis/Sensors population                             │   │
│  │    - Error log attribution to correct FRU                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files in [phosphor-inventory-manager](https://github.com/openbmc/phosphor-inventory-manager):

| File | Description |
|------|-------------|
| `manager.cpp` | Main inventory manager with D-Bus object creation |
| `associations.cpp` | Association endpoint management |
| `errors.cpp` | Error handling and logging |
| `functor.cpp` | Property change handlers |
| `gen/generated.cpp` | YAML-generated inventory definitions |

---

## References

- [phosphor-inventory-manager](https://github.com/openbmc/phosphor-inventory-manager)
- [Redfish Chassis Schema](https://redfish.dmtf.org/schemas/Chassis.v1_18_0.json)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
