#!/usr/bin/env bash

set -euo pipefail

# Create 1Password's groups with pinned GIDs BEFORE the dnf module installs
# 1password / 1password-cli.
#
# Both RPM scriptlets follow the same pattern:
#
#   if [ ! "$(getent group "${GROUP_NAME}")" ]; then groupadd "${GROUP_NAME}"; fi
#   chgrp "${GROUP_NAME}" "$BINARY"
#   chmod g+s "$BINARY"
#
# Because they skip groupadd when the group already exists, pre-creating the
# groups here means chgrp/setgid uses our pinned GIDs instead of whatever the
# build container happens to hand out.
#
# /usr/lib/sysusers.d/1password.conf is the single source of truth; it also
# ensures the groups exist on a freshly installed host at runtime.

CONF=/usr/lib/sysusers.d/1password.conf

if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF missing - the files module must run before this script"
    exit 1
fi

echo "Pinning 1Password group GIDs from $CONF..."
systemd-sysusers "$CONF"

for g in onepassword onepassword-cli onepassword-mcp; do
    if ! getent group "$g" >/dev/null; then
        echo "ERROR: group $g was not created"
        exit 1
    fi
    echo "  $(getent group "$g")"
done

echo "1Password group GIDs pinned"
