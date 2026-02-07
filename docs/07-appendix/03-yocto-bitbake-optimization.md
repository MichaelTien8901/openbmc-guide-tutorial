---
layout: default
title: Yocto BitBake Build Optimization
parent: Appendix
nav_order: 3
difficulty: intermediate
prerequisites:
  - environment-setup
  - first-build
---

# Yocto BitBake Build Optimization

## Overview

A first-time OpenBMC build can take 1–3 hours depending on hardware, network speed, and configuration. Subsequent builds are faster thanks to caching, but poorly tuned settings can still waste significant time. This appendix covers practical optimizations — from hardware selection to BitBake tuning — that can dramatically reduce build times for both initial and incremental OpenBMC builds.

## Hardware Recommendations

Build performance is primarily bound by CPU, RAM, and disk I/O. Invest in these areas for the biggest gains.

### Minimum vs Recommended Specs

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 4 cores | 8–16 cores | More cores = more parallel tasks |
| **RAM** | 16 GB | 32–64 GB | BitBake + compiler processes consume memory quickly |
| **Storage** | 100 GB HDD | 250+ GB NVMe SSD | I/O is often the bottleneck |
| **Swap** | 8 GB | 16 GB | Safety net for memory-intensive recipes |

{: .warning }
Builds on spinning HDDs can be 3–5x slower than on NVMe SSDs. If your build is slow and you are on an HDD, upgrading storage is the single biggest improvement you can make.

### Storage Best Practices

- **Dedicated build disk** — put the build directory on its own disk to avoid contention with the OS
- **NVMe SSD** — preferred over SATA SSD for the build directory
- **ext4 filesystem** — use ext4 over ext2/ext3 for improved performance with extents
- **Disable journaling** (optional, for dedicated build disks only):
  ```bash
  sudo tune2fs -O ^has_journal /dev/sdX
  ```
- **Optimized mount options** — reduce unnecessary disk writes:
  ```
  noatime,barrier=0,commit=6000
  ```
- **tmpfs for /tmp** — mount /tmp as tmpfs to speed up temporary file operations:
  ```bash
  sudo mount -t tmpfs -o size=8G tmpfs /tmp
  ```

{: .note }
Using tmpfs for the entire TMPDIR provides limited additional benefit because GCC's `-pipe` flag already keeps intermediate files in memory. However, tmpfs for `/tmp` is still worthwhile.

## BitBake Parallel Build Settings

These variables control how many tasks and compilations run simultaneously.

### Key Variables

| Variable | Purpose | Default | Recommended |
|----------|---------|---------|-------------|
| `BB_NUMBER_THREADS` | Max simultaneous BitBake tasks | Number of CPU cores | `nproc` or `nproc - 1` |
| `PARALLEL_MAKE` | Parallel `make` jobs per recipe | `-j` + number of CPU cores | `-j $(nproc)` |
| `BB_NUMBER_PARSE_THREADS` | Threads for recipe parsing | Number of CPU cores | `nproc` |
| `PARALLEL_MAKEINST` | Parallel `make install` jobs | Same as `PARALLEL_MAKE` | Leave as default |

### Configuration in local.conf

```bash
# conf/local.conf

# Match to your CPU core count (example: 8-core system)
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
BB_NUMBER_PARSE_THREADS = "8"
```

Or use dynamic calculation:

```bash
# Automatically scale to available cores
BB_NUMBER_THREADS = "${@oe.utils.cpu_count()}"
PARALLEL_MAKE = "-j ${@oe.utils.cpu_count()}"
```

### Scaling Considerations

{: .note }
Research from Yocto Project benchmarks shows that small builds (minimal images) do not scale well beyond ~8 cores due to package inter-dependencies. Larger builds like full OpenBMC images benefit more from additional cores. Going beyond 16 threads on a single machine typically yields diminishing returns.

If your system is running out of memory during builds, **reduce** `BB_NUMBER_THREADS` rather than adding swap:

```bash
# Memory-constrained system (16 GB RAM)
BB_NUMBER_THREADS = "4"
PARALLEL_MAKE = "-j 4"
```

## Shared State Cache (sstate-cache)

The shared state cache is BitBake's most powerful optimization. It stores the output of individual build tasks and reuses them when inputs haven't changed.

### How It Works

```
Recipe Task (e.g., do_compile for phosphor-logging)
    │
    ├─ Hash inputs (source, config, dependencies)
    │
    ├─ Hash matches sstate? ──YES──> Skip task, use cached output
    │
    └─ Hash doesn't match? ──NO───> Build task, store result in sstate
```

### Shared sstate-cache Directory

By default, each build gets its own sstate-cache. Share it across builds to avoid redundant work:

```bash
# conf/local.conf — shared sstate directory
SSTATE_DIR = "/var/cache/yocto/sstate-cache"
```

A typical OpenBMC build generates 4–8 GB of sstate data. With a warm cache, rebuild times drop from hours to minutes.

### Remote sstate Mirrors

Pull pre-built artifacts from a shared server to skip building common packages:

```bash
# conf/local.conf — use a remote sstate mirror
SSTATE_MIRRORS ?= "\
    file://.* https://your-server.example.com/sstate/PATH;downloadfilename=PATH \
"
```

The Yocto Project provides a public sstate mirror:

```bash
SSTATE_MIRRORS ?= "\
    file://.* https://sstate.yoctoproject.org/all/PATH;downloadfilename=PATH \
"
```

{: .tip }
For team environments, set up an HTTP server hosting your sstate-cache directory. Every developer benefits from artifacts built by any team member or CI system.

### OpenBMC CI Seed Builds

OpenBMC's Jenkins CI runs a `build-seed` job that pre-populates sstate caches for ~19 supported machines (romulus, witherspoon, p10bmc, etc.). This is why CI builds for submitted patches are much faster than first-time local builds — they reuse the seeded cache.

## Download Directory (DL_DIR)

BitBake downloads source tarballs and git repositories to the `DL_DIR`. Sharing this across builds prevents redundant downloads.

### Shared Download Directory

```bash
# conf/local.conf
DL_DIR = "/var/cache/yocto/downloads"
```

### Generate Mirror Tarballs

Create tarballs from git fetches so they can be mirrored more easily:

```bash
BB_GENERATE_MIRROR_TARBALLS = "1"
```

### Pre-fetch All Sources

Download everything before building (useful for preparing offline builds):

```bash
bitbake obmc-phosphor-image --runonly=fetch
```

### Offline Builds

Verify that all sources are cached, then build without network access:

```bash
# Test that everything is cached
BB_NO_NETWORK = "1"
bitbake obmc-phosphor-image
```

### Source Mirrors

Point to an organizational mirror to avoid relying on upstream servers:

```bash
# conf/local.conf
SOURCE_MIRROR_URL ?= "file:///var/cache/yocto/downloads/"
INHERIT += "own-mirrors"
```

## Hash Equivalence

Hash equivalence is an advanced caching optimization that recognizes when two different task input hashes produce functionally identical output. This avoids unnecessary rebuilds when cosmetic changes (like timestamps or build paths) alter the input hash without changing the actual result.

### How It Works

```
Task A (hash: abc123) ─── produces ──> Output X
Task B (hash: def456) ─── produces ──> Output X  (same!)

Hash equivalence server records: abc123 ≡ def456
Next time hash def456 is seen, reuse cached Output X from abc123
```

### Configuration

```bash
# conf/local.conf

# Enable hash equivalence
BB_SIGNATURE_HANDLER = "OEEquivHash"

# Run a local hash equivalence server (auto-started by BitBake)
BB_HASHSERVE = "auto"

# Optionally connect to the Yocto Project upstream server
BB_HASHSERVE_UPSTREAM = "wss://hashserv.yoctoproject.org/ws"
```

### Running Your Own Server

For teams, run a shared hash equivalence server:

```bash
# Start a persistent hash equivalence server
bitbake-hashserv --bind 0.0.0.0:8687 --database /var/cache/yocto/hashserv.db

# In local.conf on developer machines:
BB_HASHSERVE = "your-server.example.com:8687"
BB_SIGNATURE_HANDLER = "OEEquivHash"
```

{: .note }
The hash equivalence server must be maintained alongside the shared state cache. If you share sstate but not hash equivalence data (or vice versa), the benefit is reduced.

### Persistent Cache Directory

Store hash equivalence databases across builds:

```bash
PERSISTENT_DIR = "/var/cache/yocto/persistent"
```

## rm_work: Reducing Disk Usage

The `rm_work` class removes a recipe's work directory after it finishes building, freeing disk space as the build progresses.

### Configuration

```bash
# conf/local.conf
INHERIT += "rm_work"

# Exclude specific recipes you want to debug or inspect
RM_WORK_EXCLUDE += "phosphor-logging bmcweb"
```

### Benefits and Trade-offs

| Benefit | Trade-off |
|---------|-----------|
| Reduces peak disk usage by 50–70% | Cannot inspect build artifacts after the fact |
| Faster cleanup of TMPDIR | Rebuilding an excluded recipe requires re-fetching/building |
| Slightly faster builds (less data in cache to index) | Harder to debug build failures |

{: .tip }
Use `rm_work` on CI servers and space-constrained systems. Exclude recipes you are actively developing so you can inspect their build output.

## Reducing Build Scope

### Strip Unnecessary DISTRO_FEATURES

Remove features you don't need to avoid building unnecessary packages:

```bash
# conf/local.conf
DISTRO_FEATURES:remove = "x11 wayland bluetooth wifi nfc 3g"
```

### Disable Debug Packages

Skip generating `-dbg` packages to save packaging time:

```bash
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
```

### Packaging Backend

IPK is the fastest packaging backend (and the OpenBMC default). If your configuration doesn't specify one, ensure it's set:

```bash
PACKAGE_CLASSES = "package_ipk"
```

## Distributed Compilation with icecc

[Icecream (icecc)](https://github.com/icecc/icecream) distributes compilation jobs across a network of machines, turning multiple build hosts into a single compilation cluster.

### Setup

1. Install icecc on all machines in the cluster:
   ```bash
   sudo apt install icecc    # Debian/Ubuntu
   sudo dnf install icecream  # Fedora
   ```

2. Start the scheduler on one machine:
   ```bash
   sudo systemctl start icecc-scheduler
   ```

3. Start the daemon on all machines (including the scheduler host):
   ```bash
   sudo systemctl start iceccd
   ```

4. Configure BitBake:
   ```bash
   # conf/local.conf
   INHERIT += "icecc"
   ICECC_PARALLEL_MAKE = "-j 32"   # Total jobs across cluster
   PARALLEL_MAKE = "-j 8"           # Fallback for non-icecc recipes
   ```

### Considerations

- icecc changes task hashes — sstate built with icecc is **not** reusable without icecc
- To toggle icecc without invalidating sstate, always inherit the class and use `ICECC_DISABLED`:
  ```bash
  INHERIT += "icecc"
  ICECC_DISABLED = "1"  # Set to "0" to enable
  ```
- Blacklist recipes that fail with distributed compilation:
  ```bash
  ICECC_USER_PACKAGE_BL = "some-problematic-recipe"
  ```

## Uninative: Avoiding Host Tool Rebuilds

Uninative provides a pre-built native C library that prevents unnecessary rebuilds when host system tools are updated.

Without uninative, updating your host's glibc (e.g., via `apt upgrade`) can invalidate the entire sstate cache, forcing a full rebuild. Uninative locks the native toolchain to a specific version.

### Configuration

Uninative is typically enabled by default in modern Yocto/OpenBMC setups:

```bash
# Usually already set in your distro config
INHERIT += "uninative"
```

{: .warning }
If you see unexpected full rebuilds after a host OS update, verify that uninative is enabled. This is one of the most common causes of unnecessary rebuild cycles.

## Build Monitoring and Profiling

### Enable buildstats

Track per-recipe build times to identify bottlenecks:

```bash
# conf/local.conf
INHERIT += "buildstats"
```

Build statistics are written to `tmp/buildstats/` and can be analyzed to find the slowest recipes:

```bash
# Find the 10 slowest recipes in the last build
cd tmp/buildstats/
find . -name "do_compile" -exec sh -c \
  'echo "$(cat "$1" | grep "Elapsed" | awk "{print \$3}") $1"' _ {} \; \
  | sort -rn | head -10
```

### BitBake Build Time Summary

BitBake prints a task execution summary at the end of each build. Pay attention to:

```
NOTE: Tasks Summary: Attempted 4532 tasks of which 4201 didn't need to be rerun and all succeeded.
```

If the number of "didn't need to be rerun" is low relative to total tasks, your sstate cache is not being utilized effectively.

## Quick Reference: Optimized local.conf

Here is a consolidated example of optimization settings for a typical 8-core, 32 GB RAM development machine:

```bash
# conf/local.conf — OpenBMC Build Optimization

# ── Parallelism ──
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"

# ── Shared Caches ──
DL_DIR = "/var/cache/yocto/downloads"
SSTATE_DIR = "/var/cache/yocto/sstate-cache"

# ── Hash Equivalence ──
BB_SIGNATURE_HANDLER = "OEEquivHash"
BB_HASHSERVE = "auto"

# ── Disk Space ──
INHERIT += "rm_work"
RM_WORK_EXCLUDE += "phosphor-logging bmcweb"

# ── Performance Monitoring ──
INHERIT += "buildstats"

# ── Packaging ──
PACKAGE_CLASSES = "package_ipk"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
```

## Optimization Impact Summary

Approximate build time improvements (cumulative, on a first-time full OpenBMC build):

| Optimization | Typical Impact | Effort |
|--------------|---------------|--------|
| NVMe SSD instead of HDD | 3–5x faster I/O | Hardware purchase |
| Shared sstate-cache (warm) | 60–90% time reduction | One-time config |
| Shared DL_DIR | 10–20 min saved on first build | One-time config |
| Parallel build tuning | 10–30% improvement | One-time config |
| Hash equivalence | 5–15% fewer rebuilds | One-time config |
| rm_work | 50–70% less disk usage | One-time config |
| icecc cluster (4 machines) | 2–4x faster compilation | Infrastructure setup |
| Remote sstate mirror | Near-instant rebuilds for unchanged recipes | Server setup |

## References

- [Yocto Project: Speeding Up a Build](https://docs.yoctoproject.org/dev/dev-manual/speeding-up-build.html) — official Yocto optimization guide
- [Yocto Project: Hash Equivalence Server Setup](https://docs.yoctoproject.org/next/dev-manual/hashequivserver.html) — hash equivalence configuration
- [Yocto Project: Variables Glossary](https://docs.yoctoproject.org/ref-manual/variables.html) — complete reference for all BitBake variables
- [Yocto Project Wiki: Build Performance](https://wiki.yoctoproject.org/wiki/Build_Performance) — community benchmarks and filesystem tips
- [Improving Yocto Build Time (The Good Penguin)](https://www.thegoodpenguin.co.uk/blog/improving-yocto-build-time/) — practical optimization walkthrough
- [OpenBMC Yocto Development Docs](https://github.com/openbmc/docs/blob/master/yocto-development.md) — OpenBMC-specific Yocto usage
- [OpenBMC Cheatsheet](https://github.com/openbmc/docs/blob/master/cheatsheet.md) — quick reference for OpenBMC builds
- [Icecream Distributed Compiler](https://github.com/icecc/icecream) — icecc project for distributed builds
