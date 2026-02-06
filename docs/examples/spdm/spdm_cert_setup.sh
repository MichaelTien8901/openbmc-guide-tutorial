#!/bin/bash
#
# SPDM Certificate Chain Setup
#
# Creates a test certificate chain for SPDM authentication:
#   Root CA -> Intermediate CA -> BMC Certificate
#
# This generates test certificates for development/QEMU testing.
# In production, use certificates from your organization's PKI.
#
# Usage:
#   ./spdm_cert_setup.sh [output-dir]
#
# Arguments:
#   output-dir   Optional: directory for generated certs (default: ./certs)
#
# Prerequisites:
#   - openssl installed

set -e

CERT_DIR=${1:-./certs}

echo "========================================"
echo "SPDM Certificate Chain Setup"
echo "========================================"
echo ""

if ! command -v openssl &>/dev/null; then
    echo "Error: openssl not found"
    exit 1
fi

mkdir -p "$CERT_DIR"

# --- Step 1: Root CA ---
echo "Step 1: Generate Root CA"
echo "------------------------"

openssl ecparam -name secp384r1 -genkey -noout \
    -out "$CERT_DIR/root_ca_key.pem"

openssl req -new -x509 -key "$CERT_DIR/root_ca_key.pem" \
    -out "$CERT_DIR/root_ca.pem" \
    -days 3650 \
    -subj "/CN=Test Root CA/O=OpenBMC Test/OU=SPDM" \
    -sha384

echo "  Created: $CERT_DIR/root_ca_key.pem (private key)"
echo "  Created: $CERT_DIR/root_ca.pem (certificate)"
echo ""

# --- Step 2: Intermediate CA ---
echo "Step 2: Generate Intermediate CA"
echo "---------------------------------"

openssl ecparam -name secp384r1 -genkey -noout \
    -out "$CERT_DIR/intermediate_key.pem"

openssl req -new -key "$CERT_DIR/intermediate_key.pem" \
    -out "$CERT_DIR/intermediate.csr" \
    -subj "/CN=Test Intermediate CA/O=OpenBMC Test/OU=SPDM"

openssl x509 -req -in "$CERT_DIR/intermediate.csr" \
    -CA "$CERT_DIR/root_ca.pem" \
    -CAkey "$CERT_DIR/root_ca_key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/intermediate.pem" \
    -days 1825 \
    -sha384 \
    -extfile <(echo -e "basicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign")

rm -f "$CERT_DIR/intermediate.csr"
echo "  Created: $CERT_DIR/intermediate_key.pem (private key)"
echo "  Created: $CERT_DIR/intermediate.pem (certificate)"
echo ""

# --- Step 3: BMC Device Certificate ---
echo "Step 3: Generate BMC Device Certificate"
echo "-----------------------------------------"

openssl ecparam -name secp384r1 -genkey -noout \
    -out "$CERT_DIR/bmc_key.pem"

openssl req -new -key "$CERT_DIR/bmc_key.pem" \
    -out "$CERT_DIR/bmc.csr" \
    -subj "/CN=BMC-test/O=OpenBMC Test/OU=SPDM"

openssl x509 -req -in "$CERT_DIR/bmc.csr" \
    -CA "$CERT_DIR/intermediate.pem" \
    -CAkey "$CERT_DIR/intermediate_key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/bmc_cert.pem" \
    -days 365 \
    -sha384 \
    -extfile <(echo -e "basicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature,keyAgreement")

rm -f "$CERT_DIR/bmc.csr"
echo "  Created: $CERT_DIR/bmc_key.pem (private key)"
echo "  Created: $CERT_DIR/bmc_cert.pem (certificate)"
echo ""

# --- Step 4: Build full chain ---
echo "Step 4: Build Certificate Chain"
echo "--------------------------------"

cat "$CERT_DIR/bmc_cert.pem" "$CERT_DIR/intermediate.pem" "$CERT_DIR/root_ca.pem" \
    > "$CERT_DIR/bmc_chain.pem"

echo "  Created: $CERT_DIR/bmc_chain.pem (full chain)"
echo ""

# --- Step 5: Verify chain ---
echo "Step 5: Verify Certificate Chain"
echo "----------------------------------"

if openssl verify -CAfile "$CERT_DIR/root_ca.pem" \
    -untrusted "$CERT_DIR/intermediate.pem" \
    "$CERT_DIR/bmc_cert.pem" 2>/dev/null; then
    echo "  Chain verification: PASSED"
else
    echo "  Chain verification: FAILED"
    exit 1
fi
echo ""

# --- Summary ---
echo "========================================"
echo "Generated Files"
echo "========================================"
echo ""
ls -la "$CERT_DIR"/*.pem
echo ""

echo "========================================"
echo "Installation on OpenBMC"
echo "========================================"
echo ""
echo "# Copy trust anchor (root CA) to BMC:"
echo "  scp -P 2222 $CERT_DIR/root_ca.pem root@localhost:/etc/spdm/certs/trust/"
echo ""
echo "# Copy BMC certificate and key:"
echo "  scp -P 2222 $CERT_DIR/bmc_cert.pem root@localhost:/etc/spdm/certs/bmc/cert.pem"
echo "  scp -P 2222 $CERT_DIR/bmc_key.pem root@localhost:/etc/spdm/certs/bmc/key.pem"
echo ""
echo "# Set permissions on BMC:"
echo "  ssh -p 2222 root@localhost 'chmod 600 /etc/spdm/certs/bmc/key.pem'"
echo ""
echo "# Restart SPDM daemon:"
echo "  ssh -p 2222 root@localhost 'systemctl restart spdmd'"

# Cleanup serial files
rm -f "$CERT_DIR"/*.srl
