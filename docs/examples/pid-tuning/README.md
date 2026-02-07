# PID Thermal Tuning Examples

Example configurations and analysis tools for tuning phosphor-pid-control
thermal management on OpenBMC. These files demonstrate three common tuning
strategies and provide a script to evaluate PID response quality from log data.

> **Requires OpenBMC environment** -- these configurations are consumed by
> `phosphor-pid-control` (swampd) on a booted OpenBMC system (QEMU or hardware).

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image with PID fan control
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " phosphor-pid-control "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy a config to the BMC
scp -P 2222 zone-config-conservative.json root@localhost:/usr/share/swampd/config.json

# 4. Restart the PID controller
ssh -p 2222 root@localhost
systemctl restart phosphor-pid-control

# 5. Collect log data and analyze
#    (on BMC) Enable CSV logging:
busctl set-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/settings/fanctrl \
    xyz.openbmc_project.Control.FanCtrl LogEnabled b true

#    (on host) Copy logs and run analysis:
scp -P 2222 root@localhost:/tmp/swampd.log ./swampd.log
./analyze-pid-log.sh swampd.log
```

## Configuration Files

| File | Strategy | Use Case |
|------|----------|----------|
| `zone-config-conservative.json` | PID with low Kp, moderate Ki, no Kd | General-purpose server; prioritizes stability over fast response |
| `zone-config-aggressive.json` | PID with higher Kp+Ki and derivative damping | Noise-sensitive environments (labs, offices); reaches setpoint quickly |
| `zone-config-stepwise.json` | Stepwise lookup table (no PID) | Simple platforms; deterministic temp-to-PWM mapping with hysteresis |

## Scripts

| Script | Description |
|--------|-------------|
| `analyze-pid-log.sh <logfile>` | Parse phosphor-pid-control CSV log output and compute response metrics (overshoot, settling time, steady-state error) |

## PID Coefficient Reference

phosphor-pid-control uses the following PID parameters:

| Parameter | JSON Key | Description |
|-----------|----------|-------------|
| Kp | `proportionalCoeff` | Proportional gain -- reacts to current error magnitude |
| Ki | `integralCoeff` | Integral gain -- eliminates steady-state error over time (negative = cooling) |
| Kd | `feedFwdOffsetCoeff` | Derivative / feed-forward offset -- dampens oscillation |
| FF | `feedFwdGainCoeff` | Feed-forward gain -- direct mapping (typically 1.0 for fan PIDs) |
| Sample Period | `samplePeriod` | Control loop interval in seconds |
| Slew Positive | `slewPos` | Max PWM increase per cycle (0 = unlimited) |
| Slew Negative | `slewNeg` | Max PWM decrease per cycle (0 = unlimited) |

### Tuning Guidelines

1. **Start conservative** -- use `zone-config-conservative.json` as a baseline
2. **Increase Ki first** -- if temperature drifts above setpoint, increase the
   magnitude of `integralCoeff` (more negative for cooling)
3. **Add Kp for faster response** -- if the system reacts too slowly to load
   spikes, increase `proportionalCoeff`
4. **Use slew limits** -- set `slewPos` and `slewNeg` to prevent abrupt fan
   speed changes that cause audible noise
5. **Avoid Kd unless needed** -- derivative gain amplifies sensor noise; only
   add it if you see oscillation that Ki alone cannot correct
6. **Validate with logs** -- run `analyze-pid-log.sh` on captured CSV data to
   measure overshoot, settling time, and steady-state error

## Deployment Paths

### Direct JSON Configuration

Place the JSON file at `/usr/share/swampd/config.json` on the BMC. This is the
quickest method for testing:

```bash
scp -P 2222 zone-config-conservative.json root@localhost:/usr/share/swampd/config.json
ssh -p 2222 root@localhost systemctl restart phosphor-pid-control
```

### Entity Manager Integration

For production, define PID parameters in Entity Manager JSON and let
phosphor-pid-control read them via D-Bus. See the `entity-manager-fan.json`
example in `../fan-control/` for the Entity Manager format.

## Troubleshooting

```bash
# Check PID controller status
systemctl status phosphor-pid-control

# View real-time logs
journalctl -u phosphor-pid-control -f

# Verify sensor readings
busctl tree xyz.openbmc_project.Sensor

# Check current fan PWM output
cat /sys/class/hwmon/hwmon0/pwm*

# Force failsafe (all fans to 100%)
busctl set-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/settings/fanctrl \
    xyz.openbmc_project.Control.FanCtrl ManualMode b true
```

## References

- [Fan Control Guide](../../03-core-concepts/05-fan-control-guide.md) -- full architecture and configuration details
- [Fan Control Examples](../fan-control/) -- basic zone and stepwise configurations
- [phosphor-pid-control](https://github.com/openbmc/phosphor-pid-control) -- upstream source
- [Entity Manager](https://github.com/openbmc/entity-manager) -- D-Bus-driven hardware configuration
