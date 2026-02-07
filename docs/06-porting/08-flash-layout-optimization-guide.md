---
layout: default
title: Flash Layout & Optimization Guide
parent: Porting
nav_order: 8
difficulty: advanced
prerequisites:
  - machine-layer
  - uboot
  - porting-reference
last_modified_date: 2025-02-06
---

# Flash Layout & Optimization Guide
{: .no_toc }

Understand OpenBMC flash partitioning, image construction, and techniques for reducing firmware image size.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Every OpenBMC image must fit inside the SPI NOR flash attached to the BMC SoC. The flash stores U-Boot, the Linux kernel (packaged as a FIT image), a read-only root filesystem (squashfs), and a read-write data partition. Understanding how these pieces are arranged and assembled is essential for porting to new hardware, reducing image size, and enabling reliable firmware updates.

This guide walks you through the complete flash lifecycle: how the Yocto build system constructs the final firmware image, how the partitions are laid out on flash, and how to shrink or restructure the image for your platform. You also learn how to configure A/B dual-image updates for rollback-safe firmware deployment.

**Key concepts covered:**
- Static MTD and UBI flash layouts for 32MB and 64MB configurations
- Image construction via `image_types_phosphor.bbclass`
- Image size reduction checklist (packages, kernel, compression)
- A/B dual-image partitioning and rollback flow
- eMMC vs NOR flash storage comparison

{: .warning }
Full validation of flash layout changes requires real hardware. The architectural concepts in this guide are testable conceptually, but partition offsets and boot behavior must be verified on your target BMC platform.

---

## Flash Layout Diagrams

OpenBMC supports two primary flash layouts: **static MTD** (flat partitions on raw flash) and **UBI** (managed volumes with wear leveling). The choice depends on your platform requirements and flash size.

### Static MTD Layout (32MB)

The static layout divides the flash into fixed partitions at compile-time offsets. This is the simpler and more common approach for 32MB (0x2000000) SPI NOR flash.

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  512 KB
 0x080000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  64 KB
 0x090000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~480 KB
 0x100000  ├────────────────────────────────────────┤
           │         FIT Image (kernel + dtb)       │  4 MB
           │    ┌─────────────────────────────┐     │
           │    │  Linux Kernel (compressed)  │     │
           │    │  Device Tree Blob (.dtb)    │     │
           │    │  FIT Header + Signatures    │     │
           │    └─────────────────────────────┘     │
 0x500000  ├────────────────────────────────────────┤
           │      Read-Only Root Filesystem         │  22 MB
           │         (squashfs + xz/zstd)           │
           │                                        │
           │    /usr/bin, /usr/lib, /etc (static)   │
           │    systemd services, phosphor daemons  │
           │                                        │
 0x1B00000 ├────────────────────────────────────────┤
           │      Read-Write Data Partition         │  5 MB
           │           (JFFS2 or ext4)              │
           │                                        │
           │    /var, logs, persistent config       │
           │    U-Boot env backup, user data        │
           │                                        │
 0x2000000 └────────────────────────────────────────┘
```

### Static MTD Layout (64MB)

Platforms with 64MB (0x4000000) flash gain more space for the root filesystem and read-write data. This is common on AST2600-based systems.

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  1 MB
 0x100000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  64 KB
 0x110000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~960 KB
 0x200000  ├────────────────────────────────────────┤
           │         FIT Image (kernel + dtb)       │  8 MB
           │    ┌─────────────────────────────┐     │
           │    │  Linux Kernel (compressed)  │     │
           │    │  Device Tree Blob (.dtb)    │     │
           │    │  FIT Header + Signatures    │     │
           │    └─────────────────────────────┘     │
 0xA00000  ├────────────────────────────────────────┤
           │      Read-Only Root Filesystem         │  44 MB
           │         (squashfs + xz/zstd)           │
           │                                        │
           │    Full phosphor stack, debug tools,   │
           │    WebUI assets, additional daemons    │
           │                                        │
 0x3600000 ├────────────────────────────────────────┤
           │      Read-Write Data Partition         │  10 MB
           │           (JFFS2 or ext4)              │
           │                                        │
           │    /var, logs, persistent config,      │
           │    crash dumps, extended user data     │
           │                                        │
 0x4000000 └────────────────────────────────────────┘
```

### UBI Layout (32MB)

UBI (Unsorted Block Images) provides wear leveling and dynamic volume sizing on top of raw NAND or NOR flash. OpenBMC uses UBI on platforms that require better flash endurance.

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  512 KB
 0x080000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  64 KB
 0x090000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~480 KB
 0x100000  ├────────────────────────────────────────┤
           │         UBI Partition                  │  ~31 MB
           │  ┌──────────────────────────────────┐  │
           │  │  UBI Volume 0: kernel            │  │  ~4 MB
           │  │    (FIT image: kernel + dtb)     │  │
           │  ├──────────────────────────────────┤  │
           │  │  UBI Volume 1: rofs              │  │  ~22 MB
           │  │    (squashfs rootfs image)       │  │
           │  ├──────────────────────────────────┤  │
           │  │  UBI Volume 2: rwfs              │  │  ~4 MB
           │  │    (UBIFS read-write data)       │  │
           │  ├──────────────────────────────────┤  │
           │  │  (UBI overhead: PEB headers,     │  │  ~1 MB
           │  │   wear leveling tables, etc.)    │  │
           │  └──────────────────────────────────┘  │
 0x2000000 └────────────────────────────────────────┘
```

### UBI Layout (64MB)

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  1 MB
 0x100000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  64 KB
 0x110000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~960 KB
 0x200000  ├────────────────────────────────────────┤
           │         UBI Partition                  │  ~62 MB
           │  ┌──────────────────────────────────┐  │
           │  │  UBI Volume 0: kernel            │  │  ~8 MB
           │  │    (FIT image: kernel + dtb)     │  │
           │  ├──────────────────────────────────┤  │
           │  │  UBI Volume 1: rofs              │  │  ~44 MB
           │  │    (squashfs rootfs image)       │  │
           │  ├──────────────────────────────────┤  │
           │  │  UBI Volume 2: rwfs              │  │  ~8 MB
           │  │    (UBIFS read-write data)       │  │
           │  ├──────────────────────────────────┤  │
           │  │  (UBI overhead: PEB headers,     │  │  ~2 MB
           │  │   wear leveling tables, etc.)    │  │
           │  └──────────────────────────────────┘  │
 0x4000000 └────────────────────────────────────────┘
```

### Static vs UBI Comparison

| Aspect | Static MTD | UBI |
|--------|-----------|-----|
| **Wear leveling** | None (fixed erase blocks) | Built-in across all PEBs |
| **Partition sizing** | Fixed at compile time | Dynamic volume allocation |
| **Read-write FS** | JFFS2 (slow mount) | UBIFS (faster mount) |
| **Flash overhead** | None | ~2-5% for UBI metadata |
| **Update method** | Write raw MTD partitions | Update UBI volumes |
| **Complexity** | Simple, well understood | More complex, better endurance |
| **Typical use** | SPI NOR, short lifecycle | SPI NOR/NAND, long lifecycle |

{: .tip }
Use static MTD for platforms where simplicity matters and flash writes are infrequent. Use UBI when the read-write partition receives heavy writes (logging, configuration changes) and flash endurance is a concern.

---

## Image Construction Process

The Yocto build system assembles the final firmware image through the `image_types_phosphor.bbclass` class. This section explains how each component is built and combined into the final flashable image.

### image_types_phosphor.bbclass Walkthrough

The `image_types_phosphor.bbclass` file in `meta-phosphor` defines the image assembly logic. It reads partition offset variables from your machine configuration and combines individual components into a single binary.

#### Key Configuration Variables

Set these variables in your machine configuration file (`conf/machine/<machine>.conf`):

| Variable | Unit | Description | 32MB Example | 64MB Example |
|----------|------|-------------|-------------|-------------|
| `FLASH_SIZE` | KB | Total flash size | `32768` | `65536` |
| `FLASH_UBOOT_OFFSET` | KB | U-Boot start offset | `0` | `0` |
| `FLASH_KERNEL_OFFSET` | KB | FIT image start offset | `1024` | `2048` |
| `FLASH_ROFS_OFFSET` | KB | Root filesystem start | `5120` | `10240` |
| `FLASH_RWFS_OFFSET` | KB | Read-write partition start | `27648` | `55296` |

{: .note }
All offset values are in **kilobytes**, not bytes. The build system converts them to byte offsets internally. For example, `FLASH_KERNEL_OFFSET = "1024"` corresponds to byte offset `0x100000`.

#### Machine Configuration Example

```bitbake
# conf/machine/myboard.conf

# Flash layout for 32MB SPI NOR
FLASH_SIZE = "32768"

# Partition offsets (in KB)
FLASH_UBOOT_OFFSET = "0"
FLASH_KERNEL_OFFSET = "1024"
FLASH_ROFS_OFFSET = "5120"
FLASH_RWFS_OFFSET = "27648"

# Image type selection
OBMC_IMAGE_TYPE = "static"  # or "ubi"
```

For a 64MB platform:

```bitbake
# conf/machine/myboard-64.conf

# Flash layout for 64MB SPI NOR
FLASH_SIZE = "65536"

# Partition offsets (in KB)
FLASH_UBOOT_OFFSET = "0"
FLASH_KERNEL_OFFSET = "2048"
FLASH_ROFS_OFFSET = "10240"
FLASH_RWFS_OFFSET = "55296"
```

### Assembly Process

The build system constructs the final image through a multi-stage pipeline. Each component is built independently, then combined into the final flashable binary.

#### Stage 1: Build Individual Components

```
┌─────────────────────────────────────────────────────────────┐
│                   Yocto Build System                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  u-boot recipe          linux-aspeed recipe                 │
│  ─────────────          ──────────────────                  │
│  u-boot.bin             fitImage                            │
│  u-boot-spl.bin           ├── vmlinux (compressed)          │
│                           ├── aspeed-bmc-*.dtb              │
│                           └── FIT header                    │
│                                                             │
│  obmc-phosphor-image recipe                                 │
│  ──────────────────────────                                 │
│  obmc-phosphor-image.squashfs                               │
│    ├── /usr/bin/ (phosphor daemons)                         │
│    ├── /usr/lib/ (shared libraries)                         │
│    ├── /etc/ (static configuration)                         │
│    └── /usr/share/ (data files, WebUI)                      │
│                                                             │
│  rwfs recipe                                                │
│  ───────────                                                │
│  rwfs.jffs2  (empty JFFS2 for read-write data)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Stage 2: Assemble Final Image

The `image_types_phosphor.bbclass` combines all components using `dd` commands with calculated offsets:

```bash
# Simplified assembly logic from image_types_phosphor.bbclass

# Create empty flash image (all 0xFF, matching erased NOR flash)
dd if=/dev/zero bs=1k count=${FLASH_SIZE} | tr '\000' '\377' > flash.img

# Write U-Boot at offset 0
dd if=u-boot-spl.bin of=flash.img bs=1k seek=${FLASH_UBOOT_OFFSET} conv=notrunc

# Write FIT image (kernel + dtb) at kernel offset
dd if=fitImage of=flash.img bs=1k seek=${FLASH_KERNEL_OFFSET} conv=notrunc

# Write squashfs root filesystem at rofs offset
dd if=obmc-phosphor-image.squashfs of=flash.img bs=1k \
   seek=${FLASH_ROFS_OFFSET} conv=notrunc

# Write empty JFFS2 read-write partition at rwfs offset
dd if=rwfs.jffs2 of=flash.img bs=1k seek=${FLASH_RWFS_OFFSET} conv=notrunc

# Result: flash.img is the complete .static.mtd image
```

The final output file is named `obmc-phosphor-image-<machine>.static.mtd` for static layouts or `obmc-phosphor-image-<machine>.ubi.mtd` for UBI layouts.

#### Stage 3: Output Artifacts

After the build completes, find the image artifacts in the deploy directory:

```bash
ls tmp/deploy/images/<machine>/

# Key output files:
# obmc-phosphor-image-<machine>.static.mtd    - Complete flash image (static)
# obmc-phosphor-image-<machine>.ubi.mtd       - Complete flash image (UBI)
# fitImage-<machine>.bin                       - Standalone FIT image
# u-boot-spl.bin                               - U-Boot SPL binary
# u-boot.bin                                   - U-Boot main binary
# obmc-phosphor-image-<machine>.squashfs      - Root filesystem
```

### Partition Size Calculations

Calculate available space for each partition to verify your image fits:

```
Kernel space  = FLASH_ROFS_OFFSET  - FLASH_KERNEL_OFFSET
RootFS space  = FLASH_RWFS_OFFSET  - FLASH_ROFS_OFFSET
RWFS space    = FLASH_SIZE         - FLASH_RWFS_OFFSET
```

For a 32MB static layout:

```
Kernel space  = 5120  - 1024  = 4096 KB  (4 MB)
RootFS space  = 27648 - 5120  = 22528 KB (22 MB)
RWFS space    = 32768 - 27648 = 5120 KB  (5 MB)
```

{: .warning }
If your squashfs rootfs exceeds the RootFS space, the build produces an image that overlaps partitions. The build system does not always catch this error. Always verify your image sizes after building.

### Verifying Image Sizes

Run this check after every build:

```bash
# Check individual component sizes
ls -lh tmp/deploy/images/<machine>/fitImage-*.bin
ls -lh tmp/deploy/images/<machine>/obmc-phosphor-image-<machine>.squashfs

# Compare against partition limits
KERNEL_MAX=$((5120 - 1024))  # 4096 KB for 32MB layout
ROFS_MAX=$((27648 - 5120))   # 22528 KB for 32MB layout

KERNEL_SIZE=$(stat -c%s tmp/deploy/images/<machine>/fitImage-*.bin)
ROFS_SIZE=$(stat -c%s tmp/deploy/images/<machine>/obmc-phosphor-image-*.squashfs)

echo "Kernel: $(($KERNEL_SIZE / 1024)) KB / ${KERNEL_MAX} KB"
echo "RootFS: $(($ROFS_SIZE / 1024)) KB / ${ROFS_MAX} KB"
```

---

## Image Size Reduction Techniques

When your image exceeds the available flash space, apply these techniques in order of impact and risk. Start with package removal, then move to kernel trimming and compression changes.

### Size Reduction Checklist

Use this prioritized checklist when you need to shrink your image:

- [ ] Remove unused packages from `IMAGE_INSTALL`
- [ ] Disable unnecessary `IMAGE_FEATURES`
- [ ] Strip debug symbols from all binaries
- [ ] Trim kernel configuration (disable unused subsystems)
- [ ] Switch to more aggressive filesystem compression
- [ ] Remove unused kernel modules
- [ ] Minimize WebUI assets (or remove WebUI entirely)
- [ ] Remove documentation and man pages from rootfs

### Technique 1: Remove Unused Packages

The most effective way to reduce image size is to remove packages you do not need. Use `IMAGE_INSTALL:remove` in your machine configuration or image recipe.

```bitbake
# In your machine layer: recipes-phosphor/images/obmc-phosphor-image.bbappend

# Remove packages not needed on your platform
IMAGE_INSTALL:remove = "\
    phosphor-snmp \
    phosphor-ipmi-ipmb \
    phosphor-host-postd \
    phosphor-post-code-manager \
    obmc-ikvm \
    phosphor-webui \
"

# Remove debug and development tools from production images
IMAGE_INSTALL:remove = "\
    gdb \
    strace \
    tcpdump \
    openssh-sftp-server \
    ipmitool \
"
```

{: .tip }
Run `bitbake -g obmc-phosphor-image && cat recipe-depends.dot | grep IMAGE_INSTALL` to see all packages pulled into the image. Alternatively, inspect `tmp/deploy/images/<machine>/obmc-phosphor-image-<machine>.manifest` for an installed package list with sizes.

#### Package Size Reference

Common packages and their approximate installed sizes:

| Package | Approx. Size | Notes |
|---------|-------------|-------|
| `phosphor-webui` | 3-5 MB | Web interface assets |
| `obmc-ikvm` | 1-2 MB | KVM-over-IP |
| `phosphor-snmp` | 200-500 KB | SNMP agent |
| `gdb` | 3-5 MB | GNU debugger |
| `strace` | 500 KB | System call tracer |
| `openssh-sftp-server` | 200 KB | SFTP subsystem |
| `tcpdump` | 800 KB | Network packet capture |
| `ipmitool` | 500 KB | IPMI command-line tool |

### Technique 2: Disable IMAGE_FEATURES

OpenBMC inherits several Yocto `IMAGE_FEATURES` that increase image size. Disable features you do not need:

```bitbake
# In your image recipe or local.conf

# Remove debug-related features
IMAGE_FEATURES:remove = "debug-tweaks"
IMAGE_FEATURES:remove = "tools-debug"
IMAGE_FEATURES:remove = "tools-profile"
IMAGE_FEATURES:remove = "dev-pkgs"
IMAGE_FEATURES:remove = "dbg-pkgs"

# If you do not need SSH access during development
# IMAGE_FEATURES:remove = "ssh-server-openssh"
```

{: .warning }
Removing `debug-tweaks` disables passwordless root login. Make sure you have an alternative authentication method configured before deploying to hardware.

### Technique 3: Kernel Configuration Trimming

The Linux kernel is the second-largest component in the FIT image. Trim unused subsystems to reduce kernel and module sizes.

#### Create a Kernel Config Fragment

```bash
# meta-<your-machine>/recipes-kernel/linux/linux-aspeed/<machine>-size.cfg

# ===== Disable Debug Options =====
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_FS is not set
# CONFIG_DEBUG_KERNEL is not set
# CONFIG_DEBUG_BUGVERBOSE is not set
# CONFIG_SCHED_DEBUG is not set
# CONFIG_FTRACE is not set
# CONFIG_FUNCTION_TRACER is not set
# CONFIG_STACK_TRACER is not set

# ===== Disable Unused Filesystems =====
# CONFIG_EXT4_FS is not set
# CONFIG_BTRFS_FS is not set
# CONFIG_XFS_FS is not set
# CONFIG_NFS_FS is not set
# CONFIG_NFSD is not set
# CONFIG_CIFS is not set
# CONFIG_FAT_FS is not set

# ===== Disable Unused Drivers =====
# CONFIG_SOUND is not set
# CONFIG_USB_GADGET is not set
# CONFIG_WIRELESS is not set
# CONFIG_WLAN is not set
# CONFIG_BLUETOOTH is not set
# CONFIG_INPUT_MOUSEDEV is not set
# CONFIG_INPUT_JOYDEV is not set
# CONFIG_VT is not set

# ===== Disable Unused Network Protocols =====
# CONFIG_IPV6 is not set          (only if IPv6 not needed)
# CONFIG_NETFILTER is not set     (only if iptables not needed)
# CONFIG_BRIDGE is not set
# CONFIG_DECNET is not set
# CONFIG_ECONET is not set
```

#### Apply the Fragment

```bitbake
# meta-<your-machine>/recipes-kernel/linux/linux-aspeed_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-aspeed:"

SRC_URI += "file://<machine>-size.cfg"
```

{: .note }
After changing kernel configuration, rebuild and check the FIT image size. Disabling `CONFIG_DEBUG_INFO` alone can save 5-10 MB from the uncompressed kernel. The compressed FIT image savings are typically 1-3 MB.

### Technique 4: Filesystem Compression

The root filesystem compression algorithm significantly affects the final image size. OpenBMC uses squashfs with configurable compression.

#### Compression Options

| Compression | Ratio | Decompress Speed | CPU Usage | Image Size (typical) |
|-------------|-------|-------------------|-----------|---------------------|
| `squashfs+gzip` | Good | Fast | Low | ~20 MB |
| `squashfs+xz` | Best | Slower | High | ~16 MB |
| `squashfs+zstd` | Very Good | Fast | Medium | ~17 MB |
| `squashfs+lzo` | Fair | Fastest | Lowest | ~22 MB |

Configure compression in your machine layer:

```bitbake
# In your machine.conf or local.conf

# Use xz for maximum compression (best for 32MB flash)
IMAGE_FSTYPES = "squashfs-xz"
EXTRA_IMAGECMD:squashfs-xz = "-comp xz -Xbcj arm -b 256K"

# Use zstd for good compression with faster boot (recommended for 64MB flash)
IMAGE_FSTYPES = "squashfs-zstd"
EXTRA_IMAGECMD:squashfs-zstd = "-comp zstd -Xcompression-level 19 -b 256K"
```

{: .tip }
Use `squashfs+xz` when you need to squeeze every byte for 32MB flash. Use `squashfs+zstd` when you have 64MB flash and prefer faster boot times. The `-Xbcj arm` option for xz enables ARM bytecode filtering, which improves compression of ARM binaries by 2-5%.

### Technique 5: Strip Debug Symbols

Ensure all binaries are stripped in production images:

```bitbake
# In your local.conf or machine.conf

# Strip all installed binaries
INHIBIT_PACKAGE_STRIP = "0"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

# Remove .debug directories from rootfs
PACKAGE_DEBUG_SPLIT_STYLE = "debug-without-src"
```

### Technique 6: Minimize WebUI and Static Assets

The WebUI can consume several megabytes. If you use Redfish API exclusively, remove it:

```bitbake
# Remove WebUI entirely
IMAGE_INSTALL:remove = "phosphor-webui"

# Or, if keeping WebUI, ensure assets are compressed
# The WebUI recipe typically includes pre-built compressed assets
```

### Size Reduction Summary

Expected savings from each technique (approximate, based on typical 32MB platform):

| Technique | Typical Savings | Risk Level |
|-----------|----------------|------------|
| Remove unused packages | 2-10 MB | Low |
| Disable IMAGE_FEATURES | 1-3 MB | Low |
| Kernel config trim | 1-3 MB | Medium |
| squashfs+gzip to squashfs+xz | 3-5 MB | Low |
| Strip debug symbols | 1-2 MB | Low |
| Remove WebUI | 3-5 MB | Low |
| **Total possible savings** | **11-28 MB** | |

---

## A/B Update Partitioning

A/B dual-image partitioning provides reliable firmware updates with automatic rollback. The flash stores two complete firmware images, and U-Boot selects which one to boot. If the newly updated image fails to boot, the system automatically falls back to the known-good image.

### A/B Flash Layout (32MB)

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  512 KB
 0x080000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  128 KB
           │   (bootside, bootcount, bootlimit)     │
 0x0A0000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~384 KB
 0x100000  ├────────────────────────────────────────┤
           │                                        │
           │          Image A (Active)              │  ~14 MB
           │    ┌─────────────────────────────┐     │
           │    │  FIT Image (kernel + dtb)   │     │  ~3 MB
           │    ├─────────────────────────────┤     │
           │    │  squashfs rootfs            │     │  ~11 MB
           │    └─────────────────────────────┘     │
           │                                        │
 0xF00000  ├────────────────────────────────────────┤
           │                                        │
           │         Image B (Standby)              │  ~14 MB
           │    ┌─────────────────────────────┐     │
           │    │  FIT Image (kernel + dtb)   │     │  ~3 MB
           │    ├─────────────────────────────┤     │
           │    │  squashfs rootfs            │     │  ~11 MB
           │    └─────────────────────────────┘     │
           │                                        │
 0x1D00000 ├────────────────────────────────────────┤
           │      Read-Write Data Partition         │  3 MB
           │           (shared between A/B)         │
 0x2000000 └────────────────────────────────────────┘
```

{: .warning }
A/B partitioning on 32MB flash is tight. Each image slot has roughly half the space of a single-image layout. Aggressive image size reduction (see previous section) is essential to fit both images.

### A/B Flash Layout (64MB)

With 64MB flash, A/B partitioning is comfortable:

```
 Offset       Size        Partition
 ─────────────────────────────────────────────────────
 0x000000  ┌────────────────────────────────────────┐
           │           U-Boot SPL + U-Boot          │  1 MB
 0x100000  ├────────────────────────────────────────┤
           │         U-Boot Environment             │  128 KB
 0x120000  ├────────────────────────────────────────┤
           │            (Reserved)                  │  ~896 KB
 0x200000  ├────────────────────────────────────────┤
           │                                        │
           │          Image A (Active)              │  ~28 MB
           │    ┌─────────────────────────────┐     │
           │    │  FIT Image (kernel + dtb)   │     │  ~6 MB
           │    ├─────────────────────────────┤     │
           │    │  squashfs rootfs            │     │  ~22 MB
           │    └─────────────────────────────┘     │
           │                                        │
 0x1E00000 ├────────────────────────────────────────┤
           │                                        │
           │         Image B (Standby)              │  ~28 MB
           │    ┌─────────────────────────────┐     │
           │    │  FIT Image (kernel + dtb)   │     │  ~6 MB
           │    ├─────────────────────────────┤     │
           │    │  squashfs rootfs            │     │  ~22 MB
           │    └─────────────────────────────┘     │
           │                                        │
 0x3A00000 ├────────────────────────────────────────┤
           │      Read-Write Data Partition         │  6 MB
           │           (shared between A/B)         │
 0x4000000 └────────────────────────────────────────┘
```

### U-Boot Environment Variables for A/B Boot

U-Boot manages the A/B boot selection through environment variables. These variables persist across reboots in the U-Boot environment partition.

| Variable | Description | Values |
|----------|-------------|--------|
| `bootside` | Currently selected boot image | `a` or `b` |
| `bootcount` | Number of consecutive boot attempts | Integer (0-N) |
| `bootlimit` | Maximum boot attempts before rollback | Integer (default: 3) |
| `bootcmd` | Top-level boot command | `run bootcmd_obmc` |
| `kerneladdr_a` | Load address for Image A kernel | Platform-specific |
| `kerneladdr_b` | Load address for Image B kernel | Platform-specific |

### Boot Selection Logic

The U-Boot boot command implements A/B selection with automatic rollback:

```bash
# U-Boot environment script for A/B boot

# Top-level boot command
bootcmd_obmc=run select_image; run load_kernel; run set_bootargs; bootm ${loadaddr}

# Select image based on bootside variable
select_image=\
  if test "${bootside}" = "a"; then \
    setenv kerneloff ${kerneloff_a}; \
    setenv rootfsoff ${rootfsoff_a}; \
    echo "Booting Image A"; \
  else \
    setenv kerneloff ${kerneloff_b}; \
    setenv rootfsoff ${rootfsoff_b}; \
    echo "Booting Image B"; \
  fi

# Load kernel from selected partition
load_kernel=sf probe 0; sf read ${loadaddr} ${kerneloff} ${kernelsize}

# Set kernel boot arguments with selected rootfs
set_bootargs=setenv bootargs console=ttyS4,115200 root=/dev/mtdblock${rootmtd} ro

# Partition offsets for each image
kerneloff_a=0x100000
rootfsoff_a=0x400000
kerneloff_b=0xF00000
rootfsoff_b=0x1200000
```

### Rollback Flow

The rollback mechanism works through a boot counter managed between U-Boot and the OpenBMC userspace:

```
┌─────────────────────────────────────────────────────────────┐
│                    A/B Rollback Flow                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Power On / Reset                                        │
│     │                                                       │
│     ▼                                                       │
│  2. U-Boot reads bootside (e.g., "a") and bootcount         │
│     │                                                       │
│     ├── bootcount < bootlimit?                              │
│     │   ├── YES: Increment bootcount, boot Image A          │
│     │   └── NO:  Switch bootside to "b", reset bootcount,   │
│     │            boot Image B (rollback)                    │
│     │                                                       │
│     ▼                                                       │
│  3. Linux kernel boots, systemd starts                      │
│     │                                                       │
│     ▼                                                       │
│  4. phosphor-bmc-state-manager reaches "Ready" state        │
│     │                                                       │
│     ▼                                                       │
│  5. phosphor-software-manager resets bootcount to 0         │
│     (Successful boot confirmed)                             │
│     │                                                       │
│     ▼                                                       │
│  6. System operational on Image A                           │
│                                                             │
│  ─── Firmware Update Flow ───                               │
│                                                             │
│  7. New firmware uploaded via Redfish/IPMI                  │
│     │                                                       │
│     ▼                                                       │
│  8. phosphor-software-manager writes new image to Image B   │
│     │                                                       │
│     ▼                                                       │
│  9. Set bootside="b", bootcount=0, reboot                   │
│     │                                                       │
│     ▼                                                       │
│  10. U-Boot boots Image B (new firmware)                    │
│      │                                                      │
│      ├── Boot succeeds: bootcount reset to 0                │
│      └── Boot fails: After bootlimit attempts,              │
│          U-Boot switches back to Image A (rollback)         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Configuring A/B in Your Machine Layer

Enable A/B update support in your machine configuration:

```bitbake
# conf/machine/myboard.conf

# Enable dual image support
OBMC_MACHINE_FEATURES += "obmc-phosphor-flash-mgmt"

# Flash layout for A/B partitioning (64MB example)
FLASH_SIZE = "65536"
FLASH_UBOOT_OFFSET = "0"

# Image A offsets
FLASH_KERNEL_OFFSET = "2048"
FLASH_ROFS_OFFSET = "10240"

# Image B offsets (set by alternate image configuration)
# These are managed by phosphor-software-manager

# Shared read-write partition
FLASH_RWFS_OFFSET = "59392"
```

```bitbake
# recipes-phosphor/flash/phosphor-software-manager_%.bbappend

# Enable dual image support
EXTRA_OEMESON:append = " -Dfwupd-type=static-dual"
```

{: .note }
The `phosphor-software-manager` handles writing the update to the alternate partition. You do not manually manage Image B offsets in the machine configuration. The software manager calculates the alternate partition location based on the flash layout.

---

## eMMC vs NOR Flash Comparison

Some newer BMC platforms offer eMMC storage as an alternative to traditional SPI NOR flash. This section compares the two options to help you choose the right storage technology.

### Comparison Table

| Aspect | SPI NOR Flash | eMMC |
|--------|--------------|------|
| **Typical capacity** | 32 MB - 128 MB | 4 GB - 64 GB |
| **Read speed** | 50-100 MB/s | 100-300 MB/s |
| **Write speed** | 1-5 MB/s (page write) | 30-90 MB/s |
| **Erase block size** | 4-64 KB | 512 KB (managed internally) |
| **Wear leveling** | None (manual via UBI) | Built-in controller |
| **Endurance** | 100K erase cycles (typical) | 3K-10K P/E cycles (per cell) |
| **Boot time** | Fast (XIP capable) | Slightly slower (needs init) |
| **Execute in place (XIP)** | Yes | No |
| **Cost per MB** | High | Low |
| **Power failure safety** | Good (atomic page writes) | Varies (needs FTL) |
| **OpenBMC support** | Mature, well tested | Emerging, platform-specific |

### NOR Flash Filesystem Layout

```
SPI NOR Flash (32MB)
┌──────────────────────────────┐
│  U-Boot     │  MTD raw       │
│  Kernel     │  MTD raw       │
│  RootFS     │  squashfs      │
│  RWFS       │  JFFS2/UBIFS   │
└──────────────────────────────┘
   Direct memory-mapped access
   Simple, predictable boot path
```

### eMMC Filesystem Layout

```
eMMC (4GB+)
┌───────────────────────────────────────────────────────┐
│  Boot Partition 0  │  U-Boot (hardware boot partition)│
│  Boot Partition 1  │  U-Boot (backup)                 │  
├───────────────────────────────────────────────────────┤
│  User Data Area                                       │
│  ┌────────────────────────────────────────────┐       │
│  │  Partition 1: /boot    (ext4)   200 MB     │       │
│  │    fitImage, dtb                           │       │
│  ├────────────────────────────────────────────┤       │
│  │  Partition 2: /        (ext4)   2 GB       │       │
│  │    Full root filesystem                    │       │
│  ├────────────────────────────────────────────┤       │
│  │  Partition 3: /var     (ext4)   1 GB       │       │
│  │    Logs, persistent data                   │       │
│  ├────────────────────────────────────────────┤       │
│  │  Partition 4: (spare)          remaining   │       │
│  │    A/B alternate image, factory reset      │       │
│  └────────────────────────────────────────────┘       │
└───────────────────────────────────────────────────────┘
   Block device access via MMC controller
   Standard partition table (GPT)
```

### When to Use Each

**Choose SPI NOR when:**
- Your platform has 32-64 MB flash and does not need more
- You need the fastest possible boot time (XIP support)
- You want the most mature and tested OpenBMC support
- Your design is cost-sensitive and does not need large storage
- You prefer the simplest possible boot path

**Choose eMMC when:**
- You need more than 128 MB of storage (diagnostics, crash dumps, logs)
- Your platform performs frequent write operations to persistent storage
- You want built-in wear leveling without UBI overhead
- You plan to store large assets (BIOS images, firmware bundles)
- Your SoC has a built-in eMMC controller (AST2600 supports eMMC)

{: .note }
The AST2600 supports both SPI NOR and eMMC boot. You can use SPI NOR as the primary boot device with eMMC for extended storage, giving you the reliability of NOR flash boot with the capacity of eMMC.

---

## Code Examples

### Example 1: Image Size Analysis Script

Use this script to identify the largest packages in your OpenBMC image:

```bash
#!/bin/bash
# analyze-image-size.sh - Analyze OpenBMC image size contributors
# Usage: ./analyze-image-size.sh <build-dir> <machine>

BUILD_DIR=${1:-.}
MACHINE=${2:-$(cat ${BUILD_DIR}/conf/local.conf | grep ^MACHINE | awk -F'"' '{print $2}')}
DEPLOY="${BUILD_DIR}/tmp/deploy/images/${MACHINE}"
MANIFEST="${DEPLOY}/obmc-phosphor-image-${MACHINE}.manifest"

echo "=== Flash Image Size Analysis ==="
echo "Machine: ${MACHINE}"
echo ""

# Total image size
if [ -f "${DEPLOY}/obmc-phosphor-image-${MACHINE}.static.mtd" ]; then
    TOTAL=$(stat -c%s "${DEPLOY}/obmc-phosphor-image-${MACHINE}.static.mtd")
    echo "Total flash image: $(($TOTAL / 1024 / 1024)) MB"
fi

# Individual component sizes
echo ""
echo "=== Component Sizes ==="
for f in fitImage*.bin *.squashfs u-boot*.bin; do
    FILE="${DEPLOY}/${f}"
    if [ -f "${FILE}" ]; then
        SIZE=$(stat -c%s "${FILE}")
        printf "  %-50s %8d KB\n" "${f}" "$(($SIZE / 1024))"
    fi
done

# Package manifest (top 20 largest)
echo ""
echo "=== Top 20 Packages by Installed Size ==="
if [ -f "${MANIFEST}" ]; then
    # The manifest lists package-name arch version
    # Use opkg to get sizes from the package database
    ROOTFS="${BUILD_DIR}/tmp/work/*-openbmc-linux/obmc-phosphor-image/*/rootfs"
    if [ -d ${ROOTFS} ]; then
        du -sk ${ROOTFS}/usr/bin/* ${ROOTFS}/usr/lib/* ${ROOTFS}/usr/sbin/* \
            2>/dev/null | sort -rn | head -20 | \
            awk '{printf "  %-50s %8d KB\n", $2, $1}'
    fi
fi

echo ""
echo "=== Filesystem Space Check ==="
echo "Compare sizes against partition limits in your machine.conf"
```

See the complete example at [examples/flash-layout/]({{ site.baseurl }}/examples/flash-layout/).

### Example 2: Custom Flash Layout Configuration

This example shows a minimal machine configuration with A/B support for a 64MB platform:

```bitbake
# conf/machine/example-bmc.conf - Flash layout with A/B support

#@TYPE: Machine
#@NAME: Example BMC with A/B flash
#@DESCRIPTION: 64MB flash with dual-image support

require conf/machine/include/ast2600.inc
require conf/machine/include/obmc-bsp-common.inc

# Flash configuration
FLASH_SIZE = "65536"
FLASH_UBOOT_OFFSET = "0"
FLASH_KERNEL_OFFSET = "2048"
FLASH_ROFS_OFFSET = "10240"
FLASH_RWFS_OFFSET = "59392"

# Use static image with dual support
OBMC_IMAGE_TYPE = "static"

# Compression for fitting A/B images
EXTRA_IMAGECMD:squashfs-xz = "-comp xz -Xbcj arm -b 256K"

# Enable flash management
OBMC_MACHINE_FEATURES += "obmc-phosphor-flash-mgmt"
```

### Example 3: Verifying Flash Layout on Target

Run these commands on a booted OpenBMC system to inspect the actual flash layout:

```bash
# View MTD partition table
cat /proc/mtd
# Output:
# dev:    size   erasesize  name
# mtd0: 00060000 00010000 "u-boot"
# mtd1: 00020000 00010000 "u-boot-env"
# mtd2: 00400000 00010000 "kernel"
# mtd3: 01600000 00010000 "rofs"
# mtd4: 00500000 00010000 "rwfs"

# Check mounted filesystems
mount | grep mtd
# /dev/mtdblock3 on / type squashfs (ro)
# /dev/mtdblock4 on /var type jffs2 (rw)

# Check flash usage
df -h
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/root        22M   18M   0  100% /
# /dev/mtdblock4  5.0M  1.2M  3.8M  24% /var

# Read flash info via sysfs
for mtd in /sys/class/mtd/mtd*/; do
    echo "$(basename $mtd): $(cat ${mtd}name) - $(cat ${mtd}size) bytes"
done
```

---

## Troubleshooting

### Issue: Image Exceeds Flash Partition Size

**Symptom**: Build completes but the system fails to boot, or you see warnings about image size during build.

**Cause**: The squashfs rootfs or FIT image has grown beyond the space allocated between partition offsets.

**Solution**:
1. Check component sizes: `ls -lh tmp/deploy/images/<machine>/*.squashfs`
2. Compare against available space: `FLASH_RWFS_OFFSET - FLASH_ROFS_OFFSET` (in KB)
3. Apply image size reduction techniques from the section above
4. If size reduction is insufficient, increase `FLASH_RWFS_OFFSET` or use a larger flash part

### Issue: JFFS2 Mount Fails After Flash Update

**Symptom**: System boots but `/var` or other read-write paths are not available. Kernel log shows JFFS2 errors.

**Cause**: The read-write partition was not properly erased before writing the new JFFS2 image, or the partition offset changed between firmware versions.

**Solution**:
1. Erase the RWFS partition from U-Boot: `sf erase <rwfs_offset> <rwfs_size>`
2. Verify partition offsets match between old and new firmware
3. Consider using UBI layout for better flash management

### Issue: A/B Rollback Loop

**Symptom**: System continuously switches between Image A and Image B without successfully booting.

**Cause**: Both images are corrupted or have the same boot-blocking issue. The boot counter reaches `bootlimit` on each side.

**Solution**:
1. Interrupt U-Boot at the serial console (press a key during countdown)
2. Manually set the boot side: `setenv bootside a; setenv bootcount 0; saveenv`
3. Boot manually: `run bootcmd_obmc`
4. If both images are bad, reflash via UART or JTAG using a known-good image

### Issue: UBI Volume Attach Fails

**Symptom**: Boot fails with UBI errors like `ubi0 error: ubi_io_read` or `UBI error: cannot attach`.

**Cause**: The UBI metadata on flash is corrupted, often from a power loss during a UBI write or from flashing a static image to a UBI-formatted partition.

**Solution**:
1. Reformat the UBI partition from U-Boot:
   ```bash
   sf probe 0
   sf erase 0x100000 0x1F00000  # Erase entire UBI area
   ```
2. Reflash the complete UBI image
3. Ensure you flash UBI images (`.ubi.mtd`) to UBI-formatted flash, not static images

### Debug Commands

```bash
# Check MTD partition layout
cat /proc/mtd

# Read flash ID and status
mtd_debug info /dev/mtd0

# Dump flash content for analysis
nanddump /dev/mtd2 -f /tmp/kernel-dump.bin

# Check UBI device info
ubinfo -a

# View U-Boot environment from Linux
fw_printenv

# Modify U-Boot environment from Linux
fw_setenv bootside a
fw_setenv bootcount 0

# Check image version and activation status
busctl tree xyz.openbmc_project.Software.BMC.Updater
busctl introspect xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software
```

---

## References

### Official Resources
- [OpenBMC image_types_phosphor.bbclass](https://github.com/openbmc/openbmc/blob/master/meta-phosphor/classes/image_types_phosphor.bbclass)
- [phosphor-bmc-code-mgmt (Software Manager)](https://github.com/openbmc/phosphor-bmc-code-mgmt)
- [OpenBMC Flash Layout Documentation](https://github.com/openbmc/docs/blob/master/architecture/code-update/flash-layout.md)

### Related Guides
- [U-Boot Guide]({% link docs/06-porting/04-uboot.md %})
- [Machine Layer Guide]({% link docs/06-porting/02-machine-layer.md %})
- [Firmware Update Guide]({% link docs/05-advanced/03-firmware-update-guide.md %})
- [Porting Reference]({% link docs/06-porting/01-porting-reference.md %})

### External Documentation
- [MTD Subsystem Documentation](http://www.linux-mtd.infradead.org/)
- [UBI - Unsorted Block Images](http://www.linux-mtd.infradead.org/doc/ubi.html)
- [SquashFS Documentation](https://docs.kernel.org/filesystems/squashfs.html)
- [Yocto Project Image Creation](https://docs.yoctoproject.org/dev-manual/images.html)

---

{: .note }
**Tested on**: Architectural reference documentation - requires real hardware for full flash layout validation.
Last updated: 2025-02-06
