#!/bin/bash
#
# ACPI EINJ Error Injection
#
# Injects hardware errors via the ACPI Error INJection (EINJ) sysfs interface.
# Supports correctable memory errors, uncorrectable memory errors, and PCIe
# fatal errors. Each injection requires explicit user confirmation.
#
# Usage:
#   ./einj-inject-error.sh <error-type>
#   ./einj-inject-error.sh ce             # Correctable memory error
#   ./einj-inject-error.sh uce            # Uncorrectable memory error (non-fatal)
#   ./einj-inject-error.sh fatal          # Uncorrectable memory error (fatal)
#   ./einj-inject-error.sh pcie-ce        # PCIe correctable error
#   ./einj-inject-error.sh pcie-fatal     # PCIe fatal error
#   ./einj-inject-error.sh list           # List available error types
#
# Prerequisites:
#   - Run on the host (not the BMC)
#   - ACPI EINJ enabled in BIOS/UEFI
#   - Kernel module loaded: modprobe einj
#   - Root privileges required
#
# WARNING: This script injects real hardware errors. Uncorrectable and fatal
#          errors can cause system crashes, data corruption, and unexpected
#          reboots. Only use on dedicated test systems.

set -euo pipefail

# --- Configuration ---
EINJ_PATH="/sys/kernel/debug/apei/einj"
LOG_TAG="einj-inject"

# EINJ error type codes (ACPI 6.4, Table 18-389)
declare -A ERROR_TYPES=(
    [ce]="0x00000008"
    [uce]="0x00000010"
    [fatal]="0x00000020"
    [pcie-ce]="0x00000040"
    [pcie-uce]="0x00000080"
    [pcie-fatal]="0x00000100"
)

declare -A ERROR_DESCRIPTIONS=(
    [ce]="Correctable Memory Error"
    [uce]="Uncorrectable Memory Error (non-fatal)"
    [fatal]="Uncorrectable Memory Error (fatal)"
    [pcie-ce]="PCIe Correctable Error"
    [pcie-uce]="PCIe Uncorrectable Error (non-fatal)"
    [pcie-fatal]="PCIe Fatal Error"
)

declare -A ERROR_SEVERITY=(
    [ce]="LOW"
    [uce]="HIGH"
    [fatal]="CRITICAL"
    [pcie-ce]="LOW"
    [pcie-uce]="HIGH"
    [pcie-fatal]="CRITICAL"
)

# --- Helper functions ---

log() {
    logger -t "$LOG_TAG" "$@" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

die() {
    echo "Error: $*" >&2
    exit 1
}

list_error_types() {
    echo "Available EINJ error types:"
    echo ""
    printf "  %-12s %-45s %-10s %s\n" "TYPE" "DESCRIPTION" "SEVERITY" "CODE"
    printf "  %-12s %-45s %-10s %s\n" "----" "-----------" "--------" "----"
    for type in ce uce fatal pcie-ce pcie-uce pcie-fatal; do
        printf "  %-12s %-45s %-10s %s\n" \
            "$type" \
            "${ERROR_DESCRIPTIONS[$type]}" \
            "${ERROR_SEVERITY[$type]}" \
            "${ERROR_TYPES[$type]}"
    done
    echo ""
    echo "Supported types on this system:"
    if [ -f "${EINJ_PATH}/available_error_type" ]; then
        while IFS= read -r line; do
            echo "  $line"
        done < "${EINJ_PATH}/available_error_type"
    else
        echo "  EINJ interface not available (${EINJ_PATH} not found)"
    fi
}

confirm_injection() {
    local error_type=$1
    local severity=${ERROR_SEVERITY[$error_type]}

    echo ""
    echo "========================================"
    echo "  WARNING: HARDWARE ERROR INJECTION"
    echo "========================================"
    echo ""
    echo "  Error type:  ${ERROR_DESCRIPTIONS[$error_type]}"
    echo "  Error code:  ${ERROR_TYPES[$error_type]}"
    echo "  Severity:    ${severity}"
    echo ""

    if [ "$severity" = "CRITICAL" ]; then
        echo "  *** CRITICAL: This injection will likely CRASH the host ***"
        echo "  *** Ensure crash dump collection is configured on the BMC ***"
        echo ""
    elif [ "$severity" = "HIGH" ]; then
        echo "  *** HIGH: This injection may cause system instability ***"
        echo ""
    fi

    echo "  Target system: $(hostname)"
    echo "  Date/Time:     $(date)"
    echo ""

    read -r -p "Type 'INJECT' to confirm (anything else to abort): " response
    if [ "$response" != "INJECT" ]; then
        echo "Injection aborted by user."
        exit 0
    fi
}

check_prerequisites() {
    # Must be root
    if [ "$(id -u)" -ne 0 ]; then
        die "Root privileges required. Run with sudo."
    fi

    # Check for debugfs mount
    if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
        log "Mounting debugfs..."
        mount -t debugfs none /sys/kernel/debug || \
            die "Failed to mount debugfs"
    fi

    # Check for EINJ module
    if [ ! -d "$EINJ_PATH" ]; then
        log "Loading EINJ kernel module..."
        modprobe einj 2>/dev/null || \
            die "EINJ interface not available. Ensure ACPI EINJ is enabled in BIOS and run: modprobe einj"
    fi

    # Verify EINJ files exist
    if [ ! -f "${EINJ_PATH}/error_type" ]; then
        die "EINJ error_type file not found at ${EINJ_PATH}/error_type"
    fi

    if [ ! -f "${EINJ_PATH}/error_inject" ]; then
        die "EINJ error_inject file not found at ${EINJ_PATH}/error_inject"
    fi
}

get_sel_count() {
    # Get current SEL entry count (via IPMI if available)
    if command -v ipmitool &>/dev/null; then
        ipmitool sel info 2>/dev/null | grep "Entries" | awk '{print $3}' || echo "unknown"
    else
        echo "unknown"
    fi
}

inject_error() {
    local error_type=$1
    local error_code=${ERROR_TYPES[$error_type]}

    log "Starting EINJ injection: ${ERROR_DESCRIPTIONS[$error_type]} (${error_code})"

    # Record pre-injection state
    local sel_before
    sel_before=$(get_sel_count)
    log "SEL entries before injection: ${sel_before}"

    # Set the error type
    log "Setting error type to ${error_code}..."
    echo "$error_code" > "${EINJ_PATH}/error_type" || \
        die "Failed to write error type"

    # Set memory address for memory errors (optional, 0 = random)
    if [[ "$error_type" == "ce" || "$error_type" == "uce" || "$error_type" == "fatal" ]]; then
        if [ -f "${EINJ_PATH}/param1" ]; then
            # Use 0 for random address selection
            echo "0x0" > "${EINJ_PATH}/param1" 2>/dev/null || true
            log "Memory address: random (0x0)"
        fi
        if [ -f "${EINJ_PATH}/param2" ]; then
            # Mask: full cacheline
            echo "0xfffffffffffff000" > "${EINJ_PATH}/param2" 2>/dev/null || true
        fi
    fi

    # Trigger injection
    log "Injecting error NOW..."
    echo 1 > "${EINJ_PATH}/error_inject" || \
        die "Failed to trigger error injection"

    log "Error injection triggered successfully"
    echo ""

    # Wait briefly for BMC to process
    echo "Waiting 5 seconds for BMC-side processing..."
    sleep 5

    # Check post-injection state
    local sel_after
    sel_after=$(get_sel_count)
    log "SEL entries after injection: ${sel_after}"

    echo ""
    echo "========================================"
    echo "  Injection Complete"
    echo "========================================"
    echo ""
    echo "  Error type:       ${ERROR_DESCRIPTIONS[$error_type]}"
    echo "  SEL before:       ${sel_before}"
    echo "  SEL after:        ${sel_after}"
    echo ""
    echo "  Verify on BMC:"
    echo "    ipmitool sel list"
    echo "    busctl tree xyz.openbmc_project.Logging"
    echo "    ls -la /var/lib/crashdump/"
    echo ""
}

# --- Main ---

ERROR_TYPE="${1:-}"

case "$ERROR_TYPE" in
    list)
        check_prerequisites
        list_error_types
        exit 0
        ;;
    ce|uce|fatal|pcie-ce|pcie-uce|pcie-fatal)
        check_prerequisites
        confirm_injection "$ERROR_TYPE"
        inject_error "$ERROR_TYPE"
        ;;
    "")
        echo "ACPI EINJ Error Injection"
        echo ""
        echo "Usage: $0 <error-type>"
        echo ""
        echo "Error types:"
        echo "  ce          Correctable memory error"
        echo "  uce         Uncorrectable memory error (non-fatal)"
        echo "  fatal       Uncorrectable memory error (fatal)"
        echo "  pcie-ce     PCIe correctable error"
        echo "  pcie-uce    PCIe uncorrectable error (non-fatal)"
        echo "  pcie-fatal  PCIe fatal error"
        echo "  list        List available error types on this system"
        echo ""
        echo "Examples:"
        echo "  $0 ce            # Inject correctable memory error"
        echo "  $0 pcie-fatal    # Inject PCIe fatal error"
        echo ""
        echo "WARNING: Only use on dedicated test systems."
        exit 1
        ;;
    *)
        die "Unknown error type: ${ERROR_TYPE}. Use '$0 list' to see available types."
        ;;
esac
