# Flash Layout Optimization Examples

Scripts, annotated flash layouts, and configuration snippets for understanding and
optimizing OpenBMC flash usage on AST2500/AST2600 platforms.

> **Target audience** -- platform engineers porting OpenBMC or working to reduce
> image size on constrained 32 MB SPI-NOR flash parts.

## Files

| File | Description |
|------|-------------|
| `analyze-image-size.sh` | Analyze a built OpenBMC rootfs: list installed packages by size, show image partition breakdown |
| `flash-layout-32mb.txt` | Annotated ASCII flash map for 32 MB static MTD layout (U-Boot + kernel FIT + squashfs + JFFS2) |
| `flash-layout-64mb-ubi.txt` | Annotated ASCII flash map for 64 MB UBI layout with A/B kernel+rootfs volumes |
| `image-size-reduction.conf` | Example `local.conf` snippet with `IMAGE_INSTALL:remove` entries, kernel config trimming, and compression options |

## Quick Start

### Analyze a Built Image

```bash
# After building OpenBMC:
cd build/tmp/deploy/images/<machine>/

# Analyze the rootfs directory (created by bitbake)
./analyze-image-size.sh ../../work/<machine>-openbmc-linux/obmc-phosphor-image/1.0-r0/rootfs

# Or analyze an extracted image
mkdir /tmp/rootfs && unsquashfs -d /tmp/rootfs obmc-phosphor-image-*.rootfs.squashfs
./analyze-image-size.sh /tmp/rootfs
```

### Apply Size Reduction Config

```bash
# Copy the snippet into your build configuration
cat image-size-reduction.conf >> build/conf/local.conf

# Rebuild
bitbake obmc-phosphor-image
```

### View Flash Layouts

The `.txt` layout files are reference diagrams. Compare them against your
machine configuration:

```bash
# Check your machine's flash layout definition
cat meta-<vendor>/conf/machine/<machine>.conf | grep -E 'FLASH_SIZE|FLASH_UBOOT|FLASH_KERNEL'

# Check actual MTD partitions on a running BMC
cat /proc/mtd
```

## Typical OpenBMC Image Sizes

| Component | Typical Size | Notes |
|-----------|-------------|-------|
| U-Boot (SPL + full) | 384 KB -- 512 KB | Rarely changes between releases |
| Kernel FIT (zImage + DTB) | 3.5 MB -- 4.5 MB | Trimming unused drivers helps significantly |
| Root filesystem (squashfs) | 18 MB -- 28 MB | Largest component; main optimization target |
| Read-write data (JFFS2/UBIFS) | 4 MB -- 8 MB | Persistent settings, logs, certificates |

## Common Optimization Strategies

1. **Remove unused packages** -- Drop debug tools, test utilities, unused daemons
2. **Trim kernel config** -- Disable unused filesystems, network protocols, USB gadget drivers
3. **Switch to musl libc** -- Saves 1--2 MB vs glibc
4. **Strip binaries aggressively** -- Ensure `INHIBIT_PACKAGE_STRIP` is not set
5. **Use squashfs XZ compression** -- Better compression ratio than gzip/lzo
6. **Remove locale data** -- Set `IMAGE_LINGUAS = ""` to drop translations

## References

- [Flash Layout Optimization Guide](../../05-advanced/08-flash-layout-optimization.md) -- full guide with architecture details
- [OpenBMC flash layout documentation](https://github.com/openbmc/docs/blob/master/architecture/code-update/flash-layout.md)
- [Yocto IMAGE_INSTALL variable](https://docs.yoctoproject.org/ref-manual/variables.html#term-IMAGE_INSTALL)
- [squashfs-tools documentation](https://github.com/plougher/squashfs-tools)
