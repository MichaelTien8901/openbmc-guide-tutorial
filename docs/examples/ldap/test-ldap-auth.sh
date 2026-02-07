#!/bin/bash
#
# Test LDAP Authentication on OpenBMC via Redfish
#
# Verifies that LDAP authentication is working by attempting to log in
# to the Redfish API with LDAP user credentials. The script performs
# several checks:
#
#   1. Confirms the BMC is reachable with local admin credentials
#   2. Verifies LDAP or Active Directory is enabled
#   3. Attempts a Redfish session login with the LDAP user
#   4. Reads the session details to confirm the assigned role
#   5. Cleans up the session
#
# Usage:
#   ./test-ldap-auth.sh
#
# Environment variables (override defaults):
#   BMC_HOST    - BMC address with port (default: localhost:2443)
#   BMC_USER    - BMC local admin username for setup checks (default: root)
#   BMC_PASS    - BMC local admin password (default: 0penBmc)
#   LDAP_USER   - LDAP username to test (default: testuser)
#   LDAP_PASS   - LDAP user password (default: testpassword)
#
# Prerequisites:
#   - curl and jq installed on the machine running this script
#   - BMC has LDAP or Active Directory configured and enabled
#   - LDAP server is reachable from the BMC network
#   - The test user exists in the LDAP directory

set -euo pipefail

# --- Configuration variables (override via environment) ---

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"
LDAP_USER="${LDAP_USER:-testuser}"
LDAP_PASS="${LDAP_PASS:-testpassword}"

CURL_ADMIN="curl -k -s -u ${BMC_USER}:${BMC_PASS}"
BASE_URL="https://${BMC_HOST}/redfish/v1"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "========================================"
echo "LDAP Authentication Test"
echo "BMC: ${BMC_HOST}"
echo "LDAP User: ${LDAP_USER}"
echo "========================================"
echo ""

# --- Test 1: Verify BMC Redfish connectivity ---
# Use local admin credentials to confirm the BMC is reachable.

echo "Test 1: Verify BMC connectivity"
ACCT_SVC=$($CURL_ADMIN "${BASE_URL}/AccountService" 2>/dev/null)
if echo "$ACCT_SVC" | jq -e '.Id' > /dev/null 2>&1; then
    pass "Redfish AccountService is reachable"
else
    fail "Cannot reach Redfish AccountService at ${BASE_URL}"
    echo "       Check BMC_HOST, BMC_USER, and BMC_PASS"
    exit 1
fi
echo ""

# --- Test 2: Check LDAP/AD service status ---
# Verify that at least one directory service (LDAP or Active Directory)
# is enabled on the BMC before attempting authentication.

echo "Test 2: Check directory service status"
LDAP_ENABLED=$(echo "$ACCT_SVC" | jq -r '.LDAP.ServiceEnabled // false')
AD_ENABLED=$(echo "$ACCT_SVC" | jq -r '.ActiveDirectory.ServiceEnabled // false')

if [ "$LDAP_ENABLED" = "true" ]; then
    pass "OpenLDAP service is enabled"
    LDAP_ADDR=$(echo "$ACCT_SVC" | jq -r '.LDAP.ServiceAddresses[0] // "N/A"')
    echo "       Server: ${LDAP_ADDR}"
elif [ "$AD_ENABLED" = "true" ]; then
    pass "Active Directory service is enabled"
    AD_ADDR=$(echo "$ACCT_SVC" | jq -r '.ActiveDirectory.ServiceAddresses[0] // "N/A"')
    echo "       Server: ${AD_ADDR}"
else
    fail "Neither LDAP nor Active Directory is enabled"
    echo "       Run configure-openldap.sh or configure-active-directory.sh first"
    exit 1
fi
echo ""

# --- Test 3: Attempt Redfish session login with LDAP credentials ---
# Create a Redfish session using the LDAP user's credentials. If LDAP
# authentication is working, the BMC will validate the credentials against
# the directory server and create a session. The session token and location
# are returned in the response headers.

echo "Test 3: Redfish session login with LDAP credentials"
echo "  POST ${BASE_URL}/SessionService/Sessions"

# Use -D to capture response headers (contains X-Auth-Token and Location)
HEADER_FILE=$(mktemp)
LOGIN_RESULT=$(curl -k -s \
    -D "$HEADER_FILE" \
    -H "Content-Type: application/json" \
    -d "{\"UserName\": \"${LDAP_USER}\", \"Password\": \"${LDAP_PASS}\"}" \
    "${BASE_URL}/SessionService/Sessions" 2>/dev/null)

# Extract the session token and location from response headers
SESSION_TOKEN=$(grep -i "X-Auth-Token" "$HEADER_FILE" 2>/dev/null | tr -d '\r' | awk '{print $2}' || true)
SESSION_LOCATION=$(grep -i "Location" "$HEADER_FILE" 2>/dev/null | tr -d '\r' | awk '{print $2}' || true)
rm -f "$HEADER_FILE"

if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "" ]; then
    pass "LDAP session login succeeded"
    echo "       Session Token: ${SESSION_TOKEN:0:20}..."

    # Display the session details (username, role assigned by role mapping)
    SESSION_USER=$(echo "$LOGIN_RESULT" | jq -r '.UserName // "N/A"')
    SESSION_ID=$(echo "$LOGIN_RESULT" | jq -r '.Id // "N/A"')
    echo "       Session ID: ${SESSION_ID}"
    echo "       Username: ${SESSION_USER}"
else
    fail "LDAP session login failed"
    echo "       Response:"
    echo "$LOGIN_RESULT" | jq '.' 2>/dev/null || echo "  $LOGIN_RESULT"
    echo ""
    echo "       Possible causes:"
    echo "         - LDAP user does not exist in the directory"
    echo "         - Incorrect LDAP password"
    echo "         - LDAP server unreachable from BMC"
    echo "         - Bind DN credentials are incorrect"
    echo "         - Base DN does not contain the user"
fi
echo ""

# --- Test 4: Verify session with token-based request ---
# If the session was created, use the token to make an authenticated request.
# This confirms the session is valid and shows the user's effective role.

echo "Test 4: Verify session with token-based request"
if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "" ]; then
    SESSION_CHECK=$(curl -k -s \
        -H "X-Auth-Token: ${SESSION_TOKEN}" \
        "${BASE_URL}/SessionService/Sessions" 2>/dev/null)

    if echo "$SESSION_CHECK" | jq -e '.Members' > /dev/null 2>&1; then
        MEMBER_COUNT=$(echo "$SESSION_CHECK" | jq '.Members | length')
        pass "Token-based request succeeded (${MEMBER_COUNT} active session(s))"
    else
        fail "Token-based request failed"
    fi
else
    echo "  Skipped (no session token from Test 3)"
fi
echo ""

# --- Test 5: Check role mapping for the LDAP user ---
# Query the AccountService to show current role mappings. This helps
# diagnose issues where login succeeds but the user gets the wrong role.

echo "Test 5: Current role mappings"
echo "  LDAP RemoteRoleMapping:"
echo "$ACCT_SVC" | jq '.LDAP.RemoteRoleMapping // []' 2>/dev/null
echo "  ActiveDirectory RemoteRoleMapping:"
echo "$ACCT_SVC" | jq '.ActiveDirectory.RemoteRoleMapping // []' 2>/dev/null
echo ""

# --- Cleanup: Delete the test session ---
# Remove the session to avoid leaving stale sessions on the BMC.

if [ -n "$SESSION_TOKEN" ] && [ "$SESSION_TOKEN" != "" ] && [ -n "$SESSION_LOCATION" ]; then
    echo "Cleanup: Deleting test session"
    # Extract the session path from the Location header
    SESSION_PATH=$(echo "$SESSION_LOCATION" | sed 's|https://[^/]*||')
    if [ -n "$SESSION_PATH" ]; then
        curl -k -s \
            -X DELETE \
            -H "X-Auth-Token: ${SESSION_TOKEN}" \
            "https://${BMC_HOST}${SESSION_PATH}" > /dev/null 2>&1
        echo "  Session deleted"
    fi
    echo ""
fi

# --- Summary ---
echo "========================================"
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "Troubleshooting:"
    echo "  - Check BMC logs:  ssh -p 2222 root@localhost journalctl -u phosphor-user-manager -f"
    echo "  - Verify LDAP config:  curl -k -s -u root:0penBmc ${BASE_URL}/AccountService | jq '.LDAP'"
    echo "  - Test LDAP server:  ldapsearch -x -H <server-uri> -b <base-dn> -D <bind-dn> -w <bind-pass> '(uid=${LDAP_USER})'"
    exit 1
fi
