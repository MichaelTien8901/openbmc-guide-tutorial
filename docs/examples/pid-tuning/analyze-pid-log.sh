#!/bin/bash
#
# PID Log Analyzer for phosphor-pid-control
#
# Parses CSV log output from phosphor-pid-control (swampd) and computes
# response metrics for each temperature controller: overshoot, settling
# time, steady-state error, and PWM range.
#
# Usage:
#   ./analyze-pid-log.sh <logfile> [setpoint]
#
# Arguments:
#   logfile   - CSV file from phosphor-pid-control logging
#   setpoint  - (optional) override setpoint for analysis (default: auto-detect)
#
# Expected CSV format (phosphor-pid-control output):
#   timestamp,controller,input,setpoint,output
#   1706000000,CPU_Temp_Controller,72.5,80.0,35.2
#   1706000001,CPU_Temp_Controller,73.1,80.0,36.8
#   ...
#
# Prerequisites:
#   - awk (busybox awk on OpenBMC is sufficient)
#   - CSV log captured from phosphor-pid-control
#
# To enable CSV logging on the BMC:
#   busctl set-property xyz.openbmc_project.State.FanCtrl \
#       /xyz/openbmc_project/settings/fanctrl \
#       xyz.openbmc_project.Control.FanCtrl LogEnabled b true
#
#   Log file is written to /tmp/swampd.log
#
# Copy log to host for analysis:
#   scp -P 2222 root@localhost:/tmp/swampd.log ./swampd.log
#   ./analyze-pid-log.sh swampd.log

set -e

LOGFILE="${1:-}"
SETPOINT_OVERRIDE="${2:-}"

if [ -z "$LOGFILE" ]; then
    echo "Usage: $0 <logfile> [setpoint]"
    echo ""
    echo "Parses phosphor-pid-control CSV log and computes PID response metrics."
    echo ""
    echo "Arguments:"
    echo "  logfile   - CSV log file from phosphor-pid-control"
    echo "  setpoint  - (optional) override setpoint value"
    echo ""
    echo "Example:"
    echo "  $0 /tmp/swampd.log"
    echo "  $0 /tmp/swampd.log 80.0"
    exit 1
fi

if [ ! -f "$LOGFILE" ]; then
    echo "Error: File not found: $LOGFILE"
    exit 1
fi

# Count total data lines (skip header)
TOTAL_LINES=$(awk -F',' 'NR > 1 && NF >= 5 { count++ } END { print count+0 }' "$LOGFILE")

if [ "$TOTAL_LINES" -eq 0 ]; then
    echo "Error: No valid CSV data found in $LOGFILE"
    echo "Expected format: timestamp,controller,input,setpoint,output"
    exit 1
fi

echo "========================================"
echo "PID Log Analysis"
echo "========================================"
echo "File: $LOGFILE"
echo "Data points: $TOTAL_LINES"
echo ""

# Extract unique controller names (skip fan controllers -- they use feedforward)
CONTROLLERS=$(awk -F',' 'NR > 1 && NF >= 5 && $2 !~ /Fan|fan/ { print $2 }' "$LOGFILE" | sort -u)

if [ -z "$CONTROLLERS" ]; then
    echo "Warning: No temperature controllers found. Analyzing all controllers."
    CONTROLLERS=$(awk -F',' 'NR > 1 && NF >= 5 { print $2 }' "$LOGFILE" | sort -u)
fi

for CTRL in $CONTROLLERS; do
    echo "----------------------------------------"
    echo "Controller: $CTRL"
    echo "----------------------------------------"

    # Extract data for this controller
    awk -F',' -v ctrl="$CTRL" -v sp_override="$SETPOINT_OVERRIDE" '
    NR > 1 && $2 == ctrl && NF >= 5 {
        ts = $1
        input = $3 + 0
        sp = (sp_override != "") ? sp_override + 0 : $4 + 0
        output = $5 + 0

        n++
        if (n == 1) {
            first_ts = ts
            setpoint = sp
            min_input = input
            max_input = input
            min_output = output
            max_output = output
            sum_error = 0
            sum_abs_error = 0
            max_overshoot = 0
            settled = 0
            settle_ts = ts
        }

        # Track min/max
        if (input < min_input) min_input = input
        if (input > max_input) max_input = input
        if (output < min_output) min_output = output
        if (output > max_output) max_output = output

        # Error calculation (for cooling: positive error = above setpoint)
        error = input - setpoint
        sum_error += error
        abs_error = (error < 0) ? -error : error
        sum_abs_error += abs_error

        # Overshoot: how far above setpoint did temperature go?
        if (error > max_overshoot) max_overshoot = error

        # Settling time: last time error exceeded 2% band around setpoint
        band = setpoint * 0.02
        if (band < 1.0) band = 1.0
        if (abs_error > band) {
            settle_ts = ts
            settled = 0
        } else if (!settled) {
            settled = 1
            settle_ts = ts
        }

        last_ts = ts
        last_input = input
        last_output = output

        # Collect last 10 samples for steady-state analysis
        if (n > 10) {
            ss_count++
            ss_sum += error
            ss_abs_sum += abs_error
        }
    }
    END {
        if (n == 0) {
            print "  No data found for this controller."
            next
        }

        printf "  Setpoint:          %.1f\n", setpoint
        printf "  Samples:           %d\n", n
        duration = last_ts - first_ts
        if (duration > 0) {
            printf "  Duration:          %d seconds\n", duration
        }
        printf "\n"

        # Temperature range
        printf "  Input Range:       %.1f - %.1f\n", min_input, max_input
        printf "  Output Range:      %.1f%% - %.1f%% PWM\n", min_output, max_output
        printf "\n"

        # Overshoot
        if (max_overshoot > 0) {
            overshoot_pct = (max_overshoot / setpoint) * 100
            printf "  Peak Overshoot:    +%.1f C (%.1f%% of setpoint)\n", max_overshoot, overshoot_pct
        } else {
            printf "  Peak Overshoot:    None (stayed at or below setpoint)\n"
        }

        # Settling time (time until error stays within 2% band)
        if (settled && duration > 0) {
            settle_time = settle_ts - first_ts
            printf "  Settling Time:     %d seconds (2%% band = +/-%.1f C)\n", settle_time, band
        } else if (duration > 0) {
            printf "  Settling Time:     Did not settle within recording window\n"
        }

        # Steady-state error (average of last samples after initial transient)
        if (ss_count > 0) {
            ss_avg = ss_sum / ss_count
            ss_abs_avg = ss_abs_sum / ss_count
            printf "  Steady-State Err:  %.2f C (avg), %.2f C (avg absolute)\n", ss_avg, ss_abs_avg
        }

        # Mean absolute error over entire run
        mae = sum_abs_error / n
        printf "  Mean Abs Error:    %.2f C (entire run)\n", mae
        printf "\n"

        # Rating
        if (max_overshoot > 5) {
            printf "  [!] High overshoot -- consider reducing Kp or Ki\n"
        }
        if (!settled && duration > 30) {
            printf "  [!] Did not settle -- check for oscillation, increase Kd or reduce Ki\n"
        }
        if (ss_count > 0 && ss_abs_avg > 2.0) {
            printf "  [!] Large steady-state error -- consider increasing Ki\n"
        }
        if (max_output - min_output > 60 && duration > 60) {
            printf "  [!] Wide PWM swing -- consider adding slew limits\n"
        }
    }
    ' "$LOGFILE"
    echo ""
done

# Summary across all controllers
echo "========================================"
echo "Global Summary"
echo "========================================"
awk -F',' '
NR > 1 && NF >= 5 {
    n++
    if (n == 1) { first_ts = $1 }
    last_ts = $1
    output = $5 + 0
    sum_output += output
}
END {
    if (n == 0) { print "  No data."; next }
    duration = last_ts - first_ts
    avg_output = sum_output / n
    printf "  Total samples:     %d\n", n
    if (duration > 0) {
        printf "  Total duration:    %d seconds\n", duration
    }
    printf "  Avg PWM output:    %.1f%%\n", avg_output
}
' "$LOGFILE"
echo ""
echo "Done. For visualization, import the CSV into a spreadsheet"
echo "or use gnuplot:"
echo ""
echo "  gnuplot -e \"set datafile separator ','; set xlabel 'Time';"
echo "    set ylabel 'Value'; plot '$LOGFILE' using 1:3 title 'Temp',"
echo "    '' using 1:4 title 'Setpoint', '' using 1:5 title 'Output'\""
