#!/bin/bash
#
# SPDM Authentication Flow
#
# Demonstrates the SPDM authentication sequence:
#   1. Version negotiation
#   2. Capability exchange
#   3. Algorithm negotiation
#   4. Certificate retrieval
#   5. Challenge-response authentication
#
# Usage:
#   ./spdm_auth.sh <eid>
#
# Prerequisites:
#   - Running on OpenBMC with SPDM support
#   - spdmtool installed
#   - Trust anchors configured in /etc/spdm/certs/trust/

set -e

EID=${1:?Usage: $0 <eid>}

echo "========================================"
echo "SPDM Authentication Flow (EID=$EID)"
echo "========================================"
echo ""

if ! command -v spdmtool &>/dev/null; then
    echo "Error: spdmtool not found"
    echo "Ensure SPDM packages are installed:"
    echo "  IMAGE_INSTALL:append = \" libspdm spdm-emu phosphor-spdm \""
    exit 1
fi

# Step 1: Get SPDM version
echo "Step 1: Version Negotiation"
echo "----------------------------"
spdmtool version -m "$EID" 2>/dev/null || \
    echo "  Failed to negotiate version"
echo ""

# Step 2: Get capabilities
echo "Step 2: Capability Exchange"
echo "----------------------------"
CAPS=$(spdmtool capabilities -m "$EID" 2>/dev/null || true)
if [ -n "$CAPS" ]; then
    echo "$CAPS"
else
    echo "  Failed to get capabilities"
fi
echo ""

# Step 3: Negotiate algorithms
echo "Step 3: Algorithm Negotiation"
echo "------------------------------"
spdmtool algorithms -m "$EID" 2>/dev/null || \
    echo "  Failed to negotiate algorithms"
echo ""

# Step 4: Get certificate chain
echo "Step 4: Certificate Retrieval (Slot 0)"
echo "----------------------------------------"
spdmtool getdigest -m "$EID" 2>/dev/null || \
    echo "  Failed to get certificate digest"
echo ""

CERT_RESULT=$(spdmtool getcert -m "$EID" -s 0 2>/dev/null || true)
if [ -n "$CERT_RESULT" ]; then
    echo "$CERT_RESULT"

    # Save certificate for inspection
    spdmtool getcert -m "$EID" -s 0 -o /tmp/device_chain_eid${EID}.pem 2>/dev/null && \
        echo "  Certificate saved to /tmp/device_chain_eid${EID}.pem"
else
    echo "  Failed to get certificate chain"
fi
echo ""

# Step 5: Challenge
echo "Step 5: Challenge-Response Authentication"
echo "-------------------------------------------"
CHALLENGE_RESULT=$(spdmtool challenge -m "$EID" -s 0 2>/dev/null || true)
if [ -n "$CHALLENGE_RESULT" ]; then
    echo "$CHALLENGE_RESULT"
    echo ""
    echo "Authentication PASSED"
else
    echo "  Challenge failed or not supported"
    echo ""
    echo "Authentication FAILED"
fi
echo ""

# Verify saved certificate (if openssl available)
if [ -f "/tmp/device_chain_eid${EID}.pem" ] && command -v openssl &>/dev/null; then
    echo "========================================"
    echo "Certificate Details"
    echo "========================================"
    echo ""
    echo "Subject:"
    openssl x509 -in "/tmp/device_chain_eid${EID}.pem" -noout -subject 2>/dev/null || true
    echo "Validity:"
    openssl x509 -in "/tmp/device_chain_eid${EID}.pem" -noout -dates 2>/dev/null || true
    echo "Key Usage:"
    openssl x509 -in "/tmp/device_chain_eid${EID}.pem" -noout -text 2>/dev/null | \
        grep -A1 "Key Usage" || true
fi
