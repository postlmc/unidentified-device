#!/usr/bin/env bash

set -euo pipefail

# Create an empty /nix directory in the image.
#
# Aurora's root filesystem is read-only (composefs, since Fedora 42), so nothing
# at runtime can create a top-level /nix. Fedora's own nix-filesystem package
# creates it via tmpfiles.d, which also fails for the same reason -- this is what
# the Fedora Change page means by "/nix is incompatible with rpm-ostree".
#
# Baking the directory into the image sidesteps all of it. /nix only ever needs
# to be a *mount point*: the Determinate installer's nix.mount unit bind-mounts
# persistent storage onto it at boot. Once the dirent exists in the ostree
# commit, upstream Nix installs and runs with no wrappers, no transient root,
# and no local initramfs regeneration.
#
# Universal Blue will not ship this directory themselves (ublue-os/main#765,
# closed 2025-03-22), so it has to come from our own image.

echo "Creating /nix mount point..."
mkdir -p /nix

if [ ! -d /nix ]; then
    echo "ERROR: /nix was not created"
    exit 1
fi

echo "/nix created successfully"
