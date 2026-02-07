---
layout: default
title: Devtool Workflow Guide
parent: Getting Started
nav_order: 6
difficulty: beginner
prerequisites:
  - first-build
  - development-workflow
last_modified_date: 2026-02-06
---

# Devtool Workflow Guide
{: .no_toc }

Master the modify-build-deploy-debug cycle for rapid OpenBMC development using devtool and QEMU.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

When you develop OpenBMC services, you need a fast feedback loop: change code, build it, push it to a running system, and verify the result. A full `bitbake obmc-phosphor-image` rebuild takes 30 minutes or more, which makes iterative development painfully slow.

This guide teaches you the **devtool modify-build-deploy** cycle that reduces your iteration time to under 5 minutes. You will learn how to extract a recipe's source code, make changes, build only the modified recipe, deploy the updated binary to a running QEMU instance, and debug it with gdbserver -- all without rebuilding the entire image.

By the end of this guide, you will have hands-on experience modifying `phosphor-state-manager`, deploying your changes to QEMU, and verifying them with D-Bus commands.

**Key concepts covered:**
- Extracting recipe source with `devtool modify`
- Incremental builds with `devtool build`
- Deploying binaries via SCP and `devtool deploy-target`
- Remote debugging with gdbserver and GDB
- Complete worked example with phosphor-state-manager

---

## Prerequisites

Before starting this guide, make sure you have:

- [ ] A working OpenBMC build environment ([Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}))
- [ ] A completed first build of `obmc-phosphor-image` ([First Build]({% link docs/01-getting-started/03-first-build.md %}))
- [ ] QEMU running with the ast2600-evb image ([Building QEMU]({% link docs/01-getting-started/05-qemu-build.md %}))
- [ ] Familiarity with devtool basics ([Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}))

{: .note }
This guide assumes you can SSH into your QEMU instance at `localhost:2222` with credentials `root` / `0penBmc`. Start QEMU before proceeding.

---

## Step 1: Extract Source with devtool modify

The `devtool modify` command extracts a recipe's source code into a local workspace directory where you can edit it freely. The build system automatically redirects future builds of that recipe to use your local copy instead of fetching from upstream.

### Initialize Your Build Environment

```bash
cd openbmc
. setup ast2600-evb
```

### Extract the Recipe Source

```bash
# Extract phosphor-state-manager source to your workspace
devtool modify phosphor-state-manager
```

This command performs three actions:

1. Clones the recipe's source repository into `workspace/sources/phosphor-state-manager/`
2. Creates a bbappend file at `workspace/appends/phosphor-state-manager.bbappend`
3. Configures the build system to use your local source for all future builds

### Verify the Extraction

```bash
# Check that the recipe is now in your workspace
devtool status

# Expected output:
# phosphor-state-manager  /path/to/openbmc/build/ast2600-evb/workspace/sources/phosphor-state-manager

# Browse the source tree
ls workspace/sources/phosphor-state-manager/
```

You see the full source tree including `meson.build`, source files under `host_state_manager.cpp`, `chassis_state_manager.cpp`, and other service implementations.

### Understand the Workspace Layout

```
workspace/
├── sources/
│   └── phosphor-state-manager/    # Your editable source code (git repo)
│       ├── meson.build
│       ├── host_state_manager.cpp
│       ├── chassis_state_manager.cpp
│       ├── bmc_state_manager.cpp
│       └── ...
└── appends/
    └── phosphor-state-manager.bbappend  # Auto-generated build redirect
```

{: .tip }
The workspace source directory is a full git repository. You can use `git diff`, `git stash`, and `git commit` to manage your changes just like any other git project.

---

## Step 2: Build Incrementally with devtool build

After modifying source code, you use `devtool build` to compile only the changed recipe. This skips fetching, patching, and building all other recipes, reducing build time from 30+ minutes to 1-3 minutes.

### Make a Code Change

Open a source file and add a visible marker so you can verify your change on the target:

```bash
cd workspace/sources/phosphor-state-manager
```

Edit `bmc_state_manager.cpp` and add a log message near the top of the constructor or an initialization function:

```cpp
// Add this line after the existing includes
#include <phosphor-logging/lg2.hpp>

// Inside the BMCStateManager constructor or relevant init path, add:
lg2::info("DEVTOOL-TEST: phosphor-state-manager modified successfully");
```

{: .note }
The exact location depends on the current upstream code. Look for the `BMCStateManager` constructor in `bmc_state_manager.cpp` and add the log line at the beginning of the function body.

### Build the Modified Recipe

```bash
# Return to the build directory
cd /path/to/openbmc/build/ast2600-evb

# Build only phosphor-state-manager
devtool build phosphor-state-manager
```

The build takes 1-3 minutes. Watch for any compilation errors in the output. If you see errors, fix them in the source file and run `devtool build` again.

### Locate the Build Output

After a successful build, find the compiled binaries:

```bash
# Find the built binary
find tmp/work/*/phosphor-state-manager/*/image -name "phosphor-bmc-state-manager" -type f

# Typical location:
# tmp/work/armv7ahf-vfpv4d16-openbmc-linux-gnueabi/phosphor-state-manager/1.0+git*/image/usr/bin/phosphor-bmc-state-manager
```

{: .tip }
You can also find all installed files from the recipe by listing the `image/` directory. This shows you exactly what the recipe installs on the target system.

### Rebuild After Additional Changes

The devtool build cycle is fully incremental. Each time you edit source files and run `devtool build`, only the changed files are recompiled:

```bash
# Edit source...
vi workspace/sources/phosphor-state-manager/bmc_state_manager.cpp

# Rebuild (only recompiles changed files)
devtool build phosphor-state-manager
```

---

## Step 3: Deploy to Target

You have two options for getting your modified binary onto the running QEMU instance: manual SCP or `devtool deploy-target`. Each has advantages depending on your workflow.

### Option A: Deploy via SCP (Manual)

SCP gives you precise control over which files you copy and where they go. This is useful when you want to replace a single binary without touching anything else.

**Find the binary on the target:**

```bash
# SSH into QEMU to find where the binary lives
ssh -p 2222 root@localhost "which phosphor-bmc-state-manager"
# Output: /usr/bin/phosphor-bmc-state-manager
```

**Copy the built binary to the target:**

```bash
# From your build host, SCP the new binary
scp -P 2222 \
    tmp/work/armv7ahf-vfpv4d16-openbmc-linux-gnueabi/phosphor-state-manager/1.0+git*/image/usr/bin/phosphor-bmc-state-manager \
    root@localhost:/usr/bin/phosphor-bmc-state-manager
```

{: .warning }
The OpenBMC root filesystem is a read-only overlay by default on some configurations. If SCP fails with a "read-only file system" error, remount the filesystem read-write first: `ssh -p 2222 root@localhost "mount -o remount,rw /"`.

**Restart the service to load the new binary:**

```bash
ssh -p 2222 root@localhost "systemctl restart xyz.openbmc_project.State.BMC"
```

**Verify the service is running with your changes:**

```bash
ssh -p 2222 root@localhost "systemctl status xyz.openbmc_project.State.BMC"
ssh -p 2222 root@localhost "journalctl -u xyz.openbmc_project.State.BMC --no-pager -n 20"
```

Look for your `DEVTOOL-TEST` log message in the journal output.

### Option B: Deploy via devtool deploy-target (Automated)

`devtool deploy-target` automates the file copy process. It deploys all files that the recipe installs (binaries, configuration files, libraries) to the correct locations on the target.

**Set up SSH key access (one-time setup):**

```bash
# Generate an SSH key if you do not have one
ssh-keygen -t ed25519 -f ~/.ssh/id_openbmc -N ""

# Copy the key to the QEMU target
ssh-copy-id -p 2222 -i ~/.ssh/id_openbmc root@localhost
```

**Deploy all recipe files to the target:**

```bash
devtool deploy-target phosphor-state-manager root@localhost:2222
```

This command:
1. Identifies all files the recipe installs (binaries, configs, systemd units)
2. Copies them to the correct paths on the target via SSH
3. Preserves file permissions and ownership

{: .note }
`devtool deploy-target` uses SSH internally, so you need password-less SSH access (key-based) or you will be prompted for the password multiple times.

**Restart the service after deployment:**

```bash
ssh -p 2222 root@localhost "systemctl restart xyz.openbmc_project.State.BMC"
```

**Verify the deployment:**

```bash
ssh -p 2222 root@localhost "journalctl -u xyz.openbmc_project.State.BMC --no-pager -n 20"
```

### Undeploy from Target

If you need to revert the target to its original state, use `devtool undeploy-target`:

```bash
devtool undeploy-target phosphor-state-manager root@localhost:2222
```

This removes all files that `deploy-target` installed and restores the originals.

### When to Use SCP vs deploy-target

| Situation | Recommended Method |
|-----------|-------------------|
| Replace a single binary quickly | SCP |
| Deploy recipe with many files (bins + configs + units) | `devtool deploy-target` |
| Target has no SSH key set up | SCP with password |
| Need to revert changes easily | `devtool deploy-target` (supports undeploy) |
| Deploying to real hardware over network | `devtool deploy-target` |

---

## Step 4: Iterative Debug with gdbserver

When log messages are not enough to diagnose a problem, you can attach a debugger to a running service on the target. This section shows you how to use gdbserver on the QEMU target and connect to it with GDB on your build host.

### Install gdbserver on the Target

The default OpenBMC image may not include gdbserver. You have two ways to add it.

**Option A: Add gdbserver to the image (recommended for repeated use):**

Add the following to your `conf/local.conf` before building:

```bash
# In conf/local.conf
IMAGE_INSTALL:append = " gdbserver"
```

Then rebuild the image:

```bash
bitbake obmc-phosphor-image
```

**Option B: Build and deploy gdbserver separately:**

```bash
# Build gdbserver as a standalone package
devtool modify gdb
devtool build gdb

# Deploy just gdbserver to target
scp -P 2222 \
    tmp/work/armv7ahf-vfpv4d16-openbmc-linux-gnueabi/gdb/*/image/usr/bin/gdbserver \
    root@localhost:/usr/bin/gdbserver
```

### Attach gdbserver to a Running Service

On the QEMU target, find the process ID of the service you want to debug and attach gdbserver:

```bash
# SSH into the target
ssh -p 2222 root@localhost

# Find the PID of the service
pidof phosphor-bmc-state-manager
# Example output: 1234

# Attach gdbserver to the running process on port 3333
gdbserver --attach :3333 1234
```

gdbserver pauses the process and waits for a GDB client to connect.

{: .warning }
Attaching gdbserver pauses the target process. Other OpenBMC services that depend on the paused service may time out or report errors. This is expected during debugging.

### Start gdbserver with a New Process

If you prefer to start the service under gdbserver from the beginning (to catch initialization issues):

```bash
# On the target, stop the service first
ssh -p 2222 root@localhost

systemctl stop xyz.openbmc_project.State.BMC

# Start under gdbserver
gdbserver :3333 /usr/bin/phosphor-bmc-state-manager
```

### Connect from the Host with GDB

On your build host, you need an ARM-compatible GDB. The OpenBMC SDK provides one, or you can use the one built by bitbake:

```bash
# Find the cross GDB in your build environment
find tmp/work/x86_64-linux -name "arm-openbmc-linux-gnueabi-gdb" -type f 2>/dev/null

# Or use the SDK's GDB if you have the SDK installed
# Typically at: /opt/openbmc-sdk/sysroots/x86_64-pokysdk-linux/usr/bin/arm-openbmc-linux-gnueabi/arm-openbmc-linux-gnueabi-gdb
```

Connect to the remote gdbserver:

```bash
# Start GDB with the unstripped binary (contains debug symbols)
arm-openbmc-linux-gnueabi-gdb \
    tmp/work/armv7ahf-vfpv4d16-openbmc-linux-gnueabi/phosphor-state-manager/1.0+git*/image/usr/bin/phosphor-bmc-state-manager
```

Inside the GDB session:

```
(gdb) target remote localhost:3333
Remote debugging using localhost:3333
...

(gdb) break bmc_state_manager.cpp:42
Breakpoint 1 at 0x...: file bmc_state_manager.cpp, line 42.

(gdb) continue
Continuing.
```

{: .tip }
QEMU forwards port 3333 from the target if you add `-net user,hostfwd=tcp::3333-:3333` to your QEMU command line. Alternatively, since you already have SSH access, you can use an SSH tunnel: `ssh -p 2222 -L 3333:localhost:3333 root@localhost`.

### Common GDB Commands for OpenBMC Debugging

| Command | Description |
|---------|-------------|
| `bt` | Print backtrace of the current thread |
| `info threads` | List all threads in the process |
| `thread 2` | Switch to thread 2 |
| `p variable_name` | Print the value of a variable |
| `watch variable_name` | Break when a variable changes |
| `info breakpoints` | List all breakpoints |
| `continue` | Resume execution |
| `next` | Step over (execute next line) |
| `step` | Step into (enter function calls) |
| `finish` | Run until current function returns |

### Build with Debug Symbols

For the most useful debugging experience, ensure your recipe builds with debug symbols. Add this to `conf/local.conf`:

```bash
# Enable debug symbols for all recipes
DEBUG_BUILD = "1"

# Or enable debug symbols for a specific recipe only
DEBUG_FLAGS:pn-phosphor-state-manager = "-g -Og"
```

{: .note }
Debug builds produce larger binaries and run slightly slower. Use this only during active debugging and remove it when you are done.

---

## Complete Worked Example: Modify phosphor-state-manager

This section walks through the entire modify-build-deploy-verify cycle from start to finish. Follow each step exactly to build confidence with the workflow.

### Background

`phosphor-state-manager` manages BMC, chassis, and host power states in OpenBMC. It exposes D-Bus interfaces that other services use to query and control system power. You will add a custom property to the BMC state manager and verify it appears on D-Bus.

### Step 1: Start QEMU

If QEMU is not already running, start it in a separate terminal:

```bash
cd openbmc/build/ast2600-evb

qemu-system-arm -m 1G \
    -M ast2600-evb \
    -nographic \
    -drive file=tmp/deploy/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
```

Wait for the login prompt (takes 2-3 minutes). Verify SSH access:

```bash
ssh -p 2222 root@localhost "obmcutil state"
```

### Step 2: Extract the Source

```bash
cd openbmc
. setup ast2600-evb

# Extract phosphor-state-manager
devtool modify phosphor-state-manager

# Verify
devtool status
```

### Step 3: Examine the Current State on the Target

Before making changes, observe the current D-Bus state so you can compare later:

```bash
# Query the BMC state object
ssh -p 2222 root@localhost \
    "busctl introspect xyz.openbmc_project.State.BMC \
     /xyz/openbmc_project/state/bmc0"
```

You see properties like `CurrentBMCState`, `RequestedBMCTransition`, and others. Note the current values.

```bash
# Check the service journal
ssh -p 2222 root@localhost \
    "journalctl -u xyz.openbmc_project.State.BMC --no-pager -n 10"
```

### Step 4: Make the Code Change

Navigate to the workspace source and add a log message:

```bash
cd workspace/sources/phosphor-state-manager
```

Edit `bmc_state_manager.cpp`. Find the `BMC::BMC` constructor (or the `discoverInitialState` method) and add a log line:

```cpp
// Add near the top of the constructor or discoverInitialState():
lg2::info("DEVTOOL-GUIDE: BMC State Manager started with devtool modifications");
```

Save the file.

### Step 5: Build

```bash
# Return to build directory
cd /path/to/openbmc/build/ast2600-evb

# Build only the modified recipe
devtool build phosphor-state-manager
```

Watch the output for `NOTE: Tasks Summary: ...` at the end. A successful build shows zero failed tasks.

{: .warning }
If the build fails with a meson error, check that your code change has correct C++ syntax. Common mistakes include missing semicolons and unmatched braces. Run `devtool build phosphor-state-manager` again after fixing.

### Step 6: Deploy to QEMU

Use SCP to deploy the modified binary:

```bash
# Find the built binary path
BINARY=$(find tmp/work/armv7ahf-vfpv4d16-openbmc-linux-gnueabi/phosphor-state-manager/ \
    -path "*/image/usr/bin/phosphor-bmc-state-manager" -type f | head -1)

echo "Deploying: $BINARY"

# Copy to target
scp -P 2222 "$BINARY" root@localhost:/usr/bin/phosphor-bmc-state-manager
```

### Step 7: Restart and Verify

Restart the service on the target and check for your log message:

```bash
# Restart the BMC state manager service
ssh -p 2222 root@localhost "systemctl restart xyz.openbmc_project.State.BMC"

# Wait a moment for the service to start
sleep 2

# Check service status
ssh -p 2222 root@localhost "systemctl status xyz.openbmc_project.State.BMC"
```

Verify your log message appears in the journal:

```bash
ssh -p 2222 root@localhost \
    "journalctl -u xyz.openbmc_project.State.BMC --no-pager -n 30 | grep DEVTOOL-GUIDE"
```

You should see output similar to:

```
<timestamp> ast2600-evb phosphor-bmc-state-manager[1234]: DEVTOOL-GUIDE: BMC State Manager started with devtool modifications
```

Verify the D-Bus interface is still functioning correctly:

```bash
# Query BMC state - should return valid state
ssh -p 2222 root@localhost \
    "busctl get-property xyz.openbmc_project.State.BMC \
     /xyz/openbmc_project/state/bmc0 \
     xyz.openbmc_project.State.BMC CurrentBMCState"

# Expected: s "xyz.openbmc_project.State.BMC.BMCState.Ready"
```

### Step 8: Iterate

Now that you have a working deploy cycle, you can iterate quickly:

1. Edit source in `workspace/sources/phosphor-state-manager/`
2. Run `devtool build phosphor-state-manager`
3. SCP the binary to the target
4. Restart the service
5. Check the logs

Each iteration takes 2-3 minutes instead of 30+.

### Step 9: Clean Up

When you are done experimenting, reset your workspace:

```bash
# Remove the recipe from your workspace
devtool reset phosphor-state-manager

# Verify it is removed
devtool status
```

{: .warning }
`devtool reset` deletes your workspace source directory. If you want to keep your changes, commit them with `git commit` inside the workspace source directory first. You can also use `devtool finish phosphor-state-manager meta-your-layer` to save changes as a bbappend with patches.

---

## Quick Reference: devtool Commands

| Command | Purpose |
|---------|---------|
| `devtool modify <recipe>` | Extract recipe source to workspace |
| `devtool build <recipe>` | Build only the modified recipe |
| `devtool deploy-target <recipe> root@<host>:<port>` | Deploy built files to target via SSH |
| `devtool undeploy-target <recipe> root@<host>:<port>` | Remove deployed files from target |
| `devtool finish <recipe> <layer>` | Create bbappend + patches in a layer |
| `devtool reset <recipe>` | Remove recipe from workspace |
| `devtool status` | List all recipes in workspace |

---

## Troubleshooting

### Issue: devtool build fails with "Nothing PROVIDES"

**Symptom**: Build error mentioning missing dependencies.

**Cause**: The recipe depends on other recipes that have not been built yet.

**Solution**:
1. Build the full image first to populate the sstate cache:
   ```bash
   bitbake obmc-phosphor-image
   ```
2. Then use `devtool build`:
   ```bash
   devtool build phosphor-state-manager
   ```

### Issue: SCP fails with "Permission denied"

**Symptom**: `scp: /usr/bin/phosphor-bmc-state-manager: Permission denied`

**Cause**: The target filesystem is mounted read-only or the file is in use.

**Solution**:
1. Remount the filesystem read-write:
   ```bash
   ssh -p 2222 root@localhost "mount -o remount,rw /"
   ```
2. Stop the service before copying:
   ```bash
   ssh -p 2222 root@localhost "systemctl stop xyz.openbmc_project.State.BMC"
   scp -P 2222 "$BINARY" root@localhost:/usr/bin/phosphor-bmc-state-manager
   ssh -p 2222 root@localhost "systemctl start xyz.openbmc_project.State.BMC"
   ```

### Issue: Service fails to start after deploying new binary

**Symptom**: `systemctl status` shows the service in "failed" state.

**Cause**: The new binary may have a runtime error, missing library, or ABI mismatch.

**Solution**:
1. Check the journal for error details:
   ```bash
   ssh -p 2222 root@localhost \
       "journalctl -u xyz.openbmc_project.State.BMC --no-pager -n 50"
   ```
2. Verify the binary is the correct architecture:
   ```bash
   ssh -p 2222 root@localhost "file /usr/bin/phosphor-bmc-state-manager"
   # Expected: ELF 32-bit LSB executable, ARM, ...
   ```
3. Check for missing shared libraries:
   ```bash
   ssh -p 2222 root@localhost "ldd /usr/bin/phosphor-bmc-state-manager"
   ```

### Issue: gdbserver connection refused

**Symptom**: GDB reports "Connection refused" when connecting to the remote target.

**Cause**: Port forwarding is not configured or gdbserver is not running.

**Solution**:
1. Verify gdbserver is running on the target:
   ```bash
   ssh -p 2222 root@localhost "ps aux | grep gdbserver"
   ```
2. Use an SSH tunnel instead of direct port forwarding:
   ```bash
   # Set up tunnel in a separate terminal
   ssh -p 2222 -L 3333:localhost:3333 root@localhost -N

   # Then connect GDB to localhost:3333
   (gdb) target remote localhost:3333
   ```

### Issue: GDB cannot find source files

**Symptom**: GDB shows `No source file named...` when setting breakpoints by file name.

**Cause**: The debug symbol paths in the binary do not match your host filesystem.

**Solution**: Set the source search path in GDB:
```
(gdb) set substitute-path /usr/src/debug workspace/sources/phosphor-state-manager
(gdb) directory workspace/sources/phosphor-state-manager
```

### Debug Commands Cheat Sheet

```bash
# Check service status on target
ssh -p 2222 root@localhost "systemctl status xyz.openbmc_project.State.BMC"

# View live logs
ssh -p 2222 root@localhost "journalctl -u xyz.openbmc_project.State.BMC -f"

# List D-Bus objects owned by state manager
ssh -p 2222 root@localhost "busctl tree xyz.openbmc_project.State.BMC"

# Introspect a specific D-Bus object
ssh -p 2222 root@localhost \
    "busctl introspect xyz.openbmc_project.State.BMC \
     /xyz/openbmc_project/state/bmc0"

# Check what files a recipe installs
devtool build phosphor-state-manager
find tmp/work/*/phosphor-state-manager/*/image -type f

# Check workspace status
devtool status
```

---

## Next Steps

- [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) - Learn bbappend customization and build optimization
- [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) - Understand D-Bus interfaces used by OpenBMC services
- [State Manager Guide]({% link docs/02-architecture/03-state-manager-guide.md %}) - Deep dive into power state management
- [Unit Testing Guide]({% link docs/05-advanced/10-unit-testing-guide.md %}) - Write tests for your code changes

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC master branch (Kirkstone/Scarthgap)
Last updated: 2026-02-06
