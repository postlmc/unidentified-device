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

Create an empty `/nix` at image build time (`files/scripts/create-nix-dir.sh`). That is the entire contribution of the image.

`/nix` only ever needs to be a **mount point**. Once the dirent exists in the ostree commit, the Determinate installer runs normally
and does the rest itself: it selects its `ostree` planner, persists the store at `/var/home/nix`, and writes a `nix.mount` unit that
bind-mounts the latter onto the former at boot. No wrapper scripts, no store relocation, and nothing to hand-write.

"Nothing to hand-write" is not the same as "nothing exists", and the difference matters. The installer creates five units under
`/etc/systemd/system/`: `nix.mount`, `nix-daemon.service`, `nix-daemon.socket`, `nix-directory.service`, and
`determinate-nixd.socket`. None of them come from the image.

This supersedes the earlier wrapper-based approach, which hand-built that bind-mount (`/run/nix/store` -> `/var/lib/nix/store`) with
eight files of wrappers and units. That design was correct in shape; it is simply now redundant, because the installer does it
upstream.

## What Lives Where

Only `/nix` itself comes from the image. Everything else that makes Nix work is host state created at install time:

| Component          | Location               | Persists In      | In the Image |
|--------------------|------------------------|------------------|--------------|
| `/nix` mount point | `/nix`                 | ostree commit    | Yes          |
| Five systemd units | `/etc/systemd/system/` | `/etc`           | No           |
| `determinate-nixd` | `/usr/local/bin/`      | `/var/usrlocal`  | No           |
| `devbox`           | `/usr/local/bin/`      | `/var/usrlocal`  | No           |
| Nix store          | `/var/home/nix`        | `home` subvolume | No           |

Two consequences follow. The store lives inside the **home** subvolume, so anything that wipes or relocates `/home` takes the Nix
store with it. And a rebuilt host needs the installer re-run, because rebasing to this image restores the mount point and nothing
else.

## Setup After Rebasing to an Image with /nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
nix --version
devbox version
```

No planner argument is needed. The installer detects the ostree system on its own, and `/nix/receipt.json` on this host records
`"planner": "ostree"` with `"persistence": "/var/home/nix"`. Verified 2026-08-27 running Determinate Nix 3.22.2 on Nix 2.35.2.

## Known Risk

SELinux, and the risk is more real than "it currently works" makes it sound. It is the stated reason Universal Blue refuses to
support Nix.

Verified 2026-08-27: SELinux is `Enforcing`, and both Nix and devbox work. But **no SELinux policy is installed for Nix**. `/nix`
and `/nix/store` are both labelled `default_t`, the generic fallback, which means no file-context rule exists for the store at all.
It works because nothing currently objects to `default_t`, not because the labelling is correct. Listing policy modules requires
root and was not checked; the label evidence alone is what this rests on.

So a policy tightening upstream, or any confined domain that needs to execute out of the store, can break this without warning. If
Nix misbehaves, check `ausearch -m avc -ts recent` before assuming a Nix bug.

## References

- <https://fedoraproject.org/wiki/Changes/Nix_package_tool>
- <https://github.com/DeterminateSystems/nix-installer/issues/1445>
- <https://github.com/ublue-os/main/issues/765>
- <https://bootc.dev/bootc/filesystem.html>
