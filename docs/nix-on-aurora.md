# Nix + devbox on Aurora

## Goal

Run `devbox` on Aurora for project-local development environments, consistent with the same `devbox.json` on macOS. Global packages
stay on brew + flatpak.

## Why the Image Has to Do Anything at All

Nix insists on `/nix`. Since Fedora 42, Aurora's root filesystem is genuinely read-only (composefs), so nothing at runtime can
create a top-level directory. Three consequences:

1. The Determinate installer's `nix-directory.service` fails — it runs `chattr -i /`,
which composefs rejects (DeterminateSystems/nix-installer#1445).
2. Fedora's official `nix` package does not help. Its `nix-filesystem` subpackage
creates `/nix` through tmpfiles.d, which fails for the same reason. This is what the Fedora Change page means by *"/nix is
incompatible with rpm-ostree: so on ostree systems one should use nix either within a toolbox container or nix-core with a rootless
mode installation."*
3. Universal Blue will not ship an empty `/nix` in their base images. Request
ublue-os/main#765 was closed 2025-03-22 — a settled policy decision, because Nix upstream has no SELinux support and they get bug
reports they cannot action. Do not wait for this to change.

## Why Not Rootless Mode

Fedora suggests `nix-core` rootless, with the store under `~/.local/share/nix/root/nix/store/`. Binary cache NARs are built for the
`/nix/store` prefix, so a relocated store cannot consume them and everything compiles from source. That defeats the purpose of
devbox.

## Why Not Transient Root

`[root] transient = true` in `prepare-root.conf` makes `/` a writable overlay and does work, but the config must live at
`/usr/lib/ostree/prepare-root.conf` — `rpm-ostree initramfs-etc --track=/etc/ostree/prepare-root.conf` places it at the `/etc` path,
where `ostree-prepare-root` never reads it, and it fails silently. Verified on Aurora 43.20260317 / libostree 2025.7 on 2026-08-26:
the system booted fine but `findmnt /` still reported `ro`.

Making it work requires `rpm-ostree initramfs --enable` to inject the file at the `/usr/lib` path via dracut. That switches the host
to a locally generated initramfs, which slows updates and risks interacting badly with the NVIDIA driver. Rejected.

## What We Actually Do

Create an empty `/nix` at image build time (`files/scripts/create-nix-dir.sh`).

`/nix` only ever needs to be a **mount point**. The Determinate installer creates a `nix.mount` unit that bind-mounts persistent
storage onto it at boot. Once the dirent exists in the ostree commit, upstream Nix installs and runs normally — no wrapper scripts,
no custom systemd units, no store relocation.

This supersedes the earlier wrapper-based approach, which hand-built that bind-mount (`/run/nix/store` -> `/var/lib/nix/store`) with
eight files of wrappers and units. That design was correct in shape; it is simply now redundant, because the installer does it
upstream.

## Setup After Rebasing to an Image with /nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
nix --version
devbox version
```

## Known Risk

SELinux. It is the stated reason Universal Blue refuses to support Nix, and it is the most likely thing to break. If Nix misbehaves,
check `ausearch -m avc -ts recent` before assuming a Nix bug.

## References

- <https://fedoraproject.org/wiki/Changes/Nix_package_tool>
- <https://github.com/DeterminateSystems/nix-installer/issues/1445>
- <https://github.com/ublue-os/main/issues/765>
- <https://bootc.dev/bootc/filesystem.html>
