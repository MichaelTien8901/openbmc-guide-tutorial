# SPDM Examples

Shell scripts and configuration files for working with SPDM (Security Protocol and
Data Model) device attestation on OpenBMC.

> **Requires OpenBMC environment** — most scripts run on a booted OpenBMC system
> (QEMU or hardware) with SPDM support enabled. The certificate setup script
> runs on any system with OpenSSL.

## Quick Start

### Certificate Setup (runs anywhere with OpenSSL)

```bash
# Generate test certificate chain
./spdm_cert_setup.sh ./certs

# Copy to BMC
scp -P 2222 certs/root_ca.pem root@localhost:/etc/spdm/certs/trust/
scp -P 2222 certs/bmc_cert.pem root@localhost:/etc/spdm/certs/bmc/cert.pem
scp -P 2222 certs/bmc_key.pem root@localhost:/etc/spdm/certs/bmc/key.pem
```

### On-BMC Scripts (QEMU or hardware)

```bash
# 1. Build OpenBMC image with SPDM support
IMAGE_INSTALL:append = " libspdm spdm-emu phosphor-spdm "

# 2. Enable Redfish ComponentIntegrity in bmcweb
EXTRA_OEMESON:pn-bmcweb = " -Dredfish-component-integrity=enabled "

# 3. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 4. Copy scripts to BMC
scp -P 2222 spdm_auth.sh spdm_measurements.sh root@localhost:/tmp/

# 5. SSH in and run
ssh -p 2222 root@localhost
chmod +x /tmp/spdm_*.sh
/tmp/spdm_auth.sh 10           # Authenticate GPU at EID 10
/tmp/spdm_measurements.sh 10   # Collect measurements
```

### Redfish Queries (from host)

```bash
./spdm_redfish.sh localhost:2443
```

## Scripts

| Script | Runs On | Description |
|--------|---------|-------------|
| `spdm_cert_setup.sh [dir]` | Any (OpenSSL) | Generate test Root CA / Intermediate / BMC certificate chain |
| `spdm_auth.sh <eid>` | OpenBMC | Full SPDM authentication flow: version, capabilities, certs, challenge |
| `spdm_measurements.sh <eid> [policy]` | OpenBMC | Collect measurements, optionally compare against policy file |
| `spdm_redfish.sh <bmc-ip>` | Remote host | Query Redfish ComponentIntegrity collection and trigger re-attestation |

## Configuration Files

| File | Install To | Description |
|------|-----------|-------------|
| `config/algorithms.json` | `/etc/spdm/algorithms.json` | Crypto algorithm preferences (asymmetric, hash, DHE, AEAD) |
| `config/gpu_expected.json` | `/etc/spdm/policy/gpu_expected.json` | Expected measurement policy for GPU attestation |
| `config/component_integrity.json` | N/A (reference) | Example Redfish ComponentIntegrity response |

## SPDM Authentication Flow

```
BMC (Requester)                    Device (Responder)
       |                                  |
       |--- GET_VERSION ----------------->|
       |<-- VERSION ----------------------|
       |                                  |
       |--- GET_CAPABILITIES ------------>|
       |<-- CAPABILITIES -----------------|
       |                                  |
       |--- NEGOTIATE_ALGORITHMS -------->|
       |<-- ALGORITHMS -------------------|
       |                                  |
       |--- GET_DIGESTS ----------------->|
       |<-- DIGESTS ----------------------|
       |                                  |
       |--- GET_CERTIFICATE ------------->|
       |<-- CERTIFICATE ------------------|
       |                                  |
       |--- CHALLENGE ------------------->|
       |<-- CHALLENGE_AUTH (signed) ------|
       |                                  |
       |--- GET_MEASUREMENTS ------------>|
       |<-- MEASUREMENTS (signed) --------|
```

## Yocto Build Configuration

### Enable SPDM in Image

```bitbake
IMAGE_INSTALL:append = " \
    libspdm \
    spdm-emu \
    phosphor-spdm \
"

# Enable Redfish ComponentIntegrity
EXTRA_OEMESON:pn-bmcweb = " \
    -Dredfish-component-integrity=enabled \
"
```

### libspdm Build Options

```bitbake
EXTRA_OECMAKE:pn-libspdm = " \
    -DLIBSPDM_ENABLE_CAPABILITY_CERT_CAP=ON \
    -DLIBSPDM_ENABLE_CAPABILITY_CHAL_CAP=ON \
    -DLIBSPDM_ENABLE_CAPABILITY_MEAS_CAP=ON \
    -DLIBSPDM_ENABLE_CAPABILITY_KEY_EX_CAP=ON \
    -DLIBSPDM_ENABLE_CAPABILITY_HBEAT_CAP=ON \
    -DLIBSPDM_ENABLE_CAPABILITY_MUT_AUTH_CAP=ON \
"
```

## Key File Locations on OpenBMC

| Path | Description |
|------|-------------|
| `/etc/spdm/certs/trust/` | Trusted root CA certificates |
| `/etc/spdm/certs/bmc/cert.pem` | BMC device certificate |
| `/etc/spdm/certs/bmc/key.pem` | BMC private key (mode 600) |
| `/etc/spdm/algorithms.json` | Algorithm preferences |
| `/etc/spdm/policy/*.json` | Expected measurement policies |

## Troubleshooting

```bash
# Check SPDM daemon
systemctl status spdmd
journalctl -u spdmd -f

# Enable debug logging
echo "SPDM_DEBUG=1" >> /etc/default/spdmd
systemctl restart spdmd

# Verify MCTP connectivity first
mctp endpoint
pldmtool base getTID -m <eid>

# Check trust anchors
ls -la /etc/spdm/certs/trust/

# Verify certificate chain
openssl verify -CAfile root_ca.pem -untrusted intermediate.pem device_cert.pem

# Check certificate dates
openssl x509 -in cert.pem -noout -dates
```

## References

- [SPDM Guide](../../05-advanced/02-spdm-guide.md) — full protocol details, architecture, and Redfish integration
- [DMTF SPDM specification](https://www.dmtf.org/standards/spdm) (DSP0274)
- [Redfish ComponentIntegrity schema](https://redfish.dmtf.org/schemas/v1/ComponentIntegrity.json)
- [libspdm](https://github.com/DMTF/libspdm) — reference implementation
