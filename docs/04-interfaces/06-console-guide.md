---
layout: default
title: Console Guide
parent: Interfaces
nav_order: 6
difficulty: intermediate
prerequisites:
  - dbus-guide
  - ipmi-guide
---

# Console Guide
{: .no_toc }

Configure serial console access and host logging on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**Serial Console** provides text-mode access to the host system through the BMC, enabling boot monitoring, BIOS configuration, and command-line access when graphical interfaces are unavailable.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Console Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      Clients                                ││
│  │                                                             ││
│  │   ┌────────────┐  ┌────────────┐  ┌────────────┐            ││
│  │   │  WebUI     │  │  SSH       │  │  IPMI SOL  │            ││
│  │   │  Console   │  │  Console   │  │  ipmitool  │            ││
│  │   └─────┬──────┘  └─────┬──────┘  └─────┬──────┘            ││
│  └─────────┼───────────────┼───────────────┼───────────────────┘│
│            │               │               │                    │
│  ┌─────────┴───────────────┴───────────────┴───────────────────┐│
│  │                        bmcweb                               ││
│  │              WebSocket: /console/default                    ││
│  └─────────────────────────┬───────────────────────────────────┘│
│                            │                                    │
│  ┌─────────────────────────┴───────────────────────────────────┐│
│  │                     obmc-console                            ││
│  │                                                             ││
│  │   ┌─────────────────┐  ┌─────────────────────────────────┐  ││
│  │   │  Console Server │  │  hostlogger                     │  ││
│  │   │  (multiplexer)  │  │  (persistent logging)           │  ││
│  │   └────────┬────────┘  └─────────────────────────────────┘  ││
│  └────────────┼────────────────────────────────────────────────┘│
│               │                                                 │
│  ┌────────────┴────────────────────────────────────────────────┐│
│  │                   Serial Port Interface                     ││
│  │             (/dev/ttyS*, /dev/ttyVUART*)                    ││
│  └────────────────────────┬────────────────────────────────────┘│
│                           │                                     │
│  ┌────────────────────────┴────────────────────────────────────┐│
│  │                      Host System                            ││
│  │                   (Serial console)                          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Components

### obmc-console-server

- Multiplexes serial port to multiple clients
- Provides Unix socket interface
- Handles console access control

### obmc-console-client

- Command-line console access
- Connects to console-server socket

### hostlogger

- Captures console output persistently
- Stores in rotating log files
- Available via Redfish API

---

## Hardware Configuration

### Serial Port Types

| Type | Description | Device Path |
|------|-------------|-------------|
| Physical UART | Hardware serial port | /dev/ttyS0, /dev/ttyS1 |
| Virtual UART | LPC/VUART interface | /dev/ttyVUART0 |
| PTY | Pseudo-terminal (testing) | /dev/pts/* |

### ASPEED VUART

ASPEED BMCs use Virtual UART for LPC-based console:

```dts
// Device tree configuration
&vuart {
    status = "okay";
};
```

### Nuvoton Serial

```dts
// Device tree for serial ports
&serial1 {
    status = "okay";
};
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include console packages
IMAGE_INSTALL:append = " \
    obmc-console \
    phosphor-hostlogger \
"

# Configure console device in machine config
OBMC_CONSOLE_HOST_TTY ?= "ttyVUART0"

# For physical serial port:
# OBMC_CONSOLE_HOST_TTY ?= "ttyS2"
```

### Console Server Configuration

Configuration file: `/etc/obmc-console/server.ttyVUART0.conf`

```ini
# Console server configuration

# Socket directory
socket-id = default

# Console device
console-id = default

# Baud rate
baud = 115200

# Local echo (for testing)
#local-echo = true

# Logfile (if not using hostlogger)
#logfile = /var/log/obmc-console.log
```

### Multiple Console Support

```ini
# /etc/obmc-console/server.ttyS0.conf
socket-id = host0
console-id = host0
baud = 115200

# /etc/obmc-console/server.ttyS1.conf
socket-id = host1
console-id = host1
baud = 115200
```

### Runtime Configuration

```bash
# Check console service status
systemctl status obmc-console-server@ttyVUART0

# View console logs
journalctl -u obmc-console-server@ttyVUART0 -f

# Restart console service
systemctl restart obmc-console-server@ttyVUART0
```

---

## Accessing the Console

### Via WebUI

1. Login to WebUI at `https://<bmc-ip>/`
2. Navigate to **Operations** → **Serial over LAN Console**
3. Terminal opens in browser window
4. Type commands to interact with host

### Via SSH

```bash
# Direct console access via SSH
ssh -t root@bmc-ip /usr/bin/obmc-console-client

# With specific console ID
ssh -t root@bmc-ip /usr/bin/obmc-console-client -i host0
```

### Via IPMI SOL

```bash
# Activate SOL session
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol activate

# Deactivate SOL session
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol deactivate

# SOL configuration
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol info
```

### Via Redfish

```bash
# Get console URL
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc

# Look for SerialConsole property
# WebSocket endpoint: wss://bmc-ip/console/default
```

### Via obmc-console-client

```bash
# On the BMC directly
obmc-console-client

# Specify console ID
obmc-console-client -i default

# Exit: Ctrl+] or ~.
```

---

## SOL Configuration

### IPMI SOL Settings

```bash
# Get SOL configuration
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol info

# Set SOL parameters
# Enable SOL
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol set enabled true

# Set baud rate
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol set volatile-bit-rate 115.2

# Set non-volatile baud rate
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol set non-volatile-bit-rate 115.2

# Set privilege level
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol set privilege-level operator
```

### SOL Baud Rates

| Value | Rate |
|-------|------|
| 6 | 9600 |
| 7 | 19200 |
| 8 | 38400 |
| 9 | 57600 |
| 10 | 115200 |

### Redfish SOL Configuration

```bash
# Get network protocol settings
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol

# Note: SOL is typically configured via IPMI
# Redfish Serial Console is different from IPMI SOL
```

---

## Host Logger Configuration

### Enable Host Logger

```bitbake
# In Yocto build
IMAGE_INSTALL:append = " phosphor-hostlogger"
```

### Configure Host Logger

```bash
# Configuration file
cat /etc/hostlogger.conf

# Common settings:
# - Buffer size
# - Log rotation
# - Flush interval
```

### systemd Service

```ini
# /lib/systemd/system/phosphor-hostlogger@.service
[Unit]
Description=Host Console Logger for %i
After=obmc-console-server@%i.service

[Service]
ExecStart=/usr/bin/hostlogger -i %i
Restart=always

[Install]
WantedBy=multi-user.target
```

### View Host Logs

```bash
# Via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/HostLogger/Entries

# Local files (if configured)
ls /var/log/host*

# Via journal
journalctl -u phosphor-hostlogger@ttyVUART0
```

---

## Console Escape Sequences

### obmc-console-client

| Sequence | Action |
|----------|--------|
| `~.` | Disconnect |
| `~?` | Show help |
| `~^Z` | Suspend |
| `~~` | Send literal ~ |

### SSH Session

| Sequence | Action |
|----------|--------|
| `~.` | Disconnect (SSH + console) |
| `Enter ~.` | Disconnect properly |

### IPMI SOL

| Sequence | Action |
|----------|--------|
| `~.` | Deactivate SOL |
| `~^Z` | Suspend SOL |
| `~B` | Send break |

---

## Multiple Host Consoles

For systems with multiple hosts:

```bash
# Configuration for each host
# /etc/obmc-console/server.host0.conf
socket-id = host0
console-id = host0

# /etc/obmc-console/server.host1.conf
socket-id = host1
console-id = host1
```

### Access Each Console

```bash
# Via WebUI - select from dropdown
# Via SSH
ssh -t root@bmc-ip /usr/bin/obmc-console-client -i host0
ssh -t root@bmc-ip /usr/bin/obmc-console-client -i host1

# Via IPMI - use channel parameter
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc -c 1 sol activate
```

---

## Troubleshooting

### No Console Output

```bash
# Check if console server is running
systemctl status obmc-console-server@ttyVUART0

# Check device exists
ls -la /dev/ttyVUART0

# Check permissions
stat /dev/ttyVUART0

# Check serial port configuration
stty -F /dev/ttyVUART0 -a

# Verify baud rate matches host
stty -F /dev/ttyVUART0 115200
```

### Console Frozen

```bash
# Restart console server
systemctl restart obmc-console-server@ttyVUART0

# Kill stuck clients
pkill obmc-console-client

# Check for hardware issues
dmesg | grep -i uart
```

### Garbled Text

```bash
# Baud rate mismatch - verify settings match
# Host BIOS/OS must use same baud rate as BMC

# Common baud rates to try:
stty -F /dev/ttyVUART0 9600
stty -F /dev/ttyVUART0 19200
stty -F /dev/ttyVUART0 38400
stty -F /dev/ttyVUART0 57600
stty -F /dev/ttyVUART0 115200
```

### SOL Connection Failed

```bash
# Check IPMI service
systemctl status phosphor-ipmi-net

# Verify SOL is enabled
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol info

# Check for active sessions
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc session info all

# Force deactivate stale session
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol deactivate
```

### Permission Denied

```bash
# Check user permissions
# User needs Operator or Administrator role

# Verify via Redfish
curl -k -u user:password \
    https://localhost/redfish/v1/AccountService/Accounts/user
```

---

## Security Considerations

### Access Control

```bash
# Console access requires authentication
# Recommended role: Operator or Administrator

# View user roles
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/AccountService/Accounts
```

### SOL Encryption

IPMI SOL uses RMCP+ encryption:

```bash
# Check cipher suite
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc -C 17 sol activate

# Cipher 17 = AES-CBC-128 + HMAC-SHA256 (recommended)
```

### Console Logging Security

```bash
# Console logs may contain sensitive data
# Configure retention policy
# Restrict access to log files

# File permissions
chmod 600 /var/log/hostlogger/*
```

---

## Enabling/Disabling Console

### Build-Time Disable

```bitbake
# Remove console packages
IMAGE_INSTALL:remove = "obmc-console phosphor-hostlogger"
```

### Runtime Disable

```bash
# Stop console service
systemctl stop obmc-console-server@ttyVUART0
systemctl disable obmc-console-server@ttyVUART0

# Stop hostlogger
systemctl stop phosphor-hostlogger@ttyVUART0
systemctl disable phosphor-hostlogger@ttyVUART0
```

### Disable SOL via IPMI

```bash
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sol set enabled false
```

---

## References

- [obmc-console](https://github.com/openbmc/obmc-console)
- [phosphor-hostlogger](https://github.com/openbmc/phosphor-hostlogger)
- [IPMI SOL Specification](https://www.intel.com/content/dam/www/public/us/en/documents/product-briefs/ipmi-second-gen-interface-spec-v2-rev1-1.pdf)
- [OpenBMC Console Design](https://github.com/openbmc/docs/blob/master/console.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
