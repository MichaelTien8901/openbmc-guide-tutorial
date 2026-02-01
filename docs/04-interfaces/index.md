---
layout: default
title: Interfaces
nav_order: 4
has_children: true
permalink: /docs/interfaces
---

# External Interfaces

Learn how to interact with OpenBMC through its management interfaces.

## What You'll Learn

- IPMI protocol and OEM command implementation
- Redfish REST API, OEM extensions, and multi-BMC aggregation
- WebUI customization and branding
- Remote access via KVM, virtual media, and console
- SSH access and security hardening

## Interface Overview

```
                    ┌─────────────────────────────────────┐
                    │          Management Client          │
                    └─────────────────────────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
        ▼                            ▼                            ▼
┌───────────────┐          ┌─────────────────┐          ┌─────────────────┐
│     IPMI      │          │     Redfish     │          │     WebUI       │
│  (ipmitool)   │          │   (REST API)    │          │   (Browser)     │
└───────────────┘          └─────────────────┘          └─────────────────┘
        │                            │                            │
        ▼                            ▼                            ▼
┌────────────────┐         ┌─────────────────┐          ┌─────────────────┐
│  ipmid/netipmid│         │     bmcweb      │          │   webui-vue     │
└────────────────┘         └─────────────────┘          └─────────────────┘
        │                            │                            │
        └────────────────────────────┼────────────────────────────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────────┐
                    │             D-Bus Services          │
                    └─────────────────────────────────────┘
```

## Guides in This Section

### Management Protocols

| Guide | Description | Use Case |
|-------|-------------|----------|
| [IPMI]({% link docs/04-interfaces/01-ipmi-guide.md %}) | IPMI protocol, OEM commands | Legacy management, scripting |
| [Redfish]({% link docs/04-interfaces/02-redfish-guide.md %}) | REST API, modern management | Cloud integration, automation |
| [WebUI]({% link docs/04-interfaces/03-webui-guide.md %}) | Browser-based management | Human operators |

### Remote Access

| Guide | Description | Use Case |
|-------|-------------|----------|
| [KVM]({% link docs/04-interfaces/04-kvm-guide.md %}) | Remote keyboard/video/mouse | OS installation, troubleshooting |
| [Virtual Media]({% link docs/04-interfaces/05-virtual-media-guide.md %}) | Remote ISO/image mounting | OS installation |
| [Console]({% link docs/04-interfaces/06-console-guide.md %}) | Serial over LAN | Boot monitoring, recovery |

### Security

| Guide | Description |
|-------|-------------|
| [SSH]({% link docs/04-interfaces/07-ssh-security-guide.md %}) | SSH access and hardening |

## Which Interface to Use?

| Scenario | Recommended Interface |
|----------|----------------------|
| Scripting / Automation | Redfish (REST) |
| Legacy tools / ipmitool | IPMI |
| Human operators | WebUI |
| Cloud management platforms | Redfish |
| Bulk operations | Redfish with scripting |

## Prerequisites

- Complete [Core Services]({% link docs/03-core-services/index.md %}) basics
- Understand D-Bus object model
- Working QEMU environment with network access
