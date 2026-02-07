# LDAP Configuration Examples

Shell scripts and configuration files for setting up LDAP authentication on OpenBMC
via the Redfish AccountService API.

> **Requires a running OpenBMC system** -- these scripts target the Redfish
> AccountService endpoints on a booted OpenBMC instance (QEMU or hardware).
> An external LDAP or Active Directory server must be reachable from the BMC
> network.

## Quick Start

```bash
# 1. Set environment variables for your BMC and LDAP server
export BMC_HOST="localhost:2443"
export LDAP_SERVER="ldap://ldap.example.com:389"

# 2. Configure OpenLDAP client on the BMC
./configure-openldap.sh

# 3. Or configure Active Directory instead
./configure-active-directory.sh

# 4. Add LDAP group-to-BMC role mappings
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d @ldap-role-mapping.json \
    "https://${BMC_HOST}/redfish/v1/AccountService"

# 5. Test authentication with an LDAP user
LDAP_USER="jdoe" LDAP_PASS="secret" ./test-ldap-auth.sh
```

## Files

| File | Description |
|------|-------------|
| `configure-openldap.sh` | Configure BMC LDAP client via Redfish (server URI, base DN, bind DN, search scope) |
| `configure-active-directory.sh` | Configure BMC Active Directory client with AD-specific settings |
| `test-ldap-auth.sh` | Test LDAP authentication by attempting a Redfish login with LDAP credentials |
| `ldap-role-mapping.json` | Sample Redfish AccountService RoleMapping config mapping LDAP groups to BMC roles |

## Redfish AccountService LDAP Overview

OpenBMC exposes LDAP configuration through the standard Redfish AccountService
resource at `/redfish/v1/AccountService`. Two service types are supported:

| Service Type | Redfish Property | Typical Use |
|--------------|-----------------|-------------|
| OpenLDAP | `AccountService.LDAP` | Standard LDAP directories (OpenLDAP, 389 Directory Server) |
| Active Directory | `AccountService.ActiveDirectory` | Microsoft Active Directory / Azure AD DS |

### Key Configuration Properties

| Property | Example | Description |
|----------|---------|-------------|
| `ServiceEnabled` | `true` | Enable or disable the LDAP service |
| `ServiceAddresses` | `["ldap://ldap.example.com:389"]` | LDAP server URI(s) |
| `Authentication.Username` | `"cn=readonly,dc=example,dc=com"` | Bind DN for directory lookups |
| `Authentication.Password` | `"bind_password"` | Bind credential |
| `LDAPService.SearchSettings.BaseDistinguishedNames` | `["ou=users,dc=example,dc=com"]` | Search base for user lookups |
| `LDAPService.SearchSettings.UsernameAttribute` | `"uid"` | Attribute that holds the login name |
| `LDAPService.SearchSettings.GroupsAttribute` | `"memberOf"` | Attribute for group membership |
| `RemoteRoleMapping` | See `ldap-role-mapping.json` | Maps LDAP groups to local BMC privilege roles |

## Troubleshooting

```bash
# Check phosphor-user-manager status
ssh -p 2222 root@localhost systemctl status phosphor-user-manager

# View LDAP-related logs
ssh -p 2222 root@localhost journalctl -u phosphor-user-manager -f

# Verify LDAP server reachability from BMC
ssh -p 2222 root@localhost ping -c 3 ldap.example.com

# Check current AccountService config via Redfish
curl -k -s -u root:0penBmc \
    "https://${BMC_HOST}/redfish/v1/AccountService" | jq '.LDAP, .ActiveDirectory'

# Test LDAP connectivity with ldapsearch (if installed on BMC)
ssh -p 2222 root@localhost ldapsearch -x -H ldap://ldap.example.com \
    -b "ou=users,dc=example,dc=com" -D "cn=readonly,dc=example,dc=com" -w password "(uid=jdoe)"
```

## References

- [User Management Guide](../../03-core-features/index.md) -- OpenBMC user and authentication overview
- [Redfish AccountService Schema](https://redfish.dmtf.org/schemas/v1/AccountService.json)
- [OpenBMC phosphor-user-manager](https://github.com/openbmc/phosphor-user-manager)
- [DMTF Redfish Specification](https://www.dmtf.org/standards/redfish)
