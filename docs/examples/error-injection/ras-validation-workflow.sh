#!/bin/bash
#
# RAS Validation Workflow
#
# Comprehensive end-to-end RAS (Reliability, Availability, Serviceability)
# validation workflow that runs from the BMC. Injects correctable errors,
# uncorrectable errors, and PCIe errors, then verifies the expected BMC-side
# responses (SEL entries, crash dumps, event logs).
#
# Workflow steps:
#   1. Pre-flight checks (PECI connectivity, services, SEL baseline)
#   2. Inject correctable memory error (CE) via PECI --> verify SEL entry
#   3. Inject machine check exception (MCE) via PECI --> verify crash dump
#   4. Inject PCIe error via PECI --> verify event log
#   5. Summary report
#
# Usage:
#   ./ras-validation-workflow.sh              # Run full workflow
#   ./ras-validation-workflow.sh --skip-mce   # Skip MCE (host-crashing) test
#   ./ras-validation-workflow.sh --dry-run    # Check prerequisites only
#
# Prerequisites:
#   - Run on the BMC (not the host)
#   - Host must be powered on
#   - peci_cmds tool installed
#   - Crash dump service enabled
#   - Root privileges required
#
# WARNING: This workflow injects real hardware errors. Step 3 (MCE injection)
#          will crash the host. Only run on dedicated test systems. Use
#          --skip-mce to skip the host-crashing test.

set -euo pipefail

# --- Configuration ---
LOG_TAG="ras-validation"
LOG_FILE="/tmp/ras-validation-$(date '+%Y%m%d-%H%M%S').log"
PECI_ADDR_CPU0="0x30"
CRASH_DUMP_DIR="/var/lib/crashdump"
WAIT_CE_SEC=10
WAIT_MCE_SEC=30
WAIT_PCIE_SEC=10
WAIT_HOST_RECOVERY_SEC=120

# MCA bank register MSR addresses
# Bank 12 = IMC Channel 0 (good for memory error injection)
MCA_BANK_CE=12
MCA_MSR_STATUS_BANK12="0x431"    # 0x401 + (12 * 4) = 0x431
MCA_MSR_ADDR_BANK12="0x432"     # 0x402 + (12 * 4) = 0x432

# Bank 0 = DCU (good for MCE/crash injection)
MCA_BANK_MCE=0
MCA_MSR_STATUS_BANK0="0x401"    # 0x401 + (0 * 4)
MCA_MSR_ADDR_BANK0="0x402"      # 0x402 + (0 * 4)

# Bank 5 = IIO (good for PCIe error injection)
MCA_BANK_PCIE=5
MCA_MSR_STATUS_BANK5="0x415"    # 0x401 + (5 * 4) = 0x415
MCA_MSR_ADDR_BANK5="0x416"      # 0x402 + (5 * 4) = 0x416

# MC_STATUS patterns
MC_STATUS_CE="0xCC00000000000090"      # VAL + EN + ADDRV, correctable
MC_STATUS_UCE="0xFE00000000000090"     # VAL + UC + EN + PCC + ADDRV
MC_STATUS_PCIE="0xCC00000000000070"    # VAL + EN + ADDRV, PCIe error code
MC_ADDR_DEFAULT="0x00000000DEADBEEF"

# --- State tracking ---
SKIP_MCE=false
DRY_RUN=false
PASS=0
FAIL=0
SKIP=0

# --- Helper functions ---

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
    logger -t "$LOG_TAG" "$*" 2>/dev/null || true
}

pass() {
    echo "  [PASS] $1"
    echo "  [PASS] $1" >> "$LOG_FILE"
    PASS=$((PASS + 1))
}

fail() {
    echo "  [FAIL] $1"
    echo "  [FAIL] $1" >> "$LOG_FILE"
    FAIL=$((FAIL + 1))
}

skip() {
    echo "  [SKIP] $1"
    echo "  [SKIP] $1" >> "$LOG_FILE"
    SKIP=$((SKIP + 1))
}

die() {
    log "FATAL: $*"
    exit 1
}

separator() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
    echo ""
}

confirm_workflow() {
    echo ""
    echo "========================================"
    echo "  WARNING: RAS VALIDATION WORKFLOW"
    echo "========================================"
    echo ""
    echo "  This workflow will inject the following errors:"
    echo ""
    echo "    1. Correctable memory error (CE)"
    echo "       Expected: SEL entry logged, no host impact"
    echo ""
    if [ "$SKIP_MCE" = true ]; then
        echo "    2. Machine Check Exception (MCE) -- SKIPPED"
        echo ""
    else
        echo "    2. Machine Check Exception (MCE)"
        echo "       Expected: HOST CRASH, crash dump collected"
        echo ""
    fi
    echo "    3. PCIe error via IIO MCA bank"
    echo "       Expected: SEL/event entry logged"
    echo ""
    echo "  Log file: ${LOG_FILE}"
    echo "  Date/Time: $(date)"
    echo ""

    if [ "$SKIP_MCE" = false ]; then
        echo "  *** WARNING: Step 2 WILL crash the host ***"
        echo ""
    fi

    read -r -p "Type 'RUN' to start the workflow (anything else to abort): " response
    if [ "$response" != "RUN" ]; then
        echo "Workflow aborted by user."
        exit 0
    fi
}

get_sel_entries() {
    # Return list of SEL entries as text (via ipmitool or busctl)
    if command -v ipmitool &>/dev/null; then
        ipmitool sel list 2>/dev/null || echo ""
    else
        # Fallback to D-Bus
        busctl tree xyz.openbmc_project.Logging 2>/dev/null | \
            grep "/xyz/openbmc_project/logging/entry/" || echo ""
    fi
}

get_sel_count() {
    if command -v ipmitool &>/dev/null; then
        ipmitool sel info 2>/dev/null | grep "Entries" | awk '{print $3}' || echo "0"
    else
        busctl tree xyz.openbmc_project.Logging 2>/dev/null | \
            grep -c "/xyz/openbmc_project/logging/entry/" || echo "0"
    fi
}

get_crashdump_count() {
    if [ -d "$CRASH_DUMP_DIR" ]; then
        find "$CRASH_DUMP_DIR" -name "*.json" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

get_host_state() {
    obmcutil state 2>/dev/null | grep "CurrentHostState" | awk -F'.' '{print $NF}' || echo "Unknown"
}

wait_for_host_state() {
    local expected=$1
    local timeout=$2
    local count=0

    log "Waiting for host state '${expected}' (timeout: ${timeout}s)..."
    while [ $count -lt "$timeout" ]; do
        local state
        state=$(get_host_state)
        if [ "$state" = "$expected" ]; then
            log "Host reached state: ${expected}"
            return 0
        fi
        sleep 5
        count=$((count + 5))
        if [ $((count % 30)) -eq 0 ]; then
            log "  Still waiting... current state: ${state} (${count}s/${timeout}s)"
        fi
    done

    log "Timeout waiting for host state '${expected}' (last state: $(get_host_state))"
    return 1
}

# ============================================================
# Pre-flight Checks
# ============================================================

preflight_checks() {
    separator "Step 0: Pre-flight Checks"

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        die "Root privileges required. Run with sudo."
    fi
    pass "Running as root"

    # peci_cmds available
    if command -v peci_cmds &>/dev/null; then
        pass "peci_cmds tool found"
    else
        fail "peci_cmds not found"
        die "Cannot proceed without peci_cmds"
    fi

    # PECI connectivity
    if peci_cmds ping -a "$PECI_ADDR_CPU0" &>/dev/null; then
        pass "PECI ping to CPU 0 (${PECI_ADDR_CPU0}) successful"
    else
        fail "PECI ping to CPU 0 failed"
        die "Cannot proceed without PECI connectivity"
    fi

    # Host power state
    local host_state
    host_state=$(get_host_state)
    if [ "$host_state" = "Running" ]; then
        pass "Host is powered on (state: ${host_state})"
    else
        fail "Host is not running (state: ${host_state})"
        die "Host must be powered on for error injection"
    fi

    # Crash dump service
    if systemctl is-active --quiet crashdump 2>/dev/null; then
        pass "crashdump service is running"
    elif systemctl is-enabled --quiet crashdump 2>/dev/null; then
        pass "crashdump service is enabled (will activate on trigger)"
    else
        fail "crashdump service is not enabled"
        log "  Try: systemctl enable crashdump"
    fi

    # Logging service
    if busctl list 2>/dev/null | grep -q "xyz.openbmc_project.Logging"; then
        pass "OpenBMC Logging service is active"
    else
        fail "OpenBMC Logging service not found"
    fi

    # Record baseline counts
    SEL_BASELINE=$(get_sel_count)
    DUMP_BASELINE=$(get_crashdump_count)
    log "Baseline SEL entries: ${SEL_BASELINE}"
    log "Baseline crash dumps: ${DUMP_BASELINE}"
}

# ============================================================
# Step 1: Correctable Error (CE) Injection
# ============================================================

step_inject_ce() {
    separator "Step 1: Correctable Memory Error (CE) Injection"

    local sel_before
    sel_before=$(get_sel_count)
    log "SEL entries before CE injection: ${sel_before}"

    # Inject CE via PECI: write MC_ADDR then MC_STATUS for bank 12 (IMC)
    log "Injecting CE on CPU 0, MCA bank ${MCA_BANK_CE} (IMC Channel 0)..."
    log "  Writing MC${MCA_BANK_CE}_ADDR (MSR ${MCA_MSR_ADDR_BANK12}) = ${MC_ADDR_DEFAULT}"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_ADDR_BANK12" -d "$MC_ADDR_DEFAULT" || {
        fail "Failed to write MC_ADDR via PECI"
        return 1
    }

    log "  Writing MC${MCA_BANK_CE}_STATUS (MSR ${MCA_MSR_STATUS_BANK12}) = ${MC_STATUS_CE}"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_STATUS_BANK12" -d "$MC_STATUS_CE" || {
        fail "Failed to write MC_STATUS via PECI"
        return 1
    }

    log "CE injection sent. Waiting ${WAIT_CE_SEC}s for BMC processing..."
    sleep "$WAIT_CE_SEC"

    # Verify: check for new SEL entry
    local sel_after
    sel_after=$(get_sel_count)
    log "SEL entries after CE injection: ${sel_after}"

    if [ "$sel_after" -gt "$sel_before" ]; then
        pass "New SEL entry detected after CE injection (${sel_before} -> ${sel_after})"
    else
        fail "No new SEL entry after CE injection (count unchanged: ${sel_after})"
    fi

    # Verify: host should still be running
    local host_state
    host_state=$(get_host_state)
    if [ "$host_state" = "Running" ]; then
        pass "Host still running after CE injection (expected)"
    else
        fail "Host state changed after CE: ${host_state} (expected: Running)"
    fi

    return 0
}

# ============================================================
# Step 2: Machine Check Exception (MCE) Injection
# ============================================================

step_inject_mce() {
    separator "Step 2: Machine Check Exception (MCE) Injection"

    if [ "$SKIP_MCE" = true ]; then
        skip "MCE injection skipped (--skip-mce flag)"
        return 0
    fi

    local sel_before dump_before
    sel_before=$(get_sel_count)
    dump_before=$(get_crashdump_count)
    log "SEL entries before MCE injection: ${sel_before}"
    log "Crash dumps before MCE injection: ${dump_before}"

    # Inject UCE via PECI: write MC_ADDR then MC_STATUS for bank 0 (DCU)
    log "Injecting UCE (MCE) on CPU 0, MCA bank ${MCA_BANK_MCE} (DCU)..."
    log "  Writing MC${MCA_BANK_MCE}_ADDR (MSR ${MCA_MSR_ADDR_BANK0}) = ${MC_ADDR_DEFAULT}"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_ADDR_BANK0" -d "$MC_ADDR_DEFAULT" || {
        fail "Failed to write MC_ADDR via PECI"
        return 1
    }

    log "  Writing MC${MCA_BANK_MCE}_STATUS (MSR ${MCA_MSR_STATUS_BANK0}) = ${MC_STATUS_UCE}"
    log "  *** Host crash expected ***"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_STATUS_BANK0" -d "$MC_STATUS_UCE" || {
        fail "Failed to write MC_STATUS via PECI"
        return 1
    }

    log "MCE injection sent. Waiting ${WAIT_MCE_SEC}s for crash dump collection..."
    sleep "$WAIT_MCE_SEC"

    # Verify: check for new crash dump
    local dump_after
    dump_after=$(get_crashdump_count)
    log "Crash dumps after MCE injection: ${dump_after}"

    if [ "$dump_after" -gt "$dump_before" ]; then
        pass "New crash dump collected after MCE injection (${dump_before} -> ${dump_after})"
        # Show the latest dump file
        local latest_dump
        latest_dump=$(find "$CRASH_DUMP_DIR" -name "*.json" -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | tail -1 | awk '{print $2}' || echo "")
        if [ -n "$latest_dump" ]; then
            log "  Latest dump: ${latest_dump}"
            log "  Dump size: $(du -h "$latest_dump" 2>/dev/null | awk '{print $1}')"
        fi
    else
        fail "No new crash dump after MCE injection (count unchanged: ${dump_after})"
    fi

    # Verify: check for new SEL entries
    local sel_after
    sel_after=$(get_sel_count)
    if [ "$sel_after" -gt "$sel_before" ]; then
        pass "New SEL entries after MCE injection (${sel_before} -> ${sel_after})"
    else
        fail "No new SEL entries after MCE injection"
    fi

    # Wait for host recovery (if auto-restart is configured)
    log "Waiting for host recovery (timeout: ${WAIT_HOST_RECOVERY_SEC}s)..."
    if wait_for_host_state "Running" "$WAIT_HOST_RECOVERY_SEC"; then
        pass "Host recovered after MCE injection"
    else
        local final_state
        final_state=$(get_host_state)
        log "Host did not auto-recover (state: ${final_state})"
        log "Attempting manual power on..."
        obmcutil poweron 2>/dev/null || true
        sleep 30
        final_state=$(get_host_state)
        if [ "$final_state" = "Running" ]; then
            pass "Host recovered after manual power on"
        else
            fail "Host did not recover (state: ${final_state})"
            log "  Manual intervention may be required"
        fi
    fi

    return 0
}

# ============================================================
# Step 3: PCIe Error Injection
# ============================================================

step_inject_pcie() {
    separator "Step 3: PCIe Error Injection"

    # Verify host is running
    local host_state
    host_state=$(get_host_state)
    if [ "$host_state" != "Running" ]; then
        fail "Host is not running (state: ${host_state}), cannot inject PCIe error"
        skip "PCIe error injection skipped (host not running)"
        return 1
    fi

    # Re-verify PECI connectivity
    if ! peci_cmds ping -a "$PECI_ADDR_CPU0" &>/dev/null; then
        fail "PECI connectivity lost"
        skip "PCIe error injection skipped (no PECI)"
        return 1
    fi

    local sel_before
    sel_before=$(get_sel_count)
    log "SEL entries before PCIe injection: ${sel_before}"

    # Inject PCIe error via PECI: write MC_STATUS for bank 5 (IIO)
    log "Injecting PCIe error on CPU 0, MCA bank ${MCA_BANK_PCIE} (IIO)..."
    log "  Writing MC${MCA_BANK_PCIE}_ADDR (MSR ${MCA_MSR_ADDR_BANK5}) = ${MC_ADDR_DEFAULT}"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_ADDR_BANK5" -d "$MC_ADDR_DEFAULT" || {
        fail "Failed to write MC_ADDR via PECI"
        return 1
    }

    log "  Writing MC${MCA_BANK_PCIE}_STATUS (MSR ${MCA_MSR_STATUS_BANK5}) = ${MC_STATUS_PCIE}"
    peci_cmds wrmsr -a "$PECI_ADDR_CPU0" -s "$MCA_MSR_STATUS_BANK5" -d "$MC_STATUS_PCIE" || {
        fail "Failed to write MC_STATUS via PECI"
        return 1
    }

    log "PCIe error injection sent. Waiting ${WAIT_PCIE_SEC}s for BMC processing..."
    sleep "$WAIT_PCIE_SEC"

    # Verify: check for new SEL/event entry
    local sel_after
    sel_after=$(get_sel_count)
    log "SEL entries after PCIe injection: ${sel_after}"

    if [ "$sel_after" -gt "$sel_before" ]; then
        pass "New SEL/event entry detected after PCIe error injection (${sel_before} -> ${sel_after})"
    else
        fail "No new SEL/event entry after PCIe error injection (count unchanged: ${sel_after})"
    fi

    # Verify: host should still be running (correctable PCIe error)
    host_state=$(get_host_state)
    if [ "$host_state" = "Running" ]; then
        pass "Host still running after PCIe error injection (expected)"
    else
        fail "Host state changed after PCIe error: ${host_state}"
    fi

    return 0
}

# ============================================================
# Summary Report
# ============================================================

print_summary() {
    separator "RAS Validation Summary"

    local total=$((PASS + FAIL + SKIP))

    echo "  Results:"
    echo "    Passed:  ${PASS}"
    echo "    Failed:  ${FAIL}"
    echo "    Skipped: ${SKIP}"
    echo "    Total:   ${total}"
    echo ""
    echo "  Log file: ${LOG_FILE}"
    echo ""

    # Final SEL and dump counts
    local sel_final dump_final
    sel_final=$(get_sel_count)
    dump_final=$(get_crashdump_count)
    echo "  Final SEL entries:  ${sel_final} (baseline: ${SEL_BASELINE:-0})"
    echo "  Final crash dumps:  ${dump_final} (baseline: ${DUMP_BASELINE:-0})"
    echo ""

    # Host state
    echo "  Host state: $(get_host_state)"
    echo ""

    if [ "$FAIL" -gt 0 ]; then
        echo "  RESULT: FAIL (${FAIL} test(s) failed)"
        echo ""
        echo "  Troubleshooting:"
        echo "    journalctl -u crashdump --no-pager -n 50"
        echo "    journalctl -u peci-pcie --no-pager -n 50"
        echo "    ipmitool sel list"
        echo "    cat ${LOG_FILE}"
        exit 1
    else
        echo "  RESULT: PASS (all checks passed)"
    fi
}

# --- Argument parsing ---

SEL_BASELINE="0"
DUMP_BASELINE="0"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-mce)
            SKIP_MCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "RAS Validation Workflow"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-mce    Skip MCE injection (avoids host crash)"
            echo "  --dry-run     Run pre-flight checks only"
            echo "  --help        Show this help message"
            echo ""
            echo "Workflow steps:"
            echo "  0. Pre-flight checks (PECI, services, baseline)"
            echo "  1. Inject correctable error (CE) --> verify SEL entry"
            echo "  2. Inject machine check (MCE) --> verify crash dump"
            echo "  3. Inject PCIe error --> verify event log"
            echo "  4. Print summary report"
            echo ""
            echo "WARNING: Step 2 will crash the host. Use --skip-mce to skip."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# --- Main workflow ---

log "RAS Validation Workflow started"
log "Options: skip-mce=${SKIP_MCE}, dry-run=${DRY_RUN}"
log "Log file: ${LOG_FILE}"

preflight_checks

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "Dry run complete. Pre-flight checks passed."
    echo "Run without --dry-run to execute the full workflow."
    exit 0
fi

confirm_workflow

step_inject_ce
step_inject_mce
step_inject_pcie
print_summary
