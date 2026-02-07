# GPIO Monitor Examples

Configuration files and systemd units for phosphor-multi-gpio-monitor, the
OpenBMC daemon that watches GPIO lines for edge events and triggers systemd
targets or D-Bus property changes in response.

> **Requires OpenBMC environment** -- these configuration files are installed on
> a booted OpenBMC system (QEMU or hardware) running phosphor-multi-gpio-monitor.

## Files

| File | Install To | Description |
|------|-----------|-------------|
| `multi-gpio-monitor.json` | `/etc/phosphor-multi-gpio-monitor.json` | Main GPIO monitor config: power button, reset button, chassis intrusion, NIC presence |
| `presence-monitor.json` | `/etc/phosphor-multi-gpio-presence.json` | Continuous presence detection for PSU, DIMM, riser card, and NVMe drive slots |
| `obmc-chassis-buttons-power-press.target` | `/lib/systemd/system/` | Example systemd target activated on power button press |

## How phosphor-multi-gpio-monitor Works

1. On startup the daemon reads a JSON configuration file listing GPIO line names,
   edge triggers, and associated systemd targets.
2. It opens each GPIO line using the Linux chardev interface (`/dev/gpiochipN`)
   by requesting lines by **name** (as defined in the device tree).
3. When an edge event occurs the daemon either:
   - Starts/stops the configured systemd target, or
   - Updates a D-Bus presence property under `xyz.openbmc_project.Inventory`.
4. For `"continue": true` entries the daemon keeps monitoring after the first
   event (used for presence pins that may toggle at runtime).

## GPIO Line Names

GPIO line names come from the platform device tree. For example, an AST2600
device tree might define:

```dts
&gpio0 {
    gpio-line-names =
        /* ... */
        "POWER_BUTTON",       /* GPIO A3 */
        "RESET_BUTTON",       /* GPIO B1 */
        "CHASSIS_INTRUSION",  /* GPIO C5 */
        "NIC0_PRSNT_N",       /* GPIO D0 - active low */
        "PSU0_PRSNT_N",       /* GPIO E2 - active low */
        /* ... */
        ;
};
```

Use `gpioinfo` on a running BMC to list available line names:

```bash
gpioinfo gpiochip0 | grep -i prsnt
gpioinfo gpiochip0 | grep -i button
```

## Quick Start (QEMU)

```bash
# 1. Build image with GPIO monitor
IMAGE_INSTALL:append = " phosphor-multi-gpio-monitor "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy config to BMC
scp -P 2222 multi-gpio-monitor.json root@localhost:/etc/phosphor-multi-gpio-monitor.json

# 4. Copy systemd target
scp -P 2222 obmc-chassis-buttons-power-press.target root@localhost:/lib/systemd/system/
ssh -p 2222 root@localhost systemctl daemon-reload

# 5. Restart the monitor
ssh -p 2222 root@localhost systemctl restart phosphor-multi-gpio-monitor
```

## Yocto Integration

To install a custom config from your machine layer:

```bitbake
# In meta-myplatform/recipes-phosphor/gpio/phosphor-multi-gpio-monitor_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://multi-gpio-monitor.json \
    file://presence-monitor.json \
"

do_install:append() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/multi-gpio-monitor.json \
        ${D}${sysconfdir}/phosphor-multi-gpio-monitor.json
    install -m 0644 ${WORKDIR}/presence-monitor.json \
        ${D}${sysconfdir}/phosphor-multi-gpio-presence.json
}
```

## Troubleshooting

```bash
# Check daemon status
systemctl status phosphor-multi-gpio-monitor

# View logs (edge events are logged at info level)
journalctl -u phosphor-multi-gpio-monitor -f

# List all GPIO lines on the system
gpioinfo

# Read current value of a specific GPIO
gpioget gpiochip0 POWER_BUTTON

# Manually trigger an edge (for testing)
gpioset gpiochip0 POWER_BUTTON=0
sleep 0.2
gpioset gpiochip0 POWER_BUTTON=1

# Verify systemd target was activated
systemctl status obmc-chassis-buttons-power-press.target
```

## References

- [phosphor-multi-gpio-monitor](https://github.com/openbmc/phosphor-gpio-monitor) -- upstream repository
- [Linux GPIO chardev API](https://www.kernel.org/doc/html/latest/userspace-api/gpio/chardev.html)
- [OpenBMC Device Tree GPIO naming](https://github.com/openbmc/docs/blob/master/architecture/device-tree-gpio-naming.md)
