#!/bin/bash
#
# Configure Active Directory Client on OpenBMC via Redfish
#
# Configures the BMC's Active Directory settings through the Redfish
# AccountService API. Active Directory uses different attribute names
# and DN formats compared to OpenLDAP:
#
#   - Username attribute is typically "sAMAccountName" (not "uid")
#   - Bind DN uses CN= and OU= format (not cn= and ou=)
#   - Group membership uses "memberOf" with full DN values
#   - Base DN uses DC= components matching the AD domain
#
# Usage:
#   ./configure-active-directory.sh
#
# Environment variables (override defaults):
#   BMC_HOST       - BMC address with port (default: localhost:2443)
#   BMC_USER       - BMC admin username (default: root)
#   BMC_PASS       - BMC admin password (default: 0penBmc)
#   AD_SERVER      - AD server URI (default: ldap://ad.example.com:389)
#   AD_BIND_DN     - AD service account DN for lookups
#   AD_BIND_PASS   - AD service account password
#   AD_BASE_DN     - Search base in the AD tree
#   AD_USER_ATTR   - Username attribute (default: sAMAccountName)
#   AD_GROUP_ATTR  - Group membership attribute (default: memberOf)
#
# Prerequisites:
#   - curl and jq installed on the machine running this script
#   - BMC is booted and Redfish API is accessible
#   - Active Directory server is reachable from the BMC network
#   - A dedicated AD service account exists for BMC directory lookups

set -euo pipefail

# --- Configuration variables (override via environment) ---
# Active Directory typically uses different naming conventions than OpenLDAP.
# The bind DN references a service account in AD's OU structure, and
# sAMAccountName is the standard pre-Windows 2000 logon name attribute.

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"

AD_SERVER="${AD_SERVER:-ldap://ad.example.com:389}"
AD_BIND_DN="${AD_BIND_DN:-CN=BMC Service,OU=Service Accounts,DC=example,DC=com}"
AD_BIND_PASS="${AD_BIND_PASS:-service_password}"
AD_BASE_DN="${AD_BASE_DN:-OU=Users,DC=example,DC=com}"
AD_USER_ATTR="${AD_USER_ATTR:-sAMAccountName}"
AD_GROUP_ATTR="${AD_GROUP_ATTR:-memberOf}"

CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"
BASE_URL="https://${BMC_HOST}/redfish/v1"

echo "========================================"
echo "Configure Active Directory on OpenBMC"
echo "BMC: ${BMC_HOST}"
echo "AD Server: ${AD_SERVER}"
echo "========================================"
echo ""

# --- Step 1: Verify Redfish connectivity ---
# Confirm the BMC is reachable and Redfish API responds before making changes.

echo "Step 1: Verify Redfish connectivity"
RESULT=$($CURL "${BASE_URL}/AccountService" 2>/dev/null)
if ! echo "$RESULT" | jq -e '.Id' > /dev/null 2>&1; then
    echo "  ERROR: Cannot reach Redfish AccountService at ${BASE_URL}"
    echo "  Check BMC_HOST, BMC_USER, and BMC_PASS"
    exit 1
fi
echo "  AccountService is reachable"
echo ""

# --- Step 2: Show current Active Directory configuration ---
# Display any existing AD settings so the user can see what will be changed.

echo "Step 2: Current Active Directory configuration"
echo "$RESULT" | jq '.ActiveDirectory | {
    ServiceEnabled,
    ServiceAddresses,
    Authentication: {Username: .Authentication.Username},
    SearchSettings: .LDAPService.SearchSettings
}' 2>/dev/null || echo "  No existing Active Directory configuration found"
echo ""

# --- Step 3: Disable OpenLDAP if currently enabled ---
# OpenBMC supports either LDAP or Active Directory, but not both simultaneously.
# If OpenLDAP is currently enabled, disable it before enabling AD.

LDAP_ENABLED=$(echo "$RESULT" | jq -r '.LDAP.ServiceEnabled // false')
if [ "$LDAP_ENABLED" = "true" ]; then
    echo "Step 3: Disabling OpenLDAP (only one LDAP service can be active)"
    $CURL -X PATCH \
        -H "Content-Type: application/json" \
        -d '{"LDAP": {"ServiceEnabled": false}}' \
        "${BASE_URL}/AccountService" > /dev/null 2>&1
    echo "  OpenLDAP disabled"
    echo ""
else
    echo "Step 3: OpenLDAP is not enabled (no conflict)"
    echo ""
fi

# --- Step 4: Configure Active Directory service ---
# PATCH the AccountService with AD-specific settings. The key differences
# from OpenLDAP configuration are:
#
#   - Uses the "ActiveDirectory" property instead of "LDAP"
#   - sAMAccountName is the standard AD username attribute (the pre-Windows
#     2000 logon name, e.g., "jdoe"). This differs from OpenLDAP's "uid".
#   - The bind DN uses AD's CN/OU/DC naming (e.g.,
#     "CN=BMC Service,OU=Service Accounts,DC=example,DC=com")
#   - The base DN points to the AD organizational unit containing user objects
#   - For LDAPS (port 636), change the URI to ldaps://ad.example.com:636

echo "Step 4: Configure Active Directory service"
PATCH_RESULT=$($CURL -X PATCH \
    -H "Content-Type: application/json" \
    -d "{
        \"ActiveDirectory\": {
            \"ServiceEnabled\": true,
            \"ServiceAddresses\": [\"${AD_SERVER}\"],
            \"Authentication\": {
                \"AuthenticationType\": \"UsernameAndPassword\",
                \"Username\": \"${AD_BIND_DN}\",
                \"Password\": \"${AD_BIND_PASS}\"
            },
            \"LDAPService\": {
                \"SearchSettings\": {
                    \"BaseDistinguishedNames\": [\"${AD_BASE_DN}\"],
                    \"UsernameAttribute\": \"${AD_USER_ATTR}\",
                    \"GroupsAttribute\": \"${AD_GROUP_ATTR}\"
                }
            }
        }
    }" \
    "${BASE_URL}/AccountService" 2>/dev/null)

# Check if the PATCH succeeded by looking for error messages in the response.
if echo "$PATCH_RESULT" | jq -e '.error' > /dev/null 2>&1; then
    echo "  ERROR: Active Directory configuration failed"
    echo "$PATCH_RESULT" | jq '.error'
    exit 1
fi
echo "  Active Directory service configured successfully"
echo ""

# --- Step 5: Verify the new configuration ---
# Re-read the AccountService to confirm the AD settings were applied.

echo "Step 5: Verify new Active Directory configuration"
VERIFY=$($CURL "${BASE_URL}/AccountService" 2>/dev/null)
echo "$VERIFY" | jq '.ActiveDirectory | {
    ServiceEnabled,
    ServiceAddresses,
    Authentication: {Username: .Authentication.Username},
    SearchSettings: .LDAPService.SearchSettings
}' 2>/dev/null
echo ""

# --- Step 6: Show both service states for confirmation ---
# Display a summary of both LDAP and AD to confirm only AD is active.

echo "Step 6: Service summary"
echo "$VERIFY" | jq '{
    LDAP_Enabled: .LDAP.ServiceEnabled,
    ActiveDirectory_Enabled: .ActiveDirectory.ServiceEnabled
}' 2>/dev/null
echo ""

echo "========================================"
echo "Active Directory configuration complete"
echo ""
echo "Next steps:"
echo "  1. Apply role mappings (use AD group DNs in ldap-role-mapping.json):"
echo "     Example AD group DN:"
echo "       CN=BMC-Admins,OU=Groups,DC=example,DC=com"
echo "  2. Test authentication:"
echo "     LDAP_USER=jdoe LDAP_PASS=secret ./test-ldap-auth.sh"
echo "========================================"
