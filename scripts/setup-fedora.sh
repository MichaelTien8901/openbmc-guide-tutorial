#!/bin/bash
# OpenBMC Development Environment Setup for Fedora 34+
# Usage: ./setup-fedora.sh

set -e

echo "=========================================="
echo "OpenBMC Development Environment Setup"
echo "Fedora 34+"
echo "=========================================="

# Check Fedora version
if ! grep -q "Fedora" /etc/os-release 2>/dev/null; then
    echo "Warning: This script is designed for Fedora"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install required packages
echo ""
echo ">>> Installing Yocto/BitBake dependencies..."
sudo dnf install -y \
    gawk make wget tar bzip2 gzip python3 unzip perl patch \
    diffutils diffstat git cpp gcc gcc-c++ glibc-devel \
    texinfo chrpath ccache perl-Data-Dumper perl-Text-ParseWords \
    perl-Thread-Queue perl-bignum socat python3-pexpect \
    findutils which file cpio python python3-pip xz python3-GitPython \
    python3-jinja2 SDL-devel xterm rpcgen mesa-libGL-devel \
    perl-FindBin perl-File-Compare perl-File-Copy perl-locale \
    zstd lz4

# Install additional tools
echo ""
echo ">>> Installing additional development tools..."
sudo dnf install -y \
    curl vim tmux htop tree \
    openssl-devel libffi-devel

# Install QEMU
echo ""
echo ">>> Installing QEMU..."
sudo dnf install -y qemu-system-arm

# Verify installations
echo ""
echo "=========================================="
echo "Verification"
echo "=========================================="
echo "Git version: $(git --version)"
echo "Python version: $(python3 --version)"
echo "GCC version: $(gcc --version | head -1)"
echo "QEMU version: $(qemu-system-arm --version | head -1)"

# Check resources
echo ""
echo "System Resources:"
echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Disk: $(df -h ~ | awk 'NR==2 {print $4}') available"
echo "CPUs: $(nproc)"

# Recommendations
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Clone OpenBMC:"
echo "     git clone https://github.com/openbmc/openbmc.git"
echo "     cd openbmc"
echo ""
echo "  2. Initialize build environment:"
echo "     . setup romulus"
echo ""
echo "  3. Build OpenBMC:"
echo "     bitbake obmc-phosphor-image"
echo ""
echo "Note: First build takes 2-4 hours depending on your system."
