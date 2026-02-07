---
layout: default
title: I2C Device Integration
parent: Core Services
nav_order: 16
difficulty: intermediate
prerequisites:
  - environment-setup
  - first-build
  - machine-layer
last_modified_date: 2026-02-06
---

# I2C Device Integration
{: .no_toc }

Configure I2C bus topology, debug devices with i2c-tools, bind kernel drivers through device tree and sysfs, and prepare for I3C migration on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The **I2C (Inter-Integrated Circuit)** bus is the primary communication backbone on every BMC platform. Temperature sensors, voltage regulators, fan controllers, EEPROM FRU storage, power sequencers, and mux expanders all sit on I2C buses connected to the ASPEED BMC SoC. Understanding I2C bus topology, device tree configuration, and runtime driver management is essential for bringing up any new OpenBMC platform.

This guide covers the full I2C integration workflow: mapping your hardware bus topology, using i2c-tools to discover and debug devices, writing device tree nodes so the kernel binds drivers automatically, and using sysfs to bind or unbind drivers at runtime. It also introduces I3C -- the next-generation successor to I2C -- and explains what the migration path looks like for OpenBMC platforms.

**Key concepts covered:**
- I2C bus numbering and mux hierarchy on ASPEED SoCs
- i2c-tools commands: `i2cdetect`, `i2cget`, `i2cset`, `i2cdump`
- Device tree I2C node configuration and driver binding
- Runtime driver bind/unbind through sysfs `new_device` and `delete_device`
- I3C protocol overview and kernel status
- Common I2C device types in BMC platforms

{: .note }
I2C bus operations are **fully testable** in QEMU. The ast2600-evb QEMU target emulates I2C controllers with a few default devices. You can practice i2c-tools commands, device tree changes, and driver binding in the emulated environment before deploying to physical hardware.

---

## Architecture

The ASPEED AST2600 BMC SoC provides 16 I2C controllers, each appearing as a separate Linux I2C bus. Physical hardware typically routes these buses through I2C multiplexers (muxes) to expand the address space and isolate device groups. The Linux I2C subsystem assigns sequential bus numbers to each mux channel, creating a tree of buses rooted at the SoC controllers.

### I2C Bus Topology

```
ASPEED AST2600 SoC
├── Bus 0 ── TMP75 @ 0x48, TMP75 @ 0x49
├── Bus 1 ── PCA9548 Mux @ 0x70
│              ├── Ch 0 → Bus 16 ── PSU0 @ 0x58
│              ├── Ch 1 → Bus 17 ── PSU1 @ 0x59
│              ├── Ch 2 → Bus 18 ── FAN CPLD @ 0x3C
│              └── Ch 3 → Bus 19 ── NVMe0 @ 0x6A
├── Bus 2 ── EEPROM @ 0x50, EEPROM @ 0x51
├── Bus 3 ── PCA9546 Mux @ 0x71
│              ├── Ch 0 → Bus 20 ── TMP421 @ 0x4C
│              └── Ch 1 → Bus 21 ── TMP421 @ 0x4D
├── Bus 4 ── ADM1278 HSC @ 0x10, IR35221 VRM @ 0x40
└── Bus 5..15 ── (platform-specific devices)
```

### Bus Numbering Rules

The kernel assigns I2C bus numbers following these rules:

1. **SoC controllers** get the lowest numbers (0-15 on AST2600), based on the device tree node order.
2. **Mux channels** receive dynamically assigned numbers starting after the last SoC controller. The exact number depends on mux probe order.
3. **Nested muxes** add further bus numbers. A mux behind another mux creates buses at the next available numbers.

{: .warning }
Mux bus numbers are assigned at probe time and can change if you add or remove mux entries in the device tree. Never hardcode mux channel bus numbers in userspace scripts. Instead, use the `i2c-mux` sysfs hierarchy to discover the mapping dynamically.

### Common I2C Devices in BMC Platforms

| Device Type | Common Chips | Address Range | Purpose |
|-------------|-------------|---------------|---------|
| Temperature sensor | TMP75, TMP421, LM75 | 0x48-0x4F | Thermal monitoring |
| EEPROM | AT24C256, AT24C64 | 0x50-0x57 | FRU data, board identity |
| I2C Mux | PCA9548, PCA9546 | 0x70-0x77 | Bus expansion |
| Power supply | PMBus devices | 0x58-0x5F | PSU telemetry |
| Voltage regulator | IR35221, TPS53679 | 0x40-0x4F | VRM monitoring |
| Hot-swap controller | ADM1278, LTC4282 | 0x10-0x1F | Input power monitoring |
| Fan controller | MAX31790, EMC2305 | 0x20-0x2F | Fan tach and PWM |

### Key Dependencies

- **Linux I2C subsystem**: Provides the bus abstraction (`/dev/i2c-N`), adapter drivers, and client driver framework
- **ASPEED I2C controller driver**: `i2c-aspeed` kernel module that interfaces with SoC I2C registers
- **i2c-tools**: Userspace utilities for bus scanning and device communication
- **I2C mux framework**: Kernel subsystem that creates virtual I2C buses for mux channels

---

## i2c-tools Debugging

The `i2c-tools` package provides four essential commands for I2C debugging on a running BMC. These tools communicate directly with devices through the Linux I2C subsystem, bypassing any OpenBMC daemons.

### i2cdetect -- Scan for Devices

Use `i2cdetect` to discover which addresses respond on a given bus. This is typically your first step when bringing up a new platform.

```bash
# List all I2C buses on the system
i2cdetect -l
# i2c-0  i2c  1e78a080.i2c-bus  I2C adapter
# i2c-16 i2c  i2c-1-mux (chan_id 0)  I2C adapter  ...

# Scan bus 0 for responding devices (-y skips confirmation prompt)
i2cdetect -y 0

# Sample output (abbreviated):
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- --
# ...
# 40: -- -- -- -- -- -- -- -- 48 49 -- -- -- -- -- --
# ...
# 70: -- -- -- -- -- -- -- --
```

The output shows device addresses in hexadecimal. Addresses showing a value (like `48`) have a device responding; `--` means no response; `UU` means the address is already claimed by a kernel driver.

{: .tip }
The `-y` flag skips the interactive confirmation prompt. Use `-r` for SMBus quick-read scan mode, which works better with some devices that do not respond to the default quick-write probe.

### i2cget -- Read a Register

Use `i2cget` to read a single register from an I2C device. This is useful for verifying device identity and checking register values.

```bash
# Read one byte from device 0x48 on bus 0, register 0x00 (temperature)
i2cget -y 0 0x48 0x00 b

# Read a 16-bit (word) value from the same register
i2cget -y 0 0x48 0x00 w

# Read without specifying a register (current pointer)
i2cget -y 0 0x48
```

Command format: `i2cget -y <bus> <address> [register] [mode]`

| Mode | Description |
|------|-------------|
| `b` | Read a single byte (default) |
| `w` | Read a 16-bit word |
| `c` | Read a byte without writing a register address first |

### i2cset -- Write a Register

Use `i2cset` to write values to device registers. This is useful for configuring devices and testing write paths.

```bash
# Write byte 0x60 to register 0x01 (configuration) on device 0x48, bus 0
i2cset -y 0 0x48 0x01 0x60 b

# Write a 16-bit word to register 0x02 (high limit)
i2cset -y 0 0x48 0x02 0x5000 w
```

Command format: `i2cset -y <bus> <address> <register> <value> [mode]`

{: .warning }
Writing to I2C devices can change hardware configuration and potentially damage components if you write incorrect values to control registers (voltage regulator output, fan speed limits, etc.). Double-check the device datasheet before using `i2cset` on production hardware.

### i2cdump -- Dump All Registers

Use `i2cdump` to read the entire register map of a device. This gives you a complete picture of the device state.

```bash
# Dump all registers from device 0x48 on bus 0
i2cdump -y 0 0x48

# Sample output (TMP75 temperature sensor):
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00: 19 60 4b 00 19 60 4b 00 19 60 4b 00 19 60 4b 00
# ...

# Dump using word (16-bit) reads
i2cdump -y 0 0x48 w

# Dump a specific range of registers (bytes 0x00 to 0x0F)
i2cdump -y -r 0x00-0x0F 0 0x48
```

### Practical Debugging Workflow

When a sensor or device is not working, follow this sequence:

1. Verify the bus exists: `i2cdetect -l | grep "i2c-1"`
2. Scan for the device: `i2cdetect -y 1` (look for your expected address)
3. If device responds, read its ID register: `i2cget -y 1 0x48 0x00 w`
4. If device does NOT respond, check wiring, mux selection, and address conflicts. Try read-mode scan: `i2cdetect -y -r 1`

{: .tip }
In QEMU ast2600-evb, run `i2cdetect -l` to see which buses are emulated and `i2cdetect -y <bus>` to find the default emulated devices.

---

## Device Tree I2C Node Configuration

The Linux kernel uses the device tree to discover I2C devices at boot time and automatically bind the correct driver to each device. Properly configuring device tree I2C nodes is the standard method for declaring hardware on your platform.

### I2C Controller Nodes

The ASPEED device tree defines I2C controller nodes as children of the APB bus. Each controller maps to one I2C bus. Enable the controllers you need by setting `status = "okay"` in your platform device tree.

```dts
/* Enable I2C bus 0 and bus 1 in your platform .dts file */
&i2c0 {
    status = "okay";
};

&i2c1 {
    status = "okay";
};
```

### Adding I2C Device Nodes

Declare each I2C device as a child node of its parent bus. The key properties are `compatible` (selects the kernel driver) and `reg` (specifies the 7-bit I2C address).

```dts
&i2c0 {
    status = "okay";

    /* TMP75 temperature sensor at address 0x48 */
    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
    };

    /* TMP75 temperature sensor at address 0x49 */
    tmp75@49 {
        compatible = "ti,tmp75";
        reg = <0x49>;
    };

    /* AT24 EEPROM at address 0x50 */
    eeprom@50 {
        compatible = "atmel,24c256";
        reg = <0x50>;
        pagesize = <64>;
    };
};
```

### Device Tree Properties Reference

| Property | Required | Description | Example |
|----------|----------|-------------|---------|
| `compatible` | Yes | Driver binding string (vendor,device) | `"ti,tmp75"` |
| `reg` | Yes | 7-bit I2C address in hex | `<0x48>` |
| `status` | No | Enable/disable (`"okay"` or `"disabled"`) | `"okay"` |
| `label` | No | Human-readable device label | `"inlet_temp"` |
| `pagesize` | EEPROM | EEPROM page size for write operations | `<64>` |

### I2C Mux Configuration

I2C multiplexers create child buses in the device tree. Each channel becomes a new I2C bus that you can attach devices to.

```dts
&i2c1 {
    status = "okay";

    /* PCA9548 8-channel I2C mux at address 0x70 */
    i2c-mux@70 {
        compatible = "nxp,pca9548";
        reg = <0x70>;
        #address-cells = <1>;
        #size-cells = <0>;

        /* Channel 0: PSU bus */
        i2c@0 {
            reg = <0>;
            #address-cells = <1>;
            #size-cells = <0>;

            psu@58 {
                compatible = "pmbus";
                reg = <0x58>;
            };
        };

        /* Channel 1: Sensor bus */
        i2c@1 {
            reg = <1>;
            #address-cells = <1>;
            #size-cells = <0>;

            tmp421@4c {
                compatible = "ti,tmp421";
                reg = <0x4c>;
            };
        };

        /* Additional channels follow the same pattern */
    };
};
```

{: .note }
The `#address-cells = <1>` and `#size-cells = <0>` properties are required on each mux channel node. They tell the device tree parser that child nodes use a single cell for their address (the I2C address) and have no size component.

### Common Compatible Strings

| Device | Compatible String | Kernel Driver |
|--------|------------------|---------------|
| TMP75 | `"ti,tmp75"` | lm75 |
| TMP421 | `"ti,tmp421"` | tmp421 |
| LM75A | `"nxp,lm75a"` | lm75 |
| AT24C256 | `"atmel,24c256"` | at24 |
| PCA9548 | `"nxp,pca9548"` | i2c-mux-pca954x |
| PCA9546 | `"nxp,pca9546"` | i2c-mux-pca954x |
| ADM1278 | `"adi,adm1278"` | adm1275 |

### Adding Device Tree Changes to Your Layer

Place your device tree in a `.dts` file in your machine layer and include it via a kernel bbappend (`linux-aspeed_%.bbappend`) using `FILESEXTRAPATHS:prepend` and `SRC_URI += "file://aspeed-bmc-myplatform.dts"`. Copy the file into the kernel source tree in `do_configure:append()`.

---

## Runtime Driver Bind/Unbind

Sometimes you need to add or remove I2C devices without rebooting, for example when hot-swapping a component, debugging a sensor, or testing a new device. The Linux I2C subsystem provides sysfs interfaces for runtime device management.

### Adding a Device at Runtime (new_device)

Write the driver name and address to the bus's `new_device` file to instantiate a device without a device tree entry.

```bash
# Instantiate a TMP75 at address 0x48 on bus 0
echo tmp75 0x48 > /sys/bus/i2c/devices/i2c-0/new_device

# Verify the device was created
ls /sys/bus/i2c/devices/0-0048/
# driver  hwmon  modalias  name  power  subsystem  uevent

# Verify hwmon appeared
ls /sys/bus/i2c/devices/0-0048/hwmon/
# hwmon3

# Read the sensor value
cat /sys/bus/i2c/devices/0-0048/hwmon/hwmon3/temp1_input
# 25500  (25.5 degrees C in millidegrees)
```

The `new_device` file takes two space-separated arguments: the driver name (e.g., `tmp75`, `at24`) and the 7-bit I2C address in hex (e.g., `0x48`).

### Removing a Device at Runtime (delete_device)

Write the address to the bus's `delete_device` file to remove a previously instantiated device:

```bash
echo 0x48 > /sys/bus/i2c/devices/i2c-0/delete_device
```

{: .warning }
Removing a device that is in use by a sensor daemon (phosphor-hwmon, dbus-sensors) will cause that daemon to lose the sensor. The daemon may log errors or restart. Stop the daemon first if you need to remove a device cleanly.

### Driver Bind/Unbind via sysfs

If a device exists in the device tree but you need to rebind its driver (for example after loading an updated module), use the driver's `bind` and `unbind` files.

```bash
# Find the device's driver
ls -la /sys/bus/i2c/devices/0-0048/driver
# lrwxrwxrwx ... -> ../../../../../../bus/i2c/drivers/lm75

# Unbind the driver from the device
echo "0-0048" > /sys/bus/i2c/drivers/lm75/unbind

# Rebind the driver to the device
echo "0-0048" > /sys/bus/i2c/drivers/lm75/bind
```

The device identifier format is `<bus>-<address>`, where `<bus>` is the bus number and `<address>` is the zero-padded 4-digit hex address (e.g., `0-0048` for bus 0, address 0x48).

### When to Use Runtime Binding

Use `new_device` for testing sensors before committing to device tree changes, or for hot-swap scenarios where a GPIO presence signal triggers device instantiation. Use `unbind`/`bind` when reloading driver modules or isolating a misbehaving device during debugging.

{: .tip }
For hot-swappable devices, you can automate bind/unbind with a script triggered by GPIO events. Wire a GPIO presence signal to a systemd target that calls `new_device` on insertion and `delete_device` on removal. See the [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %}) for details on event-driven scripting.

{: .note }
When using `new_device`, the kernel matches the driver name to a loaded I2C driver. If the driver is built as a module and not yet loaded, run `modprobe <driver>` first. For devices declared in the device tree, driver modules are loaded automatically by `udev`.

---

## Porting Guide

Follow these steps to integrate I2C devices on a new OpenBMC platform:

### Step 1: Map Your Hardware I2C Topology

Obtain the platform schematic and identify:
- [ ] Which ASPEED I2C bus each device connects to
- [ ] I2C addresses for every device (check for address pin strapping)
- [ ] Mux locations and channel assignments
- [ ] Pull-up resistor values (SDA/SCL should have 2.2k-10k pull-ups)

### Step 2: Verify Devices with i2c-tools

Boot your BMC with a minimal image and scan each bus with `i2cdetect -y <bus>`. Compare the results against your hardware map -- every expected device should respond at its documented address.

### Step 3: Add Device Tree Nodes

Create or update your platform device tree to declare every I2C device. Follow the patterns in the [Device Tree I2C Node Configuration](#device-tree-i2c-node-configuration) section for sensors, EEPROMs, and muxes. Each device needs a `compatible` string and `reg` address that match your hardware.

### Step 4: Build and Verify Driver Binding

```bash
bitbake obmc-phosphor-image
# Flash, boot, then verify:
dmesg | grep i2c                          # Check I2C init messages
ls /sys/bus/i2c/devices/0-0048/driver     # Verify driver bound
ls /sys/bus/i2c/devices/0-0048/hwmon/     # Verify hwmon appeared
i2cdetect -l | grep mux                   # Verify mux channels
```

### Step 5: Connect to OpenBMC Sensor Framework

Once device tree binding is confirmed, configure Entity Manager or phosphor-hwmon to expose your sensors on D-Bus. See the [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) and [Hwmon Sensors Guide]({% link docs/03-core-services/02-hwmon-sensors-guide.md %}) for details.

---

## Code Examples

### Example 1: I2C Bus Scan Script

A script that scans all I2C buses and reports discovered devices with their driver status.

```bash
#!/bin/bash
# i2c-scan-all.sh -- Scan all I2C buses and report device status

for bus_path in /sys/bus/i2c/devices/i2c-*; do
    bus=$(basename "$bus_path" | sed 's/i2c-//')
    echo "Bus $bus: $(cat "$bus_path/name" 2>/dev/null)"
    for dev_path in /sys/bus/i2c/devices/${bus}-*; do
        [ -d "$dev_path" ] || continue
        driver="(no driver)"
        [ -L "$dev_path/driver" ] && driver=$(basename "$(readlink "$dev_path/driver")")
        echo "  $(basename "$dev_path"): $(cat "$dev_path/name" 2>/dev/null) [$driver]"
    done
done
```

### Example 2: Runtime I2C Device Management

```bash
# Add a TMP75 at 0x48 on bus 0, read its temperature, then remove it
echo tmp75 0x48 > /sys/bus/i2c/devices/i2c-0/new_device
ls /sys/bus/i2c/devices/0-0048/hwmon/              # Verify hwmon appeared
cat /sys/bus/i2c/devices/0-0048/hwmon/hwmon*/temp1_input  # Read temperature
echo 0x48 > /sys/bus/i2c/devices/i2c-0/delete_device     # Remove device
```

See additional working examples in the [examples/i2c-tools/]({{ site.baseurl }}/examples/i2c-tools/) directory.

---

## I3C Overview

**I3C (Improved Inter-Integrated Circuit)** is the MIPI Alliance standard that succeeds I2C. It maintains backward compatibility with I2C devices while adding significant performance and feature improvements. As BMC platforms evolve, I3C will gradually replace I2C for high-speed sensor and device communication.

### Key Differences Between I2C and I3C

| Feature | I2C | I3C |
|---------|-----|-----|
| Maximum speed | 3.4 Mbps (High-Speed) | 12.5 Mbps (SDR), 25+ Mbps (HDR) |
| Addressing | 7-bit static (set by hardware pins) | Dynamic address assignment by controller |
| In-band interrupts | Not supported (requires separate IRQ line) | Supported natively on SDA |
| Hot-join | Not supported | Devices can join the bus at runtime |
| Device discovery | Manual scan (i2cdetect) | Automatic via CCC (Common Command Codes) |
| Power consumption | Higher (external pull-ups) | Lower (push-pull drivers, no pull-ups) |
| Legacy support | N/A | I2C devices work on same bus |

### I3C in the Linux Kernel

The Linux kernel includes an I3C subsystem (available since kernel 5.0). The ASPEED AST2600 has a supported controller driver (`aspeed-i3c`), but I3C device driver support in OpenBMC is still maturing. Most platforms continue to use I2C for the near term.

Key kernel components: `drivers/i3c/master.c` (core), `aspeed-i3c` (ASPEED controller), `dw-i3c-master` (DesignWare), and emerging device drivers.

### Migration Path: I2C to I3C

If you are planning for I3C migration, follow these guidelines:

1. **Keep I2C working today** -- Use standard I2C device tree nodes and drivers. Do not wait for I3C.
2. **Identify I3C-capable hardware** -- Check which next-generation devices support I3C natively.
3. **Enable the I3C subsystem** -- Add `CONFIG_I3C=y` and `CONFIG_I3C_MASTER_ASPEED=y` in your kernel config.
4. **Test with a mixed bus** -- I3C controllers support legacy I2C devices on the same bus.
5. **Watch upstream** -- Monitor `drivers/i3c/` for new device drivers relevant to your platform.

{: .tip }
The AST2600 has 6 I3C controllers in addition to its 16 I2C controllers. You can use both simultaneously. Start I3C evaluation on a dedicated bus while keeping production devices on I2C.

---

## Troubleshooting

### Issue: Device Not Found on i2cdetect Scan

**Symptom**: `i2cdetect -y <bus>` shows `--` at the expected device address.

**Cause**: The device is not responding on the bus. Possible reasons include wrong bus number, wrong address, device not powered, missing pull-ups, or a mux channel not selected.

**Solution**:
1. Verify the correct bus with `i2cdetect -l`
2. If behind a mux, scan the parent bus for the mux first (`i2cdetect -y 1`, look for 0x70-0x77)
3. Select the mux channel manually: `i2cset -y 1 0x70 0x01` then rescan
4. Try read-mode scan: `i2cdetect -y -r 0`

### Issue: Driver Not Binding to Device

**Symptom**: The device appears in `i2cdetect` output, but no driver is bound (no `driver` symlink in `/sys/bus/i2c/devices/<bus>-<addr>/`).

**Cause**: The `compatible` string in the device tree does not match any loaded driver, or the driver module is not built into the kernel.

**Solution**:
1. Check the modalias: `cat /sys/bus/i2c/devices/0-0048/modalias`
2. Verify the driver is loaded: `modprobe lm75 && ls /sys/bus/i2c/drivers/lm75/`
3. Try manual binding: `echo "0-0048" > /sys/bus/i2c/drivers/lm75/bind`
4. Check for probe errors: `dmesg | grep "0-0048"`

### Issue: I2C Bus Stuck (SDA Held Low)

**Symptom**: All devices on a bus stop responding. `i2cdetect` hangs or returns errors.

**Cause**: A device is holding SDA low due to an interrupted transfer or device hang.

**Solution**: Check `dmesg | grep -i "i2c.*recover"` for recovery attempts. Force a controller reset by unbinding and rebinding the ASPEED I2C driver: `echo "1e78a080.i2c-bus" > /sys/bus/platform/drivers/aspeed-i2c-bus/unbind` then `echo "1e78a080.i2c-bus" > /sys/bus/platform/drivers/aspeed-i2c-bus/bind`. As a last resort, power-cycle the misbehaving device.

### Issue: Wrong Hwmon Values After new_device

**Symptom**: You create a device with `new_device` and the hwmon sensor appears, but readings are incorrect or zero.

**Cause**: The driver name you specified does not match the actual chip on the bus, or the chip needs initialization that the wrong driver does not perform.

**Solution**:
1. Verify the chip identity by reading its ID register directly:
   ```bash
   i2cdump -y 0 0x48
   # Compare register map against the datasheet
   ```
2. Remove and re-add with the correct driver name:
   ```bash
   echo 0x48 > /sys/bus/i2c/devices/i2c-0/delete_device
   echo lm75 0x48 > /sys/bus/i2c/devices/i2c-0/new_device
   ```

### Debug Commands

```bash
# List all I2C buses and adapters
i2cdetect -l

# Scan a specific bus
i2cdetect -y 0

# Check device driver binding
ls -la /sys/bus/i2c/devices/0-0048/driver

# View I2C kernel messages
dmesg | grep -i i2c

# Enable I2C debug tracing (requires CONFIG_I2C_DEBUG_CORE=y)
echo 1 > /sys/module/i2c_core/parameters/debug
```

---

## References

### Official Resources
- [Linux I2C Subsystem Documentation](https://www.kernel.org/doc/html/latest/i2c/index.html)
- [Linux I2C Device Tree Bindings](https://www.kernel.org/doc/html/latest/i2c/instantiating-devices.html)
- [i2c-tools Source and Documentation](https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/)
- [OpenBMC Documentation](https://github.com/openbmc/docs)

### Related Guides
- [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %})
- [Hwmon Sensors Guide]({% link docs/03-core-services/02-hwmon-sensors-guide.md %})
- [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %})
- [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %})

### External Documentation
- [MIPI I3C Specification](https://www.mipi.org/specifications/i3c-sensor-specification)
- [Linux I3C Subsystem](https://www.kernel.org/doc/html/latest/driver-api/i3c/index.html)
- [ASPEED AST2600 Datasheet (I2C/I3C Controllers)](https://www.aspeedtech.com/products.php?fPath=20&rId=440)
- [PCA9548 I2C Mux Datasheet (NXP)](https://www.nxp.com/docs/en/data-sheet/PCA9548A.pdf)

---

{: .note }
**Tested on**: QEMU ast2600-evb (emulated I2C buses with default devices). Full I2C topology and mux testing requires physical hardware with wired I2C devices.
Last updated: 2026-02-06
