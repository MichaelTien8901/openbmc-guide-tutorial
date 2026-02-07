---
layout: default
title: Systemd Boot Ordering Guide
parent: Architecture
nav_order: 5
difficulty: intermediate
prerequisites:
  - openbmc-overview
  - dbus-guide
  - state-manager-guide
last_modified_date: 2026-02-06
---

# Systemd Boot Ordering Guide
{: .no_toc }

Understand how OpenBMC uses systemd targets, dependencies, and template units to orchestrate the boot sequence and host power management.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC relies on systemd as its init system and service manager. Every daemon, one-shot script, and power-state transition is controlled through systemd units. Understanding how these units relate to each other is essential for developing or debugging OpenBMC services.

This guide covers the target hierarchy that drives the BMC boot sequence, the dependency directives that control service ordering, tools for diagnosing boot timing and failures, and the template unit mechanism that enables multi-host support. All commands run directly on the BMC and are fully testable in a QEMU ast2600-evb environment.

**Key concepts covered:**
- OpenBMC systemd target hierarchy (boot and power-on chains)
- Wants vs Requires and After vs Before semantics
- Boot time profiling with `systemd-analyze`
- Service failure debugging with `journalctl` and `systemctl`
- Multi-host template units (`@.service`, `%i` specifier)
- The `RemainAfterExit=yes` pattern for oneshot services

---

## OpenBMC Target Hierarchy

systemd uses **targets** as synchronization points. A target groups related services together and establishes ordering between boot phases. OpenBMC defines a custom set of targets on top of the standard systemd targets.

### BMC Boot Sequence

When the BMC powers on, systemd walks the following target chain to bring the system to a ready state:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    BMC Boot Target Chain                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   sysinit.target                                                        │
│        │                                                                │
│        ▼                                                                │
│   basic.target                                                          │
│        │                                                                │
│        ▼                                                                │
│   multi-user.target                                                     │
│        │  (standard Linux boot complete)                                │
│        ▼                                                                │
│   obmc-standby.target                                                   │
│        │  (BMC-specific services ready: D-Bus, mapper, REST/Redfish)    │
│        │                                                                │
│        │  BMC is now Ready.                                             │
│        │  Host power-on targets activate on user request.               │
│        │                                                                │
│        ▼                                                                │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  Power-on chain (triggered by obmcutil poweron):                │   │
│   │                                                                 │   │
│   │  obmc-chassis-poweron@0.target                                  │   │
│   │       │  (PSU monitoring, fan control, power sequencing)        │   │
│   │       ▼                                                         │   │
│   │  obmc-host-startmin@0.target                                    │   │
│   │       │  (minimal host services: state manager, host check)     │   │
│   │       ▼                                                         │   │
│   │  obmc-host-start@0.target                                       │   │
│   │       │  (full host services: IPMI host, watchdog, SOL)         │   │
│   │       ▼                                                         │   │
│   │  Host is Running.                                               │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Power-off chain (reverse order):                                      │
│   obmc-host-stop@0.target → obmc-chassis-poweroff@0.target              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### What Each Target Provides

| Target | Services Pulled In |
|--------|--------------------|
| `multi-user.target` | systemd core, networking, sshd |
| `obmc-standby.target` | D-Bus broker, phosphor-mapper, bmcweb, state-manager |
| `obmc-chassis-poweron@.target` | PSU monitor, fan monitor, power sequencing |
| `obmc-host-startmin@.target` | Host state manager, host check services |
| `obmc-host-start@.target` | IPMI host, watchdog, SOL console, sensor polling |
| `obmc-host-stop@.target` | IPMI stop, graceful shutdown coordination |
| `obmc-chassis-poweroff@.target` | Power rail disable, fan ramp-down |

{: .note }
The `obmc-standby.target` is the dividing line between "BMC boot" and "host management." The BMC state manager transitions to `Ready` when this target completes. Everything below it activates only when a host power-on is requested.

### Viewing the Target Hierarchy

Use `systemctl list-dependencies` to explore the live target tree on a running BMC:

```bash
# Show what obmc-standby.target pulls in
systemctl list-dependencies obmc-standby.target

# Show the full host power-on chain
systemctl list-dependencies obmc-host-start@0.target

# Show reverse dependencies (what depends on a target)
systemctl list-dependencies --reverse obmc-chassis-poweron@0.target

# Show all targets and their current state
systemctl list-units --type=target
```

{: .tip }
Add `--all` to `list-dependencies` to include inactive units. This helps you see services that are installed but not currently running.

---

## Wants, Requires, After, and Before

systemd separates two concepts that developers often confuse: **dependency** (whether to start a unit) and **ordering** (when to start it). OpenBMC services use both, and getting them wrong causes subtle boot failures.

### Dependency Directives: Wants vs Requires

| Directive | Effect | If dependency fails |
|-----------|--------|---------------------|
| `Wants=B.service` | Start B when A starts | A keeps running |
| `Requires=B.service` | Start B when A starts | A is stopped |
| `BindsTo=B.service` | Start B when A starts | A is stopped immediately |

**Wants** is the most common directive in OpenBMC. It creates a soft dependency: the system tries to start the wanted unit, but the wanting unit survives if the dependency fails.

**Requires** creates a hard dependency: if the required unit fails to start or is stopped, the requiring unit is also stopped. Use this sparingly -- it creates brittle dependency chains.

```ini
# Typical OpenBMC pattern: soft dependency with Wants
[Unit]
Description=Phosphor Fan Monitor
Wants=phosphor-fan-presence-tach.service
After=phosphor-fan-presence-tach.service
```

{: .warning }
Never use `Requires=` when `Wants=` is sufficient. If a `Requires=` target fails transiently (for example, a sensor driver takes an extra second to load), the entire dependent chain collapses. OpenBMC targets use `Wants=` for this reason.

### Ordering Directives: After vs Before

| Directive | Effect |
|-----------|--------|
| `After=B.service` | Start A only after B finishes starting |
| `Before=B.service` | Start A before B begins starting |

{: .note }
`Wants=` and `After=` are independent. `Wants=B` without `After=B` starts both A and B simultaneously. `After=B` without `Wants=B` means A waits for B only if something else starts B. You almost always need both together.

### Common OpenBMC Ordering Patterns

#### Pattern 1: Start After D-Bus Is Available

Most OpenBMC services need the D-Bus broker running before they can register their interfaces:

```ini
[Unit]
Description=My OpenBMC Service
After=dbus.service
Wants=dbus.service
```

#### Pattern 2: Start After Phosphor-Mapper

Services that need to look up other services through the object mapper must wait for it:

```ini
[Unit]
Description=My Mapper-Dependent Service
After=mapper-wait@-xyz-openbmc_project-sensors.service
Wants=mapper-wait@-xyz-openbmc_project-sensors.service
```

The `mapper-wait@.service` template is a special helper that blocks until a specific D-Bus object path is available. The path `/xyz/openbmc_project/sensors` is encoded with dashes as `-xyz-openbmc_project-sensors` in the unit name.

#### Pattern 3: Start After Sensors Are Available

A service that processes sensor data should not start until the sensor daemons have registered their D-Bus objects:

```ini
[Unit]
Description=Thermal Policy Engine
After=phosphor-hwmon-readall.service
After=xyz.openbmc_project.EntityManager.service
Wants=phosphor-hwmon-readall.service
```

#### Pattern 4: Hook Into a Power-On Target

To run a custom script when the host powers on, use `WantedBy=` in the `[Install]` section:

```ini
[Unit]
Description=Platform-specific power on hook
After=obmc-chassis-poweron@0.target
Before=obmc-host-startmin@0.target

[Service]
Type=oneshot
ExecStart=/usr/bin/my-platform-power-on.sh
RemainAfterExit=yes

[Install]
WantedBy=obmc-host-start@0.target
```

#### Pattern 5: Service That Must Finish Before Another Starts

When a configuration service must complete before the main daemon starts:

```ini
# config-loader.service
[Unit]
Description=Load sensor configuration
Before=phosphor-pid-control.service

[Service]
Type=oneshot
ExecStart=/usr/bin/load-sensor-config.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### Dependency vs Ordering Summary

| Combination | Meaning |
|-------------|---------|
| `Wants=B` + `After=B` | Start B, then start A (most common) |
| `Requires=B` + `After=B` | Start B, then start A (hard dependency) |
| `After=B` (alone) | Wait for B if B is active (passive wait) |
| `Wants=B` (alone) | Start B in parallel (rarely correct) |
| `WantedBy=T.target` | T.target pulls this service in via Wants= |

---

## Boot Time Debugging

When the BMC boots slowly or a service fails to start, systemd provides powerful diagnostic tools. All of these commands work on the BMC over SSH (or via QEMU serial console).

### Profiling Boot Time with systemd-analyze

#### Overall Boot Time

```bash
# Show total boot time breakdown
systemd-analyze

# Example output:
# Startup finished in 1.234s (kernel) + 12.345s (userspace) = 13.579s
# graphical.target reached after 12.000s in userspace
```

#### Blame: Which Services Are Slowest

```bash
# List services sorted by startup time (slowest first)
systemd-analyze blame

# Example output:
# 5.123s phosphor-image-signing.service
# 3.456s obmc-flash-bmc-init.service
# 2.789s phosphor-mapper.service
# 1.234s phosphor-hwmon@org-openbmc-sensors.service
# 0.987s bmcweb.service
# 0.654s phosphor-certificate-manager@authority.service
# ...
```

{: .tip }
On a typical QEMU environment, boot takes 15-30 seconds. On real hardware with flash storage, expect 30-90 seconds. Anything significantly above that indicates a problem worth investigating.

#### Critical Chain: The Longest Dependency Path

```bash
# Show the critical path to default.target
systemd-analyze critical-chain

# Show the critical path to a specific target
systemd-analyze critical-chain obmc-standby.target

# Example output:
# obmc-standby.target @12.345s
# └─bmcweb.service @8.123s +2.456s
#   └─phosphor-certificate-manager@authority.service @6.789s +1.234s
#     └─phosphor-mapper.service @3.456s +3.333s
#       └─dbus.service @1.234s +0.567s
#         └─basic.target @1.200s
#           └─sockets.target @1.199s
#             └─dbus.socket @0.987s
```

The `@` values show when each unit started, and the `+` values show how long each unit took. The critical chain reveals which service is the actual bottleneck, not just which service is slow.

{: .note }
`systemd-analyze blame` shows raw duration. `systemd-analyze critical-chain` shows the actual bottleneck path. A service that takes 5 seconds is not a problem if it starts in parallel with a 10-second service on the critical path. Focus on the critical chain.

### Debugging Service Failures with journalctl

#### View Logs for a Specific Service

```bash
# Follow live logs for a service
journalctl -u phosphor-state-manager.service -f

# View recent logs (last 50 lines)
journalctl -u phosphor-state-manager.service -n 50

# View logs from this boot only
journalctl -u phosphor-state-manager.service -b

# View logs with full output (no truncation)
journalctl -u phosphor-state-manager.service -b --no-pager
```

You can also filter by priority (`-p err` for errors only) or view all boot errors across services with `journalctl -b -p err`.

### Tracing Dependency Chains with systemctl

When a service fails because of a dependency problem, trace the chain:

```bash
# Check service status and recent log output
systemctl status phosphor-pid-control.service

# List what a unit depends on
systemctl list-dependencies phosphor-pid-control.service

# List what depends on a unit (reverse)
systemctl list-dependencies --reverse dbus.service

# Show the full unit file with all overrides applied
systemctl cat phosphor-pid-control.service
```

---

## Multi-Host Template Units

OpenBMC supports platforms with multiple host CPUs. Each host is managed independently through systemd **template units**, which use the `@` syntax to create parameterized service instances.

### Template Unit Basics

A template unit has `@` in its filename before the suffix:

```
obmc-host-start@.target      ← template (no instance)
obmc-host-start@0.target     ← instance 0 (first host)
obmc-host-start@1.target     ← instance 1 (second host)
```

The portion after `@` and before the suffix is the **instance identifier**. In OpenBMC, the instance identifier is typically the host number (0, 1, 2, ...).

### The %i Specifier

Inside a template unit file, `%i` expands to the instance identifier at runtime:

```ini
# /lib/systemd/system/phosphor-host-state-manager@.service
[Unit]
Description=Phosphor Host State Manager for host %i
After=obmc-host-startmin@%i.target
BindsTo=obmc-host-startmin@%i.target

[Service]
ExecStart=/usr/bin/phosphor-host-state-manager --host %i

[Install]
WantedBy=obmc-host-startmin@%i.target
```

When systemd starts `phosphor-host-state-manager@0.service`, every `%i` becomes `0`. When it starts `phosphor-host-state-manager@1.service`, every `%i` becomes `1`.

### Common systemd Specifiers in OpenBMC

| Specifier | Expands To | Example |
|-----------|------------|---------|
| `%i` | Instance identifier | `0`, `1`, `2` |
| `%n` | Full unit name | `my-service@0.service` |
| `%p` | Unit prefix (before @) | `my-service` |

### OpenBMC Multi-Host Target Instances

Every power-management target in OpenBMC is a template. On a single-host platform, only `@0` instances exist. On a multi-host platform (for example, a 4-socket server), instances `@0` through `@3` activate independently:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Multi-Host Target Instances                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Single-Host Platform:                                                 │
│                                                                         │
│   obmc-chassis-poweron@0.target                                         │
│        └── obmc-host-startmin@0.target                                  │
│              └── obmc-host-start@0.target                               │
│                                                                         │
│   Multi-Host Platform (2 hosts):                                        │
│                                                                         │
│   obmc-chassis-poweron@0.target    obmc-chassis-poweron@1.target        │
│        │                                │                               │
│        ▼                                ▼                               │
│   obmc-host-startmin@0.target     obmc-host-startmin@1.target           │
│        │                                │                               │
│        ▼                                ▼                               │
│   obmc-host-start@0.target        obmc-host-start@1.target              │
│                                                                         │
│   Each host chain operates independently.                               │
│   Host 0 can be powered on while host 1 remains off.                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Creating a Multi-Host Aware Service

When you write a service that must run per-host, create a template unit:

```ini
# /lib/systemd/system/my-host-monitor@.service
[Unit]
Description=My Host Monitor for host %i
After=obmc-host-startmin@%i.target
BindsTo=obmc-host-startmin@%i.target

[Service]
Type=simple
ExecStart=/usr/bin/my-host-monitor --host %i
Restart=on-failure

[Install]
WantedBy=obmc-host-start@%i.target
```

Enable it for specific host instances:

```bash
# Enable for host 0
systemctl enable my-host-monitor@0.service

# Enable for host 1 (multi-host platform)
systemctl enable my-host-monitor@1.service

# Start manually for testing
systemctl start my-host-monitor@0.service

# Check status of a specific instance
systemctl status my-host-monitor@0.service
```

### The RemainAfterExit Pattern

Many OpenBMC power-sequencing services are `Type=oneshot` scripts that run once and must be considered "active" after they exit. Without `RemainAfterExit=yes`, systemd marks a oneshot service as `inactive (dead)` after the script finishes, which breaks dependency chains that use `BindsTo=` or `After=`.

```ini
# /lib/systemd/system/chassis-power-on@.service
[Unit]
Description=Chassis Power On Sequence for host %i
After=obmc-chassis-poweron@%i.target

[Service]
Type=oneshot
ExecStart=/usr/bin/power-on-sequence.sh %i
RemainAfterExit=yes

[Install]
WantedBy=obmc-host-startmin@%i.target
```

{: .note }
`RemainAfterExit=yes` tells systemd to treat the service as `active (exited)` after the ExecStart command completes successfully. This is critical for oneshot services that other units depend on. Without it, `After=chassis-power-on@0.service` would see the service as "dead" and behave unpredictably.

### Inspecting Template Instances

```bash
# List all instantiated units from a template
systemctl list-units 'phosphor-host-state-manager@*'

# Show the template unit file
systemctl cat phosphor-host-state-manager@.service

# Show a specific instance's resolved configuration
systemctl show phosphor-host-state-manager@0.service

# Check which instance specifier values are active
systemctl list-units --type=target 'obmc-host-start@*'
```

---

## Troubleshooting

### Issue: Service Starts Before Its Dependency Is Ready

**Symptom**: A service fails with "Connection refused" or "D-Bus name not found" errors during boot, but works when restarted manually.

**Cause**: The service has `Wants=` on its dependency but is missing `After=`. Both units start simultaneously, and the dependency loses the race.

**Solution**:
1. Add `After=` for the dependency:
   ```ini
   [Unit]
   Wants=phosphor-mapper.service
   After=phosphor-mapper.service
   ```
2. Reload and restart:
   ```bash
   systemctl daemon-reload
   systemctl restart my-service.service
   ```

### Issue: Service Is Not Started During Host Power-On

**Symptom**: Your service never starts when you run `obmcutil poweron`, even though it is enabled.

**Cause**: The `WantedBy=` in the `[Install]` section does not reference a power-on target, or the service was not properly enabled.

**Solution**:
1. Verify `[Install]` has `WantedBy=obmc-host-start@0.target`
2. Re-enable: `systemctl disable my-service && systemctl enable my-service`
3. Verify the symlink: `ls -la /etc/systemd/system/obmc-host-start@0.target.wants/`

### Issue: Oneshot Service Shows "inactive (dead)"

**Symptom**: A oneshot service runs successfully but shows `inactive (dead)`. Dependent services behave inconsistently.

**Cause**: Missing `RemainAfterExit=yes` in the unit file.

**Solution**: Add `RemainAfterExit=yes` to the `[Service]` section. The service then shows `active (exited)` instead of `inactive (dead)`.

### Issue: Boot Hangs at a Specific Target

**Symptom**: The BMC boot stalls and never reaches `obmc-standby.target`.

**Cause**: A service in the dependency chain has hung or timed out.

**Solution**:
```bash
# Identify the stuck service
systemctl list-jobs
systemctl list-units --state=activating

# Examine logs for the stuck service
journalctl -u stuck-service.service -b --no-pager

# Temporarily skip the stuck service
systemctl mask stuck-service.service
# After debugging, unmask: systemctl unmask stuck-service.service
```

{: .warning }
Circular dependencies cause unpredictable boot order. If you see `Found ordering cycle` in the journal, review your `After=`/`Before=` directives and remove one direction of the cycle.

---

## References

### Official Resources
- [OpenBMC systemd Design](https://github.com/openbmc/docs/blob/master/architecture/openbmc-systemd.md)
- [phosphor-state-manager](https://github.com/openbmc/phosphor-state-manager)
- [OpenBMC Target Definitions](https://github.com/openbmc/phosphor-state-manager/tree/master/target_files)
- [OpenBMC Documentation](https://github.com/openbmc/docs)

### Related Guides
- [State Management]({% link docs/02-architecture/03-state-manager-guide.md %})
- [D-Bus Fundamentals]({% link docs/02-architecture/02-dbus-guide.md %})

### External Documentation
- [systemd Unit Configuration](https://www.freedesktop.org/software/systemd/man/systemd.unit.html)
- [systemd Service Configuration](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd Template Units](https://www.freedesktop.org/software/systemd/man/systemd.unit.html#Description)
- [systemd-analyze Manual](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html)

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC master branch
Last updated: 2026-02-06
