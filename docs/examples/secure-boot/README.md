# Secure Boot Examples

Reference scripts and configuration for ASPEED AST2600 secure boot on OpenBMC.

> **WARNING: OTP programming is IRREVERSIBLE.** Once a key hash is burned into OTP
> (One-Time Programmable) memory and secure boot is enabled, it CANNOT be undone.
> A misconfigured OTP will permanently brick the device. Always validate on
> development boards with non-production keys before touching production hardware.

> **These are REFERENCE examples only.** The actual signing tool (`socsec`) is
> ASPEED proprietary software. Adapt these templates to your specific platform,
> toolchain, and security requirements.

## Files

| File | Description |
|------|-------------|
| `generate-keys.sh` | Generate RSA-4096 key pair for secure boot signing; outputs public key hash for OTP |
| `sign-image.sh` | Reference workflow for signing U-Boot SPL with `socsec` (ASPEED tool) |
| `otp-config-reference.json` | Example OTP configuration showing key regions, security straps, and boot mode |

## Security Warnings

- **Never commit production signing keys to version control.** The `generate-keys.sh`
  script creates development keys only. Production keys must be generated and stored
  in an HSM (Hardware Security Module) or equivalent secure key management system.
- **OTP is write-once.** Every bit programmed into OTP is permanent. There is no
  factory reset, no recovery mode, and no way to reprogram a fused bit.
- **Test the full chain on development hardware first.** Verify that your signed
  image boots correctly before enabling secure boot enforcement in OTP.
- **Key rotation is not possible after OTP fusing.** Choose your key strategy
  carefully. Some platforms support multiple key slots for revocation, but the
  total number of slots is fixed and finite.

## Workflow Overview

```
1. Generate Keys          2. Sign Image             3. Program OTP
   generate-keys.sh          sign-image.sh             (ASPEED tools)
         |                        |                         |
         v                        v                         v
   keys/dev/                 signed image             Key hash burned
   +-- private.pem           (U-Boot SPL +            into OTP fuses
   +-- public.pem            secure header)            + secure boot
   +-- public_hash.txt                                  mode enabled
```

## Quick Start (Development Only)

```bash
# 1. Generate development key pair
./generate-keys.sh

# 2. Sign a U-Boot SPL image (requires socsec from ASPEED)
./sign-image.sh keys/dev/private.pem u-boot-spl.bin signed-spl.bin

# 3. Verify the key hash matches what will go into OTP
cat keys/dev/public_hash.txt

# 4. Review OTP configuration reference
cat otp-config-reference.json
```

## Prerequisites

- `openssl` (for key generation and hash computation)
- `socsec` (ASPEED secure boot signing tool -- proprietary, not open source)
- ASPEED AST2600 evaluation board or compatible hardware for OTP programming
- ASPEED OTP programming tool (for actual fusing -- not covered here)

## Key Management Best Practices

1. **Development keys:** Use `generate-keys.sh` to create throwaway keys for
   development and QEMU testing. Never use these on production hardware.
2. **Production keys:** Generate in an HSM. The private key should never exist
   on a general-purpose computer. Use ceremony procedures with multiple witnesses.
3. **Key backup:** Maintain encrypted offline backups of production keys. Loss
   of the signing key means you can never produce new firmware for devices that
   have that key hash in OTP.
4. **Access control:** Limit signing key access to authorized build systems only.
   Use CI/CD pipeline integration with HSM for automated signing.

## References

- [Secure Boot Guide](../../05-advanced/03-secure-boot-guide.md) -- full architecture, OTP details, and verification
- [ASPEED AST2600 Security Documentation](https://www.aspeedtech.com/) (requires NDA)
- [OpenBMC Secure Boot Design](https://github.com/openbmc/docs/blob/master/architecture/code-update/secure-boot.md)
- [socsec on GitHub](https://github.com/AspeedTech-BMC/socsec) -- ASPEED secure boot tool
