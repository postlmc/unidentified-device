# Automating a Bare-Metal Rebuild

## Goal

Rebuild this machine from empty drives with as little manual work as possible, and without being in the room. The KVM provides
remote power control, console, and attachable virtual storage, so the only physical prerequisites are power and a network.

## The Invariant

Drive 1 is the OS and is disposable. Drive 2 holds `/home`, the Steam library, and local snapshots, and the installer never touches
it.

That is what makes an unattended install safe: the kickstart wipes one whole drive and ignores the other, rather than performing
partition-level surgery to preserve a subvolume on a drive it is otherwise recreating. Relocating `/home` to drive 2 is a
prerequisite, and must be done before an unattended install is attempted.

The Nix store is deliberately on the disposable side of that line. It persists to `/var/lib/nix` on drive 1 rather than inside
`/home`, so a wipe discards it and devbox repopulates from the binary cache. The store is a cache, not data.

Backups still go off-box to the NAS. Drive 2 surviving a deliberate wipe is not the same as drive 2 surviving a failure, and once it
holds home, Steam, and the snapshots at once, a snapshot sent to it is not redundancy.

## What the Image Actually Describes Today

The recipe builds and the image works, but it does not describe the machine. Auditing the running host against `recipes/recipe.yml`
on 2026-08-27 found several categories of state that a bare-metal rebuild would not reproduce.

| State                        | Where It Lives                                                                  | In the Image | Notes                                                                                                  |
|------------------------------|---------------------------------------------------------------------------------|--------------|--------------------------------------------------------------------------------------------------------|
| Base packages and repos      | Image                                                                           | Yes          | The `dnf` module works as intended                                                                     |
| Declared flatpaks            | Image                                                                           | Yes          | All 13 are installed                                                                                   |
| Undeclared flatpaks          | Host                                                                            | No           | 29 present: 18 Aurora defaults, 11 host-only                                                           |
| Layered RPMs                 | Host, `rpm-ostree`                                                              | n/a          | None as of 2026-11-07; `fira-code-fonts` and `gamescope` are gone                                      |
| Masked sleep targets         | Image                                                                           | Yes          | NVIDIA suspend crash workaround, four units; the redundant `/etc` copies were removed 2026-11-07       |
| FiraCode Nerd Font           | Dotfiles (`nerd-fonts.fira-code` in devbox), linked into `~/.local/share/fonts` | No           | Owned by the dotfiles repo, deliberately not in the image                                              |
| Nix systemd units            | `/etc/systemd/system/`                                                          | No           | Five units, installer-generated                                                                        |
| `determinate-nixd`, `devbox` | `/usr/local/bin`                                                                | No           | `/usr/local` is `/var/usrlocal`, host state                                                            |
| Kernel arguments             | Base image `kargs.d`                                                            | Yes          | `initcall_blacklist=simpledrm_platform_driver_init` comes from `/usr/lib/bootc/kargs.d/00-nvidia.toml` |

The table was re-checked on 2026-11-07. The kernel argument comes from the base image, so the
`kargs` module is not needed. The sleep masks are in the image. The Nerd Font stays with the
dotfiles repo, which also manages it on other machines, so the image does not carry it.

Shrinking this table matters more than the orchestration around it. Every row moved into the recipe is a step that never has to be
scripted, sequenced, or debugged on a broken machine. BlueBuild already ships modules covering several of these directly, including
`kargs`, `systemd`, and `chezmoi`, none of which this recipe currently uses.

Note that the `systemd` module exposes only `enabled` and `disabled`. Masking the sleep targets needs a `script` module, because
`sleep.target` is pulled in as a dependency by logind rather than being started because it is enabled.

## The Install Mechanism Is Kickstart

`bluebuild generate-iso` exists and works, but it produces an interactive Anaconda installer that expects a human to complete the
configuration screens. It is a convenience for a fresh install, not an automation path.

Unattended bare-metal provisioning of a bootc system is done with a kickstart file, using the `ostreecontainer` directive to point
Anaconda at the published image:

```text
clearpart --drives=nvme0n1 --all --initlabel
ignoredisk --only-use=nvme0n1
ostreecontainer --source-imgref registry:ghcr.io/postlmc/unidentified-device:latest \
                --target-imgref ghcr.io/postlmc/unidentified-device:latest
```

Because the kickstart pulls the image from the registry, **the ISO does not need to be custom**. Any Anaconda-capable Fedora
installation media can execute this kickstart and end up running this image. That sidesteps the ISO hosting problem noted in the
README, and it matters for the KVM specifically: a stock netinstall ISO is a few hundred megabytes, where a full custom ISO is
several gigabytes over virtual media.

The kickstart is the real configuration artifact. It should cover partitioning of drive 1, filesystem creation with pinned UUIDs,
subvolume layout, account creation with pinned UIDs, and a `%post` section installing the cosign policy so the deployment is
signature-verified rather than pulled unverified.

## The Alternative: bootc install

The host has `bootc` 1.16.9, and Aurora ships `/usr/lib/bootc/install/20-aurora.toml` declaring `root-fs-type = "btrfs"`. From a
live environment with podman, the image can install itself directly:

```bash
podman run --rm --privileged --pid=host \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    --security-opt label=type:unconfined_t \
    ghcr.io/postlmc/unidentified-device:latest \
    bootc install to-disk /dev/nvme0n1
```

This trades Anaconda for a boot medium and a shell. It is worth knowing about, but kickstart is the better fit because it handles
bootloader and ESP setup and needs no interactive environment.

## Phases

| Phase | Work                                       | Automatable | Mechanism                  |
|-------|--------------------------------------------|-------------|----------------------------|
| 0     | Power on, attach install media             | Remote      | KVM virtual media          |
| 1     | Wipe drive 1, partition, install the image | Yes         | Kickstart                  |
| 2     | Accounts, signing policy                   | Yes         | Kickstart `%post`          |
| 3     | Restore the age identity                   | No          | Human, via 1Password       |
| 4     | Apply dotfiles, install Nix and devbox     | Yes         | chezmoi `run_once` scripts |
| 5     | Restore anything missing                   | Yes         | NAS                        |

Phase 3 is the only irreducible human gate and should stay that way. It is a credential unlock, and automating it would mean storing
the thing it protects.

## Hardware Configuration

Disk and filesystem identity is machine-specific and does not belong in documentation or in a public repository. It lives in
`rebuild/hardware.env`, which is gitignored, with `rebuild/hardware.env.example` committed as the documented shape. Generate the
real file on a running system with `rebuild/capture-hardware.sh`.

The kickstart should be templated from that file rather than hardcoding identifiers. Note that filesystem UUIDs are only stable if
pinned: reformatting generates new ones unless `mkfs.btrfs -U` is used, which is worth doing so a rebuilt machine matches the
recorded configuration exactly.

## Open Questions

- The kickstart has not been validated against this image. It needs proving in a VM.
- Signature verification is not available at install time. `ostreecontainer` exposes only `--stateroot`, `--source-imgref`,
  `--target-imgref`, and on Fedora 45 also `--bootloader` and `--composefs`. There is no signature-verification option, so the
  install pulls unverified and the cosign policy must be established in `%post` for later upgrades to be checked.
- Whether to declare the 11 host-only flatpaks in the recipe or leave them as host state:
  `com.google.Chrome`, `io.github.dvlv.boxbuddyrs`, `io.github.input_leap.input-leap`,
  `io.github.pwr_solaar.solaar`, `io.github.Qalculate.qalculate-qt`, `it.mijorus.gearlever`,
  `org.cvfosammmm.Setzer`, `org.gnome.Loupe`, `org.gnome.World.PikaBackup`,
  `org.gustavoperedo.FontDownloader`, and `org.mozilla.thunderbird_esr`. The other 18 undeclared
  flatpaks are Aurora base defaults.
- Whether the KVM's virtual media can boot a netinstall ISO reliably, and at what speed.
