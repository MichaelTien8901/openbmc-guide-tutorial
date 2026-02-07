#!/bin/bash
#
# Configure OpenLDAP Client on OpenBMC via Redfish
#
# Configures the BMC's LDAP client settings through the Redfish AccountService
# API. This script sets the LDAP server URI, bind credentials, search base DN,
# username/group attributes, and enables the LDAP service.
#
# Usage:
#   ./configure-openldap.sh
#
# Environment variables (override defaults):
#   BMC_HOST       - BMC address with port (default: localhost:2443)
#   BMC_USER       - BMC admin username (default: root)
#   BMC_PASS       - BMC admin password (default: 0penBmc)
#   LDAP_SERVER    - LDAP server URI (default: ldap://ldap.example.com:389)
#   LDAP_BIND_DN   - Bind DN for directory lookups
#   LDAP_BIND_PASS - Bind password
#   LDAP_BASE_DN   - Search base distinguished name
#   LDAP_USER_ATTR - Username attribute (default: uid)
#   LDAP_GROUP_ATTR - Group membership attribute (default: memberOf)
#
# Prerequisites:
#   - curl and jq installed on the machine running this script
#   - BMC is booted and Redfish API is accessible
#   - LDAP server is reachable from the BMC network

set -euo pipefail

# --- Configuration variables (override via environment) ---

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"

LDAP_SERVER="${LDAP_SERVER:-ldap://ldap.example.com:389}"
LDAP_BIND_DN="${LDAP_BIND_DN:-cn=readonly,dc=example,dc=com}"
LDAP_BIND_PASS="${LDAP_BIND_PASS:-readonly_password}"
LDAP_BASE_DN="${LDAP_BASE_DN:-ou=users,dc=example,dc=com}"
LDAP_USER_ATTR="${LDAP_USER_ATTR:-uid}"
LDAP_GROUP_ATTR="${LDAP_GROUP_ATTR:-memberOf}"

CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"
BASE_URL="https://${BMC_HOST}/redfish/v1"

echo "========================================"
echo "Configure OpenLDAP Client on OpenBMC"
echo "BMC: ${BMC_HOST}"
echo "LDAP Server: ${LDAP_SERVER}"
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

# --- Step 2: Show current LDAP configuration ---
# Display the existing LDAP settings so the user can see what will be changed.

echo "Step 2: Current LDAP configuration"
echo "$RESULT" | jq '.LDAP | {
    ServiceEnabled,
    ServiceAddresses,
    Authentication: {Username: .Authentication.Username},
    SearchSettings: .LDAPService.SearchSettings
}' 2>/dev/null || echo "  No existing LDAP configuration found"
echo ""

# --- Step 3: Configure LDAP service ---
# PATCH the AccountService with OpenLDAP settings. This sets the server URI,
# bind credentials for directory lookups, the search base DN where user
# accounts are located, and the attributes used to identify users and groups.
#
# Key fields:
#   ServiceEnabled       - Activates the LDAP service
#   ServiceAddresses     - Array of LDAP server URIs (ldap:// or ldaps://)
#   Authentication       - Bind DN and password for authenticated searches
#   SearchSettings       - Where and how to search for user entries
#     BaseDistinguishedNames - The DN subtree to search under
#     UsernameAttribute      - LDAP attribute that holds the login username
#     GroupsAttribute        - LDAP attribute listing group memberships

echo "Step 3: Configure LDAP service"
PATCH_RESULT=$($CURL -X PATCH \
    -H "Content-Type: application/json" \
    -d "{
        \"LDAP\": {
            \"ServiceEnabled\": true,
            \"ServiceAddresses\": [\"${LDAP_SERVER}\"],
            \"Authentication\": {
                \"AuthenticationType\": \"UsernameAndPassword\",
                \"Username\": \"${LDAP_BIND_DN}\",
                \"Password\": \"${LDAP_BIND_PASS}\"
            },
            \"LDAPService\": {
                \"SearchSettings\": {
                    \"BaseDistinguishedNames\": [\"${LDAP_BASE_DN}\"],
                    \"UsernameAttribute\": \"${LDAP_USER_ATTR}\",
                    \"GroupsAttribute\": \"${LDAP_GROUP_ATTR}\"
                }
            }
        }
    }" \
    "${BASE_URL}/AccountService" 2>/dev/null)

# Check if the PATCH succeeded by looking for error messages in the response.
if echo "$PATCH_RESULT" | jq -e '.error' > /dev/null 2>&1; then
    echo "  ERROR: LDAP configuration failed"
    echo "$PATCH_RESULT" | jq '.error'
    exit 1
fi
echo "  LDAP service configured successfully"
echo ""

# --- Step 4: Verify the new configuration ---
# Re-read the AccountService to confirm the settings were applied.

echo "Step 4: Verify new LDAP configuration"
VERIFY=$($CURL "${BASE_URL}/AccountService" 2>/dev/null)
echo "$VERIFY" | jq '.LDAP | {
    ServiceEnabled,
    ServiceAddresses,
    Authentication: {Username: .Authentication.Username},
    SearchSettings: .LDAPService.SearchSettings
}' 2>/dev/null
echo ""

echo "========================================"
echo "OpenLDAP configuration complete"
echo ""
echo "Next steps:"
echo "  1. Apply role mappings:  curl -k -u root:0penBmc -X PATCH \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d @ldap-role-mapping.json \\"
echo "       ${BASE_URL}/AccountService"
echo "  2. Test authentication:  LDAP_USER=jdoe LDAP_PASS=secret ./test-ldap-auth.sh"
echo "========================================"
