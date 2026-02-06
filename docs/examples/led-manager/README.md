# LED Manager Examples

Example configurations and code for phosphor-led-manager.

## Contents

- `led-groups.json` - LED group definitions
- `led-config.yaml` - Physical LED to D-Bus mapping
- `identify-led.sh` - Script to control identify LED

## Related Guide

[LED Manager Guide](../../docs/03-core-services/08-led-manager-guide.md)

## Quick Test

```bash
# Turn on identify LED
busctl set-property xyz.openbmc_project.LED.GroupManager \
    /xyz/openbmc_project/led/groups/enclosure_identify \
    xyz.openbmc_project.Led.Group Asserted b true

# Check LED state
busctl get-property xyz.openbmc_project.LED.GroupManager \
    /xyz/openbmc_project/led/groups/enclosure_identify \
    xyz.openbmc_project.Led.Group Asserted
```
