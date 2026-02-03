---
layout: default
title: Architecture
nav_order: 3
has_children: true
permalink: /docs/architecture
---

# Architecture

Understand how OpenBMC is designed and how its components work together.

## What You'll Learn

- OpenBMC's overall architecture and design philosophy
- The D-Bus communication system that connects all services
- State management for BMC, chassis, and host
- How to navigate the codebase and find components

## Key Concepts

### D-Bus: The Nervous System

OpenBMC uses D-Bus as the central communication backbone. All services expose their data and functionality through D-Bus interfaces, enabling:

- Loose coupling between components
- Dynamic service discovery
- Language-agnostic communication
- Easy debugging and introspection

### Phosphor Services

The "phosphor-*" repositories contain the core OpenBMC services:

- **phosphor-state-manager**: System state control
- **phosphor-logging**: Event and error logging
- **phosphor-dbus-interfaces**: Standard interface definitions
- And many more...

## Guides in This Section

| Guide | Description | Difficulty |
|-------|-------------|------------|
| [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) | Architecture, build system, community | Beginner |
| [D-Bus Fundamentals]({% link docs/02-architecture/02-dbus-guide.md %}) | D-Bus concepts and usage | Beginner |
| [State Management]({% link docs/02-architecture/03-state-manager-guide.md %}) | BMC/Chassis/Host states | Intermediate |

## Prerequisite Knowledge

Before diving into architecture:
- Complete the [Getting Started]({% link docs/01-getting-started/index.md %}) section
- Have a working QEMU environment
- Basic understanding of Linux services (systemd)
