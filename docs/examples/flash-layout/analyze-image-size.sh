#!/bin/bash
# =============================================================================
# analyze-image-size.sh -- Analyze OpenBMC image size breakdown
#
# Examines a built OpenBMC rootfs directory (or deploy directory) and reports:
#   - Top 20 largest installed packages (via opkg status or du fallback)
#   - Directory-level size breakdown of the rootfs
#   - Estimated partition sizes (kernel, rootfs, rwfs)
#   - Shared library usage summary
#
# Usage:
#   ./analyze-image-size.sh <rootfs-dir>
#   ./analyze-image-size.sh <deploy-dir>    # contains *.rootfs.squashfs, fitImage, etc.
#   ./analyze-image-size.sh --help
#
# Examples:
#   # Analyze rootfs from bitbake work directory
#   ./analyze-image-size.sh build/tmp/work/ast2600-evb-openbmc-linux/obmc-phosphor-image/1.0-r0/rootfs
#
#   # Analyze extracted squashfs
#   mkdir /tmp/rootfs
#   unsquashfs -d /tmp/rootfs obmc-phosphor-image-ast2600-evb.rootfs.squashfs
#   ./analyze-image-size.sh /tmp/rootfs
#
#   # Analyze deploy directory for full image breakdown
#   ./analyze-image-size.sh build/tmp/deploy/images/ast2600-evb
#
# Requires: du, sort, awk, find (standard coreutils)
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TOP_N=20
DIVIDER="============================================================================="
SUBDIV="-----------------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 <rootfs-directory | deploy-directory>"
    echo ""
    echo "Analyze OpenBMC image size breakdown."
    echo ""
    echo "Arguments:"
    echo "  <rootfs-directory>   Path to an OpenBMC rootfs (e.g., from unsquashfs)"
    echo "  <deploy-directory>   Path to deploy/images/<machine>/ with built artifacts"
    echo ""
    echo "Options:"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /tmp/rootfs"
    echo "  $0 build/tmp/deploy/images/ast2600-evb"
    exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
human_size() {
    # Convert bytes to human-readable
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f GB\", $bytes/1073741824}")"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f MB\", $bytes/1048576}")"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.1f KB\", $bytes/1024}")"
    else
        echo "${bytes} B"
    fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
fi

TARGET_DIR="$1"

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: Directory not found: $TARGET_DIR"
    exit 1
fi

echo "$DIVIDER"
echo "  OpenBMC Image Size Analyzer"
echo "$DIVIDER"
echo ""
echo "Target: $TARGET_DIR"
echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ---------------------------------------------------------------------------
# Detect mode: rootfs directory vs deploy directory
# ---------------------------------------------------------------------------
IS_ROOTFS=false
IS_DEPLOY=false

if [ -d "$TARGET_DIR/usr" ] && [ -d "$TARGET_DIR/etc" ]; then
    IS_ROOTFS=true
    echo "Mode: rootfs analysis"
elif ls "$TARGET_DIR"/*.squashfs >/dev/null 2>&1 || \
     ls "$TARGET_DIR"/fitImage* >/dev/null 2>&1 || \
     ls "$TARGET_DIR"/image-* >/dev/null 2>&1; then
    IS_DEPLOY=true
    echo "Mode: deploy directory analysis"
else
    # Assume rootfs if it has some typical directories
    if [ -d "$TARGET_DIR/lib" ] || [ -d "$TARGET_DIR/bin" ]; then
        IS_ROOTFS=true
        echo "Mode: rootfs analysis (best guess)"
    else
        echo "WARNING: Cannot determine directory type. Treating as rootfs."
        IS_ROOTFS=true
    fi
fi

echo ""

# ===========================================================================
# Section 1: Deploy directory -- image artifact sizes
# ===========================================================================
if [ "$IS_DEPLOY" = true ]; then
    echo "$DIVIDER"
    echo "  IMAGE ARTIFACT SIZES"
    echo "$DIVIDER"
    echo ""

    printf "%-50s %12s\n" "Artifact" "Size"
    echo "$SUBDIV"

    TOTAL_BYTES=0
    for f in "$TARGET_DIR"/image-* "$TARGET_DIR"/fitImage* "$TARGET_DIR"/*.squashfs \
             "$TARGET_DIR"/u-boot* "$TARGET_DIR"/*.static.mtd "$TARGET_DIR"/*.ubi \
             "$TARGET_DIR"/*.jffs2; do
        if [ -f "$f" ]; then
            SIZE_BYTES=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
            TOTAL_BYTES=$((TOTAL_BYTES + SIZE_BYTES))
            printf "%-50s %12s\n" "$(basename "$f")" "$(human_size "$SIZE_BYTES")"
        fi
    done

    echo "$SUBDIV"
    printf "%-50s %12s\n" "TOTAL" "$(human_size "$TOTAL_BYTES")"
    echo ""

    # If there is a squashfs, extract and analyze it
    SQUASHFS=$(ls "$TARGET_DIR"/*.rootfs.squashfs 2>/dev/null | head -1)
    if [ -n "$SQUASHFS" ] && command -v unsquashfs >/dev/null 2>&1; then
        echo "Found squashfs: $(basename "$SQUASHFS")"
        echo "Extracting for detailed analysis..."
        TMPDIR=$(mktemp -d)
        trap 'rm -rf "$TMPDIR"' EXIT
        unsquashfs -d "$TMPDIR/rootfs" "$SQUASHFS" >/dev/null 2>&1
        TARGET_DIR="$TMPDIR/rootfs"
        IS_ROOTFS=true
        echo ""
    fi
fi

# ===========================================================================
# Section 2: Package sizes (opkg status or du-based estimation)
# ===========================================================================
if [ "$IS_ROOTFS" = true ]; then
    echo "$DIVIDER"
    echo "  TOP $TOP_N LARGEST PACKAGES"
    echo "$DIVIDER"
    echo ""

    OPKG_STATUS="$TARGET_DIR/var/lib/opkg/status"

    if [ -f "$OPKG_STATUS" ]; then
        # Parse opkg status file for installed-size data
        printf "%-40s %12s\n" "Package" "Installed Size"
        echo "$SUBDIV"

        awk '
        /^Package:/ { pkg = $2 }
        /^Installed-Size:/ {
            size = $2
            if (size > 0) {
                sizes[pkg] = size
            }
        }
        END {
            # Sort by size descending
            n = asorti(sizes, sorted)
            # Build array for sorting by value
            for (i = 1; i <= n; i++) {
                val_pkg[i] = sizes[sorted[i]] "\t" sorted[i]
            }
            # Simple selection sort (top N)
            for (i = 1; i <= n; i++) {
                max_idx = i
                split(val_pkg[i], a, "\t")
                max_val = a[1] + 0
                for (j = i + 1; j <= n; j++) {
                    split(val_pkg[j], b, "\t")
                    if (b[1] + 0 > max_val) {
                        max_val = b[1] + 0
                        max_idx = j
                    }
                }
                if (max_idx != i) {
                    tmp = val_pkg[i]
                    val_pkg[i] = val_pkg[max_idx]
                    val_pkg[max_idx] = tmp
                }
            }
            total = 0
            count = (n < '"$TOP_N"') ? n : '"$TOP_N"'
            for (i = 1; i <= count; i++) {
                split(val_pkg[i], parts, "\t")
                sz = parts[1] + 0
                pkg_name = parts[2]
                total += sz
                if (sz >= 1048576) {
                    printf "%-40s %10.1f MB\n", pkg_name, sz / 1048576
                } else if (sz >= 1024) {
                    printf "%-40s %10.1f KB\n", pkg_name, sz / 1024
                } else {
                    printf "%-40s %10d B\n", pkg_name, sz
                }
            }
            print "'"$SUBDIV"'"
            grand = 0
            for (i = 1; i <= n; i++) {
                split(val_pkg[i], p, "\t")
                grand += p[1] + 0
            }
            printf "%-40s %10.1f MB\n", "Total (" n " packages)", grand / 1048576
        }
        ' "$OPKG_STATUS"

    else
        # Fallback: use du to estimate package sizes by directory
        echo "(opkg status not found -- using du-based estimation)"
        echo ""
        printf "%-40s %12s\n" "Directory" "Size"
        echo "$SUBDIV"

        du -s "$TARGET_DIR"/usr/bin/* "$TARGET_DIR"/usr/sbin/* \
              "$TARGET_DIR"/usr/lib/lib*.so* "$TARGET_DIR"/usr/libexec/* \
              2>/dev/null | \
            sort -rn | \
            head -"$TOP_N" | \
            while read -r size path; do
                name=$(basename "$path")
                if [ "$size" -ge 1024 ]; then
                    printf "%-40s %10.1f MB\n" "$name" "$(awk "BEGIN {printf \"%.1f\", $size/1024}")"
                else
                    printf "%-40s %10d KB\n" "$name" "$size"
                fi
            done
    fi

    echo ""

    # =========================================================================
    # Section 3: Top-level directory breakdown
    # =========================================================================
    echo "$DIVIDER"
    echo "  ROOTFS DIRECTORY BREAKDOWN"
    echo "$DIVIDER"
    echo ""

    printf "%-30s %12s %8s\n" "Directory" "Size" "Percent"
    echo "$SUBDIV"

    TOTAL_KB=$(du -sk "$TARGET_DIR" 2>/dev/null | awk '{print $1}')

    du -sk "$TARGET_DIR"/* 2>/dev/null | sort -rn | while read -r size dir; do
        name=$(basename "$dir")
        pct=$(awk "BEGIN {printf \"%.1f\", ($size / $TOTAL_KB) * 100}")
        if [ "$size" -ge 1024 ]; then
            printf "%-30s %10.1f MB %7s%%\n" "$name" "$(awk "BEGIN {printf \"%.1f\", $size/1024}")" "$pct"
        else
            printf "%-30s %10d KB %7s%%\n" "$name" "$size" "$pct"
        fi
    done

    echo "$SUBDIV"
    printf "%-30s %10.1f MB %7s%%\n" "TOTAL" "$(awk "BEGIN {printf \"%.1f\", $TOTAL_KB/1024}")" "100.0"
    echo ""

    # =========================================================================
    # Section 4: Shared library analysis
    # =========================================================================
    echo "$DIVIDER"
    echo "  TOP 15 LARGEST SHARED LIBRARIES"
    echo "$DIVIDER"
    echo ""

    printf "%-45s %12s\n" "Library" "Size"
    echo "$SUBDIV"

    find "$TARGET_DIR" -name "*.so*" -type f 2>/dev/null | while read -r lib; do
        size=$(stat -c%s "$lib" 2>/dev/null || stat -f%z "$lib" 2>/dev/null || echo 0)
        echo "$size $lib"
    done | sort -rn | head -15 | while read -r size lib; do
        name=$(basename "$lib")
        if [ "$size" -ge 1048576 ]; then
            printf "%-45s %10.1f MB\n" "$name" "$(awk "BEGIN {printf \"%.1f\", $size/1048576}")"
        elif [ "$size" -ge 1024 ]; then
            printf "%-45s %10.1f KB\n" "$name" "$(awk "BEGIN {printf \"%.1f\", $size/1024}")"
        else
            printf "%-45s %10d B\n" "$name" "$size"
        fi
    done

    echo ""

    # =========================================================================
    # Section 5: Estimated flash partition sizes
    # =========================================================================
    echo "$DIVIDER"
    echo "  ESTIMATED FLASH PARTITION USAGE"
    echo "$DIVIDER"
    echo ""

    ROOTFS_KB=$TOTAL_KB

    # Estimate squashfs compressed size (typical 40-50% compression with XZ)
    ROOTFS_COMPRESSED_KB=$(awk "BEGIN {printf \"%d\", $ROOTFS_KB * 0.45}")

    echo "Rootfs uncompressed:     $(awk "BEGIN {printf \"%.1f MB\", $ROOTFS_KB/1024}")"
    echo "Rootfs estimated squashfs (XZ): ~$(awk "BEGIN {printf \"%.1f MB\", $ROOTFS_COMPRESSED_KB/1024}") (estimated 45% ratio)"
    echo ""

    echo "Estimated 32 MB flash usage:"
    echo "  U-Boot:        384 KB  (fixed)"
    echo "  U-Boot env:    128 KB  (fixed)"
    echo "  Kernel FIT:    ~4.0 MB (typical)"
    USED_32=$(awk "BEGIN {printf \"%.1f\", (384 + 128 + 4096 + $ROOTFS_COMPRESSED_KB) / 1024}")
    REMAIN_32=$(awk "BEGIN {printf \"%.1f\", 32 - $USED_32}")
    echo "  RO rootfs:     ~$(awk "BEGIN {printf \"%.1f MB\", $ROOTFS_COMPRESSED_KB/1024}")"
    echo "  --------------------------------"
    echo "  Used:          ~${USED_32} MB of 32.0 MB"
    echo "  Remaining (rwfs): ~${REMAIN_32} MB"
    echo ""

    if [ "$(echo "$REMAIN_32" | awk '{print ($1 < 2.0)}')" = "1" ]; then
        echo "  WARNING: Less than 2 MB remaining for read-write partition."
        echo "  Consider removing packages or switching to 64 MB flash."
        echo ""
    fi

    echo "Estimated 64 MB flash usage (UBI, A/B):"
    USED_64=$(awk "BEGIN {printf \"%.1f\", (512 + 128 + (4096 * 2) + ($ROOTFS_COMPRESSED_KB * 2)) / 1024}")
    REMAIN_64=$(awk "BEGIN {printf \"%.1f\", 64 - $USED_64}")
    echo "  U-Boot:        512 KB  (fixed)"
    echo "  U-Boot env:    128 KB  (fixed)"
    echo "  Kernel A + B:  ~8.0 MB (2x 4.0 MB)"
    echo "  Rootfs A + B:  ~$(awk "BEGIN {printf \"%.1f MB\", ($ROOTFS_COMPRESSED_KB * 2)/1024}") (2x squashfs)"
    echo "  --------------------------------"
    echo "  Used:          ~${USED_64} MB of 64.0 MB"
    echo "  Remaining (rwfs): ~${REMAIN_64} MB"
fi

echo ""
echo "$DIVIDER"
echo "  Analysis complete."
echo "$DIVIDER"
