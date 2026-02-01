#!/bin/bash
# OpenBMC Development Environment Setup for Ubuntu 20.04/22.04
# Usage: ./setup-ubuntu.sh

set -e

echo "=========================================="
echo "OpenBMC Development Environment Setup"
echo "Ubuntu 20.04/22.04"
echo "=========================================="

# Check Ubuntu version
if ! grep -qE "Ubuntu (20|22)\." /etc/os-release 2>/dev/null; then
    echo "Warning: This script is designed for Ubuntu 20.04 or 22.04"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Update system
echo ""
echo ">>> Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo ""
echo ">>> Installing Yocto/BitBake dependencies..."
sudo apt install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool

# Install additional tools
echo ""
echo ">>> Installing additional development tools..."
sudo apt install -y \
    curl vim tmux htop tree \
    libssl-dev libffi-dev

# Install QEMU
echo ""
echo ">>> Installing QEMU..."
sudo apt install -y qemu-system-arm

# Set locale
echo ""
echo ">>> Configuring locale..."
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

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
