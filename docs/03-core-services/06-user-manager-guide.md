---
layout: default
title: User Manager Guide
parent: Core Services
nav_order: 6
difficulty: intermediate
prerequisites:
  - dbus-guide
  - redfish-guide
---

# User Manager Guide
{: .no_toc }

Configure user accounts, privileges, and LDAP authentication on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC user management is handled by **phosphor-user-manager**, providing local accounts, role-based access control, and LDAP integration.

```
┌─────────────────────────────────────────────────────────────────┐
│                   User Manager Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Access Methods                           ││
│  │                                                             ││
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    ││
│  │   │ Redfish  │  │  IPMI    │  │   SSH    │  │  WebUI   │    ││
│  │   │ API      │  │  Users   │  │ Login    │  │  Login   │    ││
│  │   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘    ││
│  └────────┼─────────────┼─────────────┼─────────────┼──────────┘│
│           └─────────────┴──────┬──────┴─────────────┘           │
│                                │                                │
│  ┌─────────────────────────────┴───────────────────────────────┐│
│  │                   phosphor-user-manager                     ││
│  │                                                             ││
│  │   ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  ││
│  │   │ Local Accounts │  │ LDAP/AD Config │  │ Privilege    │  ││
│  │   │ /etc/passwd    │  │ nslcd/sssd     │  │ Management   │  ││
│  │   └────────────────┘  └────────────────┘  └──────────────┘  ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                          PAM                                ││
│  │              (Pluggable Authentication Modules)             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include user management
IMAGE_INSTALL:append = " \
    phosphor-user-manager \
"

# For LDAP support
IMAGE_INSTALL:append = " \
    nss-pam-ldapd \
    pam-plugin-ldap \
"

# Configure Meson options
EXTRA_OEMESON:pn-phosphor-user-manager = " \
    -Dldap=enabled \
"
```

### Runtime Configuration

```bash
# Check user manager service
systemctl status phosphor-user-manager

# View logs
journalctl -u phosphor-user-manager -f

# User configuration files
cat /etc/passwd
cat /etc/group
```

---

## Local User Management

### Default Users

| Username | Default Password | Role |
|----------|------------------|------|
| root | 0penBmc | Administrator |

### Create User via Redfish

```bash
# Create new user
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "UserName": "operator1",
        "Password": "SecurePass123!",
        "RoleId": "Operator",
        "Enabled": true
    }' \
    https://localhost/redfish/v1/AccountService/Accounts
```

### Create User via D-Bus

```bash
# Create user
busctl call xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user \
    xyz.openbmc_project.User.Manager \
    CreateUser ssasbs \
    "newuser" \
    3 "ipmi" "redfish" "ssh" \
    "priv-admin" \
    true
```

### Modify User

```bash
# Change password via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Password": "NewPassword123!"}' \
    https://localhost/redfish/v1/AccountService/Accounts/operator1

# Change role
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"RoleId": "Administrator"}' \
    https://localhost/redfish/v1/AccountService/Accounts/operator1

# Enable/disable user
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"Enabled": false}' \
    https://localhost/redfish/v1/AccountService/Accounts/operator1
```

### Delete User

```bash
# Via Redfish
curl -k -u root:0penBmc -X DELETE \
    https://localhost/redfish/v1/AccountService/Accounts/operator1

# Via IPMI
ipmitool -I lanplus -H bmc-ip -U root -P 0penBmc user set name 3 ""
```

---

## Privilege Roles

### Available Roles

| Role | Redfish | IPMI Priv | Description |
|------|---------|-----------|-------------|
| Administrator | Administrator | 4 (admin) | Full access |
| Operator | Operator | 3 (operator) | Operations, no user mgmt |
| ReadOnly | ReadOnly | 2 (user) | Read-only access |
| Callback | Callback | 1 | Limited callback access |

### Role Permissions

```bash
# View available roles
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/AccountService/Roles

# Get role details
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/AccountService/Roles/Operator
```

### D-Bus Privilege Mapping

```bash
# View user privileges
busctl get-property xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user/newuser \
    xyz.openbmc_project.User.Attributes \
    UserPrivilege
```

---

## IPMI User Management

### Configure IPMI Users

```bash
# List users
ipmitool user list

# Create user
ipmitool user set name 3 operator1
ipmitool user set password 3 Password123!
ipmitool user priv 3 3 1  # operator privilege, channel 1
ipmitool user enable 3

# Disable user
ipmitool user disable 3

# Delete user
ipmitool user set name 3 ""
```

### IPMI User Privileges

| Level | Name | Description |
|-------|------|-------------|
| 1 | Callback | Minimal access |
| 2 | User | Read sensors, view logs |
| 3 | Operator | Power control, sensor config |
| 4 | Administrator | Full access |
| 5 | OEM | Vendor-specific |

---

## LDAP Configuration

### Enable LDAP Authentication

```bash
# Configure LDAP via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "LDAP": {
            "ServiceEnabled": true,
            "ServiceAddresses": ["ldap://ldap.example.com"],
            "Authentication": {
                "AuthenticationType": "UsernameAndPassword",
                "Username": "cn=admin,dc=example,dc=com",
                "Password": "ldappassword"
            },
            "LDAPService": {
                "SearchSettings": {
                    "BaseDistinguishedNames": ["dc=example,dc=com"],
                    "UsernameAttribute": "uid",
                    "GroupsAttribute": "memberOf"
                }
            }
        }
    }' \
    https://localhost/redfish/v1/AccountService
```

### LDAP Role Mapping

```bash
# Map LDAP group to role
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "RemoteGroup": "cn=admins,ou=groups,dc=example,dc=com",
        "LocalRole": "Administrator"
    }' \
    https://localhost/redfish/v1/AccountService/LDAP/RemoteRoleMapping
```

### D-Bus LDAP Configuration

```bash
# Create LDAP config
busctl call xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user/ldap \
    xyz.openbmc_project.User.Ldap.Create \
    Create sssssa{ss} \
    "ldap://ldap.example.com" \
    "cn=admin,dc=example,dc=com" \
    "dc=example,dc=com" \
    "uid" \
    "OpenLDAP" \
    0
```

### Test LDAP Connection

```bash
# Test authentication
ldapsearch -x -H ldap://ldap.example.com \
    -D "cn=admin,dc=example,dc=com" \
    -w password \
    -b "dc=example,dc=com" \
    "(uid=testuser)"
```

---

## Active Directory

### Configure AD Authentication

```bash
# Configure Active Directory
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "ActiveDirectory": {
            "ServiceEnabled": true,
            "ServiceAddresses": ["ldap://ad.example.com"],
            "Authentication": {
                "AuthenticationType": "UsernameAndPassword",
                "Username": "admin@example.com",
                "Password": "adpassword"
            },
            "LDAPService": {
                "SearchSettings": {
                    "BaseDistinguishedNames": ["DC=example,DC=com"],
                    "UsernameAttribute": "sAMAccountName",
                    "GroupsAttribute": "memberOf"
                }
            }
        }
    }' \
    https://localhost/redfish/v1/AccountService
```

---

## Account Policies

### Configure Lockout

```bash
# Set account lockout policy
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "AccountLockoutThreshold": 5,
        "AccountLockoutDuration": 300,
        "AccountLockoutCounterResetAfter": 60
    }' \
    https://localhost/redfish/v1/AccountService
```

### Password Policy

```bash
# Set minimum password length
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "MinPasswordLength": 12
    }' \
    https://localhost/redfish/v1/AccountService
```

---

## Session Management

### View Active Sessions

```bash
# List sessions
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/SessionService/Sessions
```

### Terminate Session

```bash
# Delete specific session
curl -k -u root:0penBmc -X DELETE \
    https://localhost/redfish/v1/SessionService/Sessions/session_id
```

### Session Timeout

```bash
# Configure session timeout
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"SessionTimeout": 1800}' \
    https://localhost/redfish/v1/SessionService
```

---

## Troubleshooting

### Login Failures

```bash
# Check PAM logs
journalctl | grep pam

# Check user exists
cat /etc/passwd | grep username

# Verify user enabled
busctl get-property xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user/username \
    xyz.openbmc_project.User.Attributes \
    UserEnabled
```

### LDAP Issues

```bash
# Check LDAP service
systemctl status nslcd

# Test LDAP bind
ldapwhoami -x -H ldap://ldap.example.com \
    -D "uid=user,dc=example,dc=com" -W

# Check LDAP configuration
busctl introspect xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user/ldap
```

### Account Locked

```bash
# Check lockout status (via PAM tally)
pam_tally2 --user=username

# Reset lockout
pam_tally2 --user=username --reset
```

---

## References

- [phosphor-user-manager](https://github.com/openbmc/phosphor-user-manager)
- [Redfish AccountService](https://redfish.dmtf.org/schemas/AccountService.v1_10_0.json)
- [OpenBMC User Management](https://github.com/openbmc/docs/blob/master/architecture/user-management.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
