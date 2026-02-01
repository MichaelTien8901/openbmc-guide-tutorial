---
layout: default
title: Network Guide
parent: Core Services
nav_order: 7
difficulty: intermediate
prerequisites:
  - dbus-guide
---

# Network Guide
{: .no_toc }

Configure BMC network settings using phosphor-networkd.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-networkd** manages BMC network configuration, providing D-Bus interfaces for IP configuration, VLAN, DNS, and network settings.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Network Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Configuration APIs                       ││
│  │                                                             ││
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    ││
│  │   │ Redfish  │  │  IPMI    │  │  D-Bus   │  │  WebUI   │    ││
│  │   │ API      │  │ Network  │  │ busctl   │  │  Config  │    ││
│  │   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘    ││
│  └────────┼─────────────┼─────────────┼─────────────┼──────────┘│
│           └─────────────┴──────┬──────┴─────────────┘           │
│                                │                                │
│  ┌─────────────────────────────┴───────────────────────────────┐│
│  │                   phosphor-networkd                         ││
│  │                                                             ││
│  │   ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  ││
│  │   │ Interface Mgmt │  │ IP/VLAN Config │  │ DNS/DHCP     │  ││
│  │   │ eth0, eth1     │  │ static, dhcp   │  │ Hostname     │  ││
│  │   └────────────────┘  └────────────────┘  └──────────────┘  ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                    systemd-networkd                         ││
│  │                  (.network files)                           ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include network management
IMAGE_INSTALL:append = " \
    phosphor-network \
"

# Configure Meson options
EXTRA_OEMESON:pn-phosphor-network = " \
    -Ddefault-link-local-autoconf=true \
    -Ddefault-ipv6-accept-ra=true \
"
```

### Meson Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `default-link-local-autoconf` | true | Enable link-local IPv4 |
| `default-ipv6-accept-ra` | true | Accept IPv6 router advertisements |
| `sync-mac` | true | Sync MAC with hardware |
| `persist-mac` | false | Persist MAC across reboots |

### Runtime Configuration

```bash
# Check network service
systemctl status systemd-networkd
systemctl status phosphor-network

# View network configuration files
ls /etc/systemd/network/

# View current network state
networkctl status
```

---

## IP Address Configuration

### View Current Configuration

```bash
# Via D-Bus
busctl tree xyz.openbmc_project.Network

# Get interface info
busctl introspect xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0

# Via ip command
ip addr show eth0
```

### Via Redfish

```bash
# Get ethernet interfaces
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces

# Get specific interface
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0
```

### Configure Static IP

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "IPv4Addresses": [
            {
                "Address": "192.168.1.100",
                "SubnetMask": "255.255.255.0",
                "Gateway": "192.168.1.1",
                "AddressOrigin": "Static"
            }
        ]
    }' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0

# Via D-Bus
busctl call xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.IP.Create \
    IP ssys \
    "xyz.openbmc_project.Network.IP.Protocol.IPv4" \
    "192.168.1.100" \
    24 \
    "192.168.1.1"
```

### Configure DHCP

```bash
# Enable DHCP via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"DHCPv4": {"DHCPEnabled": true}}' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0

# Via D-Bus
busctl set-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.EthernetInterface \
    DHCPEnabled s "xyz.openbmc_project.Network.EthernetInterface.DHCPConf.v4"
```

### Delete IP Address

```bash
# Get IP address object path
busctl tree xyz.openbmc_project.Network | grep ipv4

# Delete via D-Bus
busctl call xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0/ipv4/abc123 \
    xyz.openbmc_project.Object.Delete \
    Delete
```

---

## IPv6 Configuration

### Enable IPv6

```bash
# Configure IPv6 static address
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "IPv6Addresses": [
            {
                "Address": "2001:db8::100",
                "PrefixLength": 64,
                "AddressOrigin": "Static"
            }
        ]
    }' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0
```

### Enable SLAAC

```bash
# Enable IPv6 router advertisement
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"IPv6StaticAddresses": [], "StatelessAddressAutoConfig": {"IPv6AutoConfigEnabled": true}}' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0
```

---

## VLAN Configuration

### Create VLAN

```bash
# Via Redfish
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "VLANEnable": true,
        "VLANId": 100
    }' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0/VLANs

# Via D-Bus
busctl call xyz.openbmc_project.Network \
    /xyz/openbmc_project/network \
    xyz.openbmc_project.Network.VLAN.Create \
    VLAN su "eth0" 100
```

### Configure VLAN IP

```bash
# Configure IP on VLAN interface
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "IPv4Addresses": [
            {
                "Address": "10.0.100.10",
                "SubnetMask": "255.255.255.0",
                "Gateway": "10.0.100.1",
                "AddressOrigin": "Static"
            }
        ]
    }' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0_100
```

### Delete VLAN

```bash
curl -k -u root:0penBmc -X DELETE \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0_100
```

---

## DNS Configuration

### Configure DNS Servers

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "StaticNameServers": ["8.8.8.8", "8.8.4.4"]
    }' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0

# Via D-Bus
busctl set-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.EthernetInterface \
    StaticNameServers as 2 "8.8.8.8" "8.8.4.4"
```

### View DNS Configuration

```bash
# Check current DNS
cat /etc/resolv.conf

# Via D-Bus
busctl get-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.EthernetInterface \
    Nameservers
```

---

## Hostname Configuration

### Set Hostname

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"HostName": "my-bmc"}' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol

# Via D-Bus
busctl set-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/config \
    xyz.openbmc_project.Network.SystemConfiguration \
    HostName s "my-bmc"
```

### Set Domain Name

```bash
busctl set-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/config \
    xyz.openbmc_project.Network.SystemConfiguration \
    DefaultGateway s "192.168.1.1"
```

---

## MAC Address Configuration

### View MAC Address

```bash
# Via ip command
ip link show eth0

# Via D-Bus
busctl get-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.MACAddress \
    MACAddress
```

### Set MAC Address

```bash
# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"MACAddress": "AA:BB:CC:DD:EE:FF"}' \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0
```

---

## Network Protocol Configuration

### Enable/Disable Protocols

```bash
# Configure network protocols
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "HTTPS": {"ProtocolEnabled": true, "Port": 443},
        "SSH": {"ProtocolEnabled": true, "Port": 22},
        "IPMI": {"ProtocolEnabled": true, "Port": 623}
    }' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol
```

---

## IPMI LAN Configuration

### View LAN Configuration

```bash
ipmitool lan print
```

### Configure LAN Channel

```bash
# Set static IP
ipmitool lan set 1 ipsrc static
ipmitool lan set 1 ipaddr 192.168.1.100
ipmitool lan set 1 netmask 255.255.255.0
ipmitool lan set 1 defgw ipaddr 192.168.1.1

# Enable DHCP
ipmitool lan set 1 ipsrc dhcp
```

---

## Troubleshooting

### No Network Connectivity

```bash
# Check interface status
ip link show eth0
networkctl status eth0

# Check for IP address
ip addr show eth0

# Check routing table
ip route

# Ping gateway
ping -c 3 192.168.1.1
```

### DHCP Not Working

```bash
# Check DHCP client
journalctl -u systemd-networkd | grep DHCP

# Force DHCP renewal
networkctl renew eth0
```

### DNS Resolution Issues

```bash
# Check DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup example.com
```

### Configuration Not Persisting

```bash
# Check network configuration files
ls -la /etc/systemd/network/

# Verify phosphor-network service
systemctl status phosphor-network

# Check for errors
journalctl -u phosphor-network
```

---

## Configuration Persistence

Network configuration is stored in:

```bash
# systemd-networkd files
/etc/systemd/network/00-bmc-eth0.network

# Example content:
[Match]
Name=eth0

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=8.8.8.8
```

---

## References

- [phosphor-networkd](https://github.com/openbmc/phosphor-networkd)
- [systemd-networkd](https://www.freedesktop.org/software/systemd/man/systemd-networkd.html)
- [Redfish EthernetInterface](https://redfish.dmtf.org/schemas/EthernetInterface.v1_8_0.json)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
