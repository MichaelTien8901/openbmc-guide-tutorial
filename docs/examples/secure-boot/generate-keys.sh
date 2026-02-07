#!/bin/bash
#
# Secure Boot Key Generation for ASPEED AST2600
#
# Generates an RSA-4096 key pair for signing OpenBMC secure boot images.
# Creates separate directories for development and production key placeholders.
# Outputs the public key SHA-256 hash that would be programmed into OTP.
#
# ============================================================================
# WARNING: These are DEVELOPMENT keys for testing only.
# NEVER use development keys on production hardware.
# Production keys MUST be generated in an HSM (Hardware Security Module).
# ============================================================================
#
# Usage:
#   ./generate-keys.sh [output-dir]
#
# Arguments:
#   output-dir   Optional: base directory for keys (default: ./keys)
#
# Output structure:
#   keys/
#   +-- dev/
#   |   +-- private.pem        # RSA-4096 private key (DEVELOPMENT ONLY)
#   |   +-- public.pem         # Corresponding public key
#   |   +-- public_hash.txt    # SHA-256 hash of public key (for OTP)
#   +-- prod/
#       +-- README.txt         # Placeholder with HSM instructions
#
# Prerequisites:
#   - openssl (1.1.0 or later)

set -e

KEY_DIR="${1:-./keys}"
DEV_DIR="$KEY_DIR/dev"
PROD_DIR="$KEY_DIR/prod"
KEY_BITS=4096

echo "========================================================"
echo "Secure Boot Key Generation (AST2600)"
echo "========================================================"
echo ""
echo "WARNING: These keys are for DEVELOPMENT AND TESTING ONLY."
echo "         Do NOT use on production hardware."
echo "         Production keys must be generated in an HSM."
echo ""
echo "========================================================"
echo ""

# --- Prerequisite check ---

if ! command -v openssl &>/dev/null; then
    echo "Error: openssl not found. Install openssl and try again."
    exit 1
fi

OPENSSL_VERSION=$(openssl version)
echo "Using: $OPENSSL_VERSION"
echo ""

# --- Create directory structure ---

echo "Step 1: Create key directories"
echo "-------------------------------"

mkdir -p "$DEV_DIR"
mkdir -p "$PROD_DIR"

# Set restrictive permissions on the key directories
chmod 700 "$DEV_DIR"
chmod 700 "$PROD_DIR"

echo "  Created: $DEV_DIR/"
echo "  Created: $PROD_DIR/"
echo ""

# --- Generate RSA-4096 private key ---

echo "Step 2: Generate RSA-$KEY_BITS private key"
echo "--------------------------------------------"

openssl genpkey -algorithm RSA \
    -pkeyopt rsa_keygen_bits:$KEY_BITS \
    -out "$DEV_DIR/private.pem"

# Set restrictive permissions on private key
chmod 600 "$DEV_DIR/private.pem"

echo "  Created: $DEV_DIR/private.pem (RSA-$KEY_BITS private key)"
echo ""

# --- Extract public key ---

echo "Step 3: Extract public key"
echo "---------------------------"

openssl rsa -in "$DEV_DIR/private.pem" \
    -pubout \
    -out "$DEV_DIR/public.pem"

echo "  Created: $DEV_DIR/public.pem"
echo ""

# --- Compute public key hash for OTP ---

echo "Step 4: Compute public key hash (for OTP programming)"
echo "-------------------------------------------------------"

# Extract the raw public key in DER format, then compute SHA-256.
# This is the hash value that gets programmed into the AST2600 OTP
# key region. The boot ROM uses this hash to verify the public key
# embedded in the signed firmware image header.
openssl rsa -in "$DEV_DIR/private.pem" \
    -pubout -outform DER 2>/dev/null | \
    openssl dgst -sha256 -hex | \
    awk '{print $NF}' > "$DEV_DIR/public_hash.txt"

PUBLIC_HASH=$(cat "$DEV_DIR/public_hash.txt")
echo "  SHA-256 hash of public key:"
echo "  $PUBLIC_HASH"
echo ""
echo "  Saved to: $DEV_DIR/public_hash.txt"
echo ""
echo "  ============================================================"
echo "  This hash is what gets programmed into OTP key region."
echo "  OTP PROGRAMMING IS IRREVERSIBLE -- verify this hash"
echo "  carefully before burning into OTP fuses."
echo "  ============================================================"
echo ""

# --- Create production key placeholder ---

echo "Step 5: Create production key placeholder"
echo "-------------------------------------------"

cat > "$PROD_DIR/README.txt" << 'PRODEOF'
================================================================================
PRODUCTION KEY MANAGEMENT
================================================================================

DO NOT generate production signing keys on a general-purpose computer.

Production keys for secure boot MUST be:

1. Generated inside a FIPS 140-2 Level 3 (or higher) HSM
2. Never exported from the HSM in plaintext
3. Backed up using HSM vendor's secure backup mechanism
4. Protected by multi-person access control (M-of-N key ceremony)
5. Audited with tamper-evident logs

Recommended HSM options:
  - Thales Luna Network HSM
  - AWS CloudHSM
  - Azure Dedicated HSM
  - Yubico YubiHSM 2 (for smaller deployments)

Signing workflow for production:
  1. Build system submits unsigned image to signing service
  2. Signing service authenticates the request and validates the image
  3. HSM performs the RSA signature operation
  4. Signed image is returned to the build system
  5. All operations are logged for audit

The public key hash for OTP programming should be derived from the HSM-stored
public key and verified by multiple authorized personnel before OTP fusing.

================================================================================
PRODEOF

echo "  Created: $PROD_DIR/README.txt (HSM instructions)"
echo ""

# --- Verify the key pair ---

echo "Step 6: Verify key pair"
echo "------------------------"

# Sign a test message and verify to confirm the key pair works
TEST_MSG=$(mktemp)
TEST_SIG=$(mktemp)
echo "secure-boot-key-verification-test" > "$TEST_MSG"

openssl dgst -sha256 -sign "$DEV_DIR/private.pem" \
    -out "$TEST_SIG" "$TEST_MSG"

if openssl dgst -sha256 -verify "$DEV_DIR/public.pem" \
    -signature "$TEST_SIG" "$TEST_MSG" &>/dev/null; then
    echo "  Key pair verification: PASSED"
else
    echo "  Key pair verification: FAILED"
    rm -f "$TEST_MSG" "$TEST_SIG"
    exit 1
fi

rm -f "$TEST_MSG" "$TEST_SIG"
echo ""

# --- Summary ---

echo "========================================================"
echo "Summary"
echo "========================================================"
echo ""
echo "Development keys (TESTING ONLY):"
echo "  Private key:   $DEV_DIR/private.pem"
echo "  Public key:    $DEV_DIR/public.pem"
echo "  OTP hash:      $DEV_DIR/public_hash.txt"
echo ""
echo "Public key hash for OTP:"
echo "  $PUBLIC_HASH"
echo ""
echo "Production keys:"
echo "  See $PROD_DIR/README.txt for HSM instructions"
echo ""
echo "Next steps:"
echo "  1. Use sign-image.sh to sign a U-Boot SPL image"
echo "  2. Test the signed image on a development board"
echo "  3. Only after successful testing, consider OTP programming"
echo ""
echo "========================================================"
echo "REMINDER: OTP programming is IRREVERSIBLE."
echo "Always test on development hardware first."
echo "========================================================"
