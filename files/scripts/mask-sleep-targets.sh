#!/usr/bin/env bash
# Mask the sleep targets. See recipes/recipe.yml for why.
#
# Symlinks are created directly rather than via `systemctl mask` because the
# build container has no running systemd, and systemctl refuses to operate
# without one. A unit symlinked to /dev/null anywhere in the search path is
# masked, and /usr/lib/systemd/system is in that path.
set -euo pipefail

for unit in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    ln -sf /dev/null "/usr/lib/systemd/system/${unit}"
    echo "masked ${unit}"
done

for unit in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    [ "$(readlink -f "/usr/lib/systemd/system/${unit}")" = "/dev/null" ] || {
        echo "ERROR: ${unit} did not end up masked"; exit 1; }
done
echo "All sleep targets masked."
