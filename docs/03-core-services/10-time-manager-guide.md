---
layout: default
title: Time Manager Guide
parent: Core Services
nav_order: 10
difficulty: beginner
prerequisites:
  - dbus-guide
---

# Time Manager Guide
{: .no_toc }

Configure NTP, RTC, and timezone settings on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-time-manager** handles time synchronization, timezone configuration, and BMC/host time ownership.

```
+-------------------------------------------------------------------+
|                   Time Manager Architecture                       |
+-------------------------------------------------------------------+
|                                                                   |
|  +-------------------+       +-------------------+                |
|  |   NTP Servers     |       |    Host System    |                |
|  |  (pool.ntp.org)   |       |   (time source)   |                |
|  +--------+----------+       +--------+----------+                |
|           |                           |                           |
|           v                           v                           |
|  +-----------------------------------------------------------+    |
|  |               phosphor-time-manager                       |    |
|  |                                                           |    |
|  |   +--------------+  +--------------+  +--------------+    |    |
|  |   |  Time Mode   |  |  Time Owner  |  |   Timezone   |    |    |
|  |   |  (NTP/Manual)|  |  (BMC/Host)  |  |   Setting    |    |    |
|  |   +--------------+  +--------------+  +--------------+    |    |
|  |                                                           |    |
|  +---------------------------+-------------------------------+    |
|                              |                                    |
|              +---------------+---------------+                    |
|              |                               |                    |
|              v                               v                    |
|  +-------------------+           +-------------------+            |
|  | systemd-timesyncd |           |       RTC         |            |
|  |   (NTP client)    |           | (Hardware Clock)  |            |
|  +-------------------+           +-------------------+            |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Setup & Configuration

### Build-Time Configuration

```bitbake
# Include time manager
IMAGE_INSTALL:append = " phosphor-time-manager"
```

### Time Modes

| Mode | Description |
|------|-------------|
| NTP | Synchronize via NTP servers |
| Manual | Set time manually |

---

## Configuring NTP

### Enable NTP

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"NTP": {"ProtocolEnabled": true}}' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol

# Configure NTP servers
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"NTP": {"NTPServers": ["pool.ntp.org", "time.google.com"]}}' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol
```

### Check NTP Status

```bash
# Check systemd-timesyncd
timedatectl status

# View NTP sync status
timedatectl show-timesync
```

---

## Setting Time Manually

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"DateTime": "2024-01-15T10:30:00+00:00"}' \
    https://localhost/redfish/v1/Managers/bmc

# Via command line
timedatectl set-time "2024-01-15 10:30:00"
```

---

## Timezone Configuration

```bash
# List timezones
timedatectl list-timezones

# Set timezone
timedatectl set-timezone America/Los_Angeles

# Via D-Bus
busctl set-property xyz.openbmc_project.Time.Manager \
    /xyz/openbmc_project/time/bmc \
    xyz.openbmc_project.Time.EpochTime \
    Elapsed t $(date +%s%N)
```

---

## Time Ownership

BMC and Host can have separate time sources:

```bash
# Set BMC as time owner
busctl set-property xyz.openbmc_project.Time.Manager \
    /xyz/openbmc_project/time/owner \
    xyz.openbmc_project.Time.Owner \
    TimeOwner s "xyz.openbmc_project.Time.Owner.Owners.BMC"
```

---

## References

- [phosphor-time-manager](https://github.com/openbmc/phosphor-time-manager)
- [systemd-timesyncd](https://www.freedesktop.org/software/systemd/man/systemd-timesyncd.html)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
