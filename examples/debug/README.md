# Debug Tools Examples

This directory contains example configuration files for enabling Linux debugging tools in OpenBMC builds.

## Files

| File | Description |
|------|-------------|
| `asan-local.conf` | Yocto local.conf additions for ASan builds |
| `valgrind.supp` | Valgrind suppression file for OpenBMC |
| `tsan.supp` | ThreadSanitizer suppression file |
| `kernel-debug.cfg` | Kernel config fragment for debug options |

## Usage

### ASan Build Configuration

Copy `asan-local.conf` contents to your `build/conf/local.conf`:

```bash
cat examples/debug/asan-local.conf >> build/conf/local.conf
bitbake obmc-phosphor-image
```

### Valgrind Suppressions

Copy to target and use with Valgrind:

```bash
scp valgrind.supp root@bmc:/etc/
valgrind --suppressions=/etc/valgrind.supp --leak-check=full /usr/bin/program
```

### TSan Suppressions

For 64-bit builds with ThreadSanitizer:

```bash
scp tsan.supp root@bmc:/etc/
export TSAN_OPTIONS="suppressions=/etc/tsan.supp"
```

### Kernel Debug Configuration

Add to your kernel build:

```bash
cp kernel-debug.cfg meta-mylayer/recipes-kernel/linux/files/
```

In your `linux-aspeed_%.bbappend`:

```bitbake
SRC_URI += "file://kernel-debug.cfg"
```

## Performance Impact

| Configuration | CPU Overhead | Memory Overhead |
|---------------|--------------|-----------------|
| ASan | ~2x | ~2-3x |
| ASan + UBSan | ~2.2x | ~2-3x |
| TSan | ~5-15x | ~5-10x |
| KASAN | ~1.5-3x | ~1.5-2x |
| Valgrind | ~10-50x | ~2x |

## Recommendations

1. **Development**: Use ASan + UBSan for regular development
2. **CI Testing**: Enable ASan + UBSan for all test builds
3. **Race Debugging**: Use TSan (64-bit) or Valgrind helgrind
4. **Production**: Never ship with sanitizers enabled

## Related Documentation

- [Linux Debug Tools Guide](../../docs/05-advanced/08-linux-debug-tools-guide.md)
- [Environment Setup Guide](../../docs/01-getting-started/02-environment-setup.md)
