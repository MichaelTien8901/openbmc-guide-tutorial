---
layout: default
title: Core Services
nav_order: 3
has_children: true
permalink: /docs/core-services
---

# Core Services

Master the essential services that make up an OpenBMC system.

## What You'll Learn

- Sensor monitoring and configuration (D-Bus sensors, hwmon)
- Entity Manager for hardware discovery
- Thermal management and fan control (PID, zones)
- Power management and sequencing
- User management (accounts, privileges, LDAP)
- Network configuration (IP, VLAN)
- LED control (identify, lamp test)
- Certificate management (TLS/SSL)
- Time synchronization (NTP, RTC)
- Hardware inventory and FRU data
- Watchdog timer configuration
- Button handling (power, reset)

## Service Categories

### Sensors & Monitoring

Monitor hardware health through temperature, voltage, current, and fan sensors.

| Guide | Description |
|-------|-------------|
| [D-Bus Sensors]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) | ADC, hwmon, virtual sensors |
| [Hwmon Sensors]({% link docs/03-core-services/02-hwmon-sensors-guide.md %}) | Linux hwmon integration |
| [Entity Manager]({% link docs/03-core-services/03-entity-manager-guide.md %}) | Hardware discovery and configuration |

### Thermal & Power

Control cooling and power systems to keep hardware within operating limits.

| Guide | Description |
|-------|-------------|
| [Fan Control]({% link docs/03-core-services/04-fan-control-guide.md %}) | PID thermal control, zones |
| [Power Management]({% link docs/03-core-services/05-power-management-guide.md %}) | Power sequencing, regulators |

### System Services

Essential services for system operation.

| Guide | Description |
|-------|-------------|
| [User Manager]({% link docs/03-core-services/06-user-manager-guide.md %}) | Accounts, privileges, LDAP |
| [Network]({% link docs/03-core-services/07-network-guide.md %}) | IP configuration, VLAN |
| [LED Manager]({% link docs/03-core-services/08-led-manager-guide.md %}) | LED control, identify, lamp test |
| [Certificate Manager]({% link docs/03-core-services/09-certificate-manager-guide.md %}) | TLS/SSL certificates |
| [Time Manager]({% link docs/03-core-services/10-time-manager-guide.md %}) | NTP, RTC, timezones |
| [Inventory Manager]({% link docs/03-core-services/11-inventory-manager-guide.md %}) | FRU, hardware inventory |
| [Watchdog]({% link docs/03-core-services/12-watchdog-guide.md %}) | Host watchdog timer |
| [Buttons]({% link docs/03-core-services/13-buttons-guide.md %}) | Power/reset buttons |

## Prerequisites

- Complete [Architecture]({% link docs/02-architecture/index.md %}) section
- Understand D-Bus basics
- Working QEMU environment
