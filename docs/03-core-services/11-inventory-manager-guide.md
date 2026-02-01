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

## References

- [phosphor-inventory-manager](https://github.com/openbmc/phosphor-inventory-manager)
- [Redfish Chassis Schema](https://redfish.dmtf.org/schemas/Chassis.v1_18_0.json)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
