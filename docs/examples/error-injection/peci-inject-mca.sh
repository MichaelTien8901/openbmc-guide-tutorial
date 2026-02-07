#!/bin/bash
#
# PECI MCA Bank Error Injection
#
# Injects Machine Check Architecture (MCA) bank errors via PECI commands to
# simulate Machine Check Exceptions (MCE) on the host CPU. Uses peci_cmds to
# write MCA bank registers (IA32_MC_STATUS, IA32_MC_ADDR) through the PECI
# interface from the BMC.
#
# Usage:
#   ./peci-inject-mca.sh <cpu> <bank>
#   ./peci-inject-mca.sh 0 0              # CPU 0, MCA bank 0 (DCU)
#   ./peci-inject-mca.sh 0 4              # CPU 0, MCA bank 4 (PCU)
#   ./peci-inject-mca.sh 1 9              # CPU 1, MCA bank 9 (CBO)
#   ./peci-inject-mca.sh list             # List MCA bank descriptions
#
# Prerequisites:
#   - Run on the BMC (not the host)
#   - peci_cmds tool installed
#   - PECI interface operational (host powered on)
#   - Root privileges required
#
# WARNING: MCA injection triggers Machine Check Exceptions on the host CPU.
#          This will cause IERR/MCERR signals and likely a host crash. The BMC
#          crash dump handler should collect diagnostic data. Only use on
#          dedicated test systems.

set -euo pipefail

# --- Configuration ---
LOG_TAG="peci-inject-mca"

# Default PECI client addresses (CPU socket addresses)
PECI_ADDR_CPU0="0x30"
PECI_ADDR_CPU1="0x31"

# MCA bank register MSR base addresses
# IA32_MCi_CTL:    0x400 + (bank * 4)
# IA32_MCi_STATUS: 0x401 + (bank * 4)
# IA32_MCi_ADDR:   0x402 + (bank * 4)
# IA32_MCi_MISC:   0x403 + (bank * 4)

# MCA bank descriptions (Intel Xeon Scalable / Ice Lake / Sapphire Rapids)
declare -A BANK_DESCRIPTIONS=(
    [0]="DCU (Data Cache Unit)"
    [1]="IFU (Instruction Fetch Unit)"
    [2]="DTLB (Data Translation Lookaside Buffer)"
    [3]="MLC (Mid-Level Cache)"
    [4]="PCU (Power Control Unit)"
    [5]="IIO (Integrated I/O)"
    [6]="CBO/LLC Slice 0"
    [7]="CBO/LLC Slice 1"
    [8]="CBO/LLC Slice 2"
    [9]="CBO/LLC Slice 3"
    [10]="CBO/LLC Slice 4"
    [11]="CBO/LLC Slice 5"
    [12]="IMC Channel 0 (Integrated Memory Controller)"
    [13]="IMC Channel 1 (Integrated Memory Controller)"
    [14]="IMC Channel 2 (Integrated Memory Controller)"
    [15]="M2M 0 (Mesh to Memory)"
    [16]="M2M 1 (Mesh to Memory)"
)

# Injection patterns for MC_STATUS register
# Bit 63: VAL (valid)
# Bit 62: OVER (overflow)
# Bit 61: UC (uncorrected)
# Bit 60: EN (error reporting enabled)
# Bit 59: MISCV (misc register valid)
# Bit 58: ADDRV (address register valid)
# Bit 57: PCC (processor context corrupt)
# Bits 15:0: MCA error code
#
# Correctable error pattern: VAL + EN + ADDRV
MC_STATUS_CE="0xCC00000000000090"
# Uncorrectable error pattern: VAL + UC + EN + PCC + ADDRV
MC_STATUS_UCE="0xFE00000000000090"

# Simulated error address
MC_ADDR_DEFAULT="0x00000000DEADBEEF"

# --- Helper functions ---

log() {
    logger -t "$LOG_TAG" "$@" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

list_banks() {
    echo "MCA Bank Descriptions (Intel Xeon Scalable)"
    echo ""
    printf "  %-6s %s\n" "BANK" "DESCRIPTION"
    printf "  %-6s %s\n" "----" "-----------"
    for bank in $(seq 0 16); do
        desc="${BANK_DESCRIPTIONS[$bank]:-Unknown}"
        printf "  %-6s %s\n" "$bank" "$desc"
    done
    echo ""
    echo "Register layout per bank:"
    echo "  IA32_MCi_CTL:    MSR 0x400 + (bank * 4)"
    echo "  IA32_MCi_STATUS: MSR 0x401 + (bank * 4)"
    echo "  IA32_MCi_ADDR:   MSR 0x402 + (bank * 4)"
    echo "  IA32_MCi_MISC:   MSR 0x403 + (bank * 4)"
}

get_peci_addr() {
    local cpu=$1
    case "$cpu" in
        0) echo "$PECI_ADDR_CPU0" ;;
        1) echo "$PECI_ADDR_CPU1" ;;
        *) die "Unsupported CPU index: $cpu (supported: 0, 1)" ;;
    esac
}

compute_msr_addr() {
    local bank=$1
    local offset=$2
    printf "0x%X" $(( 0x400 + (bank * 4) + offset ))
}

check_prerequisites() {
    # Must be root
    if [ "$(id -u)" -ne 0 ]; then
        die "Root privileges required. Run with sudo."
    fi

    # Check for peci_cmds
    if ! command -v peci_cmds &>/dev/null; then
        die "peci_cmds not found. Install the peci-pcie package."
    fi
}

verify_peci_connectivity() {
    local peci_addr=$1
    local cpu=$2

    log "Verifying PECI connectivity to CPU ${cpu} (${peci_addr})..."

    if peci_cmds ping -a "$peci_addr" &>/dev/null; then
        log "PECI ping to CPU ${cpu} successful"
        return 0
    else
        die "PECI ping to CPU ${cpu} (${peci_addr}) failed. Is the host powered on?"
    fi
}

confirm_injection() {
    local cpu=$1
    local bank=$2
    local error_mode=$3
    local bank_desc="${BANK_DESCRIPTIONS[$bank]:-Unknown}"

    echo ""
    echo "========================================"
    echo "  WARNING: MCA ERROR INJECTION VIA PECI"
    echo "========================================"
    echo ""
    echo "  Target CPU:     CPU ${cpu}"
    echo "  MCA Bank:       ${bank} - ${bank_desc}"
    echo "  Error mode:     ${error_mode}"
    echo ""

    if [ "$error_mode" = "uce" ]; then
        echo "  *** CRITICAL: UCE injection will trigger IERR/MCERR ***"
        echo "  *** The host will likely crash and reset ***"
        echo "  *** Ensure crash dump collection is enabled on the BMC ***"
        echo ""
    else
        echo "  *** Correctable error injection ***"
        echo "  *** Host should log the error without crashing ***"
        echo ""
    fi

    echo "  MC_STATUS MSR:  $(compute_msr_addr "$bank" 1)"
    echo "  MC_ADDR MSR:    $(compute_msr_addr "$bank" 2)"
    echo "  Date/Time:      $(date)"
    echo ""

    read -r -p "Type 'INJECT' to confirm (anything else to abort): " response
    if [ "$response" != "INJECT" ]; then
        echo "Injection aborted by user."
        exit 0
    fi
}

read_mca_status() {
    local peci_addr=$1
    local bank=$2
    local msr_status
    msr_status=$(compute_msr_addr "$bank" 1)

    log "Reading current MC${bank}_STATUS (MSR ${msr_status})..."
    peci_cmds rdmsr -a "$peci_addr" -s "$msr_status" 2>/dev/null || \
        echo "  (Could not read MSR -- this is normal if host is in reset)"
}

inject_mca_error() {
    local cpu=$1
    local bank=$2
    local error_mode=${3:-uce}
    local peci_addr
    peci_addr=$(get_peci_addr "$cpu")

    local msr_status msr_addr
    msr_status=$(compute_msr_addr "$bank" 1)
    msr_addr=$(compute_msr_addr "$bank" 2)

    local mc_status_value
    if [ "$error_mode" = "ce" ]; then
        mc_status_value="$MC_STATUS_CE"
    else
        mc_status_value="$MC_STATUS_UCE"
    fi

    log "Starting MCA injection: CPU ${cpu}, Bank ${bank}, Mode ${error_mode}"

    # Read current state
    echo ""
    echo "--- Pre-injection MCA State ---"
    read_mca_status "$peci_addr" "$bank"
    echo ""

    # Write MC_ADDR register first (address of the "error")
    log "Writing MC${bank}_ADDR (MSR ${msr_addr}) = ${MC_ADDR_DEFAULT}"
    peci_cmds wrmsr -a "$peci_addr" -s "$msr_addr" -d "$MC_ADDR_DEFAULT" || \
        die "Failed to write MC${bank}_ADDR via PECI"

    # Write MC_STATUS register (this triggers the MCE)
    log "Writing MC${bank}_STATUS (MSR ${msr_status}) = ${mc_status_value}"
    log "Injecting MCA error NOW..."
    peci_cmds wrmsr -a "$peci_addr" -s "$msr_status" -d "$mc_status_value" || \
        die "Failed to write MC${bank}_STATUS via PECI"

    log "MCA injection command sent"

    # Wait for BMC to process the error
    echo ""
    echo "Waiting 10 seconds for BMC error handling..."
    sleep 10

    # Check post-injection state
    echo ""
    echo "--- Post-injection State ---"
    read_mca_status "$peci_addr" "$bank"

    # Check for crash dump
    echo ""
    if [ -d /var/lib/crashdump ]; then
        local dump_count
        dump_count=$(find /var/lib/crashdump -name "*.json" -newer /tmp/.mca_inject_marker 2>/dev/null | wc -l || echo "0")
        log "New crash dump files: ${dump_count}"
    fi

    echo ""
    echo "========================================"
    echo "  MCA Injection Complete"
    echo "========================================"
    echo ""
    echo "  CPU:          ${cpu}"
    echo "  MCA Bank:     ${bank} - ${BANK_DESCRIPTIONS[$bank]:-Unknown}"
    echo "  Error mode:   ${error_mode}"
    echo ""
    echo "  Verify BMC-side:"
    echo "    ipmitool sel list"
    echo "    ls -la /var/lib/crashdump/"
    echo "    journalctl -u crashdump --no-pager -n 20"
    echo "    obmcutil state"
    echo ""
}

# --- Main ---

ACTION="${1:-}"

case "$ACTION" in
    list)
        list_banks
        exit 0
        ;;
    [0-9]*)
        CPU="${1:?Usage: $0 <cpu> <bank> [ce|uce]}"
        BANK="${2:?Usage: $0 <cpu> <bank> [ce|uce]}"
        ERROR_MODE="${3:-uce}"

        if [ "$BANK" -lt 0 ] || [ "$BANK" -gt 31 ]; then
            die "Bank must be between 0 and 31"
        fi

        if [ "$ERROR_MODE" != "ce" ] && [ "$ERROR_MODE" != "uce" ]; then
            die "Error mode must be 'ce' or 'uce'"
        fi

        check_prerequisites

        # Create timestamp marker for crash dump detection
        touch /tmp/.mca_inject_marker 2>/dev/null || true

        PECI_ADDR=$(get_peci_addr "$CPU")
        verify_peci_connectivity "$PECI_ADDR" "$CPU"
        confirm_injection "$CPU" "$BANK" "$ERROR_MODE"
        inject_mca_error "$CPU" "$BANK" "$ERROR_MODE"
        ;;
    "")
        echo "PECI MCA Bank Error Injection"
        echo ""
        echo "Usage: $0 <cpu> <bank> [ce|uce]"
        echo "       $0 list"
        echo ""
        echo "Arguments:"
        echo "  cpu     CPU socket index (0 or 1)"
        echo "  bank    MCA bank number (0-31)"
        echo "  ce|uce  Error mode: correctable or uncorrectable (default: uce)"
        echo ""
        echo "Examples:"
        echo "  $0 0 0          # UCE on CPU 0, bank 0 (DCU)"
        echo "  $0 0 4 ce       # CE on CPU 0, bank 4 (PCU)"
        echo "  $0 1 12 uce     # UCE on CPU 1, bank 12 (IMC)"
        echo "  $0 list         # List MCA bank descriptions"
        echo ""
        echo "WARNING: UCE injection will crash the host. Only use on test systems."
        exit 1
        ;;
    *)
        die "Unknown argument: ${ACTION}. Run '$0' for usage."
        ;;
esac
