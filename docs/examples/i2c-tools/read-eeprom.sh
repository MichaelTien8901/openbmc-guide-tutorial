#!/bin/bash
#
# EEPROM Reader via I2C
#
# Reads an EEPROM device on a given I2C bus and address using i2cdump,
# then formats the output as a hex dump with ASCII sidebar. Optionally
# limits the number of bytes read and saves raw output to a file.
#
# Usage:
#   ./read-eeprom.sh <bus> <address>
#   ./read-eeprom.sh <bus> <address> -r 256
#   ./read-eeprom.sh <bus> <address> -o /tmp/eeprom.bin
#   ./read-eeprom.sh -h
#
# Arguments:
#   bus       I2C bus number (e.g., 0, 1, 2)
#   address   Device address in hex (e.g., 0x50)
#
# Options:
#   -r BYTES  Number of bytes to read (default: 256, max: 65536)
#   -o FILE   Save raw binary output to file
#   -h        Show help
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - i2c-tools installed (i2cdump, i2cget)
#
# Common EEPROM addresses:
#   0x50-0x57  Standard EEPROM / FRU data
#   0x30-0x37  SPD (DIMM information)

set -euo pipefail

# --- Defaults ---
READ_BYTES=256
OUTPUT_FILE=""

# --- Usage ---
usage() {
    echo "EEPROM Reader via I2C"
    echo ""
    echo "Usage: $0 <bus> <address> [-r BYTES] [-o FILE] [-h]"
    echo ""
    echo "Arguments:"
    echo "  bus       I2C bus number (e.g., 0, 1, 2)"
    echo "  address   Device address in hex (e.g., 0x50)"
    echo ""
    echo "Options:"
    echo "  -r BYTES  Number of bytes to read (default: 256, max: 65536)"
    echo "  -o FILE   Save raw binary output to file"
    echo "  -h        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 0 0x50                  # Read 256 bytes from EEPROM at bus 0, addr 0x50"
    echo "  $0 1 0x51 -r 512           # Read 512 bytes from bus 1, addr 0x51"
    echo "  $0 0 0x50 -o /tmp/fru.bin  # Read and save to file"
    echo "  $0 0 0x50 -r 8             # Read only first 8 bytes (FRU header)"
    echo ""
    echo "Common EEPROM addresses:"
    echo "  0x50-0x57  Standard EEPROM / FRU data"
    echo "  0x30-0x37  SPD (DIMM information)"
    echo ""
    echo "Requires: i2c-tools (i2cdump, i2cget)"
}

# --- Parse positional arguments ---
if [ $# -lt 1 ]; then
    usage
    exit 1
fi

# Handle -h before positional args
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "Error: bus and address arguments are required"
    echo ""
    usage
    exit 1
fi

BUS="$1"
ADDRESS="$2"
shift 2

# --- Parse optional arguments ---
while getopts "r:o:h" opt; do
    case "$opt" in
        r) READ_BYTES="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# --- Validate inputs ---
if ! [[ "$BUS" =~ ^[0-9]+$ ]]; then
    echo "Error: bus must be a number (got: $BUS)"
    exit 1
fi

if ! [[ "$ADDRESS" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "Error: address must be in hex format (e.g., 0x50, got: $ADDRESS)"
    exit 1
fi

if ! [[ "$READ_BYTES" =~ ^[0-9]+$ ]] || [ "$READ_BYTES" -lt 1 ] || [ "$READ_BYTES" -gt 65536 ]; then
    echo "Error: byte count must be between 1 and 65536 (got: $READ_BYTES)"
    exit 1
fi

if [ ! -e "/dev/i2c-${BUS}" ]; then
    echo "Error: /dev/i2c-${BUS} does not exist"
    echo ""
    echo "Available buses:"
    i2cdetect -l 2>/dev/null || ls /dev/i2c-* 2>/dev/null || echo "  No I2C buses found"
    exit 1
fi

# --- Check prerequisites ---
if ! command -v i2cdump &>/dev/null; then
    echo "Error: i2cdump not found"
    echo "Ensure i2c-tools is installed in the image:"
    echo "  IMAGE_INSTALL:append = \" i2c-tools \""
    exit 1
fi

# --- Verify device is present ---
echo "Checking for device at bus $BUS, address $ADDRESS..."
if ! i2cdetect -y "$BUS" 2>/dev/null | grep -qE "$(printf '%02x' "$ADDRESS" 2>/dev/null || echo "${ADDRESS#0x}")"; then
    echo "Warning: device may not be present at bus $BUS, address $ADDRESS"
    echo "         Proceeding anyway (device may respond to reads but not scans)"
    echo ""
fi

# --- Read EEPROM ---
echo "========================================"
echo "EEPROM Read: Bus $BUS, Address $ADDRESS"
echo "Reading $READ_BYTES bytes"
echo "========================================"
echo ""

# Calculate the end register for the range flag.
# i2cdump -r takes an inclusive range 0xSTART-0xEND, max 0xFF per dump.
if [ "$READ_BYTES" -le 256 ]; then
    # Single dump covers the range
    END_REG=$(printf "0x%02x" $((READ_BYTES - 1)))
    echo "--- Offset 0x0000 - $(printf '0x%04x' $((READ_BYTES - 1))) ---"
    echo ""
    i2cdump -y -r "0x00-${END_REG}" "$BUS" "$ADDRESS" b 2>/dev/null || {
        echo "Error: failed to read from bus $BUS, address $ADDRESS"
        echo ""
        echo "Check:"
        echo "  i2cdetect -y $BUS        # Is the device present?"
        echo "  dmesg | tail -20          # Kernel I2C errors?"
        exit 1
    }
    echo ""
else
    # Multiple 256-byte pages
    PAGES=$(( (READ_BYTES + 255) / 256 ))
    BYTES_LEFT=$READ_BYTES

    for page in $(seq 0 $((PAGES - 1))); do
        PAGE_START=$((page * 256))
        if [ "$BYTES_LEFT" -ge 256 ]; then
            PAGE_SIZE=256
        else
            PAGE_SIZE=$BYTES_LEFT
        fi
        END_REG=$(printf "0x%02x" $((PAGE_SIZE - 1)))

        echo "--- Offset $(printf '0x%04x' $PAGE_START) - $(printf '0x%04x' $((PAGE_START + PAGE_SIZE - 1))) ---"
        echo ""

        # For multi-page reads, set the page register if the EEPROM supports it.
        # Standard 24Cxx EEPROMs use a 16-bit address. For devices with page
        # registers or address pins, you may need to adjust the slave address.
        i2cdump -y -r "0x00-${END_REG}" "$BUS" "$ADDRESS" b 2>/dev/null || {
            echo "Error: read failed at page $page (offset $(printf '0x%04x' $PAGE_START))"
            break
        }
        echo ""

        BYTES_LEFT=$((BYTES_LEFT - PAGE_SIZE))
    done
fi

# --- Save to file (optional) ---
if [ -n "$OUTPUT_FILE" ]; then
    echo "Saving raw data to $OUTPUT_FILE..."

    # Read byte-by-byte using i2cget and write as binary
    : > "$OUTPUT_FILE"
    for offset in $(seq 0 $((READ_BYTES - 1))); do
        REG=$(printf "0x%02x" $((offset % 256)))
        BYTE=$(i2cget -y "$BUS" "$ADDRESS" "$REG" b 2>/dev/null || echo "0xff")
        # Convert hex string to binary byte and append
        printf "\\x${BYTE#0x}" >> "$OUTPUT_FILE"
    done

    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    echo "Saved $FILE_SIZE bytes to $OUTPUT_FILE"
    echo ""
fi

# --- FRU header check ---
# IPMI FRU data starts with a common header (8 bytes).
# Byte 0 = format version (0x01), Byte 7 = checksum.
echo "--- FRU Header Check ---"
BYTE0=$(i2cget -y "$BUS" "$ADDRESS" 0x00 b 2>/dev/null || echo "")
if [ "$BYTE0" = "0x01" ]; then
    echo "  Byte 0 = 0x01 (IPMI FRU format version 1 detected)"
    echo ""
    echo "  FRU Area Offsets (in 8-byte units):"
    for i in 1 2 3 4 5; do
        AREA_BYTE=$(i2cget -y "$BUS" "$ADDRESS" "0x0${i}" b 2>/dev/null || echo "0x00")
        case $i in
            1) AREA_NAME="Internal Use" ;;
            2) AREA_NAME="Chassis Info" ;;
            3) AREA_NAME="Board Info" ;;
            4) AREA_NAME="Product Info" ;;
            5) AREA_NAME="MultiRecord" ;;
        esac
        if [ "$AREA_BYTE" != "0x00" ]; then
            OFFSET=$((AREA_BYTE * 8))
            echo "    $AREA_NAME: $AREA_BYTE (offset $(printf '0x%04x' $OFFSET))"
        else
            echo "    $AREA_NAME: not present"
        fi
    done
else
    echo "  Byte 0 = ${BYTE0:-??} (not an IPMI FRU header)"
    echo "  This EEPROM may contain raw data or a different format."
fi
echo ""

echo "========================================"
echo "Read complete"
echo "========================================"
