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

## Deep Dive
{: .text-delta }

Advanced implementation details for user management developers.

### PAM Integration

OpenBMC uses PAM (Pluggable Authentication Modules) for authentication:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PAM Authentication Flow                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Login Request (Redfish/IPMI/SSH)                                      │
│          │                                                              │
│          ▼                                                              │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    PAM Stack                                    │   │
│   │   /etc/pam.d/common-auth                                        │   │
│   └────────────────────────────┬────────────────────────────────────┘   │
│                                │                                        │
│          ┌─────────────────────┼─────────────────────┐                  │
│          │                     │                     │                  │
│          ▼                     ▼                     ▼                  │
│   ┌────────────┐        ┌────────────┐        ┌────────────┐            │
│   │ pam_unix   │        │ pam_ldap   │        │ pam_radius │            │
│   │ (local)    │        │ (LDAP/AD)  │        │ (RADIUS)   │            │
│   └─────┬──────┘        └─────┬──────┘        └─────┬──────┘            │
│         │                     │                     │                   │
│         ▼                     ▼                     ▼                   │
│   /etc/shadow           LDAP Server           RADIUS Server             │
│                                                                         │
│   PAM Configuration (/etc/pam.d/common-auth):                           │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ auth sufficient pam_unix.so nullok try_first_pass               │   │
│   │ auth sufficient pam_ldap.so use_first_pass                      │   │
│   │ auth required   pam_deny.so                                     │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**PAM module flow:**
- `sufficient`: If module succeeds, skip remaining; if fails, continue
- `required`: Must pass, but continue checking other modules
- `requisite`: Must pass, fail immediately if not

### LDAP Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    LDAP Authentication Sequence                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   BMC (phosphor-user-manager)              LDAP Server                  │
│          │                                      │                       │
│          │  1. Bind (service account)           │                       │
│          │─────────────────────────────────────▶│                       │
│          │◀─────────────────────────────────────│ Bind success          │
│          │                                      │                       │
│          │  2. Search (find user DN)            │                       │
│          │  filter: (uid=username)              │                       │
│          │─────────────────────────────────────▶│                       │
│          │◀─────────────────────────────────────│ User DN returned      │
│          │                                      │                       │
│          │  3. Bind (user DN + password)        │                       │
│          │─────────────────────────────────────▶│                       │
│          │◀─────────────────────────────────────│ Auth success/fail     │
│          │                                      │                       │
│          │  4. Search (get group membership)    │                       │
│          │  filter: (member=userDN)             │                       │
│          │─────────────────────────────────────▶│                       │
│          │◀─────────────────────────────────────│ Group list            │
│          │                                      │                       │
│                                                                         │
│   Group to Privilege Mapping:                                           │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ LDAP Group          │ OpenBMC Role      │ IPMI Privilege        │   │
│   ├─────────────────────┼───────────────────┼───────────────────────┤   │
│   │ cn=bmc-admins       │ Administrator     │ 4 (Administrator)     │   │
│   │ cn=bmc-operators    │ Operator          │ 3 (Operator)          │   │
│   │ cn=bmc-users        │ User              │ 2 (User)              │   │
│   │ cn=bmc-readonly     │ ReadOnly          │ 1 (Callback)          │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Password Hashing

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Password Storage                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   /etc/shadow format:                                                   │
│   username:$6$salt$hash:lastchange:min:max:warn:inactive:expire:        │
│                                                                         │
│   Hash Types:                                                           │
│   ├── $1$ = MD5 (deprecated, insecure)                                  │
│   ├── $5$ = SHA-256                                                     │
│   └── $6$ = SHA-512 (default, recommended)                              │
│                                                                         │
│   Password Change Flow:                                                 │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │ 1. Redfish PATCH /AccountService/Accounts/{id}                   │  │
│   │    { "Password": "newPassword" }                                 │  │
│   │                                                                  │  │
│   │ 2. bmcweb calls D-Bus:                                           │  │
│   │    xyz.openbmc_project.User.Manager.RenameUser() or              │  │
│   │    org.freedesktop.Accounts.User.SetPassword()                   │  │
│   │                                                                  │  │
│   │ 3. phosphor-user-manager:                                        │  │
│   │    - Validates password policy (length, complexity)              │  │
│   │    - Calls pam_chauthtok() to update /etc/shadow                 │  │
│   │    - Emits PropertiesChanged signal                              │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### D-Bus Permission Enforcement

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    D-Bus Access Control                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   /etc/dbus-1/system.d/ policy files control D-Bus access:              │
│                                                                         │
│   Example: phosphor-user-manager.conf                                   │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ <policy user="root">                                            │   │
│   │   <allow own="xyz.openbmc_project.User.Manager"/>               │   │
│   │   <allow send_destination="xyz.openbmc_project.User.Manager"/>  │   │
│   │ </policy>                                                       │   │
│   │                                                                 │   │
│   │ <policy context="default">                                      │   │
│   │   <deny send_destination="xyz.openbmc_project.User.Manager"     │   │
│   │         send_interface="xyz.openbmc_project.User.Manager"/>     │   │
│   │   <allow send_destination="xyz.openbmc_project.User.Manager"    │   │
│   │         send_interface="org.freedesktop.DBus.Properties"        │   │
│   │         send_member="Get"/>                                     │   │
│   │ </policy>                                                       │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   Privilege Enforcement in bmcweb:                                      │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ // Route with privilege requirement                             │   │
│   │ BMCWEB_ROUTE(app, "/redfish/v1/AccountService/Accounts/<str>/") │   │
│   │     .privileges(redfish::privileges::patchAccount)              │   │
│   │     .methods(boost::beast::http::verb::patch)(handlePatch);     │   │
│   │                                                                 │   │
│   │ // privileges::patchAccount requires ConfigureUsers             │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files in [phosphor-user-manager](https://github.com/openbmc/phosphor-user-manager):

| File | Description |
|------|-------------|
| `user_mgr.cpp` | Main user manager implementation |
| `users.cpp` | Individual user object handling |
| `ldap_config.cpp` | LDAP configuration management |
| `ldap_mapper.cpp` | LDAP group to privilege mapping |
| `shadowlock.cpp` | /etc/shadow file locking |
| `phosphor-ldap-conf.cpp` | LDAP config daemon |

---

## Examples

Working examples are available in the [examples/user-manager](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/examples/user-manager) directory:

- `user-management.sh` - User CRUD operations script
- `ldap-config.json` - LDAP configuration example

---

## References

- [phosphor-user-manager](https://github.com/openbmc/phosphor-user-manager)
- [Redfish AccountService](https://redfish.dmtf.org/schemas/AccountService.v1_10_0.json)
- [OpenBMC User Management](https://github.com/openbmc/docs/blob/master/architecture/user-management.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
