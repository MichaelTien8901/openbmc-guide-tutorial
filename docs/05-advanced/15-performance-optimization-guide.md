---
layout: default
title: Performance Optimization
parent: Advanced Topics
nav_order: 15
difficulty: advanced
prerequisites:
  - environment-setup
  - systemd-boot-ordering-guide
last_modified_date: 2026-02-06
---

# Performance Optimization Guide
{: .no_toc }

Profile and optimize boot time, memory usage, and runtime performance on resource-constrained BMC hardware.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

BMC systems-on-chip (SoCs) operate under tight resource constraints. A typical AST2600 provides a dual-core ARM Cortex-A7 at 800 MHz with 512 MB--1 GB of DDR4 RAM and 32--128 MB of SPI NOR flash. Every megabyte of RAM and every second of boot time matters because the BMC must be operational before the host system can power on.

This guide walks you through profiling boot time, tracking runtime memory consumption, and applying concrete optimization strategies to keep your OpenBMC image within budget.

**Key concepts covered:**
- Hardware resource budgets and how to allocate them across services
- Boot time profiling with `systemd-analyze` and critical-chain analysis
- Runtime memory profiling with `/proc/smaps`, RSS tracking, and leak detection
- Optimization strategies: lazy initialization, D-Bus batching, Python-to-C++ migration
- Kernel configuration tuning to reduce image size and memory footprint

{: .warning }
Optimization work should be guided by measurements, not assumptions. Always profile before and after each change to verify the impact.

---

## BMC Resource Constraints

### Hardware Budgets by SoC Generation

| Resource | AST2500 (G5) | AST2600 (G6) | Notes |
|----------|---------------|---------------|-------|
| **CPU** | ARM1176 single-core 800 MHz | Cortex-A7 dual-core 800 MHz | G6 adds SMP |
| **RAM** | 256--512 MB DDR3 | 512 MB--1 GB DDR4 | Shared with video engine |
| **SPI Flash** | 32--64 MB | 32--128 MB | Holds kernel + rootfs + U-Boot |
| **Root FS** | ~20 MB (typical) | ~30 MB (typical) | Compressed squashfs or UBI |

### Typical Memory Budget

On a running AST2600 system with a standard OpenBMC image:

```
┌──────────────────────────────────────────────────────────┐
│              Typical RAM Usage (~512 MB system)          │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Kernel + modules + slab caches        ~60--80 MB        │
│  Core BMC services                     ~80--120 MB       │
│  ├── bmcweb (Redfish)                  ~15--25 MB RSS    │
│  ├── entity-manager                    ~8--15 MB RSS     │
│  ├── ipmid                             ~10--15 MB RSS    │
│  ├── phosphor-logging                  ~8--12 MB RSS     │
│  └── Other services (~20 daemons)      ~40--55 MB RSS    │
│  systemd + journald + tmpfs            ~25--50 MB        │
│  Free / available                      ~260--350 MB      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

{: .note }
These numbers are approximate and vary by image configuration, number of sensors, and host platform complexity. Always measure your specific build.

### Per-Service Memory Targets

| Service Category | Target RSS | Concern Threshold |
|-----------------|------------|-------------------|
| Small daemon (state-manager, led-manager) | < 10 MB | > 15 MB |
| Medium daemon (entity-manager, ipmid) | < 15 MB | > 25 MB |
| Large daemon (bmcweb, phosphor-logging) | < 25 MB | > 40 MB |
| Python services (if any) | < 20 MB | > 30 MB |

---

## Boot Time Profiling

A BMC that boots slowly delays host power-on and extends maintenance windows. Reaching the Redfish endpoint within 30--60 seconds of power application is a common target.

### systemd-analyze and Critical Chain

```bash
# Total boot time breakdown
systemd-analyze
# Startup finished in 3.512s (kernel) + 18.234s (userspace) = 21.746s

# Show the critical boot path (longest dependency chain)
systemd-analyze critical-chain
# multi-user.target @18.102s
# └─phosphor-bmc-state-ready.target @18.050s
#   └─mapper-wait@-xyz-openbmc_project-state-bmc.service @17.892s +145ms
#     └─xyz.openbmc_project.State.BMC.service @15.234s +2.651s
#       └─phosphor-mapper.service @12.891s +2.310s
#         └─dbus.service @3.456s +120ms
```

Each line shows the service, its activation timestamp (`@`), and how long it took to start (`+`).

### Blame Analysis

```bash
# Show services ordered by startup time
systemd-analyze blame
# 4.210s phosphor-read-eeprom@...service
# 3.891s entity-manager.service
# 2.651s xyz.openbmc_project.State.BMC.service
# 2.310s phosphor-mapper.service
# 1.892s bmcweb.service
```

{: .tip }
Focus on the top 5--10 services in the blame list. Optimizing a service that takes 100 ms has negligible impact compared to one that takes 4 seconds.

### SVG Boot Chart and Kernel Time

```bash
# Generate visual boot chart (copy to host for viewing)
systemd-analyze plot > /tmp/boot-chart.svg
scp -P 2222 root@localhost:/tmp/boot-chart.svg .

# Measure kernel boot time from dmesg timestamps
dmesg | grep "Run /sbin/init"
# [    3.456789] Run /sbin/init as init process
```

### Automating Boot Time Tracking

```bash
#!/bin/bash
# boot-metrics.sh - Run on the BMC after each boot
echo "=== Boot Metrics $(date) ==="
systemd-analyze
echo "--- Critical Chain ---"
systemd-analyze critical-chain --no-pager
echo "--- Top 15 Blame ---"
systemd-analyze blame --no-pager | head -15
echo "--- Memory ---"
free -m
```

---

## Runtime Memory Profiling

### Per-Process RSS Tracking

Resident Set Size (RSS) measures the actual physical memory a process occupies:

```bash
# List all processes sorted by RSS (descending)
ps aux --sort=-rss | head -20

# Track RSS of key OpenBMC services
for svc in bmcweb phosphor-log-manager entity-manager ipmid; do
    pid=$(pidof $svc 2>/dev/null)
    if [ -n "$pid" ]; then
        rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status)
        printf "%-30s PID=%-6s RSS=%s kB\n" "$svc" "$pid" "$rss"
    fi
done
```

### Detailed Memory Maps with smaps

The `/proc/<pid>/smaps_rollup` file distinguishes shared libraries from private heap:

```bash
pid=$(pidof bmcweb)
cat /proc/$pid/smaps_rollup
# Rss:               18432 kB
# Pss:               12288 kB    <-- Proportional share (accounts for sharing)
# Private_Dirty:      8704 kB    <-- Heap + private data (primary target)
# Shared_Clean:       8192 kB    <-- Shared library text
```

| Field | Meaning | Optimization Target |
|-------|---------|---------------------|
| `Rss` | Total physical memory | Reduce overall footprint |
| `Pss` | Proportional share | More accurate for shared libs |
| `Private_Dirty` | Heap + writable private data | Primary optimization target |
| `Shared_Clean` | Shared library code pages | Reduce by linking fewer libs |

### Tracking Memory Over Time

Monitor a service for memory growth that might indicate a leak:

```bash
#!/bin/bash
# mem-track.sh <process-name> <interval-seconds> <count>
PROC=$1; INTERVAL=${2:-10}; COUNT=${3:-60}
echo "timestamp,pid,rss_kb,vsz_kb"
for i in $(seq 1 $COUNT); do
    pid=$(pidof $PROC 2>/dev/null)
    if [ -n "$pid" ]; then
        rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status)
        vsz=$(awk '/VmSize/{print $2}' /proc/$pid/status)
        echo "$(date +%s),$pid,$rss,$vsz"
    fi
    sleep $INTERVAL
done
```

{: .warning }
A steadily increasing RSS over hours or days strongly suggests a memory leak. Occasional small increases are normal due to caching, but monotonic growth requires investigation.

### Detecting Memory Leaks

For leak detection without recompiling, use Valgrind:

```bash
systemctl stop bmcweb
valgrind --tool=memcheck --leak-check=full \
    --show-leak-kinds=definite,possible \
    --log-file=/tmp/valgrind-bmcweb.log \
    /usr/bin/bmcweb &

# Exercise the service, then stop and examine
kill %1
cat /tmp/valgrind-bmcweb.log | grep "definitely lost"
```

For compile-time leak detection, use AddressSanitizer. See the [Linux Debug Tools Guide]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}) for details.

---

## Optimization Strategies

### Strategy 1: Lazy Initialization

Many services load all data at startup. Lazy initialization defers work until first use.

**Before (eager):**
```cpp
SensorManager(sdbusplus::bus_t& bus) : bus_(bus) {
    loadAllSensorConfigs();        // 200ms
    initializeAllThresholds();     // 150ms
    registerAllDbusObjects();      // 300ms
}
```

**After (lazy):**
```cpp
SensorManager(sdbusplus::bus_t& bus) : bus_(bus) {
    registerMinimalDbusInterface();  // 50ms
}
void ensureInitialized(const std::string& sensorPath) {
    if (initialized_.count(sensorPath) == 0) {
        loadSensorConfig(sensorPath);
        initializeThreshold(sensorPath);
        initialized_.insert(sensorPath);
    }
}
```

**Impact**: Reduces service startup time. The trade-off is a small latency on first access to each resource.

### Strategy 2: D-Bus Communication Patterns

D-Bus round trips are expensive on BMC hardware. Each call involves serialization, context switches, and deserialization.

**Batch property reads:**
```cpp
// Bad: N individual GetObject calls
for (const auto& path : sensorPaths) {
    bus.call(bus.new_method_call("xyz.openbmc_project.ObjectMapper", ...));
}
// Better: Single GetSubTree call
auto subtree = mapper::getSubTree(bus, "/xyz/openbmc_project/sensors",
                                   interfaces, depth);
```

**Use PropertiesChanged signals instead of polling:**
```cpp
// Bad: Polling every second
while (running) { value = readPropertyFromDbus(path, "Value"); sleep(1); }

// Better: React to changes
sdbusplus::bus::match_t match(bus,
    sdbusplus::bus::match::rules::propertiesChanged(
        sensorPath, "xyz.openbmc_project.Sensor.Value"),
    [](sdbusplus::message_t& msg) { /* handle change */ });
```

### Strategy 3: Python-to-C++ Migration

Python services consume significantly more resources than equivalent C++ implementations:

| Metric | Python Service | C++ Equivalent | Improvement |
|--------|---------------|----------------|-------------|
| RSS at idle | 15--25 MB | 3--8 MB | 3--5x less RAM |
| Startup time | 1--3 s | 0.1--0.5 s | 3--10x faster |
| CPU per D-Bus call | ~2 ms | ~0.2 ms | ~10x faster |

{: .note }
Migration is a significant effort. Target services that run persistently and handle high-frequency events. One-time scripts are fine to leave in Python.

### Strategy 4: Image Size Reduction

```bitbake
# In local.conf or your distro configuration
IMAGE_FEATURES:remove = "debug-tweaks tools-debug tools-profile"
INHIBIT_PACKAGE_STRIP = "0"
DEBUG_BUILD = "0"
FULL_OPTIMIZATION = "-O2 -pipe"

# Disable optional features in large services
EXTRA_OEMESON:append:pn-bmcweb = " -Dredfish-dbus-log=disabled"
```

### Strategy 5: Reduce Service Count

Each daemon consumes baseline RSS for its runtime, D-Bus connection, and event loop. Remove services you do not need:

| Service | When to Remove | Savings |
|---------|---------------|---------|
| `phosphor-ipmi-host` | No IPMI over KCS/BT required | ~10--15 MB |
| `phosphor-ipmi-net` | No IPMI-over-LAN required | ~8--12 MB |
| `obmc-ikvm` | No remote KVM feature | ~5--10 MB |
| `phosphor-certificate-manager` | No TLS certificate management | ~5--8 MB |
| `phosphor-post-code-manager` | No POST code logging | ~4--6 MB |

```bitbake
# Remove IPMI if using Redfish only
IMAGE_INSTALL:remove = "phosphor-ipmi-host phosphor-ipmi-net ipmitool"
```

---

## Kernel Configuration Optimization

The default AST2600 defconfig includes many features useful for development but unnecessary in production.

### Disabling Debug Options

```kconfig
# production-strip-debug.cfg

# CONFIG_DEBUG_KERNEL is not set
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_FS is not set
# CONFIG_PROVE_LOCKING is not set
# CONFIG_DEBUG_LOCK_ALLOC is not set
# CONFIG_DEBUG_MUTEXES is not set
# CONFIG_KASAN is not set
# CONFIG_KMEMLEAK is not set
# CONFIG_SLUB_DEBUG is not set
```

### Disabling Tracing

```kconfig
# production-strip-tracing.cfg

# CONFIG_FTRACE is not set
# CONFIG_FUNCTION_TRACER is not set
# CONFIG_DYNAMIC_FTRACE is not set
# CONFIG_KPROBES is not set
# CONFIG_UPROBES is not set
# CONFIG_PROFILING is not set
# CONFIG_PERF_EVENTS is not set
```

### Removing Unused Drivers

```kconfig
# production-minimal-drivers.cfg

# CONFIG_NET_VENDOR_INTEL is not set
# CONFIG_NET_VENDOR_REALTEK is not set
# CONFIG_EXT4_FS is not set          # If using squashfs + tmpfs only
# CONFIG_BTRFS_FS is not set
# CONFIG_INPUT_MOUSEDEV is not set
# CONFIG_USB_STORAGE is not set
# CONFIG_SOUND is not set
```

{: .warning }
Be conservative when removing drivers. Test thoroughly on your actual hardware after each change. A missing driver for an on-board device will cause silent failures.

### Applying Kernel Config Fragments

```bitbake
# meta-vendor/recipes-kernel/linux/linux-aspeed_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += " \
    file://production-strip-debug.cfg \
    file://production-strip-tracing.cfg \
    file://production-minimal-drivers.cfg \
"
```

```bash
# Validate all options took effect
bitbake linux-aspeed -c kernel_configcheck -f
```

### Optimization Impact Summary

| Category | Options Disabled | Image Savings | RAM Savings |
|----------|-----------------|---------------|-------------|
| Debug infrastructure | `DEBUG_KERNEL`, `DEBUG_INFO`, `DEBUG_FS` | 2--5 MB | 10--30 MB |
| Tracing and profiling | `FTRACE`, `KPROBES`, `PERF_EVENTS` | 1--3 MB | 5--15 MB |
| Unused drivers | Platform-specific | 0.5--2 MB | 1--5 MB |
| Unused filesystems | Platform-specific | 0.2--1 MB | 0.5--2 MB |
| **Total potential** | | **4--11 MB** | **17--52 MB** |

---

## Optimization Workflow

Follow this systematic process to avoid wasted effort:

```
┌──────────────────────────────────────────────────────────┐
│                 Optimization Workflow                    │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1. MEASURE                                              │
│     systemd-analyze / free -m / df -h                    │
│                                                          │
│  2. IDENTIFY                                             │
│     critical-chain / blame / RSS ranking                 │
│                                                          │
│  3. OPTIMIZE                                             │
│     Lazy init, D-Bus batching, remove services,          │
│     kernel config stripping, Python -> C++ migration     │
│                                                          │
│  4. VERIFY                                               │
│     Re-measure, regression test, document impact         │
│                                                          │
│  5. REPEAT until targets are met                         │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

{: .tip }
Keep a log of your optimization results. Record the build commit, the change made, and before/after measurements. This prevents regressions and helps justify changes during code review.

---

## Troubleshooting

### Issue: Boot Time Regressed After Image Update

**Symptom**: `systemd-analyze` shows significantly longer boot time after updating packages.

**Cause**: A new or updated service on the critical boot path, or new `Before=`/`Wants=` dependencies.

**Solution**:
1. Compare `systemd-analyze blame` output before and after
2. Run `systemd-analyze critical-chain` to find the new bottleneck
3. Inspect dependencies: `systemctl show <service> -p After -p Wants -p Before`

### Issue: Memory Usage Grows Over Time

**Symptom**: `free -m` shows available memory steadily decreasing over days.

**Cause**: Memory leak in a userspace service, or unbounded caching.

**Solution**:
1. Identify the growing process: `ps aux --sort=-rss | head -10`
2. Track with the `mem-track.sh` script from the profiling section
3. Check log entry counts: `busctl tree xyz.openbmc_project.Logging | wc -l`
4. Run the suspect under Valgrind (see [Linux Debug Tools Guide]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}))

### Issue: Flash Image Exceeds Partition Size

**Symptom**: Build fails with "image too large" or BMC fails to boot after flashing.

**Cause**: Added packages or debug symbols pushed rootfs beyond the flash partition limit.

**Solution**:
1. Examine rootfs: `du -sh tmp/work/*/obmc-phosphor-image/*/rootfs/*/ | sort -rh | head -20`
2. Remove unnecessary packages from `IMAGE_INSTALL`
3. Ensure `DEBUG_BUILD = "0"` and symbols are stripped

### Issue: systemd-analyze Shows Inaccurate Times

**Symptom**: Reported boot times do not match wall-clock observations.

**Cause**: `systemd-analyze` measures from kernel handoff to init, not from power-on. It does not account for U-Boot or firmware initialization.

**Solution**: For total power-on-to-ready time, use serial log timestamps. Add kernel boot time (`dmesg` first timestamp to init) plus userspace time for the complete picture.

---

## Quick Reference

### Boot Time Commands

| Task | Command |
|------|---------|
| Total boot time | `systemd-analyze` |
| Critical boot path | `systemd-analyze critical-chain` |
| Services by start time | `systemd-analyze blame` |
| Visual boot chart | `systemd-analyze plot > /tmp/boot.svg` |
| Kernel boot time | `dmesg \| grep "Run /sbin/init"` |

### Memory Commands

| Task | Command |
|------|---------|
| System memory overview | `free -m` |
| Per-process RSS | `ps aux --sort=-rss \| head -20` |
| Detailed memory map | `cat /proc/<pid>/smaps_rollup` |
| Kernel slab usage | `cat /proc/slabinfo \| sort -k3 -rn \| head` |

### Image Size Commands

| Task | Command |
|------|---------|
| Flash partition usage | `df -h` (on running BMC) |
| Kernel image size | `ls -lh tmp/deploy/images/*/zImage*` |
| Package count | `opkg list-installed \| wc -l` (on running BMC) |

---

## References

- [systemd-analyze man page](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html) -- Boot time analysis tool
- [OpenBMC Development Environment](https://github.com/openbmc/docs/blob/master/development/dev-environment.md) -- Development environment reference
- [Yocto Image Size Optimization](https://docs.yoctoproject.org/dev-manual/build-quality.html) -- Build quality and size optimization
- [Linux Kernel Size Tuning](https://elinux.org/Kernel_Size_Tuning_Guide) -- Embedded Linux kernel tuning
- [sdbusplus Repository](https://github.com/openbmc/sdbusplus) -- C++ D-Bus bindings used in OpenBMC
- [Systemd Boot Ordering]({% link docs/02-architecture/05-systemd-boot-ordering-guide.md %}) -- Prerequisite guide on systemd dependencies
- [Linux Debug Tools]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}) -- Sanitizers and Valgrind for leak detection

---

{: .note }
**Tested on**: OpenBMC master with QEMU ast2600-evb. Memory figures measured on a representative AST2600 build. Actual values vary by image configuration and platform.
