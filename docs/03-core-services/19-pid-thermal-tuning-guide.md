---
layout: default
title: PID Thermal Tuning
parent: Core Services
nav_order: 19
difficulty: advanced
prerequisites:
  - sensor-guide
  - environment-setup
last_modified_date: 2026-02-06
---

# PID Thermal Tuning
{: .no_toc }

Tune PID coefficients for optimal thermal control using logging, step response analysis, and systematic coefficient adjustment.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The [Fan Control Guide]({% link docs/03-core-services/04-fan-control-guide.md %}) covers the architecture and configuration of phosphor-pid-control. This guide focuses on the practical process of **tuning** PID coefficients so that fan speeds respond correctly to temperature changes on your specific hardware.

Poorly tuned PID loops cause real problems: fans that oscillate audibly, temperatures that overshoot into throttling range, or fans stuck at maximum speed wasting power and generating noise. Tuning is the process of finding coefficient values that balance responsiveness against stability for your particular thermal environment.

**Key concepts covered:**
- PID controller theory (Kp, Ki, Kd) and how each term affects fan behavior
- Zone configuration parameters that interact with tuning
- CSV logging with the `-l` flag for data-driven tuning
- Step response methodology for systematic coefficient adjustment
- When to use stepwise control instead of PID
- Failsafe behavior and how to verify it

{: .warning }
> PID tuning must be performed on actual hardware or a representative thermal simulation. QEMU does not model thermal dynamics, so while you can verify configuration syntax and service startup in QEMU, the tuning values themselves must come from real hardware testing.

---

## PID Controller Theory

### The Control Loop

phosphor-pid-control implements a discrete-time PID controller. Each sample period, the daemon reads sensor values, computes an error signal, and adjusts fan PWM output.

```
┌────────────────────────────────────────────────────────────────────────┐
│                     PID Thermal Control Loop                           │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   setpoint (target temp)                                               │
│        │                                                               │
│        ▼                                                               │
│   ┌─────────┐   error   ┌────────────────────┐  PWM %  ┌──────────┐  │
│   │  error  │──────────▶│   PID Controller    │────────▶│   Fans   │  │
│   │ = SP-PV │           │  P + I + D + FF     │         │  (PWM)   │  │
│   └─────────┘           └────────────────────┘         └────┬─────┘  │
│        ▲                                                     │        │
│        │             ┌──────────────┐                        │        │
│        └─────────────│  Temperature │◀───────────────────────┘        │
│   process variable   │   Sensors    │   thermal effect                │
│       (PV)           └──────────────┘                                 │
│                                                                        │
│   SP  = Setpoint (target temperature, e.g., 80 C)                     │
│   PV  = Process Variable (current temperature reading)                 │
│   error = SP - PV (negative when too hot)                              │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### The Three PID Terms

Each term in the PID equation contributes a different aspect of control behavior:

```
Output = Kp * error  +  Ki * integral(error)  +  Kd * d(error)/dt  +  FF
```

| Term | Coefficient | Effect | Typical OpenBMC Use |
|------|-------------|--------|---------------------|
| **Proportional (P)** | `proportionalCoeff` | Immediate response proportional to error magnitude | Often set to 0.0 for thermal |
| **Integral (I)** | `integralCoeff` | Accumulated response that eliminates steady-state error | Primary tuning parameter (negative for cooling) |
| **Derivative (D)** | `feedFwdOffsetCoeff` | Responds to rate of change, dampens oscillation | Rarely used in thermal control |
| **Feed-forward (FF)** | `feedFwdGainCoeff` | Open-loop term based on setpoint, not error | Used in fan-type PIDs (typically 1.0) |

{: .note }
> In most OpenBMC thermal configurations, the integral term alone provides sufficient control. Start with integral-only control and add proportional gain only if you need faster transient response.

### Why Negative Ki?

The sign convention in phosphor-pid-control requires a negative integral coefficient for cooling:

```
  Scenario: CPU at 85 C, setpoint = 80 C (too hot)

    error = setpoint - temperature = 80 - 85 = -5
    Ki = -0.2 (negative)
    integral += Ki * error * dt = (-0.2) * (-5) * (1.0) = +1.0
    Result: PWM output INCREASES  --> correct

  Scenario: CPU at 75 C, setpoint = 80 C (cool enough)

    error = 80 - 75 = +5
    integral += (-0.2) * (+5) * (1.0) = -1.0
    Result: PWM output DECREASES  --> correct
```

---

## Zone Configuration

Each zone groups sensors and fans into a thermal control region. The zone parameters directly affect tuning behavior.

```json
{
    "zones": [
        {
            "id": 0,
            "minThermalOutput": 25.0,
            "failsafePercent": 100.0
        }
    ]
}
```

| Parameter | Description | Tuning Impact |
|-----------|-------------|---------------|
| `minThermalOutput` | Floor PWM % when zone is active | Sets the minimum fan speed; prevents integral windup below this value |
| `failsafePercent` | PWM % when a sensor is missing or timed out | Should be 100.0 for safety; overrides all PID output |

{: .tip }
> The sensor `timeout` field is critical for tuning. If a sensor does not update within `timeout` seconds, the zone enters failsafe. During tuning, if you see unexpected failsafe events, increase `timeout` or check that the sensor daemon is publishing values at the expected rate.

### PID Controller Parameters

The full set of tunable parameters for each PID controller:

```json
{
    "name": "CPU_Temp_Controller",
    "type": "temp",
    "inputs": ["CPU_Temp"],
    "setpoint": 80.0,
    "pid": {
        "samplePeriod": 1.0,
        "proportionalCoeff": 0.0,
        "integralCoeff": -0.2,
        "feedFwdOffsetCoeff": 0.0,
        "feedFwdGainCoeff": 0.0,
        "integralLimit_min": 0.0,
        "integralLimit_max": 100.0,
        "outLim_min": 25.0,
        "outLim_max": 100.0,
        "slewNeg": 5.0,
        "slewPos": 10.0
    }
}
```

| Parameter | Range | Description |
|-----------|-------|-------------|
| `samplePeriod` | 0.1 - 5.0 s | Control loop interval; shorter = faster response, more CPU |
| `proportionalCoeff` | 0.0 - 2.0 | Proportional gain; usually 0.0 for thermal PIDs |
| `integralCoeff` | -1.0 to -0.01 | Integral gain; primary tuning knob (negative for cooling) |
| `integralLimit_min` | 0.0 | Lower clamp on integral accumulator (anti-windup) |
| `integralLimit_max` | 0.0 - 100.0 | Upper clamp on integral accumulator (anti-windup) |
| `outLim_min` | 0.0 - 100.0 | Minimum PID output (PWM %) |
| `outLim_max` | 0.0 - 100.0 | Maximum PID output (PWM %) |
| `slewNeg` | 0.0 - 20.0 | Max PWM decrease per second (0 = unlimited) |
| `slewPos` | 0.0 - 20.0 | Max PWM increase per second (0 = unlimited) |

### Output Processing Pipeline

After the PID calculation, output goes through several processing stages:

1. **Clamp** to `[outLim_min, outLim_max]` -- limits the raw PID output range
2. **Slew rate** -- limits the rate of change per second (`slewPos` for increases, `slewNeg` for decreases)
3. **Zone arbitration** -- `MAX()` of all PID outputs in the zone (highest demand wins)
4. **Floor clamp** -- ensures output is at least `minThermalOutput`

---

## Tuning Methodology

### Step 1: Enable CSV Logging

phosphor-pid-control supports CSV logging with the `-l` flag. This captures timestamped sensor readings and PID outputs for offline analysis.

```bash
# Stop the running service
systemctl stop phosphor-pid-control

# Run manually with CSV logging enabled
/usr/bin/swampd -l /tmp/pid-log.csv
```

The CSV log contains columns for each sample period:

```
timestamp,zone,sensor_name,sensor_value,setpoint,error,p_term,i_term,d_term,ff_term,output
1706140800,0,CPU_Temp,82.5,80.0,-2.5,0.0,45.2,0.0,0.0,45.2
1706140801,0,CPU_Temp,82.1,80.0,-2.1,0.0,45.6,0.0,0.0,45.6
```

{: .tip }
> Transfer the CSV file to your workstation for analysis. Tools like Python with matplotlib, gnuplot, or a spreadsheet program let you visualize temperature and PWM trends over time.

### Step 2: Establish Baseline

Before tuning PID coefficients, characterize your thermal plant by measuring steady-state temperatures at fixed fan speeds.

```bash
# Switch to manual mode
busctl set-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/control/thermal/0 \
    xyz.openbmc_project.Control.ThermalMode Current s "Manual"

# Test at several fixed PWM levels, waiting for thermal equilibrium
for pwm in 25 40 60 80 100; do
    echo "=== Testing at ${pwm}% PWM ==="
    busctl set-property xyz.openbmc_project.FanSensor \
        /xyz/openbmc_project/control/fanpwm/Fan0 \
        xyz.openbmc_project.Control.FanPwm Target t $pwm
    echo "Waiting 10 minutes for stabilization..."
    sleep 600
    busctl get-property xyz.openbmc_project.HwmonTempSensor \
        /xyz/openbmc_project/sensors/temperature/CPU_Temp \
        xyz.openbmc_project.Sensor.Value Value
done
```

Record the results in a table:

| PWM % | CPU Temp (C) | Inlet Temp (C) | Fan RPM |
|-------|--------------|-----------------|---------|
| 25 | 92 | 38 | 2100 |
| 40 | 85 | 35 | 3500 |
| 60 | 78 | 32 | 5200 |
| 80 | 73 | 29 | 6800 |
| 100 | 69 | 27 | 8500 |

This baseline tells you what PWM range affects temperature, whether your setpoint is achievable, and the approximate plant gain (degrees per PWM %).

### Step 3: Step Response Test

Apply a sudden change in fan speed and observe how temperature responds. This reveals the thermal time constant of your system.

```bash
# Start at 30% PWM, wait for equilibrium, then step to 80%
# Log temperature every 5 seconds for 20 minutes
for i in $(seq 1 240); do
    TEMP=$(busctl get-property xyz.openbmc_project.HwmonTempSensor \
        /xyz/openbmc_project/sensors/temperature/CPU_Temp \
        xyz.openbmc_project.Sensor.Value Value 2>/dev/null | awk '{print $2}')
    echo "$(date +%s),$TEMP" >> /tmp/step-response.csv
    if [ "$i" -eq 60 ]; then
        busctl set-property xyz.openbmc_project.FanSensor \
            /xyz/openbmc_project/control/fanpwm/Fan0 \
            xyz.openbmc_project.Control.FanPwm Target t 80
    fi
    sleep 5
done
```

From the step response data, identify the **time constant (tau)**: the time for temperature to reach 63% of its total change. Use tau to calculate an initial Ki:

```
Ki_initial = -1.0 / (2 * tau)
Example: tau = 120s --> Ki = -1.0 / 240 = -0.004
```

### Step 4: Set Initial Coefficients

Configure conservative initial PID values based on the step response:

```json
{
    "samplePeriod": 1.0,
    "proportionalCoeff": 0.0,
    "integralCoeff": -0.05,
    "feedFwdOffsetCoeff": 0.0,
    "feedFwdGainCoeff": 0.0,
    "integralLimit_min": 0.0,
    "integralLimit_max": 100.0,
    "outLim_min": 25.0,
    "outLim_max": 100.0,
    "slewNeg": 0.0,
    "slewPos": 0.0
}
```

{: .note }
> Start with slew rates at 0.0 (unlimited) during initial tuning. Add slew rate limits after the basic PID response is satisfactory, as slew limits mask PID behavior and make it harder to diagnose coefficient problems.

### Step 5: Iterative Adjustment

Run phosphor-pid-control with CSV logging and apply a thermal load. Observe the logged data and adjust coefficients.

```bash
systemctl stop phosphor-pid-control
/usr/bin/swampd -l /tmp/tuning-round1.csv
```

**Diagnosing common problems from CSV data:**

| Problem | CSV Clue | Fix |
|---------|----------|-----|
| **Response too slow** (temperature overshoots setpoint) | `error` stays large for many samples | Increase `|Ki|` (e.g., -0.05 to -0.1) |
| **Oscillation** (fans hunt up and down) | `output` alternates high/low periodically | Decrease `|Ki|` (e.g., -0.2 to -0.1); add slew limits |
| **Steady-state offset** (never reaches setpoint) | `error` stabilizes at non-zero value | Check `outLim_max`; increase `|Ki|` slightly |
| **Fans jump to max then slowly decrease** | `p_term` has large values | Reduce `Kp` or set to 0.0 |
| **Integral windup** (fans stay at max after load drops) | `i_term` stays at `integralLimit_max` | Reduce `integralLimit_max` or `|Ki|` |

### Step 6: Add Slew Rates

Once the PID coefficients produce stable control, add slew rate limits to smooth fan speed transitions:

```json
{
    "slewPos": 10.0,
    "slewNeg": 5.0
}
```

- `slewPos`: Max PWM increase per second (10.0 = fans can ramp up 10%/s)
- `slewNeg`: Max PWM decrease per second (asymmetric for slow ramp-down)

{: .warning }
> Setting `slewPos` too low can prevent fans from responding quickly enough to thermal spikes. Verify that slew-limited ramp-up is fast enough to prevent temperature from reaching critical thresholds under worst-case load transients.

### Step 7: Validate Under Load Scenarios

Test the tuned configuration across representative workloads:

1. **Cold boot**: Host powers on from cold state, temperature ramps up
2. **Idle to full load**: Apply CPU stress test, observe response
3. **Full load to idle**: Remove workload, observe fan speed reduction
4. **Sustained load**: Run full load for 30+ minutes, verify no drift
5. **Sensor failure**: Disconnect a sensor, verify failsafe activates

---

## Stepwise vs PID Comparison

phosphor-pid-control supports two control strategies. Choose based on your requirements.

### Stepwise Control

Stepwise uses a static lookup table to map temperature to PWM percentage:

```json
{
    "name": "Inlet_Stepwise",
    "type": "stepwise",
    "inputs": ["Inlet_Temp"],
    "reading": {
        "positiveHysteresis": 2.0,
        "negativeHysteresis": 2.0
    },
    "output": [
        { "temp": 0,  "pwm": 20 },
        { "temp": 25, "pwm": 35 },
        { "temp": 30, "pwm": 50 },
        { "temp": 35, "pwm": 65 },
        { "temp": 40, "pwm": 80 },
        { "temp": 45, "pwm": 100 }
    ]
}
```

### Comparison Table

| Characteristic | PID Control | Stepwise Control |
|----------------|-------------|------------------|
| **Tuning effort** | High (step response, iteration) | Low (define temperature-PWM table) |
| **Precision** | Maintains setpoint accurately | Steps between fixed PWM levels |
| **Noise behavior** | Smooth fan speed transitions | Discrete jumps (mitigated by hysteresis) |
| **Transient response** | Adapts dynamically to load changes | Fixed mapping, no adaptation |
| **CPU overhead** | Slightly more (PID math per sample) | Minimal (table lookup) |
| **Best for** | CPU/GPU thermal (tight control) | Inlet/ambient (coarse control) |

**Use PID when** you need to maintain a specific temperature setpoint, the thermal load is dynamic, or you need smooth continuous fan adjustment.

**Use stepwise when** simple temperature-to-fan mapping is sufficient, you want deterministic behavior with no tuning, or the temperature range is well-characterized and stable.

{: .tip }
> You can combine both strategies in a single zone. Use PID for CPU temperature and stepwise for inlet temperature, both in the same zone. Zone arbitration takes the MAX output, so the more aggressive demand always wins.

---

## Failsafe Behavior

### What Triggers Failsafe

When a zone enters failsafe mode, all fans in that zone are driven to `failsafePercent` (typically 100%). Failsafe triggers when:

1. **Sensor timeout** -- a configured input sensor has not updated within its `timeout` period
2. **Sensor missing** -- a required sensor D-Bus object does not exist (daemon not started or crashed)
3. **Sensor value NaN** -- the sensor reports NaN, indicating a hardware read failure

Recovery is automatic when all sensors return valid readings for a sustained period.

### Verifying Failsafe

Test failsafe behavior before deploying to production:

```bash
# Stop a sensor daemon to simulate sensor loss
systemctl stop xyz.openbmc_project.hwmontempsensor

# Confirm fans go to failsafe
journalctl -u phosphor-pid-control -f | grep -i failsafe

# Restart sensor daemon, verify recovery
systemctl start xyz.openbmc_project.hwmontempsensor
```

{: .warning }
> Never set `failsafePercent` below 100.0 on production systems. The failsafe condition means the system cannot determine actual temperatures, so maximum cooling is the only safe response.

### Failsafe and Tuning Interaction

During PID tuning, unexpected failsafe events are a common source of confusion. If your tuning session is interrupted by failsafe:

1. Check `journalctl -u phosphor-pid-control` for the specific reason
2. Verify all sensor daemons are running: `systemctl list-units | grep sensor`
3. Verify sensor `timeout` values are larger than the sensor polling interval
4. If using `-l` logging, check whether the sensor value column shows NaN entries

---

## Practical Tuning Example

This walkthrough illustrates the iterative tuning process for a single-zone configuration.

**Round 1** -- conservative Ki = -0.05:

```bash
systemctl stop phosphor-pid-control
/usr/bin/swampd -l /tmp/round1.csv
# Apply load, wait 15 minutes, observe CSV
```

Observation: Temperature rises to 88 C before fans respond. Integral accumulates too slowly.

**Round 2** -- increase Ki to -0.15:

Update `integralCoeff` to `-0.15`, restart. Temperature peaks at 83 C, settles to 80.5 C. No oscillation.

**Round 3** -- add slew rates (`slewPos: 10.0`, `slewNeg: 5.0`):

Fan transitions become smooth. Temperature peaks at 84 C due to slew limiting the ramp-up, but settles within acceptable range.

**Final validated coefficients:**

```json
{
    "samplePeriod": 1.0,
    "proportionalCoeff": 0.0,
    "integralCoeff": -0.15,
    "integralLimit_min": 0.0,
    "integralLimit_max": 100.0,
    "outLim_min": 25.0,
    "outLim_max": 100.0,
    "slewNeg": 5.0,
    "slewPos": 10.0
}
```

---

## Troubleshooting

### Issue: Fans Stuck at Maximum Speed

**Symptom**: All fans run at 100% even though temperatures are normal.

**Cause**: Zone is in failsafe due to a missing or timed-out sensor.

**Solution**:
1. Check the journal: `journalctl -u phosphor-pid-control | grep -i failsafe`
2. Verify sensors on D-Bus: `busctl tree xyz.openbmc_project.HwmonTempSensor`
3. Check sensor daemon: `systemctl status xyz.openbmc_project.hwmontempsensor`

### Issue: Temperature Oscillates Around Setpoint

**Symptom**: Temperature swings 5-10 C above and below setpoint periodically.

**Cause**: Integral gain too aggressive, or output limits too wide.

**Solution**:
1. Reduce `|integralCoeff|` by half (e.g., -0.2 to -0.1)
2. Add or tighten slew rate limits
3. Reduce `integralLimit_max` to prevent windup
4. Enable CSV logging to measure oscillation period and amplitude

### Issue: Fans Do Not Respond to Temperature Changes

**Symptom**: Fan speed remains constant despite rising temperature.

**Cause**: Configuration mismatch between sensor names in PID config and actual D-Bus sensor names.

**Solution**:
1. Verify the sensor name in `inputs` matches the sensor config `name` field
2. Check that thermal PID `type` is `"temp"` and fan PID `type` is `"fan"`
3. Verify the zone ID in the fan config matches the zone used by the thermal PID
4. Run in debug mode: `/usr/bin/swampd -d`

### Debug Commands

```bash
# Check service status and recent logs
systemctl status phosphor-pid-control
journalctl -u phosphor-pid-control -n 50

# Verify zone control mode
busctl get-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/control/thermal/0 \
    xyz.openbmc_project.Control.ThermalMode Current

# Read current sensor values
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Run daemon with debug output
/usr/bin/swampd -d

# Run daemon with CSV logging
/usr/bin/swampd -l /tmp/pid-debug.csv
```

---

## Code Examples

Working example configurations are available in the [examples/pid-tuning/](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/pid-tuning/) directory:

- `tuning-baseline-config.json` -- Conservative starting configuration for a single zone
- `tuning-final-config.json` -- Tuned configuration after iterative adjustment
- `stepwise-inlet-config.json` -- Stepwise configuration for inlet temperature
- `multi-sensor-zone-config.json` -- Multi-sensor zone with PID and stepwise combined

Also see the [examples/fan-control/](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/fan-control/) directory for complete zone and entity manager configurations.

---

## References

### Official Resources
- [phosphor-pid-control Repository](https://github.com/openbmc/phosphor-pid-control)
- [phosphor-pid-control README](https://github.com/openbmc/phosphor-pid-control/blob/master/README.md)
- [PID Algorithm Implementation](https://github.com/openbmc/phosphor-pid-control/blob/master/pid/ec/pid.cpp)
- [Zone Management Source](https://github.com/openbmc/phosphor-pid-control/blob/master/pid/zone.cpp)

### Related Guides
- [Fan Control Guide]({% link docs/03-core-services/04-fan-control-guide.md %})
- [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %})
- [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %})

### External Documentation
- [PID Controller Theory (Wikipedia)](https://en.wikipedia.org/wiki/PID_controller)
- [Ziegler-Nichols Tuning Method](https://en.wikipedia.org/wiki/Ziegler%E2%80%93Nichols_method)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus (configuration syntax only; tuning values require real hardware)
Last updated: 2026-02-06
