---
layout: default
title: IPMI Guide
parent: Interfaces
nav_order: 1
difficulty: intermediate
prerequisites:
  - dbus-guide
  - state-manager-guide
---

# IPMI Guide
{: .no_toc }

Implement and extend IPMI functionality in OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**IPMI** (Intelligent Platform Management Interface) is a standardized interface for out-of-band server management. OpenBMC implements IPMI through:

- **ipmid**: The main IPMI daemon
- **Host IPMI**: KCS/BT interface to the host
- **Network IPMI**: RMCP/RMCP+ over LAN

```
┌─────────────────────────────────────────────────────────────────┐
│                      IPMI Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      External Clients                       ││
│  │                    (ipmitool, vendor tools)                 ││
│  └─────────────────┬─────────────────┬─────────────────────────┘│
│                    │                 │                          │
│           ┌────────┴────────┐ ┌──────┴──────┐                   │
│           │   RMCP+/LAN     │ │   KCS/BT    │                   │
│           │   (Network)     │ │   (Host)    │                   │
│           └────────┬────────┘ └──────┬──────┘                   │
│                    │                 │                          │
│  ┌─────────────────┴─────────────────┴─────────────────────────┐│
│  │                        ipmid                                ││
│  │                                                             ││
│  │   ┌──────────────────────────────────────────────────────┐  ││
│  │   │              Command Handlers (Providers)            │  ││
│  │   │                                                      │  ││
│  │   │  Chassis  │  Sensor  │  Storage  │  OEM  │  ...      │  ││
│  │   └──────────────────────────────────────────────────────┘  ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                         D-Bus                               ││
│  │            (phosphor-* services, sensors, state)            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

Include IPMI components in your image:

```bitbake
# In your machine .conf or image recipe

# Include IPMI host daemon (required)
IMAGE_INSTALL:append = " phosphor-ipmi-host"

# Include network IPMI (RMCP+)
IMAGE_INSTALL:append = " phosphor-ipmi-net"

# Include IPMI flash support
IMAGE_INSTALL:append = " phosphor-ipmi-flash"

# Include IPMI FRU support
IMAGE_INSTALL:append = " phosphor-ipmi-fru"

# Exclude components you don't need
IMAGE_INSTALL:remove = "phosphor-ipmi-flash"
```

### Meson Build Options

```bash
# phosphor-ipmi-host options
meson setup build \
    -Dboot-flag-safe-mode-support=enabled \
    -Di2c-whitelist-check=disabled \
    -Dshort-sample-enable=enabled \
    -Dsoftoff=enabled

# phosphor-ipmi-net options
meson setup build \
    -Dpam=enabled \
    -Drmcp-ping=enabled
```

| Component | Option | Description |
|-----------|--------|-------------|
| host | `boot-flag-safe-mode-support` | Safe mode boot support |
| host | `i2c-whitelist-check` | I2C command whitelisting |
| host | `softoff` | Soft power off support |
| net | `pam` | PAM authentication |
| net | `rmcp-ping` | RMCP ping support |

### Runtime Enable/Disable

```bash
# Check IPMI services
systemctl status phosphor-ipmi-host
systemctl status phosphor-ipmi-net

# Disable network IPMI (security hardening)
systemctl stop phosphor-ipmi-net
systemctl disable phosphor-ipmi-net

# Re-enable
systemctl enable phosphor-ipmi-net
systemctl start phosphor-ipmi-net

# Restart after config change
systemctl restart phosphor-ipmi-host
```

### LAN Channel Configuration

Configure IPMI LAN settings:

```bash
# Get current LAN config
ipmitool lan print 1

# Set static IP
ipmitool lan set 1 ipsrc static
ipmitool lan set 1 ipaddr 192.168.1.100
ipmitool lan set 1 netmask 255.255.255.0
ipmitool lan set 1 defgw ipaddr 192.168.1.1

# Enable DHCP
ipmitool lan set 1 ipsrc dhcp

# Set authentication types
ipmitool lan set 1 auth admin md5

# Enable/disable LAN access
ipmitool lan set 1 access on
ipmitool lan set 1 access off
```

### User Configuration

```bash
# List users
ipmitool user list 1

# Create user
ipmitool user set name 2 operator
ipmitool user set password 2 "SecurePass123!"
ipmitool user enable 2
ipmitool user priv 2 3 1  # Operator privilege on channel 1

# Disable user
ipmitool user disable 2

# Set privilege levels
# 1=Callback, 2=User, 3=Operator, 4=Administrator
ipmitool user priv 2 4 1
```

### SOL (Serial Over LAN) Configuration

```bash
# Enable SOL
ipmitool sol set enabled true 1
ipmitool sol set privilege-level admin 1
ipmitool sol set force-payload-auth true 1

# Set baud rate
ipmitool sol set volatile-bit-rate 115.2 1
ipmitool sol set non-volatile-bit-rate 115.2 1

# Connect to SOL
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc sol activate
```

### Cipher Suite Configuration

Control encryption and authentication:

```bash
# View cipher suites
ipmitool lan print 1 | grep Cipher

# Disable weak cipher suites (security hardening)
# Cipher 0 = no auth, no encryption (insecure)
# Cipher 1 = auth only, no encryption
# Cipher 3 = auth + encryption (recommended minimum)
# Cipher 17 = strongest (AES-CBC-128, HMAC-SHA256)
```

### Watchdog Configuration

```bash
# Get watchdog status
ipmitool mc watchdog get

# Set watchdog timeout (60 seconds)
ipmitool mc watchdog set timeout 60

# Reset watchdog
ipmitool mc watchdog reset

# Disable watchdog
ipmitool mc watchdog off
```

---

## IPMI Basics

### Network Functions (NetFn)

| NetFn | Name | Description |
|-------|------|-------------|
| 0x00/0x01 | Chassis | Power control, boot options |
| 0x04/0x05 | Sensor/Event | Sensor readings, event messages |
| 0x06/0x07 | App | Device info, watchdog, sessions |
| 0x0A/0x0B | Storage | SEL, SDR, FRU access |
| 0x0C/0x0D | Transport | LAN configuration |
| 0x2C/0x2D | Group | OEM group extensions |
| 0x2E/0x2F | OEM/Group | Vendor-specific commands |
| 0x30-0x3F | OEM | Vendor-specific (by IANA) |

### Command Format

```
Request:
  [NetFn/LUN] [Command] [Data...]

Response:
  [NetFn/LUN] [Command] [Completion Code] [Data...]
```

---

## Using ipmitool

### Local Access (KCS)

```bash
# On the BMC
ipmitool raw 0x06 0x01    # Get Device ID

# Using the BMC driver
ipmitool -I open chassis status
```

### Remote Access (LAN)

```bash
# From a remote machine
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc chassis status

# Power commands
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc chassis power on
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc chassis power off
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc chassis power cycle

# Sensor reading
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc sensor list

# FRU information
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc fru print

# System Event Log
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc sel list
```

---

## ipmid Architecture

### Provider Libraries

Command handlers are implemented as shared libraries (providers):

```
/usr/lib/ipmid-providers/
├── libchassishandler.so
├── libsensorhandler.so
├── libstoragehandler.so
├── libapphandler.so
├── libuserhandler.so
└── liboemhandler.so
```

### Handler Registration

```cpp
#include <ipmid/api.hpp>

// Register a command handler
void registerHandler()
{
    ipmi::registerHandler(
        ipmi::prioOemBase,           // Priority
        ipmi::netFnChassis,          // Network function
        ipmi::chassis::cmdGetStatus, // Command
        ipmi::Privilege::User,       // Required privilege
        ipmiGetChassisStatus);       // Handler function
}

// Handler function signature
ipmi::RspType<...> ipmiGetChassisStatus()
{
    // Implementation
    return ipmi::responseSuccess(...);
}
```

---

## Implementing OEM Commands

### OEM Command Structure

OEM commands use NetFn 0x2E (OEM/Group) or 0x30-0x3F (OEM by IANA).

### Basic OEM Handler

{: .note }
> **Source Reference**: Pattern based on [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid)
> - API: [ipmid/api.hpp](https://github.com/openbmc/phosphor-host-ipmid/blob/master/include/ipmid/api.hpp)
> - Example handlers: [chassishandler.cpp](https://github.com/openbmc/phosphor-host-ipmid/blob/master/chassishandler.cpp)

```cpp
#include <ipmid/api.hpp>
#include <ipmid/utils.hpp>
#include <phosphor-logging/log.hpp>

using namespace phosphor::logging;

// OEM Network Function (use your IANA enterprise number)
constexpr ipmi::NetFn netFnOem = static_cast<ipmi::NetFn>(0x30);

// OEM Commands
constexpr uint8_t cmdOemGetVersion = 0x01;
constexpr uint8_t cmdOemSetLed = 0x02;

// Handler: Get OEM Version
ipmi::RspType<uint8_t, uint8_t, uint8_t>
    ipmiOemGetVersion()
{
    uint8_t major = 1;
    uint8_t minor = 0;
    uint8_t patch = 0;

    return ipmi::responseSuccess(major, minor, patch);
}

// Handler: Set LED state
ipmi::RspType<> ipmiOemSetLed(uint8_t ledId, uint8_t state)
{
    if (ledId > 3)
    {
        return ipmi::responseParmOutOfRange();
    }

    log<level::INFO>("OEM Set LED",
        entry("LED=%d", ledId),
        entry("STATE=%d", state));

    // Implementation via D-Bus
    auto bus = sdbusplus::bus::new_default();
    auto method = bus.new_method_call(
        "xyz.openbmc_project.LED.GroupManager",
        "/xyz/openbmc_project/led/groups/identify",
        "org.freedesktop.DBus.Properties",
        "Set");

    method.append("xyz.openbmc_project.Led.Group", "Asserted");
    method.append(std::variant<bool>(state == 1));

    try
    {
        bus.call(method);
    }
    catch (const std::exception& e)
    {
        return ipmi::responseUnspecifiedError();
    }

    return ipmi::responseSuccess();
}

// Register handlers
void registerOemHandlers()
{
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmdOemGetVersion,
        ipmi::Privilege::User,
        ipmiOemGetVersion);

    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmdOemSetLed,
        ipmi::Privilege::Operator,
        ipmiOemSetLed);
}
```

### Building OEM Provider

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.5)
project(myoem-ipmi CXX)

set(CMAKE_CXX_STANDARD 20)

find_package(PkgConfig REQUIRED)
pkg_check_modules(IPMI REQUIRED libipmid)
pkg_check_modules(SDBUSPLUS REQUIRED sdbusplus)
pkg_check_modules(PHOSPHOR_LOGGING REQUIRED phosphor-logging)

add_library(myoemhandler SHARED oem_handler.cpp)

target_include_directories(myoemhandler PRIVATE
    ${IPMI_INCLUDE_DIRS}
    ${SDBUSPLUS_INCLUDE_DIRS}
    ${PHOSPHOR_LOGGING_INCLUDE_DIRS}
)

target_link_libraries(myoemhandler
    ${IPMI_LIBRARIES}
    ${SDBUSPLUS_LIBRARIES}
    ${PHOSPHOR_LOGGING_LIBRARIES}
)

install(TARGETS myoemhandler
    LIBRARY DESTINATION lib/ipmid-providers
)
```

### BitBake Recipe

```bitbake
# myoem-ipmi_git.bb
SUMMARY = "My OEM IPMI Commands"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=..."

inherit cmake pkgconfig

DEPENDS += "sdbusplus phosphor-logging phosphor-ipmi-host"

SRC_URI = "git://github.com/myorg/myoem-ipmi.git;branch=main;protocol=https"
SRCREV = "..."

S = "${WORKDIR}/git"

HOSTIPMI_PROVIDER_LIBRARY += "libmyoemhandler.so"
```

---

## Testing OEM Commands

### Using ipmitool raw

```bash
# Test OEM Get Version (NetFn 0x30, Cmd 0x01)
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x01
# Response: 01 00 00 (version 1.0.0)

# Test OEM Set LED (NetFn 0x30, Cmd 0x02, LED 0, ON)
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x02 0x00 0x01
```

### Debugging

```bash
# Enable ipmid debug logging
systemctl stop phosphor-ipmi-host
/usr/bin/ipmid -v

# Check handler registration
journalctl -u phosphor-ipmi-host | grep -i register
```

---

## Common IPMI Operations

### Chassis Commands

```cpp
// Get Chassis Status
ipmi::RspType<uint8_t, uint8_t, uint8_t>
    ipmiGetChassisStatus()
{
    // Read power state from D-Bus
    auto bus = sdbusplus::bus::new_default();
    auto powerState = ipmi::getProperty<std::string>(
        bus,
        "xyz.openbmc_project.State.Chassis",
        "/xyz/openbmc_project/state/chassis0",
        "xyz.openbmc_project.State.Chassis",
        "CurrentPowerState");

    bool powerOn = (powerState.find("On") != std::string::npos);

    uint8_t currentPowerState = powerOn ? 0x01 : 0x00;
    uint8_t lastPowerEvent = 0x00;
    uint8_t miscState = 0x00;

    return ipmi::responseSuccess(
        currentPowerState, lastPowerEvent, miscState);
}
```

### Sensor Commands

```cpp
// Get Sensor Reading
ipmi::RspType<uint8_t, uint8_t, uint8_t>
    ipmiGetSensorReading(uint8_t sensorNumber)
{
    // Look up sensor path from SDR
    auto sensorPath = getSensorPath(sensorNumber);

    // Read value from D-Bus
    auto bus = sdbusplus::bus::new_default();
    auto value = ipmi::getProperty<double>(
        bus,
        "xyz.openbmc_project.HwmonTempSensor",
        sensorPath,
        "xyz.openbmc_project.Sensor.Value",
        "Value");

    // Convert to IPMI format
    uint8_t reading = static_cast<uint8_t>(value);
    uint8_t status = 0x40;  // Scanning enabled
    uint8_t thresholdStatus = 0x00;

    return ipmi::responseSuccess(
        reading, status, thresholdStatus);
}
```

---

## Host IPMI (KCS/BT)

### Configuration

The host interface is configured via device tree:

```dts
&kcs3 {
    status = "okay";
    aspeed,lpc-io-reg = <0xCA2>;
};
```

### systemd Service

```bash
# Check host IPMI service
systemctl status phosphor-ipmi-host

# View host IPMI messages
journalctl -u phosphor-ipmi-host -f
```

---

## LAN Configuration

### Via D-Bus

```bash
# Get LAN channel settings
busctl introspect xyz.openbmc_project.Ipmi.Channel.eth0 \
    /xyz/openbmc_project/network/eth0

# Get authentication settings
busctl get-property xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user \
    xyz.openbmc_project.User.AccountPolicy MaxLoginAttemptBeforeLockout
```

### Via ipmitool

```bash
# Get LAN configuration
ipmitool lan print 1

# Set IP address
ipmitool lan set 1 ipaddr 192.168.1.100

# Set gateway
ipmitool lan set 1 defgw ipaddr 192.168.1.1
```

---

## Troubleshooting

### Service Not Starting

```bash
# Check ipmid status
systemctl status phosphor-ipmi-host
journalctl -u phosphor-ipmi-host -n 50

# Check for provider loading errors
journalctl -u phosphor-ipmi-host | grep -i "error\|fail"
```

### Command Not Recognized

```bash
# Verify handler is registered
journalctl -u phosphor-ipmi-host | grep -i "register"

# Check provider library loaded
ls -la /usr/lib/ipmid-providers/
```

### Authentication Failures

```bash
# Check RMCP+ configuration
busctl tree xyz.openbmc_project.Ipmi.Channel.eth0

# Verify user credentials
ipmitool user list 1
```

---

## Deep Dive
{: .text-delta }

Advanced implementation details for IPMI developers.

### Command Handler Registration

IPMI commands are handled by provider libraries that register handlers at startup:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Handler Registration Flow                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   1. ipmid loads provider libraries at startup                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ /usr/lib/ipmid-providers/                                       │   │
│   │ ├── libchassishandler.so                                        │   │
│   │ ├── libsensorhandler.so                                         │   │
│   │ ├── libstoragehandler.so                                        │   │
│   │ └── liboemhandler.so                                            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                     │
│                                   ▼                                     │
│   2. Each library has constructor that calls ipmi::registerHandler()    │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ // In chassishandler.cpp                                        │   │
│   │ IPMI_REGISTER_HANDLER(                                          │   │
│   │     ipmi::prioOpenBmcBase,           // Priority                │   │
│   │     ipmi::netFnChassis,              // NetFn = 0x00            │   │
│   │     ipmi::chassis::cmdGetChassisStatus, // Cmd = 0x01           │   │
│   │     ipmi::Privilege::User,           // Minimum privilege       │   │
│   │     ipmiGetChassisStatus             // Handler function        │   │
│   │ );                                                              │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                     │
│                                   ▼                                     │
│   3. Handler stored in dispatch table                                   │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ handlers[{netFn, cmd}] = {priority, privilege, handler}         │   │
│   │                                                                 │   │
│   │ Multiple handlers can register for same (netFn, cmd)            │   │
│   │ Higher priority handler wins (OEM can override base)            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Priority levels (higher wins):**

| Priority | Value | Use Case |
|----------|-------|----------|
| `prioOpenBmcBase` | 10 | Default OpenBMC handlers |
| `prioOemBase` | 20 | OEM-specific overrides |
| `prioMax` | 40 | Highest priority handlers |

**Source reference**: [ipmid/api.hpp](https://github.com/openbmc/phosphor-host-ipmid/blob/master/include/ipmid/api.hpp)

### Message Flow Through KCS Interface

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    KCS Message Flow                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Host CPU                              BMC                             │
│   ┌────────────┐                        ┌────────────┐                  │
│   │            │                        │            │                  │
│   │  Host OS   │    KCS Registers       │   ipmid    │                  │
│   │  (driver)  │    ┌──────────┐        │            │                  │
│   │            │───▶│ Data_In  │───────▶│            │                  │
│   │            │    │ Data_Out │◀───────│            │                  │
│   │            │    │ Command  │        │            │                  │
│   │            │◀───│ Status   │───────▶│            │                  │
│   └────────────┘    └──────────┘        └────────────┘                  │
│                                                                         │
│   Message Structure (IPMI Request):                                     │
│   ┌────────┬────────┬────────┬─────────────────────┐                    │
│   │ NetFn  │  Cmd   │  Data  │        ...          │                    │
│   │ (6-bit)│ (8-bit)│ (0-N)  │                     │                    │
│   └────────┴────────┴────────┴─────────────────────┘                    │
│                                                                         │
│   KCS State Machine:                                                    │
│   ┌──────┐    Write_Start    ┌──────┐                                   │
│   │ IDLE │──────────────────▶│ WRITE│                                   │
│   └──────┘                   └───┬──┘                                   │
│       ▲                          │                                      │
│       │                          │ Write_End                            │
│       │ Response_Complete        ▼                                      │
│   ┌───┴──┐                   ┌──────┐                                   │
│   │ READ │◀──────────────────│ EXEC │                                   │
│   └──────┘    Read_Start     └──────┘                                   │
│                                                                         │
│   Device: /dev/ipmi-kcs1 (or /dev/kcs1)                                 │
│   Driver: kcs_bmc (kernel module)                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### RMCP+ Session Authentication

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RMCP+ Session Establishment                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Client                                    BMC (netipmid)              │
│      │                                          │                       │
│      │  1. Get Channel Auth Capabilities        │                       │
│      │─────────────────────────────────────────▶│                       │
│      │◀─────────────────────────────────────────│ (RMCP+ supported)     │
│      │                                          │                       │
│      │  2. Open Session Request                 │                       │
│      │   (auth algorithm, integrity, cipher)    │                       │
│      │─────────────────────────────────────────▶│                       │
│      │◀─────────────────────────────────────────│ (session ID, algos)   │
│      │                                          │                       │
│      │  3. RAKP Message 1 (client random)       │                       │
│      │─────────────────────────────────────────▶│                       │
│      │◀─────────────────────────────────────────│ RAKP 2 (BMC random,   │
│      │                                          │  session auth)        │
│      │  4. RAKP Message 3 (client auth)         │                       │
│      │─────────────────────────────────────────▶│                       │
│      │◀─────────────────────────────────────────│ RAKP 4 (success)      │
│      │                                          │                       │
│      │  5. Authenticated IPMI Commands          │                       │
│      │   (encrypted with session keys)          │                       │
│      │─────────────────────────────────────────▶│                       │
│      │                                          │                       │
│                                                                         │
│   Cipher Suite 17 (commonly used):                                      │
│   ├── Authentication: RAKP-HMAC-SHA256                                  │
│   ├── Integrity: HMAC-SHA256-128                                        │
│   └── Confidentiality: AES-CBC-128                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### SDR (Sensor Data Record) Structure

```
┌────────────────────────────────────────────────────────────────────────┐
│                    SDR Record Types                                    │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   SDR Type 0x01 - Full Sensor Record (43+ bytes):                      │
│   ┌───────────────────────────────────────────────────────────────┐    │
│   │ Offset │ Field                    │ Size │ Description        │    │
│   ├────────┼──────────────────────────┼──────┼────────────────────┤    │
│   │ 0-1    │ Record ID                │ 2    │ Unique identifier  │    │
│   │ 2      │ SDR Version              │ 1    │ 0x51 = IPMI 1.5    │    │
│   │ 3      │ Record Type              │ 1    │ 0x01 = Full        │    │
│   │ 4      │ Record Length            │ 1    │ Bytes following    │    │
│   │ 5      │ Sensor Owner ID          │ 1    │ I2C address/LUN    │    │
│   │ 6      │ Sensor Owner LUN         │ 1    │ Channel/LUN        │    │
│   │ 7      │ Sensor Number            │ 1    │ 0-255              │    │
│   │ 8      │ Entity ID                │ 1    │ CPU, memory, etc.  │    │
│   │ 9      │ Entity Instance          │ 1    │ Which instance     │    │
│   │ 10     │ Sensor Initialization    │ 1    │ Flags              │    │
│   │ 11     │ Sensor Capabilities      │ 1    │ Threshold support  │    │
│   │ 12     │ Sensor Type              │ 1    │ Temperature, etc.  │    │
│   │ 13     │ Event/Reading Type       │ 1    │ Threshold/discrete │    │
│   │ 14-15  │ Assertion Event Mask     │ 2    │ Events to assert   │    │
│   │ 16-17  │ Deassertion Event Mask   │ 2    │ Events to deassert │    │
│   │ 18-19  │ Discrete Reading Mask    │ 2    │ Readable states    │    │
│   │ 20     │ Sensor Units 1           │ 1    │ Unit modifiers     │    │
│   │ 21     │ Sensor Units 2 (Base)    │ 1    │ Degrees C, Volts   │    │
│   │ 22     │ Sensor Units 3 (Mod)     │ 1    │ Modifier unit      │    │
│   │ 23     │ Linearization            │ 1    │ Linear, log, etc.  │    │
│   │ 24-25  │ M, M Tolerance           │ 2    │ Scaling: M         │    │
│   │ 26-27  │ B, B Accuracy            │ 2    │ Scaling: B         │    │
│   │ 28     │ Accuracy/Direction       │ 1    │ Acc exp, direction │    │
│   │ 29     │ R exp, B exp             │ 1    │ Exponents          │    │
│   │ ...    │ Thresholds, ID string    │ ...  │                    │    │
│   └───────────────────────────────────────────────────────────────┘    │
│                                                                        │
│   Reading Conversion:                                                  │
│   y = (M × raw + B × 10^Bexp) × 10^Rexp                                │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### OEM Command Registration Pattern

```cpp
// Example: Custom OEM command handler
#include <ipmid/api.hpp>

// Define OEM NetFn (0x30-0x3F are OEM)
constexpr ipmi::NetFn oemNetFn = 0x30;
constexpr ipmi::Cmd oemGetInfo = 0x01;

// Handler function
ipmi::RspType<uint8_t, // version
              std::string> // description
    oemGetInfoHandler(ipmi::Context::ptr ctx)
{
    // Access D-Bus if needed
    auto bus = getSdBus();

    // Return success with data
    return ipmi::responseSuccess(
        uint8_t{0x01},           // version
        std::string{"My OEM"}    // description
    );
}

// Register at library load
void registerOemHandlers() __attribute__((constructor));
void registerOemHandlers()
{
    ipmi::registerHandler(
        ipmi::prioOemBase,
        oemNetFn,
        oemGetInfo,
        ipmi::Privilege::User,
        oemGetInfoHandler
    );
}
```

### Source Code Reference

Key implementation files in [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid):

| File | Description |
|------|-------------|
| `ipmid.cpp` | Main daemon, message dispatch |
| `chassishandler.cpp` | Chassis commands (power, identify) |
| `sensorhandler.cpp` | Sensor reading, thresholds, SDR |
| `storagehandler.cpp` | FRU, SEL, SDR repository |
| `apphandler.cpp` | Application commands (device ID) |
| `include/ipmid/api.hpp` | Handler registration API |
| `include/ipmid/types.hpp` | Type definitions |

---

## References

- [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid) - D-Bus based IPMI daemon
- [ipmid API Headers](https://github.com/openbmc/phosphor-host-ipmid/tree/master/include/ipmid)
- [IPMI Specification](https://www.intel.com/content/dam/www/public/us/en/documents/product-briefs/ipmi-second-gen-interface-spec-v2-rev1-1.pdf)
- [OpenBMC IPMI Design](https://github.com/openbmc/docs/blob/master/architecture/ipmi-architecture.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
