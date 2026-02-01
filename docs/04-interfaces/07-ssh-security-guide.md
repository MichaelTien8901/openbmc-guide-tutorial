---
layout: default
title: SSH Security Guide
parent: Interfaces
nav_order: 7
difficulty: intermediate
prerequisites:
  - environment-setup
---

# SSH Security Guide
{: .no_toc }

Configure and harden SSH access on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC uses **Dropbear** as its SSH server, a lightweight alternative to OpenSSH optimized for embedded systems. This guide covers SSH configuration, PAM integration, and security hardening.

```
┌─────────────────────────────────────────────────────────────────┐
│                     SSH Architecture                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                   SSH Client                                ││
│  │            (ssh, PuTTY, scripts)                            ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│                          TCP/22                                 │
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                       Dropbear                              ││
│  │                  (SSH Server Daemon)                        ││
│  │                                                             ││
│  │   ┌────────────────────────────────────────────────────┐    ││
│  │   │  Features: SSH2, RSA/DSS/ECDSA, SCP, SFTP proxy    │    ││
│  │   └────────────────────────────────────────────────────┘    ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                         PAM                                 ││
│  │              (Pluggable Authentication Modules)             ││
│  │                                                             ││
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    ││
│  │   │pam_unix  │  │pam_ldap  │  │pam_tally2│  │pam_limits│    ││
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────┘    ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                    User Database                            ││
│  │         (/etc/passwd, /etc/shadow, LDAP)                    ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

Configure SSH packages in your build:

```bitbake
# In your machine .conf or local.conf

# Include Dropbear (default SSH server)
IMAGE_INSTALL:append = " dropbear"

# For OpenSSH instead of Dropbear (larger, more features)
# IMAGE_INSTALL:append = " openssh-server openssh-client"
# IMAGE_INSTALL:remove = "dropbear"

# Include SSH-related utilities
IMAGE_INSTALL:append = " \
    openssh-sftp-server \
    openssh-scp \
"

# Configure dropbear options
DROPBEAR_EXTRA_ARGS ?= "-w -s"
```

### Dropbear Configuration Options

| Option | Description |
|--------|-------------|
| `-p [address:]port` | Listen on specified port (default 22) |
| `-w` | Disallow root logins |
| `-s` | Disable password logins (key only) |
| `-g` | Disable password logins for root |
| `-j` | Disable local port forwarding |
| `-k` | Disable remote port forwarding |
| `-a` | Allow connections to forwarded ports from any host |
| `-W` | Window size (performance tuning) |
| `-K` | Keepalive interval (seconds) |
| `-I` | Idle timeout (seconds, 0 = no timeout) |

### Runtime Configuration

```bash
# Check dropbear status
systemctl status dropbear

# View current configuration
cat /etc/default/dropbear

# Modify dropbear arguments
vi /etc/default/dropbear

# Restart after changes
systemctl restart dropbear
```

### /etc/default/dropbear

```bash
# Dropbear configuration
# DROPBEAR_EXTRA_ARGS contains additional arguments

# Default: allow root, password auth
DROPBEAR_EXTRA_ARGS=""

# Secure: no root login, key only
DROPBEAR_EXTRA_ARGS="-w -s"

# Custom port
DROPBEAR_EXTRA_ARGS="-p 2222"

# Disable port forwarding
DROPBEAR_EXTRA_ARGS="-j -k"
```

---

## Authentication Configuration

### Password Authentication

```bash
# Enable password authentication (default)
# Remove -s from DROPBEAR_EXTRA_ARGS

# Change user password
passwd root
passwd username

# Password hashes stored in /etc/shadow
cat /etc/shadow
```

### SSH Key Authentication

```bash
# Generate host keys (done automatically)
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key

# User authorized keys location
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Add public key to authorized_keys
echo "ssh-rsa AAAA...= user@host" >> ~/.ssh/authorized_keys
```

### Key-Only Authentication

For security, disable password authentication:

```bash
# Edit dropbear defaults
echo 'DROPBEAR_EXTRA_ARGS="-s"' > /etc/default/dropbear

# Restart dropbear
systemctl restart dropbear

# Test key-based login
ssh -i ~/.ssh/id_rsa root@bmc-ip
```

---

## PAM Configuration

### PAM Overview

OpenBMC uses PAM for authentication. Configuration files are in `/etc/pam.d/`.

```bash
# View PAM configuration for dropbear
cat /etc/pam.d/dropbear
```

### Default PAM Configuration

```pam
# /etc/pam.d/dropbear
auth       include      common-auth
account    include      common-account
password   include      common-password
session    include      common-session
```

### Common Auth Configuration

```pam
# /etc/pam.d/common-auth
auth    [success=1 default=ignore]  pam_unix.so nullok
auth    requisite                   pam_deny.so
auth    required                    pam_permit.so
```

### Enable Account Lockout

```pam
# /etc/pam.d/common-auth with tally
auth    required    pam_tally2.so deny=3 unlock_time=300 onerr=fail
auth    [success=1 default=ignore]  pam_unix.so nullok
auth    requisite   pam_deny.so
auth    required    pam_permit.so
```

### LDAP Authentication

```bitbake
# Include LDAP PAM module
IMAGE_INSTALL:append = " pam-plugin-ldap"
```

```pam
# /etc/pam.d/common-auth with LDAP
auth    sufficient  pam_ldap.so
auth    required    pam_unix.so nullok try_first_pass
```

---

## Security Hardening

### Disable Root SSH Login

```bash
# Option 1: Dropbear -w flag
echo 'DROPBEAR_EXTRA_ARGS="-w"' > /etc/default/dropbear
systemctl restart dropbear

# Option 2: PAM configuration
# Add to /etc/pam.d/dropbear:
auth    required    pam_listfile.so item=user sense=deny file=/etc/ssh/denied_users onerr=succeed
```

### Restrict SSH to Specific Users

```bash
# Create allowed users file
echo "operator" > /etc/ssh/allowed_users
echo "admin" >> /etc/ssh/allowed_users

# Add to /etc/pam.d/dropbear
auth    required    pam_listfile.so \
    item=user sense=allow file=/etc/ssh/allowed_users \
    onerr=fail
```

### Change Default Port

```bash
# Edit dropbear config
echo 'DROPBEAR_EXTRA_ARGS="-p 2222"' > /etc/default/dropbear

# Restart service
systemctl restart dropbear

# Connect on new port
ssh -p 2222 root@bmc-ip
```

### Disable Port Forwarding

```bash
# Disable both local and remote port forwarding
echo 'DROPBEAR_EXTRA_ARGS="-j -k"' > /etc/default/dropbear
systemctl restart dropbear
```

### Set Connection Timeout

```bash
# Set idle timeout (300 seconds = 5 minutes)
echo 'DROPBEAR_EXTRA_ARGS="-I 300"' > /etc/default/dropbear
systemctl restart dropbear
```

### Host Key Verification

Ensure consistent host keys across updates:

```bash
# Backup host keys
cp /etc/dropbear/dropbear_* /path/to/backup/

# Include in image build (recipe)
SRC_URI += "file://dropbear_rsa_host_key"

do_install:append() {
    install -m 0600 ${WORKDIR}/dropbear_rsa_host_key \
        ${D}${sysconfdir}/dropbear/
}
```

---

## Recommended Secure Configuration

### Production Hardening Checklist

```bash
# 1. Key-only authentication
echo 'DROPBEAR_EXTRA_ARGS="-s"' > /etc/default/dropbear

# 2. Disable root password login (allow key)
echo 'DROPBEAR_EXTRA_ARGS="-g"' > /etc/default/dropbear

# 3. Complete lockdown (no root at all)
echo 'DROPBEAR_EXTRA_ARGS="-w -s"' > /etc/default/dropbear

# 4. Set idle timeout
echo 'DROPBEAR_EXTRA_ARGS="-s -I 300"' > /etc/default/dropbear

# 5. Apply changes
systemctl restart dropbear
```

### Secure Dropbear Recipe

```bitbake
# In your machine layer
# recipes-connectivity/dropbear/dropbear_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://dropbear.default \
    file://authorized_keys \
"

do_install:append() {
    # Secure defaults
    install -m 0644 ${WORKDIR}/dropbear.default \
        ${D}${sysconfdir}/default/dropbear

    # Pre-authorized keys
    install -d ${D}/home/root/.ssh
    install -m 0600 ${WORKDIR}/authorized_keys \
        ${D}/home/root/.ssh/authorized_keys
}
```

---

## Managing SSH Access

### User Management

```bash
# Create non-root user
useradd -m operator
passwd operator

# Add to admin group for sudo
usermod -aG admin operator

# Add SSH key for user
mkdir -p /home/operator/.ssh
echo "ssh-rsa AAAA...=" > /home/operator/.ssh/authorized_keys
chmod 700 /home/operator/.ssh
chmod 600 /home/operator/.ssh/authorized_keys
chown -R operator:operator /home/operator/.ssh
```

### View Active Sessions

```bash
# List SSH connections
who

# Detailed connection info
ss -tnp | grep ssh

# Kill specific session (by PID)
pkill -9 -t pts/0
```

### Connection Logging

```bash
# View SSH authentication logs
journalctl -u dropbear

# Failed login attempts
journalctl -u dropbear | grep -i fail

# Successful logins
journalctl -u dropbear | grep -i "password auth succeeded\|pubkey auth succeeded"
```

---

## Enabling/Disabling SSH

### Build-Time Disable

```bitbake
# Remove dropbear from image
IMAGE_INSTALL:remove = "dropbear"
```

### Runtime Disable

```bash
# Stop SSH service
systemctl stop dropbear

# Disable SSH permanently
systemctl disable dropbear

# Re-enable SSH
systemctl enable dropbear
systemctl start dropbear
```

### Redfish Control

```bash
# Enable/disable SSH via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"SSH": {"ProtocolEnabled": false}}' \
    https://localhost/redfish/v1/Managers/bmc/NetworkProtocol
```

---

## SFTP Configuration

### Enable SFTP

```bash
# SFTP is handled by openssh-sftp-server
# Include in build:
IMAGE_INSTALL:append = " openssh-sftp-server"

# Dropbear uses this as SFTP subsystem
# Usage:
sftp root@bmc-ip
```

### SFTP-Only User

```bash
# Create user with restricted shell
useradd -m -s /usr/libexec/sftp-server sftpuser
passwd sftpuser

# Restrict to home directory via chroot
# (Requires additional configuration)
```

---

## Troubleshooting

### Connection Refused

```bash
# Check if dropbear is running
systemctl status dropbear

# Check listening ports
ss -tlnp | grep 22

# Start dropbear
systemctl start dropbear
```

### Authentication Failures

```bash
# Check logs for specific errors
journalctl -u dropbear -f

# Common issues:
# - Wrong password
# - Key permissions (must be 600)
# - authorized_keys format
# - PAM configuration

# Test with verbose client
ssh -vvv root@bmc-ip
```

### Key Not Accepted

```bash
# Check key permissions
ls -la ~/.ssh/
# Should be: drwx------ .ssh
# Should be: -rw------- authorized_keys

# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# Check key format in authorized_keys
# Must be single line: ssh-rsa AAAA... user@host
```

### PAM Errors

```bash
# Check PAM configuration syntax
pamtester dropbear root authenticate

# View PAM debug output
# Add to /etc/pam.d/dropbear:
auth    required    pam_warn.so
```

### Host Key Changed Warning

When reinstalling or updating BMC:

```bash
# Client side - remove old key
ssh-keygen -R bmc-ip

# Or edit known_hosts manually
vi ~/.ssh/known_hosts
```

---

## Security Comparison

| Feature | Dropbear | OpenSSH |
|---------|----------|---------|
| Binary size | ~110KB | ~900KB |
| Memory usage | Lower | Higher |
| SFTP | Via openssh-sftp-server | Built-in |
| Port forwarding | Supported | Full support |
| X11 forwarding | Limited | Full support |
| Key types | RSA, DSS, ECDSA, Ed25519 | All |
| Configuration | Command-line flags | sshd_config file |
| Chroot | Not built-in | Supported |

---

## References

- [Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html)
- [OpenBMC Security Documentation](https://github.com/openbmc/docs/tree/master/security)
- [Linux PAM Manual](https://man7.org/linux/man-pages/man8/pam.8.html)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
