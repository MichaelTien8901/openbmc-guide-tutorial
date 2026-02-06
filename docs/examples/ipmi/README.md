# IPMI OEM Command Examples

Example implementation of OEM IPMI commands for OpenBMC.

> **Requires OpenBMC bitbake environment** — this example builds a shared
> library that gets loaded by the `ipmid` daemon at runtime. It cannot
> be built standalone with Docker.

## Files

| File | Description |
|------|-------------|
| `oem_handler.cpp` | OEM command handler implementation |
| `oem_handler.hpp` | Header file with command definitions |
| `CMakeLists.txt` | CMake build configuration |
| `meson.build` | Meson build configuration |
| `myoem-ipmi.bb` | BitBake recipe for Yocto |

## Quick Start with BitBake + QEMU

### 1. Set up your layer

```bash
# In your OpenBMC build tree, create an OEM layer (or use an existing one)
mkdir -p meta-myoem/recipes-phosphor/ipmi/myoem-ipmi
mkdir -p meta-myoem/conf

# Copy the example files
cp oem_handler.cpp oem_handler.hpp meson.build \
    meta-myoem/recipes-phosphor/ipmi/myoem-ipmi/
cp myoem-ipmi.bb \
    meta-myoem/recipes-phosphor/ipmi/myoem-ipmi_1.0.bb
```

### 2. Configure the recipe for local source

Edit the `.bb` file to use local files instead of a git repo:

```bitbake
# In myoem-ipmi_1.0.bb, replace SRC_URI with:
SRC_URI = "file://oem_handler.cpp \
           file://oem_handler.hpp \
           file://meson.build \
          "
S = "${WORKDIR}"
```

### 3. Add to image and build

```bash
# In your machine conf or local.conf
IMAGE_INSTALL:append = " myoem-ipmi"

# Build
bitbake obmc-phosphor-image
```

### 4. Boot QEMU and test

```bash
# Start QEMU (from the tutorial repo)
./scripts/run-qemu.sh ast2600-evb

# From the host, test with ipmitool:

# Get OEM Version — NetFn 0x30, Cmd 0x01
ipmitool -I lanplus -H localhost -p 2623 -U root -P 0penBmc raw 0x30 0x01
# Expected: 01 00 00 (version 1.0.0)

# Get Board Info — NetFn 0x30, Cmd 0x03
ipmitool -I lanplus -H localhost -p 2623 -U root -P 0penBmc raw 0x30 0x03
# Expected: 01 02 02 10 e8 03

# Set LED — NetFn 0x30, Cmd 0x02, LED=identify(0), State=on(1)
ipmitool -I lanplus -H localhost -p 2623 -U root -P 0penBmc raw 0x30 0x02 0x00 0x01

# Set config index 0 to value 42, then read it back
ipmitool -I lanplus -H localhost -p 2623 -U root -P 0penBmc raw 0x30 0x10 0x00 0x2a
ipmitool -I lanplus -H localhost -p 2623 -U root -P 0penBmc raw 0x30 0x11 0x00
# Expected: 2a
```

## Alternative: Build with SDK and scp

If you have the OpenBMC SDK installed, you can cross-compile and deploy
without a full bitbake rebuild:

```bash
# Source the SDK
source /opt/openbmc-phosphor/VERSION/environment-setup-*

# Build
mkdir build && cd build
cmake ..
make
# Output: libmyoemhandler.so

# Deploy to BMC (QEMU or hardware)
scp libmyoemhandler.so root@localhost:/usr/lib/ipmid-providers/ -P 2222

# Restart ipmid to load the new handler
ssh -p 2222 root@localhost systemctl restart phosphor-ipmi-host
```

## OEM Commands Reference

| Cmd | Name | Privilege | Request | Response |
|-----|------|-----------|---------|----------|
| 0x01 | Get Version | User | — | major, minor, patch |
| 0x02 | Set LED | Operator | led_id, state | — |
| 0x03 | Get Board Info | User | — | type, rev, cpus, dimms, power(2B) |
| 0x10 | Set Config | Admin | index, value | — |
| 0x11 | Get Config | User | index | value |
| 0x20 | Run Diagnostic | Admin | test_id | — |
| 0x21 | Get Diagnostic Result | User | test_id | status, result_code |

All commands use NetFn `0x30`.

## How It Works

The handler is built as a shared library (`libmyoemhandler.so`) that gets
installed to `/usr/lib/ipmid-providers/`. When `ipmid` starts, it loads all
libraries in that directory. The `__attribute__((constructor))` function in
`oem_handler.cpp` runs automatically and registers each command handler
with its NetFn, command code, and required privilege level.

## Related Documentation

- [IPMI Guide](../../docs/04-interfaces/01-ipmi-guide.md)
- [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid)
