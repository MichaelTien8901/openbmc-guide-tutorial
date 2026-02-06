# IPMI OEM Command Examples

Example implementation of OEM IPMI commands for OpenBMC.

## Files

| File | Description |
|------|-------------|
| `oem_handler.cpp` | OEM command handler implementation |
| `oem_handler.hpp` | Header file with command definitions |
| `CMakeLists.txt` | Build configuration |
| `meson.build` | Alternative Meson build configuration |
| `myoem-ipmi.bb` | BitBake recipe for Yocto |

## Building

### With OpenBMC SDK

```bash
# Source the SDK
source /opt/openbmc-phosphor/VERSION/environment-setup-*

# Build
mkdir build && cd build
cmake ..
make

# The output will be libmyoemhandler.so
```

### With Meson

```bash
meson setup build
meson compile -C build
```

## Installation

```bash
# Copy to BMC
scp build/libmyoemhandler.so root@bmc:/usr/lib/ipmid-providers/

# Restart ipmid
ssh root@bmc systemctl restart phosphor-ipmi-host
```

## Testing

### Get OEM Version

```bash
# NetFn 0x30, Cmd 0x01
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x01
# Expected response: 01 00 00 (version 1.0.0)
```

### Set LED State

```bash
# NetFn 0x30, Cmd 0x02, LED=0, State=1 (on)
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x02 0x00 0x01

# Turn off
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x02 0x00 0x00
```

### Get Board Info

```bash
# NetFn 0x30, Cmd 0x03
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x03
```

### Set/Get Custom Config

```bash
# Set config index 0 to value 42
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x10 0x00 0x2a

# Get config index 0
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc raw 0x30 0x11 0x00
```

## Integrating into Yocto Build

1. Create a layer for your OEM code
2. Add the BitBake recipe (`myoem-ipmi.bb`)
3. Add to your machine's `IMAGE_INSTALL`

```bitbake
# In your machine config or image recipe
IMAGE_INSTALL:append = " myoem-ipmi"
```

## Related Documentation

- [IPMI Guide](../../docs/04-interfaces/01-ipmi-guide.md)
- [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid) - D-Bus based IPMI daemon
