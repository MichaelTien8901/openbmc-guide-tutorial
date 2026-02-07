---
layout: default
title: Secure Boot & Image Signing
parent: Advanced Topics
nav_order: 13
difficulty: advanced
prerequisites:
  - environment-setup
  - first-build
  - firmware-update-guide
last_modified_date: 2026-02-06
---

# Secure Boot & Image Signing
{: .no_toc }

Establish a hardware root of trust on AST2600-based OpenBMC platforms using OTP key provisioning, secure boot chain verification, and build-time image signing.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Secure boot ensures that every piece of firmware executed on the BMC is cryptographically verified before it runs. On ASPEED AST2600 platforms, the secure boot chain begins at the hardware level with a Root of Trust stored in One-Time Programmable (OTP) fuses and extends through each boot stage up to the Linux kernel.

This guide walks you through the complete secure boot lifecycle: understanding the chain of trust, generating and provisioning cryptographic keys, integrating image signing into the Yocto build, and managing keys across development and production environments. You will learn how each boot stage verifies the next, how the ASPEED `socsec` tool signs firmware images, and how OTP fuse programming permanently binds a platform to a specific Root of Trust.

Secure boot is essential for production BMC deployments where firmware integrity must be guaranteed. Without it, an attacker with flash access can replace BMC firmware with a malicious image. With secure boot enabled, the hardware rejects any firmware that does not carry a valid signature from the provisioned Root of Trust key.

**Key concepts covered:**
- AST2600 secure boot chain of trust (OTP through kernel)
- RSA key pair generation and OTP fuse provisioning
- ASPEED `socsec` tool for image signing
- Yocto build integration for automated signing
- Development vs production key management
- Security strap configuration and jumper handling

{: .warning }
**OTP programming is irreversible.** Once you burn a public key hash into OTP fuses, you cannot change or revoke it. A mistake during OTP provisioning can permanently brick the platform. Always verify your key material and OTP configuration on development boards before touching production hardware.

{: .note }
**Requires real hardware.** While you can test the signing workflow and build signed images using QEMU, OTP programming and actual secure boot verification require a physical AST2600 board. QEMU does not emulate OTP fuses or the ROM-based signature verification.

---

## Architecture

### AST2600 Secure Boot Chain

The AST2600 implements a multi-stage verified boot process. Each stage verifies the cryptographic signature of the next stage before transferring control. If any verification fails, the boot process halts.

```
┌─────────────────────────────────────────────────────────────────┐
│                  AST2600 Secure Boot Chain                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐                                           │
│  │   ASPEED ROM     │  Immutable code in silicon                │
│  │   (Boot ROM)     │  Reads OTP Root of Trust public key hash  │
│  └────────┬─────────┘                                           │
│           │  Verifies RSA signature                             │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │   U-Boot SPL     │  First mutable firmware stage             │
│  │   (Secondary     │  Signed with private key matching OTP     │
│  │    Program       │  ROM compares signature against OTP hash  │
│  │    Loader)       │                                           │
│  └────────┬─────────┘                                           │
│           │  Verifies RSA signature                             │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │   U-Boot         │  Full bootloader                          │
│  │   (Proper)       │  SPL verifies signature before loading    │
│  │                  │  Initializes DRAM, loads FIT image        │
│  └────────┬─────────┘                                           │
│           │  Verifies FIT image signature                       │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │   Linux Kernel   │  Kernel + DTB in signed FIT image         │
│  │   (FIT Image)    │  U-Boot verifies before booting           │
│  │                  │  Includes initramfs if configured         │
│  └──────────────────┘                                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  OTP Fuses (Root of Trust)                               │   │
│  │  ── RSA public key hash (SHA-256/SHA-512)                │   │
│  │  ── Security strap bits (enable/disable secure boot)     │   │
│  │  ── Key revocation bits (for key rotation)               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Verification Flow Summary

| Boot Stage | Verified By | Signature Type | Key Source |
|------------|-------------|----------------|------------|
| U-Boot SPL | ASPEED Boot ROM | RSA-2048/4096 + SHA-256 | OTP fuse (public key hash) |
| U-Boot | U-Boot SPL | RSA-2048/4096 + SHA-256 | Embedded in SPL image |
| Linux Kernel (FIT) | U-Boot | RSA-2048/4096 + SHA-256 | Embedded in U-Boot DTB |

### Key Dependencies

- **ASPEED Boot ROM**: The immutable first-stage bootloader in silicon. It reads OTP fuses to determine whether secure boot is enabled and which public key hash to use for verification.
- **socsec**: ASPEED's command-line tool for signing images, generating OTP configuration, and programming fuses. Part of the `socsec` Python package.
- **OpenSSL**: Used for RSA key pair generation. The private key signs images; the public key hash is burned into OTP.
- **U-Boot FIT signing**: U-Boot's Flattened Image Tree (FIT) format supports embedded RSA signatures for kernel and DTB verification.

---

## OTP Key Provisioning

OTP (One-Time Programmable) fuses provide the hardware Root of Trust for the secure boot chain. You program the SHA-256 hash of your RSA public key into the OTP region. The Boot ROM reads this hash at every boot to verify the SPL signature.

### Step 1: Generate an RSA Key Pair

Generate a 4096-bit RSA key pair using OpenSSL. This key pair is the foundation of your entire secure boot chain.

```bash
# Create a directory for your secure boot keys
mkdir -p ~/secure-boot-keys && cd ~/secure-boot-keys

# Generate 4096-bit RSA private key
openssl genrsa -out rsa4096_private.pem 4096

# Extract the public key
openssl rsa -in rsa4096_private.pem -pubout -out rsa4096_public.pem

# Verify the key pair
openssl rsa -in rsa4096_private.pem -check -noout
```

{: .tip }
Use RSA-4096 for production deployments. RSA-2048 is acceptable for development and testing but provides a smaller security margin for long-lived platforms.

For development boards, you may choose RSA-2048 for faster signing and verification:

```bash
# Development-only: 2048-bit key (faster, lower security margin)
openssl genrsa -out rsa2048_dev_private.pem 2048
openssl rsa -in rsa2048_dev_private.pem -pubout -out rsa2048_dev_public.pem
```

### Step 2: Install the socsec Tool

The ASPEED `socsec` tool handles OTP image generation, image signing, and OTP programming. Install it from PyPI or the ASPEED SDK.

```bash
# Install socsec from PyPI
pip3 install socsec

# Verify installation
socsec --version

# Alternatively, clone from ASPEED's repository
git clone https://github.com/AspeedTech-BMC/socsec.git
cd socsec && pip3 install .
```

### Step 3: Create the OTP Configuration

The OTP configuration file defines which fuse bits to program, including the public key hash and security strap settings. Create a JSON configuration for your platform.

```json
{
    "version": "A3",
    "soc": "2600",
    "otp_info": {
        "conf": {
            "secure_boot_enable": true,
            "secure_boot_header_offset": "0x20",
            "rsa_key_order": "big_endian",
            "sha_algorithm": "SHA256",
            "retire_key_id": 0
        },
        "strap": {
            "secure_boot": true,
            "boot_from_emmc": false,
            "enable_watchdog": true,
            "uart_debug_disable": false
        },
        "key": {
            "key_type": "RSA4096_SHA256",
            "number_of_keys": 1,
            "keys": [
                {
                    "key_file": "rsa4096_public.pem",
                    "key_id": 0
                }
            ]
        }
    }
}
```

Save this file as `otp_config.json` in your secure boot keys directory.

{: .note }
The `version` field must match your AST2600 silicon revision (A1, A3, etc.). Check your chip marking or datasheet. Using the wrong version causes OTP programming to fail or produce incorrect fuse values.

### Step 4: Generate the OTP Image

Use `socsec` to generate the OTP image from your configuration. This produces a binary that contains the fuse values to program.

```bash
# Generate OTP image
socsec make_otp_image \
    --config otp_config.json \
    --output otp_image.bin

# Verify the generated OTP image contents
socsec verify_otp_image \
    --config otp_config.json \
    --image otp_image.bin
```

The tool reads your public key, computes its SHA-256 hash, and embeds it in the OTP image along with the strap and configuration bits.

### Step 5: Program OTP Fuses

{: .warning }
**This step is irreversible.** Once OTP fuses are programmed, they cannot be erased or modified. Double-check your configuration and key material before proceeding. Perform this step on a development board first.

Program the OTP fuses using `socsec` over the ASPEED debug UART or JTAG interface:

```bash
# Connect to the AST2600 via debug UART
# Ensure the board is in OTP programming mode (security jumper set)

# Program OTP fuses
socsec otp_prog \
    --image otp_image.bin \
    --port /dev/ttyUSB0 \
    --baud 115200

# Read back and verify OTP contents
socsec otp_read \
    --port /dev/ttyUSB0 \
    --baud 115200 \
    --output otp_readback.bin
```

After programming, compare the readback with your expected values:

```bash
# Diff the programmed values against expected
socsec otp_verify \
    --config otp_config.json \
    --image otp_readback.bin
```

### Security Strap Configuration

The AST2600 has hardware strap pins that interact with OTP security settings. These straps control boot behavior during development.

| Strap Pin | Function | Development | Production |
|-----------|----------|-------------|------------|
| `SCU510[1]` | Secure boot enable | 0 (disabled) | 1 (enabled via OTP) |
| `SCU510[2]` | Boot source select | SPI (default) | SPI |
| `SCU510[4]` | UART debug | Enabled | Disabled |
| `SCU510[6]` | JTAG debug | Enabled | Disabled |

{: .tip }
During development, keep UART and JTAG debug enabled in the strap configuration. Disable them only in production OTP images. If you disable debug interfaces in OTP and your signed image fails to boot, you lose all debug access to the board.

---

## Image Signing Workflow

Once OTP fuses are provisioned with your public key hash, every firmware image must be signed with the corresponding private key. The ASPEED `socsec` tool signs U-Boot SPL and U-Boot images, while U-Boot itself handles FIT image (kernel) signing.

### Signing U-Boot SPL

The Boot ROM expects the SPL image to contain a signature header. Use `socsec` to wrap the SPL binary with a verified boot header.

```bash
# Sign the U-Boot SPL binary
socsec sign \
    --image u-boot-spl.bin \
    --key rsa4096_private.pem \
    --algorithm RSA4096_SHA256 \
    --soc 2600 \
    --output u-boot-spl-signed.bin

# Verify the signature offline (before flashing)
socsec verify \
    --image u-boot-spl-signed.bin \
    --key rsa4096_public.pem \
    --soc 2600
```

The signed SPL binary includes:
- A signature header with the RSA signature
- The original SPL code
- Padding to align with the Boot ROM's expectations

### Signing U-Boot Proper

U-Boot SPL verifies U-Boot proper using the same key infrastructure. Sign the U-Boot binary similarly:

```bash
# Sign U-Boot proper
socsec sign \
    --image u-boot.bin \
    --key rsa4096_private.pem \
    --algorithm RSA4096_SHA256 \
    --soc 2600 \
    --output u-boot-signed.bin

# Verify offline
socsec verify \
    --image u-boot-signed.bin \
    --key rsa4096_public.pem \
    --soc 2600
```

### Signing the Kernel FIT Image

The Linux kernel, device tree, and optional initramfs are packaged into a FIT (Flattened Image Tree) image. U-Boot verifies the FIT image signature before booting.

FIT signing uses U-Boot's built-in mechanism with `mkimage`:

```bash
# Create a FIT image description (ITS file)
# The ITS file references the kernel, DTB, and signing key

# Sign the FIT image with mkimage
mkimage -f fit-image.its \
    -K u-boot.dtb \
    -k ~/secure-boot-keys \
    -r \
    fitImage

# The -K flag writes the public key into the U-Boot DTB
# The -k flag specifies the directory containing the private key
# The -r flag marks the key as "required" for verification
```

The U-Boot DTB now contains the public key node. When U-Boot boots, it reads this key from its own DTB and uses it to verify the FIT image signature before launching the kernel.

### Verifying Signatures Offline

Always verify your signed images before flashing them to hardware:

```bash
# Verify SPL signature
socsec verify --image u-boot-spl-signed.bin --key rsa4096_public.pem --soc 2600
echo "SPL verification: $?"

# Verify U-Boot signature
socsec verify --image u-boot-signed.bin --key rsa4096_public.pem --soc 2600
echo "U-Boot verification: $?"

# Verify FIT image signature using fit_check_sign (from U-Boot tools)
fit_check_sign -f fitImage -k u-boot.dtb
echo "FIT verification: $?"
```

{: .tip }
Add offline verification as a CI/CD step. Reject any build that produces images failing signature verification. This catches signing key mismatches and corrupted images before they reach hardware.

---

## Build-Time Signing Integration

The OpenBMC Yocto build system integrates secure boot signing into the image build process. You configure signing parameters in your machine configuration, and the build automatically signs all boot-stage images.

### Yocto Configuration

Add the following variables to your machine's `local.conf` or `machine.conf`:

```bitbake
# Enable secure boot signing
SOCSEC_SIGN_ENABLE = "1"

# Path to the signing private key
SOCSEC_SIGN_KEY = "/path/to/secure-boot-keys/rsa4096_private.pem"

# Signing algorithm
SOCSEC_SIGN_ALGO = "RSA4096_SHA256"

# SOC type
SOCSEC_SIGN_SOC = "2600"

# Enable FIT image signing for the kernel
UBOOT_SIGN_ENABLE = "1"
UBOOT_SIGN_KEYNAME = "rsa4096"
UBOOT_SIGN_KEYDIR = "/path/to/secure-boot-keys"
UBOOT_MKIMAGE_DTCOPTS = "-I dts -O dtb -p 2000"
UBOOT_SIGN_IMG_KEYNAME = "rsa4096"
FIT_SIGN_INDIVIDUAL = "1"
```

### Recipe Integration

The `u-boot-aspeed-sdk` recipe (or your machine's U-Boot recipe) picks up the signing configuration and invokes `socsec` during the build. The typical integration looks like this in the recipe's bbappend:

```bitbake
# meta-<your-machine>/recipes-bsp/u-boot/u-boot-aspeed-sdk_%.bbappend

DEPENDS += "socsec-native"

do_deploy:append() {
    if [ "${SOCSEC_SIGN_ENABLE}" = "1" ]; then
        # Sign U-Boot SPL
        socsec sign \
            --image ${DEPLOYDIR}/u-boot-spl.bin \
            --key ${SOCSEC_SIGN_KEY} \
            --algorithm ${SOCSEC_SIGN_ALGO} \
            --soc ${SOCSEC_SIGN_SOC} \
            --output ${DEPLOYDIR}/u-boot-spl-signed.bin

        # Sign U-Boot proper
        socsec sign \
            --image ${DEPLOYDIR}/u-boot.bin \
            --key ${SOCSEC_SIGN_KEY} \
            --algorithm ${SOCSEC_SIGN_ALGO} \
            --soc ${SOCSEC_SIGN_SOC} \
            --output ${DEPLOYDIR}/u-boot-signed.bin

        # Replace unsigned images with signed versions
        install -m 0644 ${DEPLOYDIR}/u-boot-spl-signed.bin \
            ${DEPLOYDIR}/u-boot-spl.bin
        install -m 0644 ${DEPLOYDIR}/u-boot-signed.bin \
            ${DEPLOYDIR}/u-boot.bin
    fi
}
```

### Kernel FIT Signing in the Build

The kernel recipe uses U-Boot's `mkimage` to sign the FIT image during the build. Enable this in your kernel bbappend:

```bitbake
# meta-<your-machine>/recipes-kernel/linux/linux-aspeed_%.bbappend

inherit kernel-fitimage

# These variables drive FIT signing
UBOOT_SIGN_ENABLE = "1"
UBOOT_SIGN_KEYNAME = "rsa4096"
UBOOT_SIGN_KEYDIR = "/path/to/secure-boot-keys"

# Include both kernel and DTB in the signed FIT
FIT_SIGN_INDIVIDUAL = "1"
KERNEL_CLASSES = "kernel-fitimage"
KERNEL_IMAGETYPE = "fitImage"
```

### Build and Verify

Run the full build and verify the output images carry valid signatures:

```bash
# Build the image with signing enabled
cd openbmc
. setup <your-machine>
bitbake obmc-phosphor-image

# Check the deploy directory for signed images
ls -la build/tmp/deploy/images/<your-machine>/u-boot-spl.bin
ls -la build/tmp/deploy/images/<your-machine>/u-boot.bin
ls -la build/tmp/deploy/images/<your-machine>/fitImage

# Verify signatures offline
socsec verify \
    --image build/tmp/deploy/images/<your-machine>/u-boot-spl.bin \
    --key ~/secure-boot-keys/rsa4096_public.pem \
    --soc 2600
```

{: .note }
The build system does not program OTP fuses. OTP provisioning is always a separate, explicit step performed directly on hardware. The build only produces signed images that are compatible with the OTP-provisioned key.

---

## Development vs Production Key Management

Managing cryptographic keys is the most critical aspect of secure boot operations. A compromised private key allows an attacker to sign malicious firmware that the hardware accepts as legitimate. The irreversible nature of OTP programming amplifies the stakes: once a public key hash is fused, the platform trusts that key permanently (unless key rotation slots are available).

### Key Hierarchy

Maintain separate key sets for development and production with clearly defined boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                    Key Hierarchy                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Development Keys                                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Storage: Developer workstation or shared vault     │    │
│  │  Access:  All firmware developers                   │    │
│  │  OTP:     Burned only on development boards         │    │
│  │  Purpose: Prototyping, testing, CI builds           │    │
│  │  Type:    RSA-2048 or RSA-4096                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Production Keys                                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Storage: Hardware Security Module (HSM)            │    │
│  │  Access:  Signing service only (no human access)    │    │
│  │  OTP:     Burned on production platforms            │    │
│  │  Purpose: Release builds, customer-facing firmware  │    │
│  │  Type:    RSA-4096 (minimum)                        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Key Rotation Slots (OTP supports multiple key IDs)         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Slot 0: Primary production key (active)            │    │
│  │  Slot 1: Backup production key (provisioned, unused)│    │
│  │  Slot 2: Reserved for future rotation               │    │
│  │  Slot 3: Reserved                                   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Development Key Practices

Use development keys for all prototyping and CI/CD workflows. These keys are known and shared among the team.

```bash
# Generate a clearly labeled development key pair
openssl genrsa -out dev_rsa4096_private.pem 4096
openssl rsa -in dev_rsa4096_private.pem -pubout -out dev_rsa4096_public.pem

# Store in version control (development keys ONLY)
# NEVER store production keys in version control
cp dev_rsa4096_private.pem ~/openbmc/meta-mymachine/conf/keys/
cp dev_rsa4096_public.pem ~/openbmc/meta-mymachine/conf/keys/
```

{: .warning }
**Never reuse development keys for production.** Development keys stored in version control or on developer workstations are considered compromised by definition. Production hardware must use keys generated and stored exclusively in an HSM.

### Production Key Practices

Production keys must never leave the HSM. Use a signing service that accepts unsigned images and returns signed images without exposing the private key.

```bash
# Production signing workflow (conceptual)
# The private key never leaves the HSM

# 1. Build unsigned images
bitbake obmc-phosphor-image   # with SOCSEC_SIGN_ENABLE = "0"

# 2. Submit unsigned images to the signing service
curl -X POST https://signing-service.internal/sign \
    -F "image=@u-boot-spl.bin" \
    -F "algorithm=RSA4096_SHA256" \
    -F "key_id=production_slot0" \
    -o u-boot-spl-signed.bin

# 3. Verify the signature using the public key
socsec verify \
    --image u-boot-spl-signed.bin \
    --key production_rsa4096_public.pem \
    --soc 2600
```

### OTP Key Rotation

The AST2600 OTP supports multiple key slots, allowing you to rotate keys without replacing hardware. However, key rotation is constrained by the number of available OTP slots (typically 4).

| Operation | Possible? | Notes |
|-----------|-----------|-------|
| Add a new key to an empty slot | Yes | Program the new key hash into the next available slot |
| Retire an old key | Yes | Set the retire bit for the old key's slot ID |
| Modify an existing key | No | OTP fuses are write-once; bits can be set but not cleared |
| Erase all keys | No | OTP is permanently programmed |
| Add keys beyond slot limit | No | Once all slots are used, no more keys can be added |

To rotate to a new key:

```bash
# 1. Generate a new key pair
openssl genrsa -out rsa4096_rotation1_private.pem 4096
openssl rsa -in rsa4096_rotation1_private.pem -pubout -out rsa4096_rotation1_public.pem

# 2. Update OTP config to add the new key at slot 1 and retire slot 0
# In otp_config.json:
#   "retire_key_id": 0,
#   "keys": [
#     { "key_file": "rsa4096_public.pem", "key_id": 0 },
#     { "key_file": "rsa4096_rotation1_public.pem", "key_id": 1 }
#   ]

# 3. Generate and program the updated OTP image
socsec make_otp_image --config otp_config_rotation.json --output otp_rotation.bin
socsec otp_prog --image otp_rotation.bin --port /dev/ttyUSB0 --baud 115200

# 4. Sign all new images with the rotation key
socsec sign \
    --image u-boot-spl.bin \
    --key rsa4096_rotation1_private.pem \
    --algorithm RSA4096_SHA256 \
    --soc 2600 \
    --key-id 1 \
    --output u-boot-spl-signed.bin
```

{: .note }
Plan your key rotation strategy before the initial OTP provisioning. Decide how many slots to reserve for rotation and document the key lifecycle for your platform.

---

## Security Jumper Handling

During development, you need the ability to disable secure boot for debugging and reflashing unsigned images. The AST2600 supports a hardware security jumper that overrides OTP strap settings.

### Jumper Configuration

Most AST2600 evaluation boards provide a jumper header for secure boot override:

| Jumper State | Boot Behavior | Use Case |
|-------------|---------------|----------|
| Open (default) | OTP straps control boot | Production / secure boot active |
| Closed | Secure boot bypassed | Development / recovery |

When the security jumper is closed:
- The Boot ROM skips SPL signature verification
- Unsigned images boot normally
- UART and JTAG debug remain available regardless of OTP settings
- OTP fuse contents are not modified (the jumper only bypasses enforcement)

{: .tip }
Label development boards clearly with their jumper state and OTP provisioning status. A board with OTP fuses programmed but the security jumper closed looks identical to an unprovisioned board during boot, which can cause confusion during testing.

### Recovery Procedure

If a board with secure boot enabled fails to boot a signed image (for example, due to a corrupted flash), use the security jumper to recover:

```bash
# 1. Power off the board
# 2. Close the security jumper (bypass secure boot)
# 3. Power on — board boots unsigned recovery image or enters UART recovery mode
# 4. Reflash a correctly signed image via UART or SPI programmer

# UART recovery using ASPEED's uart_flash tool
socsec uart_flash \
    --port /dev/ttyUSB0 \
    --baud 115200 \
    --image flash-<machine>.bin

# 5. Power off
# 6. Open the security jumper (re-enable secure boot)
# 7. Power on — board boots the newly flashed signed image
```

{: .warning }
The security jumper must be removed (open) on production systems. A closed security jumper completely defeats the purpose of secure boot. Include jumper state verification in your manufacturing and deployment checklists.

---

## Code Examples

### Example 1: Key Generation Script

A complete script for generating development key pairs and OTP configuration:

```bash
#!/bin/bash
# generate-dev-keys.sh
# Generate development secure boot keys for AST2600

set -euo pipefail

KEY_DIR="${1:-./dev-keys}"
KEY_SIZE="${2:-4096}"
SOC_VERSION="${3:-A3}"

echo "Generating ${KEY_SIZE}-bit RSA development keys in ${KEY_DIR}..."

mkdir -p "${KEY_DIR}"

# Generate RSA private key
openssl genrsa -out "${KEY_DIR}/dev_rsa${KEY_SIZE}_private.pem" "${KEY_SIZE}"

# Extract public key
openssl rsa \
    -in "${KEY_DIR}/dev_rsa${KEY_SIZE}_private.pem" \
    -pubout \
    -out "${KEY_DIR}/dev_rsa${KEY_SIZE}_public.pem"

# Display key fingerprint for verification
echo "Public key fingerprint:"
openssl rsa \
    -pubin \
    -in "${KEY_DIR}/dev_rsa${KEY_SIZE}_public.pem" \
    -outform DER 2>/dev/null | sha256sum

# Generate OTP configuration
cat > "${KEY_DIR}/otp_config_dev.json" << OTPEOF
{
    "version": "${SOC_VERSION}",
    "soc": "2600",
    "otp_info": {
        "conf": {
            "secure_boot_enable": true,
            "secure_boot_header_offset": "0x20",
            "rsa_key_order": "big_endian",
            "sha_algorithm": "SHA256",
            "retire_key_id": 0
        },
        "strap": {
            "secure_boot": true,
            "boot_from_emmc": false,
            "enable_watchdog": true,
            "uart_debug_disable": false
        },
        "key": {
            "key_type": "RSA${KEY_SIZE}_SHA256",
            "number_of_keys": 1,
            "keys": [
                {
                    "key_file": "dev_rsa${KEY_SIZE}_public.pem",
                    "key_id": 0
                }
            ]
        }
    }
}
OTPEOF

echo "Development keys and OTP config generated in ${KEY_DIR}/"
echo "WARNING: These are DEVELOPMENT keys. Never use them for production."
```

See the complete example at [examples/secure-boot/]({{ site.baseurl }}/examples/secure-boot/).

### Example 2: Build-Time Signing Verification Script

A script to verify all signed images after a build completes:

```bash
#!/bin/bash
# verify-signed-images.sh
# Verify all secure boot signatures after an OpenBMC build

set -euo pipefail

DEPLOY_DIR="${1:?Usage: $0 <deploy-dir> <public-key>}"
PUBLIC_KEY="${2:?Usage: $0 <deploy-dir> <public-key>}"
SOC="2600"
ERRORS=0

echo "Verifying signed images in ${DEPLOY_DIR}..."

# Verify U-Boot SPL
echo -n "  U-Boot SPL: "
if socsec verify --image "${DEPLOY_DIR}/u-boot-spl.bin" \
    --key "${PUBLIC_KEY}" --soc "${SOC}" 2>/dev/null; then
    echo "PASS"
else
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
fi

# Verify U-Boot proper
echo -n "  U-Boot:     "
if socsec verify --image "${DEPLOY_DIR}/u-boot.bin" \
    --key "${PUBLIC_KEY}" --soc "${SOC}" 2>/dev/null; then
    echo "PASS"
else
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
fi

# Verify FIT image (kernel)
echo -n "  FIT Image:  "
if [ -f "${DEPLOY_DIR}/fitImage" ]; then
    if fit_check_sign -f "${DEPLOY_DIR}/fitImage" \
        -k "${DEPLOY_DIR}/u-boot.dtb" 2>/dev/null; then
        echo "PASS"
    else
        echo "FAIL"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "SKIP (fitImage not found)"
fi

echo ""
if [ "${ERRORS}" -eq 0 ]; then
    echo "All signature verifications passed."
    exit 0
else
    echo "ERROR: ${ERRORS} verification(s) failed!"
    exit 1
fi
```

---

## Troubleshooting

### Issue: Board does not boot after OTP programming

**Symptom**: Board appears completely dead after programming OTP fuses. No serial output, no response.

**Cause**: The OTP security straps enable secure boot, but the flash contains unsigned images (or images signed with a different key).

**Solution**:
1. Close the security jumper to bypass secure boot
2. Power cycle the board
3. Flash correctly signed images via UART recovery or SPI programmer
4. Open the security jumper and power cycle again

### Issue: socsec reports "signature verification failed"

**Symptom**: `socsec verify` fails on a signed image that previously verified correctly.

**Cause**: The image was modified after signing (e.g., by a post-processing step in the build), or you are verifying with the wrong public key.

**Solution**:
1. Confirm you are using the correct public key that matches the signing private key
2. Check that no build steps modify the image after the signing step
3. Re-sign the image and verify immediately:
   ```bash
   socsec sign --image u-boot-spl.bin --key private.pem \
       --algorithm RSA4096_SHA256 --soc 2600 --output signed.bin
   socsec verify --image signed.bin --key public.pem --soc 2600
   ```

### Issue: FIT image signature verification fails in U-Boot

**Symptom**: U-Boot prints `Bad Data Hash` or `RSA signature verification failed` when booting the kernel.

**Cause**: The FIT image was signed with a key that does not match the public key embedded in U-Boot's DTB, or the FIT image was modified after signing.

**Solution**:
1. Verify that the `UBOOT_SIGN_KEYNAME` in your build configuration matches the key filename (without extension)
2. Rebuild both U-Boot and the FIT image together (the public key is embedded in U-Boot's DTB during FIT signing)
3. Ensure the `-r` flag is passed to `mkimage` to mark the key as required

### Issue: OTP programming fails with "protected region" error

**Symptom**: `socsec otp_prog` reports a write-protection error.

**Cause**: The OTP region you are attempting to write has already been programmed. OTP bits can only transition from 0 to 1, never from 1 to 0.

**Solution**:
1. Read the current OTP contents: `socsec otp_read --port /dev/ttyUSB0 --baud 115200 --output current_otp.bin`
2. Compare against your target configuration to identify conflicting bits
3. If the existing OTP data conflicts with your new key, you cannot change it. The board is permanently bound to the previously programmed key.

### Debug Commands

```bash
# Check OTP fuse contents from a running BMC (Linux)
devmem 0x1e6f2000 32   # OTP configuration word 0
devmem 0x1e6f2004 32   # OTP configuration word 1

# Read security strap register
devmem 0x1e6e2510 32   # SCU510 — hardware strap status

# Check U-Boot verified boot status (from U-Boot shell)
# At U-Boot prompt:
env print verified_boot
iminfo ${loadaddr}      # Show FIT image info including signature status

# View kernel boot log for FIT verification
dmesg | grep -i "verified\|signature\|secure"
```

---

## References

### Official Resources
- [ASPEED socsec Repository](https://github.com/AspeedTech-BMC/socsec)
- [U-Boot Verified Boot Documentation](https://docs.u-boot.org/en/latest/usage/verified-boot.html)
- [OpenBMC U-Boot Repository](https://github.com/openbmc/u-boot)
- [ASPEED SDK Documentation](https://github.com/AspeedTech-BMC/openbmc)

### Related Guides
- [Firmware Update Guide]({% link docs/05-advanced/03-firmware-update-guide.md %})
- [SPDM Guide]({% link docs/05-advanced/02-spdm-guide.md %})

### External Documentation
- [ASPEED AST2600 Datasheet](https://www.aspeedtech.com/products.php?fPath=20&rId=440) (requires registration)
- [U-Boot FIT Image Signing](https://docs.u-boot.org/en/latest/usage/fit/signature.html)
- [Yocto kernel-fitimage Class](https://docs.yoctoproject.org/ref-manual/classes.html#kernel-fitimage)
- [NIST SP 800-57 Key Management Recommendations](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final)

---

{: .warning }
**Tested on**: AST2600-EVB hardware. OTP programming and secure boot verification require physical hardware and cannot be validated on QEMU.
Last updated: 2026-02-06
