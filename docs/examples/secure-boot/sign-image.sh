#!/bin/bash
#
# Secure Boot Image Signing for ASPEED AST2600
#
# Reference workflow for signing a U-Boot SPL image using ASPEED's socsec tool.
# This script demonstrates the signing process -- adapt to your environment.
#
# ============================================================================
# NOTE: socsec is ASPEED's proprietary secure boot signing utility.
# It is available at: https://github.com/AspeedTech-BMC/socsec
# You must obtain it from ASPEED or build it from their repository.
#
# This script is a REFERENCE TEMPLATE. The exact socsec command-line
# interface may vary by version. Consult ASPEED documentation for your
# specific SoC revision and socsec version.
# ============================================================================
#
# Usage:
#   ./sign-image.sh <signing-key> <unsigned-image> [output-image]
#
# Arguments:
#   signing-key      Path to RSA-4096 private key (PEM format)
#   unsigned-image   Path to unsigned U-Boot SPL binary
#   output-image     Optional: output path (default: signed-<input-filename>)
#
# Prerequisites:
#   - openssl (for key verification)
#   - socsec (ASPEED secure boot tool)
#   - Python 3 (required by socsec)
#
# Example:
#   ./sign-image.sh keys/dev/private.pem u-boot-spl.bin signed-spl.bin

set -e

# ============================================================================
# WARNING: This script handles cryptographic signing keys.
# Ensure your signing key is protected with appropriate file permissions.
# Never use development keys for production images.
# ============================================================================

SIGNING_KEY="${1:-}"
UNSIGNED_IMAGE="${2:-}"
OUTPUT_IMAGE="${3:-}"

# --- Argument validation ---

usage() {
    echo "Usage: $0 <signing-key> <unsigned-image> [output-image]"
    echo ""
    echo "Arguments:"
    echo "  signing-key      RSA-4096 private key in PEM format"
    echo "  unsigned-image   Unsigned U-Boot SPL binary"
    echo "  output-image     Output signed image (default: signed-<input>)"
    echo ""
    echo "Example:"
    echo "  $0 keys/dev/private.pem u-boot-spl.bin signed-spl.bin"
    exit 1
}

if [ -z "$SIGNING_KEY" ] || [ -z "$UNSIGNED_IMAGE" ]; then
    usage
fi

if [ ! -f "$SIGNING_KEY" ]; then
    echo "Error: Signing key not found: $SIGNING_KEY"
    exit 1
fi

if [ ! -f "$UNSIGNED_IMAGE" ]; then
    echo "Error: Unsigned image not found: $UNSIGNED_IMAGE"
    exit 1
fi

# Default output filename
if [ -z "$OUTPUT_IMAGE" ]; then
    INPUT_BASENAME=$(basename "$UNSIGNED_IMAGE")
    OUTPUT_IMAGE="signed-${INPUT_BASENAME}"
fi

echo "========================================================"
echo "Secure Boot Image Signing (AST2600)"
echo "========================================================"
echo ""
echo "  Signing key:     $SIGNING_KEY"
echo "  Unsigned image:  $UNSIGNED_IMAGE"
echo "  Output image:    $OUTPUT_IMAGE"
echo ""

# --- Step 1: Verify the signing key ---

echo "Step 1: Verify signing key"
echo "---------------------------"

KEY_TYPE=$(openssl rsa -in "$SIGNING_KEY" -text -noout 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo "Error: Cannot read signing key. Is it a valid RSA PEM key?"
    exit 1
fi

echo "  Key type: $KEY_TYPE"

# Verify key size is RSA-4096
KEY_BITS=$(openssl rsa -in "$SIGNING_KEY" -text -noout 2>/dev/null | grep "Private-Key:" | grep -o '[0-9]*')
if [ "$KEY_BITS" != "4096" ]; then
    echo "  WARNING: Key is $KEY_BITS bits. AST2600 secure boot typically requires RSA-4096."
    echo "  Proceeding anyway -- verify this matches your OTP configuration."
fi
echo ""

# --- Step 2: Compute key hash for reference ---

echo "Step 2: Public key hash (for OTP verification)"
echo "-------------------------------------------------"

PUBLIC_HASH=$(openssl rsa -in "$SIGNING_KEY" -pubout -outform DER 2>/dev/null | \
    openssl dgst -sha256 -hex | awk '{print $NF}')

echo "  SHA-256: $PUBLIC_HASH"
echo ""
echo "  Verify this matches the hash programmed in OTP before deploying."
echo ""

# --- Step 3: Check for socsec ---

echo "Step 3: Check socsec availability"
echo "-----------------------------------"

if ! command -v socsec &>/dev/null; then
    echo "  socsec not found in PATH."
    echo ""
    echo "  socsec is ASPEED's proprietary secure boot signing tool."
    echo "  To install:"
    echo "    git clone https://github.com/AspeedTech-BMC/socsec.git"
    echo "    cd socsec"
    echo "    pip3 install ."
    echo ""
    echo "  After installing, re-run this script."
    echo ""
    echo "  ============================================================"
    echo "  Since socsec is not available, the commands below show what"
    echo "  WOULD be executed. Review and adapt for your environment."
    echo "  ============================================================"
    echo ""
    SOCSEC_AVAILABLE=0
else
    SOCSEC_VERSION=$(socsec version 2>/dev/null || echo "unknown")
    echo "  socsec found: $SOCSEC_VERSION"
    echo ""
    SOCSEC_AVAILABLE=1
fi

# --- Step 4: Sign the image ---

echo "Step 4: Sign U-Boot SPL image"
echo "-------------------------------"
echo ""

# The socsec tool creates a secure boot header containing:
#   - Algorithm identifier (RSA-4096 + SHA-256)
#   - Public key (for ROM to hash and compare against OTP)
#   - Digital signature over the image
#   - Image load address and entry point
#
# The AST2600 boot ROM verifies the image by:
#   1. Reading the secure header from flash
#   2. Extracting the public key from the header
#   3. Computing SHA-256 of the public key
#   4. Comparing the hash against the value stored in OTP
#   5. Using the public key to verify the RSA signature over the image
#   6. If all checks pass, loading and executing the image

# socsec signing command for AST2600
# NOTE: Exact flags may differ by socsec version. Consult ASPEED docs.
SIGN_CMD="socsec make_secure_bl1_image \
    --soc AST2600 \
    --algorithm RSA4096_SHA256 \
    --rsa_sign_key $SIGNING_KEY \
    --bl1_image $UNSIGNED_IMAGE \
    --output $OUTPUT_IMAGE"

if [ "$SOCSEC_AVAILABLE" -eq 1 ]; then
    echo "  Executing: $SIGN_CMD"
    echo ""
    eval "$SIGN_CMD"
    echo ""
    echo "  Signed image created: $OUTPUT_IMAGE"
else
    echo "  [DRY RUN] The following command would be executed:"
    echo ""
    echo "  $SIGN_CMD"
    echo ""
    echo "  Install socsec to perform actual signing."
fi
echo ""

# --- Step 5: Verify the signed image (if socsec available) ---

echo "Step 5: Verify signed image"
echo "-----------------------------"

if [ "$SOCSEC_AVAILABLE" -eq 1 ] && [ -f "$OUTPUT_IMAGE" ]; then
    VERIFY_CMD="socsec verify \
        --soc AST2600 \
        --sec_image $OUTPUT_IMAGE \
        --rsa_sign_key $SIGNING_KEY"

    echo "  Executing: $VERIFY_CMD"
    echo ""

    if eval "$VERIFY_CMD"; then
        echo ""
        echo "  Verification: PASSED"
    else
        echo ""
        echo "  Verification: FAILED"
        echo "  The signed image did not pass verification."
        echo "  Do NOT deploy this image."
        exit 1
    fi
else
    echo "  [SKIPPED] socsec not available or signed image not created."
    echo ""
    echo "  To verify a signed image:"
    echo "  socsec verify \\"
    echo "      --soc AST2600 \\"
    echo "      --sec_image $OUTPUT_IMAGE \\"
    echo "      --rsa_sign_key $SIGNING_KEY"
fi
echo ""

# --- Summary ---

echo "========================================================"
echo "Summary"
echo "========================================================"
echo ""
echo "  Input:       $UNSIGNED_IMAGE ($(wc -c < "$UNSIGNED_IMAGE" 2>/dev/null || echo '?') bytes)"
if [ -f "$OUTPUT_IMAGE" ]; then
    echo "  Output:      $OUTPUT_IMAGE ($(wc -c < "$OUTPUT_IMAGE") bytes)"
else
    echo "  Output:      $OUTPUT_IMAGE (not created -- socsec not available)"
fi
echo "  Key hash:    $PUBLIC_HASH"
echo ""
echo "Next steps:"
echo "  1. Flash the signed image to a development board"
echo "  2. Verify it boots correctly with secure boot enabled"
echo "  3. Only after testing, consider OTP programming on production units"
echo ""
echo "========================================================"
echo "REMINDER: Test on development hardware before production."
echo "OTP programming is IRREVERSIBLE."
echo "========================================================"
