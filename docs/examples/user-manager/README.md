# User Manager Examples

Example configurations for phosphor-user-manager.

## Contents

- `user-management.sh` - User CRUD operations script
- `ldap-config.json` - LDAP configuration example
- `privilege-roles.md` - Role definitions and permissions

## Related Guide

[User Manager Guide](../../03-core-services/06-user-manager-guide.md)

## Quick Test

```bash
# List users
busctl tree xyz.openbmc_project.User.Manager

# Create user via Redfish
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/AccountService/Accounts \
    -H "Content-Type: application/json" \
    -d '{"UserName": "operator", "Password": "TestPass123!", "RoleId": "Operator"}'

# Get user info
busctl introspect xyz.openbmc_project.User.Manager \
    /xyz/openbmc_project/user/root
```
