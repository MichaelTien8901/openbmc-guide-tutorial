---
layout: default
title: Watchdog Guide
parent: Core Services
nav_order: 12
difficulty: intermediate
prerequisites:
  - dbus-guide
  - state-manager-guide
---

# Watchdog Guide
{: .no_toc }

Configure host watchdog timer on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-watchdog** monitors host health and triggers recovery actions if the host becomes unresponsive.

```
+--------------------------------------------------------------------+
|                    Watchdog Architecture                           |
+--------------------------------------------------------------------+
|                                                                    |
|  +-------------------+                                             |
|  |   Host System     |                                             |
|  |                   |                                             |
|  |  +-----------+    |     Periodic "kick"                         |
|  |  | Watchdog  |----+-------------------------+                   |
|  |  | Agent     |    |                         |                   |
|  |  +-----------+    |                         v                   |
|  +-------------------+         +-------------------------------+   |
|                                |      phosphor-watchdog        |   |
|                                |                               |   |
|                                |  +----------+  +----------+   |   |
|                                |  | Enabled  |  | Interval |   |   |
|                                |  | (bool)   |  | (usec)   |   |   |
|                                |  +----------+  +----------+   |   |
|                                |                               |   |
|                                |  +--------------------------+ |   |
|                                |  |    ExpireAction          | |   |
|                                |  | (None/HardReset/PowerOff)| |   |
|                                |  +-------------------------+  |   |
|                                +---------------+---------------+   |
|                                                |                   |
|                          Timeout expired       |                   |
|                                                v                   |
|                                +-------------------------------+   |
|                                |      State Manager            |   |
|                                |   (Execute recovery action)   |   |
|                                +-------------------------------+   |
|                                                                    |
+--------------------------------------------------------------------+
```

---

## Setup & Configuration

### Build-Time Configuration

```bitbake
# Include watchdog
IMAGE_INSTALL:append = " phosphor-watchdog"

# Configure Meson options
EXTRA_OEMESON:pn-phosphor-watchdog = " \
    -Ddefault-action=HardReset \
    -Ddefault-timeout=300 \
"
```

### Expiration Actions

| Action | Description |
|--------|-------------|
| None | Log event only |
| HardReset | Force power cycle |
| PowerOff | Power off system |
| PowerCycle | Power off then on |

---

## Configuring Watchdog

### Via D-Bus

```bash
# Enable watchdog
busctl set-property xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog \
    Enabled b true

# Set timeout (microseconds)
busctl set-property xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog \
    Interval t 300000000

# Set expiration action
busctl set-property xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog \
    ExpireAction s "xyz.openbmc_project.State.Watchdog.Action.HardReset"
```

### Via IPMI

```bash
# Get watchdog status
ipmitool mc watchdog get

# Set watchdog timeout
ipmitool mc watchdog set timeout 300

# Enable watchdog
ipmitool mc watchdog set action hard_reset

# Reset (kick) watchdog
ipmitool mc watchdog reset
```

### Via Redfish

```bash
# Configure watchdog via HostWatchdogTimer
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "HostWatchdogTimer": {
            "FunctionEnabled": true,
            "TimeoutAction": "ResetSystem",
            "WarningAction": "None"
        }
    }' \
    https://localhost/redfish/v1/Systems/system
```

---

## Watchdog Operation

```
Host Boot → Watchdog Enabled → Host kicks watchdog periodically
                                    ↓
                            Timeout expires?
                                    ↓
                            Execute ExpireAction
```

---

## Troubleshooting

```bash
# Check watchdog service
systemctl status phosphor-watchdog@watchdog-host0

# View watchdog state
busctl introspect xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0
```

---

## References

- [phosphor-watchdog](https://github.com/openbmc/phosphor-watchdog)
- [IPMI Watchdog Timer](https://www.intel.com/content/dam/www/public/us/en/documents/product-briefs/ipmi-second-gen-interface-spec-v2-rev1-1.pdf)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
