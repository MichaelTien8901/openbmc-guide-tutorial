# Watchdog Examples

Example configurations for phosphor-watchdog.

## Contents

- `watchdog-config.json` - Watchdog timer configuration
- `watchdog-host.service` - systemd service for host watchdog
- `watchdog-test.sh` - Test script for watchdog functionality

## Related Guide

[Watchdog Guide](../../docs/03-core-services/12-watchdog-guide.md)

## Quick Test

```bash
# Check watchdog status
busctl get-property xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog Enabled

# Enable watchdog
busctl set-property xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog Enabled b true

# Reset (kick) the watchdog
busctl call xyz.openbmc_project.Watchdog \
    /xyz/openbmc_project/watchdog/host0 \
    xyz.openbmc_project.State.Watchdog ResetTimeRemaining
```
