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

## Deep Dive

This section provides detailed technical information for developers who want to understand SSH and PAM internals in OpenBMC.

### Dropbear Connection Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Dropbear SSH Connection Flow                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SSH Client                               Dropbear Server (BMC)             │
│  ┌────────────────────────┐               ┌────────────────────────────┐    │
│  │                        │               │                            │    │
│  │  1. TCP Connect        │  ──────────>  │  accept() on port 22       │    │
│  │     (port 22)          │               │  fork() child process      │    │
│  │                        │               │                            │    │
│  └────────────────────────┘               └────────────────────────────┘    │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     SSH Protocol Negotiation                           │ │
│  │                                                                        │ │
│  │  2. Version Exchange                                                   │ │
│  │     Client: SSH-2.0-OpenSSH_8.4                                        │ │
│  │     Server: SSH-2.0-dropbear_2020.81                                   │ │
│  │                                                                        │ │
│  │  3. Key Exchange (KEX)                                                 │ │
│  │     ┌────────────────────────────────────────────────────────────────┐ │ │
│  │     │  Client                        Server                         │ │ │
│  │     │                                                               │ │ │
│  │     │  SSH_MSG_KEXINIT ────────────> SSH_MSG_KEXINIT                │ │ │
│  │     │  (supported algorithms)        (supported algorithms)         │ │ │
│  │     │                                                               │ │ │
│  │     │  KEX method: curve25519-sha256                                │ │ │
│  │     │  Host key: ssh-ed25519                                        │ │ │
│  │     │  Cipher: aes256-gcm@openssh.com                               │ │ │
│  │     │  MAC: implicit (AEAD)                                         │ │ │
│  │     │                                                               │ │ │
│  │     │  ECDH_INIT ────────────────────> ECDH_REPLY                   │ │ │
│  │     │  (client public key)            (server public key +          │ │ │
│  │     │                                  host key signature)          │ │ │
│  │     │                                                               │ │ │
│  │     │  Verify host key against known_hosts                          │ │ │
│  │     │  Derive session keys from shared secret                       │ │ │
│  │     │                                                               │ │ │
│  │     │  SSH_MSG_NEWKEYS ──────────────> SSH_MSG_NEWKEYS              │ │ │
│  │     │  (encryption begins)             (encryption begins)          │ │ │
│  │     └────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                        │ │
│  │  4. User Authentication                                                │ │
│  │     ┌────────────────────────────────────────────────────────────────┐ │ │
│  │     │  USERAUTH_REQUEST(username, "ssh-connection", method)         │ │ │
│  │     │                                                               │ │ │
│  │     │  Method: "publickey" (preferred)                              │ │ │
│  │     │    - Client sends public key                                  │ │ │
│  │     │    - Server checks ~/.ssh/authorized_keys                     │ │ │
│  │     │    - Client proves possession of private key                  │ │ │
│  │     │                                                               │ │ │
│  │     │  Method: "password" (if enabled)                              │ │ │
│  │     │    - PAM authentication (pam_unix, pam_ldap, etc.)            │ │ │
│  │     │                                                               │ │ │
│  │     │  USERAUTH_SUCCESS / USERAUTH_FAILURE                          │ │ │
│  │     └────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                        │ │
│  │  5. Channel Establishment                                              │ │
│  │     CHANNEL_OPEN("session") ──────────> CHANNEL_OPEN_CONFIRMATION      │ │
│  │     CHANNEL_REQUEST("pty-req")                                         │ │
│  │     CHANNEL_REQUEST("shell") ──────────> Start /bin/sh                 │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  6. Interactive Session                                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  CHANNEL_DATA ←──────────────────────────────→ CHANNEL_DATA            │ │
│  │  (encrypted stdin/stdout)                      (shell I/O)             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### PAM Authentication Stack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      PAM Module Execution Flow                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Dropbear calls: pam_authenticate(pamh, 0)                                  │
│                                                                             │
│  PAM Configuration: /etc/pam.d/dropbear                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  # /etc/pam.d/dropbear                                                 │ │
│  │  auth       include      common-auth                                   │ │
│  │  account    include      common-account                                │ │
│  │  password   include      common-password                               │ │
│  │  session    include      common-session                                │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Module Execution (common-auth):                                            │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  auth [success=1 default=ignore] pam_unix.so nullok              │  │ │
│  │  │                                                                  │  │ │
│  │  │  1. Read /etc/passwd for user entry                              │  │ │
│  │  │  2. Read /etc/shadow for password hash                           │  │ │
│  │  │  3. Hash provided password with same algorithm (SHA-512)         │  │ │
│  │  │  4. Compare hashes                                               │  │ │
│  │  │                                                                  │  │ │
│  │  │  Result: PAM_SUCCESS or PAM_AUTH_ERR                             │  │ │
│  │  │                                                                  │  │ │
│  │  │  [success=1] = if success, skip 1 rule (pam_deny)                │  │ │
│  │  │  [default=ignore] = if fail, continue to next rule               │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                              │                                         │ │
│  │               ┌──────────────┴──────────────┐                          │ │
│  │               │                             │                          │ │
│  │           SUCCESS                       FAILURE                        │ │
│  │               │                             │                          │ │
│  │               v                             v                          │ │
│  │  ┌─────────────────────┐     ┌─────────────────────────────────────┐   │ │
│  │  │ Skip pam_deny       │     │  auth requisite pam_deny.so         │   │ │
│  │  │ Go to pam_permit    │     │                                     │   │ │
│  │  └─────────────────────┘     │  Returns PAM_AUTH_ERR immediately   │   │ │
│  │               │              │  (requisite = fail immediately)     │   │ │
│  │               v              └─────────────────────────────────────┘   │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │  auth required pam_permit.so                                    │   │ │
│  │  │                                                                 │   │ │
│  │  │  Always returns PAM_SUCCESS                                     │   │ │
│  │  │  (ensures clean success return)                                 │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Control Flags:                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  Flag        │ On Success        │ On Failure                         │ │
│  │  ────────────┼───────────────────┼──────────────────────────────────── │ │
│  │  required    │ Continue          │ Continue, but fail eventually      │ │
│  │  requisite   │ Continue          │ Return failure immediately         │ │
│  │  sufficient  │ Return success    │ Continue                           │ │
│  │  optional    │ Continue          │ Continue                           │ │
│  │  [action=N]  │ Skip N rules      │ Custom action per result           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### SSH Key Authentication Internals

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Public Key Authentication Flow                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Client                                   Server (Dropbear)                 │
│  ┌────────────────────────────┐           ┌────────────────────────────┐    │
│  │                            │           │                            │    │
│  │  Load private key          │           │  Receive public key blob   │    │
│  │  ~/.ssh/id_ed25519         │           │                            │    │
│  │                            │           │                            │    │
│  └────────────────────────────┘           └────────────────────────────┘    │
│                                                                             │
│  Step 1: Query if public key is acceptable                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                        │ │
│  │  Client sends:                                                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  SSH_MSG_USERAUTH_REQUEST                                        │  │ │
│  │  │    username: "root"                                              │  │ │
│  │  │    service: "ssh-connection"                                     │  │ │
│  │  │    method: "publickey"                                           │  │ │
│  │  │    has_signature: FALSE (query only)                             │  │ │
│  │  │    algorithm: "ssh-ed25519"                                      │  │ │
│  │  │    public_key_blob: <32 bytes>                                   │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  Server checks:                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  1. Open /home/root/.ssh/authorized_keys                         │  │ │
│  │  │  2. Parse each line:                                             │  │ │
│  │  │     ssh-ed25519 AAAA... user@host                                │  │ │
│  │  │  3. Compare key type and blob with request                       │  │ │
│  │  │  4. Check options (from=, command=, etc.)                        │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  Server responds: SSH_MSG_USERAUTH_PK_OK (key is acceptable)           │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Step 2: Prove possession of private key                                    │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                        │ │
│  │  Client creates signature:                                             │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  data_to_sign = session_id || SSH_MSG_USERAUTH_REQUEST ||        │  │ │
│  │  │                 username || service || "publickey" ||            │  │ │
│  │  │                 TRUE || algorithm || public_key_blob             │  │ │
│  │  │                                                                  │  │ │
│  │  │  signature = ed25519_sign(private_key, data_to_sign)             │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  Client sends:                                                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  SSH_MSG_USERAUTH_REQUEST                                        │  │ │
│  │  │    has_signature: TRUE                                           │  │ │
│  │  │    signature: <64 bytes>                                         │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  Server verifies:                                                      │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │ │
│  │  │  1. Reconstruct data_to_sign (same as client)                    │  │ │
│  │  │  2. ed25519_verify(public_key, data_to_sign, signature)          │  │ │
│  │  │  3. If valid: SSH_MSG_USERAUTH_SUCCESS                           │  │ │
│  │  └──────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  authorized_keys Format:                                                    │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  [options] key-type base64-key [comment]                               │ │
│  │                                                                        │ │
│  │  Examples:                                                             │ │
│  │  ssh-ed25519 AAAAC3Nz... user@laptop                                   │ │
│  │  from="192.168.1.*" ssh-rsa AAAAB3Nz... admin@server                   │ │
│  │  command="/usr/bin/validate" ssh-ed25519 AAAAC3... script@automation   │ │
│  │  no-pty,no-port-forwarding ssh-rsa AAAAB3... restricted@host           │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Host Key Management

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Dropbear Host Key Generation                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Key Storage: /etc/dropbear/                                                │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  /etc/dropbear/                                                        │ │
│  │  ├── dropbear_rsa_host_key      # RSA 2048/4096-bit                    │ │
│  │  ├── dropbear_ecdsa_host_key    # ECDSA nistp256/384/521               │ │
│  │  └── dropbear_ed25519_host_key  # Ed25519 (recommended)                │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Key Generation (first boot or manual):                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  # Generate Ed25519 key (fast, secure)                                 │ │
│  │  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key     │ │
│  │                                                                        │ │
│  │  # Generate RSA key (for legacy client compatibility)                  │ │
│  │  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key     │ │
│  │                                                                        │ │
│  │  # Generate ECDSA key                                                  │ │
│  │  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Dropbear Key File Format (internal):                                       │ │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  Not OpenSSH compatible - binary format specific to Dropbear           │ │
│  │                                                                        │ │
│  │  Convert to OpenSSH format (for inspection):                           │ │
│  │  dropbearconvert dropbear openssh                                      │ │
│  │    /etc/dropbear/dropbear_ed25519_host_key                             │ │
│  │    /tmp/openssh_host_key                                               │ │
│  │                                                                        │ │
│  │  Extract public key:                                                   │ │
│  │  dropbearkey -y -f /etc/dropbear/dropbear_ed25519_host_key             │ │
│  │  # Output: ssh-ed25519 AAAAC3Nz... root@bmc                            │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  Yocto Persistent Key Configuration:                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  # Option 1: Generate at first boot (in init script)                   │ │
│  │  if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ]; then             │ │
│  │      dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key │ │
│  │  fi                                                                    │ │
│  │                                                                        │ │
│  │  # Option 2: Pre-generate and include in image (production)            │ │
│  │  # In recipe .bbappend:                                                │ │
│  │  SRC_URI += "file://dropbear_ed25519_host_key"                         │ │
│  │  do_install:append() {                                                 │ │
│  │      install -m 0600 ${WORKDIR}/dropbear_ed25519_host_key \            │ │
│  │          ${D}${sysconfdir}/dropbear/                                   │ │
│  │  }                                                                     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Source Code References

| Component | Repository | Key Files |
|-----------|------------|-----------|
| Dropbear SSH Server | [mkj/dropbear](https://github.com/mkj/dropbear) | `svr-main.c`, `svr-authpasswd.c`, `svr-authpubkey.c` |
| Dropbear Yocto Recipe | [openembedded-core](https://git.openembedded.org/openembedded-core) | `meta/recipes-core/dropbear/` |
| Linux PAM | [linux-pam/linux-pam](https://github.com/linux-pam/linux-pam) | `modules/pam_unix/`, `libpam/` |
| PAM Configuration | [openbmc/openbmc](https://github.com/openbmc/openbmc) | `meta-phosphor/recipes-extended/pam/` |
| OpenBMC Security Docs | [openbmc/docs](https://github.com/openbmc/docs) | `security/` |

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
