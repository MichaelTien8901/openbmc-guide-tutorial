#!/bin/bash
# User management script for OpenBMC
# Usage: user-management.sh [list|create|delete|set-password|set-role]

SERVICE="xyz.openbmc_project.User.Manager"
BASE_PATH="/xyz/openbmc_project/user"
USER_IFACE="xyz.openbmc_project.User.Attributes"
MGR_IFACE="xyz.openbmc_project.User.Manager"

list_users() {
    echo "=== User Accounts ==="
    USERS=$(busctl tree $SERVICE 2>/dev/null | grep "$BASE_PATH/" | grep -v "ldap")

    for user_path in $USERS; do
        USERNAME=$(basename $user_path)
        ROLE=$(busctl get-property $SERVICE $user_path $USER_IFACE UserPrivilege 2>/dev/null | awk -F'"' '{print $2}')
        ENABLED=$(busctl get-property $SERVICE $user_path $USER_IFACE UserEnabled 2>/dev/null | awk '{print $2}')
        LOCKED=$(busctl get-property $SERVICE $user_path $USER_IFACE UserLockedForFailedAttempt 2>/dev/null | awk '{print $2}')

        STATUS="enabled"
        [ "$ENABLED" = "false" ] && STATUS="disabled"
        [ "$LOCKED" = "true" ] && STATUS="locked"

        echo "  $USERNAME: role=$ROLE, status=$STATUS"
    done
}

create_user() {
    USERNAME="$1"
    PASSWORD="$2"
    ROLE="${3:-priv-user}"

    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo "Usage: $0 create USERNAME PASSWORD [ROLE]"
        echo "Roles: priv-admin, priv-operator, priv-user, priv-callback"
        exit 1
    fi

    # Create user via D-Bus
    busctl call $SERVICE $BASE_PATH $MGR_IFACE CreateUser "sassb" \
        "$USERNAME" \
        1 "ipmi" \
        "$ROLE" \
        true

    # Set password (requires separate call)
    echo "User $USERNAME created with role $ROLE"
    echo "Set password via Redfish or ipmitool"
}

delete_user() {
    USERNAME="$1"
    if [ -z "$USERNAME" ]; then
        echo "Usage: $0 delete USERNAME"
        exit 1
    fi

    if [ "$USERNAME" = "root" ]; then
        echo "Cannot delete root user"
        exit 1
    fi

    busctl call $SERVICE "$BASE_PATH/$USERNAME" xyz.openbmc_project.Object.Delete Delete
    echo "User $USERNAME deleted"
}

set_role() {
    USERNAME="$1"
    ROLE="$2"

    if [ -z "$USERNAME" ] || [ -z "$ROLE" ]; then
        echo "Usage: $0 set-role USERNAME ROLE"
        echo "Roles: priv-admin, priv-operator, priv-user, priv-callback"
        exit 1
    fi

    busctl set-property $SERVICE "$BASE_PATH/$USERNAME" $USER_IFACE UserPrivilege s "$ROLE"
    echo "User $USERNAME role set to $ROLE"
}

enable_user() {
    USERNAME="$1"
    ENABLED="$2"

    if [ -z "$USERNAME" ]; then
        echo "Usage: $0 enable USERNAME [true|false]"
        exit 1
    fi

    ENABLED="${ENABLED:-true}"
    busctl set-property $SERVICE "$BASE_PATH/$USERNAME" $USER_IFACE UserEnabled b "$ENABLED"
    echo "User $USERNAME enabled=$ENABLED"
}

case "$1" in
    list)
        list_users
        ;;
    create)
        create_user "$2" "$3" "$4"
        ;;
    delete)
        delete_user "$2"
        ;;
    set-role)
        set_role "$2" "$3"
        ;;
    enable)
        enable_user "$2" "$3"
        ;;
    *)
        echo "Usage: $0 [list|create|delete|set-role|enable]"
        echo ""
        echo "Commands:"
        echo "  list                       - List all users"
        echo "  create USER PASS [ROLE]    - Create new user"
        echo "  delete USER                - Delete user"
        echo "  set-role USER ROLE         - Change user role"
        echo "  enable USER [true|false]   - Enable/disable user"
        echo ""
        echo "Roles: priv-admin, priv-operator, priv-user, priv-callback"
        exit 1
        ;;
esac
