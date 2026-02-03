---
layout: default
title: Development Workflow
parent: Getting Started
nav_order: 4
difficulty: intermediate
prerequisites:
  - first-build
---

# Development Workflow
{: .no_toc }

Iterate quickly on OpenBMC code using devtool, recipe customization, and build optimization.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

{: .note }
**Yocto Compatibility**: This guide is tested with OpenBMC on Yocto Kirkstone and Scarthgap releases. Command syntax may vary slightly on older releases.

## Overview

After completing your first build, you'll want to modify OpenBMC code and test changes quickly. A full `bitbake` rebuild can take 30+ minutes, but with the right workflow you can iterate in under 5 minutes.

This guide covers three essential techniques:

| Technique | Use Case | Time Savings |
|-----------|----------|--------------|
| **devtool** | Modify and test a single recipe | 30 min → 2 min |
| **bbappend** | Sustainable recipe customization | Avoid upstream conflicts |
| **Build optimization** | Faster overall builds | 2-4x speedup |

---

## devtool Workflow

`devtool` is your primary tool for rapid iteration. It extracts recipe source code to a workspace where you can edit, build, and test without full rebuilds.

### When to Use devtool vs bitbake

| Scenario | Use |
|----------|-----|
| Modifying existing recipe source code | `devtool` |
| Adding debug output to a service | `devtool` |
| Building entire image from scratch | `bitbake` |
| Creating permanent recipe customization | `bbappend` |

### devtool modify - Extract Source Code

Extract a recipe's source code to your workspace for editing:

```bash
# Initialize build environment first
cd openbmc
. setup ast2600-evb

# Extract phosphor-logging source to workspace
devtool modify phosphor-logging

# Source is now at:
# workspace/sources/phosphor-logging/
```

The workspace directory structure:

```
workspace/
├── sources/
│   └── phosphor-logging/    # Editable source code
└── appends/
    └── phosphor-logging.bbappend  # Auto-generated append
```

{: .tip }
The `devtool modify` command automatically creates a bbappend that redirects the build to use your workspace source instead of fetching from upstream.

### devtool build - Incremental Build

After modifying source code, rebuild just that recipe:

```bash
# Build only phosphor-logging (fast!)
devtool build phosphor-logging

# Build output goes to the normal deploy directory
# tmp/work/*/phosphor-logging/*/image/
```

This builds only the modified recipe and its direct dependencies—typically completing in 1-2 minutes instead of 30+.

### devtool reset - Discard Changes

When you want to abandon workspace changes and restore the original recipe:

```bash
# Discard workspace changes for phosphor-logging
devtool reset phosphor-logging

# Verify it's removed
devtool status
```

{: .warning }
`devtool reset` permanently deletes your workspace source directory. Commit any changes you want to keep before running this command.

### devtool finish - Create Patches

When you're satisfied with your changes and want to create a permanent patch:

```bash
# Commit your changes in the workspace
cd workspace/sources/phosphor-logging
git add -A
git commit -m "Add debug logging for sensor updates"

# Create bbappend with patches in your layer
devtool finish phosphor-logging meta-my-layer

# This creates:
# meta-my-layer/recipes-phosphor/logging/phosphor-logging_%.bbappend
# meta-my-layer/recipes-phosphor/logging/phosphor-logging/0001-Add-debug-logging.patch
```

### Complete Walkthrough: Modify phosphor-logging

Let's walk through a complete example of adding debug output to phosphor-logging:

**Step 1: Extract source**

```bash
cd openbmc
. setup ast2600-evb
devtool modify phosphor-logging
```

**Step 2: Make changes**

```bash
cd workspace/sources/phosphor-logging

# Edit a source file (example: add debug log)
# Find the main logging implementation
vi lib/lg2_logger.cpp
```

Add a debug line to verify your changes are working:

```cpp
// Near the top of a frequently-called function
std::cerr << "DEBUG: phosphor-logging modified successfully\n";
```

**Step 3: Build**

```bash
devtool build phosphor-logging
```

**Step 4: Deploy and test on QEMU**

```bash
# Build image with your changes
bitbake obmc-phosphor-image

# Start QEMU (requires QEMU 6.0+)
qemu-system-arm -m 1G -M ast2600-evb -nographic \
    -drive file=tmp/deploy/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443

# In another terminal, check logs
ssh -p 2222 root@localhost
journalctl -f | grep DEBUG
```

**Step 5: Finalize or reset**

```bash
# If satisfied, create permanent patch:
cd workspace/sources/phosphor-logging
git add -A && git commit -m "Add debug logging"
devtool finish phosphor-logging meta-my-layer

# Or discard changes:
devtool reset phosphor-logging
```

---

## Recipe Customization with bbappend

For permanent, maintainable recipe customizations, use bbappend files instead of modifying upstream recipes directly.

### bbappend Naming Conventions

bbappend files must match the recipe name exactly:

```
Recipe:  meta-phosphor/recipes-phosphor/logging/phosphor-logging_git.bb
Append:  meta-my-layer/recipes-phosphor/logging/phosphor-logging_%.bbappend
```

| Pattern | Matches |
|---------|---------|
| `recipe_git.bbappend` | Only `recipe_git.bb` |
| `recipe_%.bbappend` | Any version of recipe (recommended) |
| `recipe_1.0.bbappend` | Only version 1.0 |

### bbappend Directory Structure

Your bbappend should mirror the original recipe's path:

```
meta-your-layer/
└── recipes-phosphor/
    └── logging/
        ├── phosphor-logging_%.bbappend
        └── phosphor-logging/
            ├── 0001-your-patch.patch
            └── your-config-file.conf
```

### Common bbappend Use Cases

**Adding patches:**

```bitbake
# phosphor-logging_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://0001-Add-custom-logging.patch"
```

**Modifying SRCREV (pin to specific commit):**

```bitbake
# phosphor-logging_%.bbappend
SRCREV = "abc123def456..."
```

**Adding dependencies:**

```bitbake
# phosphor-logging_%.bbappend
DEPENDS += "additional-library"
RDEPENDS:${PN} += "runtime-dependency"
```

**Modifying configuration options:**

```bitbake
# phosphor-logging_%.bbappend
EXTRA_OEMESON += "-Doption=value"
```

**Adding extra files to the image:**

```bitbake
# phosphor-logging_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://custom.conf"

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/custom.conf ${D}${sysconfdir}/
}
```

### Layer Priority

When multiple layers have bbappend files for the same recipe, priority determines which applies last (highest priority wins for conflicts):

```bash
# Check layer priorities
bitbake-layers show-layers

# Example output:
# layer                 path                                      priority
# meta                  /path/to/poky/meta                        5
# meta-phosphor         /path/to/openbmc/meta-phosphor            7
# meta-my-layer          /path/to/openbmc/meta-my-layer             10
```

Higher priority layers' appends are processed last. Set priority in your layer's `conf/layer.conf`:

```bitbake
BBFILE_PRIORITY_meta-yourlayer = "10"
```

### When to Upstream vs Maintain Local Patches

| Situation | Recommendation |
|-----------|----------------|
| Bug fix that benefits everyone | Upstream to OpenBMC |
| Platform-specific hardware support | Keep in machine layer |
| Temporary debug code | Use devtool, don't commit |
| Feature that may be rejected upstream | Start with bbappend, propose upstream |

{: .tip }
Maintaining local patches creates technical debt. Whenever possible, contribute fixes upstream and remove your bbappend once the fix is merged.

---

## Build Optimization

Speed up your builds with caching and parallelization.

### Enable ccache

ccache caches compiled objects, dramatically speeding up C/C++ recompilation:

```bash
# Add to conf/local.conf
INHERIT += "ccache"
CCACHE_DIR = "${TOPDIR}/ccache"
```

Expected improvement: **2-3x faster** C/C++ compilation on rebuilds.

Verify ccache is working:

```bash
# After a build, check cache statistics
ccache -s

# Look for "cache hit" entries
```

### Configure sstate Cache

sstate (shared state) cache stores built recipe outputs, skipping rebuilds for unchanged recipes:

```bash
# Default location (already configured)
SSTATE_DIR = "${TOPDIR}/sstate-cache"

# Share sstate between multiple build directories
SSTATE_DIR = "/opt/openbmc-sstate"

# Use a read-only shared sstate mirror
SSTATE_MIRRORS = "file://.* file:///shared/sstate/PATH"
```

{: .note }
sstate cache can grow large (50GB+). Periodically clean old entries with `sstate-cache-management.sh`.

### Parallel Build Configuration

Maximize CPU utilization during builds:

```bash
# Add to conf/local.conf

# Number of parallel BitBake tasks (recipe-level parallelism)
# Recommended: Number of CPU cores
BB_NUMBER_THREADS = "8"

# Number of parallel make jobs (within each recipe)
# Recommended: Number of CPU cores
PARALLEL_MAKE = "-j 8"
```

**Formula for your system:**

```bash
# Check your CPU cores
nproc

# Set both values to this number (or slightly less to leave headroom)
# For 8-core system:
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"

# For memory-constrained systems (< 32GB RAM), reduce values:
BB_NUMBER_THREADS = "4"
PARALLEL_MAKE = "-j 4"
```

### Verify Optimization is Working

```bash
# Check ccache hit rate
ccache -s | grep "cache hit"

# Check sstate usage during build (look for "sstate" messages)
bitbake phosphor-logging -v 2>&1 | grep -i sstate

# Monitor parallel jobs
htop  # Watch CPU usage during build
```

---

## Troubleshooting

### devtool Workspace Conflicts

**Error:** "Recipe is already in your workspace"

```bash
# Check what's in your workspace
devtool status

# Reset the conflicting recipe
devtool reset phosphor-logging

# Try again
devtool modify phosphor-logging
```

**Error:** "Workspace directory already exists"

```bash
# Remove stale workspace manually
rm -rf workspace/sources/phosphor-logging
rm -f workspace/appends/phosphor-logging.bbappend

# Try again
devtool modify phosphor-logging
```

### sstate Cache Misses

**Symptom:** Full rebuilds despite having sstate cache

Common causes:

1. **SRCREV changed** - Recipe source updated upstream
   ```bash
   # Check current vs cached SRCREV
   bitbake -e phosphor-logging | grep ^SRCREV=
   ```

2. **Configuration drift** - local.conf changes affect recipe hash
   ```bash
   # Compare build signatures
   bitbake-diffsigs tmp/stamps/*/phosphor-logging/*/do_compile.*
   ```

3. **Compiler or host tool version changed**
   ```bash
   # Check for host contamination warnings
   bitbake phosphor-logging 2>&1 | grep -i contamination
   ```

### Workspace Inspection Commands

```bash
# List all recipes in workspace
devtool status

# Show details for a specific recipe
devtool status phosphor-logging

# Find workspace source directory
ls -la workspace/sources/

# Check git status of workspace source
cd workspace/sources/phosphor-logging
git status
git log --oneline -5
```

---

## Next Steps

- [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) - Understand how services communicate
- [Sensor Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) - Modify sensor configurations
- [Machine Layer]({% link docs/06-porting/02-machine-layer.md %}) - Create custom platform layers

---

{: .note }
**Tested on**: Ubuntu 22.04, OpenBMC master branch (Kirkstone/Scarthgap)
