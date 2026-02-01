---
layout: default
title: Verification Guide
parent: Porting
nav_order: 5
difficulty: advanced
prerequisites:
  - uboot
---

# Verification Guide
{: .no_toc }

Test and validate your OpenBMC port.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Systematic verification ensures your OpenBMC port works correctly. This guide provides test procedures for each major subsystem.

---

## Verification Checklist

### Boot & Basic

- [ ] U-Boot initializes correctly
- [ ] Kernel boots without errors
- [ ] Root filesystem mounts
- [ ] BMC reaches Ready state
- [ ] Console access works
- [ ] Network connectivity

### Power Control

- [ ] Power on host
- [ ] Power off host
- [ ] Graceful shutdown
- [ ] Force power off
- [ ] Power cycle
- [ ] Reset host

### Sensors

- [ ] Temperature sensors read correctly
- [ ] Voltage sensors read correctly
- [ ] Fan tach sensors work
- [ ] Thresholds trigger events
- [ ] Sensors appear in Redfish/IPMI

### Thermal Management

- [ ] Fan PWM control works
- [ ] PID control adjusts fans
- [ ] Thermal zones configured
- [ ] Over-temperature protection

### Remote Access

- [ ] SSH login
- [ ] WebUI access
- [ ] Redfish API
- [ ] IPMI over LAN
- [ ] KVM (if applicable)
- [ ] Virtual media (if applicable)

---

## Boot Verification

### U-Boot Check

```bash
# During boot, watch for:
# - Memory initialization
# - Flash detection
# - Kernel loading

# At U-Boot prompt:
printenv
md 0x80000000 100  # Memory check
```

### Kernel Boot

```bash
# Watch console for:
# - Device tree loading
# - Driver initialization
# - Filesystem mount

# Check dmesg after boot
dmesg | grep -i error
dmesg | grep -i fail
```

### BMC State

```bash
# Check BMC state
obmcutil state

# Expected:
# BMC: Ready
# Chassis: Off (initially)
# Host: Off (initially)
```

---

## Power Control Tests

### Basic Power Operations

```bash
# Power on
obmcutil poweron
sleep 10
obmcutil state  # Check host is Running

# Power off
obmcutil poweroff
sleep 10
obmcutil state  # Check host is Off

# Power cycle
obmcutil poweron
sleep 30
obmcutil powercycle
sleep 10
obmcutil state
```

### GPIO Verification

```bash
# Check power GPIOs
cat /sys/kernel/debug/gpio | grep -i power

# Manual GPIO test (careful!)
gpioset gpiochip0 10=1  # Assert power
gpioget gpiochip0 11    # Read status
```

---

## Sensor Verification

### List Sensors

```bash
# D-Bus sensors
busctl tree xyz.openbmc_project.Sensor

# Redfish sensors
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors

# IPMI sensors
ipmitool sensor list
```

### Verify Readings

```bash
# Read specific sensor
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Check hwmon
cat /sys/class/hwmon/hwmon*/temp*_input
```

### Threshold Test

```bash
# Force threshold crossing (test environment only)
# Watch for events in Redfish logs
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/EventLog/Entries
```

---

## Fan Control Tests

### Manual Control

```bash
# Set manual mode
busctl set-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/control/fanpwm/zone0 \
    xyz.openbmc_project.Control.Mode \
    Manual b true

# Set PWM
busctl set-property xyz.openbmc_project.Hwmon.external \
    /xyz/openbmc_project/control/fanpwm/Pwm_0 \
    xyz.openbmc_project.Control.FanPwm \
    Target t 50
```

### Verify Fan Speed

```bash
# Read tachometer
busctl get-property xyz.openbmc_project.FanSensor \
    /xyz/openbmc_project/sensors/fan_tach/Fan0 \
    xyz.openbmc_project.Sensor.Value Value
```

---

## Network Tests

### Basic Connectivity

```bash
# Check interface
ip addr show eth0

# Ping gateway
ping -c 3 192.168.1.1

# DNS resolution
nslookup example.com
```

### Service Access

```bash
# SSH
ssh -p 22 root@bmc-ip

# HTTPS
curl -k https://bmc-ip/

# IPMI
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc power status
```

---

## Redfish API Tests

```bash
# Service root
curl -k -u root:0penBmc https://localhost/redfish/v1/

# System info
curl -k -u root:0penBmc https://localhost/redfish/v1/Systems/system

# Manager info
curl -k -u root:0penBmc https://localhost/redfish/v1/Managers/bmc

# Chassis info
curl -k -u root:0penBmc https://localhost/redfish/v1/Chassis/chassis
```

---

## IPMI Tests

```bash
# Power status
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc power status

# Sensor list
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sensor list

# FRU data
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc fru print

# SEL
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc sel list
```

---

## Common Issues

### Sensors Not Appearing

```bash
# Check Entity Manager
journalctl -u entity-manager

# Verify configuration
cat /usr/share/entity-manager/configurations/*.json

# Check dbus-sensors
journalctl -u dbus-sensors
```

### Power Control Fails

```bash
# Check GPIO configuration
cat /sys/kernel/debug/gpio

# Check state manager
journalctl -u phosphor-state-manager-host

# Verify device tree GPIO nodes
```

### Network Issues

```bash
# Check driver
dmesg | grep -i eth

# Check systemd-networkd
systemctl status systemd-networkd
journalctl -u systemd-networkd
```

---

## Automated Testing

### Robot Framework

```robot
*** Test Cases ***
Verify BMC State Is Ready
    ${state}=    Get BMC State
    Should Be Equal    ${state}    Ready

Verify Power On Works
    Power On Host
    Wait Until Host Is Running
    ${state}=    Get Host State
    Should Be Equal    ${state}    Running
```

---

## References

- [OpenBMC Test Documentation](https://github.com/openbmc/openbmc-test-automation)
- [Robot Framework](https://robotframework.org/)

---

{: .note }
**Prerequisites**: Working OpenBMC build on target hardware
