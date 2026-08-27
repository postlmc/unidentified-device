# BlueBuild Repo for Unidentified Device [![bluebuild build badge](https://github.com/postlmc/unidentified-device/actions/workflows/build.yml/badge.svg)](https://github.com/postlmc/unidentified-device/actions/workflows/build.yml)

This repo contains the configuration of the [Aurora Linux](https://getaurora.dev/) base image running my not-really-a-Mac-anymore PC
named Unidentified Device. (yes, really)

Built on `ghcr.io/ublue-os/aurora-dx-nvidia-open:stable` and published to **`ghcr.io/postlmc/unidentified-device`**.

See the [BlueBuild docs](https://blue-build.org/how-to/setup/) for quick setup instructions for setting up your own repository based
on the original template from which this repo was created.

## Installation

> [!WARNING] Rebase to **`ghcr.io/postlmc/unidentified-device`**, never to `ghcr.io/blue-build/template`. The template is the
> upstream BlueBuild starter, not this image. Rebasing to it silently replaces Aurora with a generic Fedora base — this has happened
> here before.

To rebase an existing atomic Fedora installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:

```shell
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/postlmc/unidentified-device:latest
```

- Reboot to complete the rebase:

```shell
systemctl reboot
```

- Then rebase to the signed image, like so:

```shell
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/postlmc/unidentified-device:latest
```

- Reboot again to complete the installation

```shell
systemctl reboot
```

The `latest` tag will automatically point to the latest build. That build will still always use the Fedora version specified in
`recipe.yml`, so you won't get accidentally updated to the next major version.

### Other tags

Builds from branches and commits are published too, which is useful for testing a change before merging:

| Tag      | Example                                                           |
|----------|-------------------------------------------------------------------|
| `latest` | `ghcr.io/postlmc/unidentified-device:latest`                      |
| branch   | `ghcr.io/postlmc/unidentified-device:br-feature_nix-store-dir-44` |
| commit   | `ghcr.io/postlmc/unidentified-device:cd6543a-44`                  |

The trailing number is the Fedora major version. Branch builds are triggered manually with `gh workflow run build.yml --ref
<branch>`; pushes to `main` build automatically.

## Nix and devbox

`devbox` is the tool of choice here for per-project development environments, and it needs Nix.

Aurora's root filesystem is genuinely read-only (composefs, since Fedora 42), so **nothing at runtime can create a top-level
`/nix`** — not the Determinate installer, and not Fedora's own `nix-filesystem` package, which uses `tmpfiles.d` and fails for the
same reason. Universal Blue [declined to ship the directory](https://github.com/ublue-os/main/issues/765) in their base images.

This image therefore creates an empty `/nix` at build time ([`files/scripts/create-nix-dir.sh`](files/scripts/create-nix-dir.sh)).
That is the entire fix: `/nix` only ever needs to be a **mount point**.

After rebasing, install Nix the ordinary way:

```shell
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

The installer detects the ostree system, creates `/var/home/nix`, bind-mounts it onto `/nix`, and installs an SELinux policy. The
root filesystem stays read-only. Then:

```shell
devbox init && devbox add jq && devbox run -- jq --version
```

See [`docs/nix-on-aurora.md`](docs/nix-on-aurora.md) for why the alternatives — transient root, rootless mode, and toolbox
containers — were each rejected.

> [!NOTE] If the installer fails at the `Cleanup` step with `path ".../profiles/profile" is not in the Nix store`, that is stale
> state from an earlier Nix attempt. Move `~/.local/state/nix`, `~/.local/share/nix`, `~/.cache/nix` and `~/.nix-profile` aside and
> run it again.

## 1Password

The image installs the 1Password desktop app, the browser extension's native-messaging host, and `op` — all as RPMs, not flatpaks,
so the browser bridge is not sandboxed away.

### Pinned group GIDs (important)

1Password setgids `1Password-BrowserSupport` and `/usr/bin/op` to the `onepassword` and `onepassword-cli` groups, and the desktop
app verifies connecting peers against those groups via `SO_PEERCRED`. The RPM scriptlets create the groups with whatever GID is next
free **in the build container**, which will not match the running host — and ostree never merges new groups into a locally-modified
`/etc/group`. The result is a setgid bit pointing at a GID that means something else, and the app rejects the peer with:

```text
peer was not in the correct application group, rejecting remote
```

which shows up as the browser extension demanding its own sign-in.

[`files/system/usr/lib/sysusers.d/1password.conf`](files/system/usr/lib/sysusers.d/1password.conf) pins the GIDs, and
[`files/scripts/pin-1password-gids.sh`](files/scripts/pin-1password-gids.sh) applies them **before** the dnf module so the RPM
scriptlets adopt them rather than inventing their own. Do not remove either without understanding the above.

On an **existing** host the groups already exist at the wrong GIDs, and `sysusers` will not renumber them, so a one-time migration
is needed:

```shell
sudo groupmod -g 1001 onepassword
sudo groupmod -g 944 onepassword-cli
```

Verify with — these two numbers must be equal:

```shell
stat -c %g /usr/lib/opt/1Password/1Password-BrowserSupport   # setgid GID
getent group onepassword                                     # group GID
```

### Known issue: CLI desktop app integration does not work

`op` cannot use "Integrate with 1Password CLI" on this image. Even with `/usr/bin/op` setgid to `onepassword-cli` and the GIDs
matching exactly, the app rejects it:

```text
[op-sys-info/src/process_information/linux.rs:409] invalid group attempted to connect
Failed to accept new connection.: PipeAuthError(NoCreds)
```

The same pipe accepts `1Password-BrowserSupport` at the `onepassword` GID in the same session, so the mechanism works — only the CLI
group is refused. Ruled out: PTY and session variables, `onepassword-cli` group membership, toggling the setting, and app start
ordering. See also the open upstream report [blue-build/modules#77](https://github.com/blue-build/modules/issues/77).

**Workaround** — turn *off* "Integrate with 1Password CLI" in the app, then authenticate `op` directly:

```shell
op account add        # sign-in address, email, Secret Key, password
eval $(op signin)
```

Sessions expire on inactivity, so `eval $(op signin)` is needed per shell.

## ISO

If build on Fedora Atomic, you can generate an offline ISO using the
[BlueBuild's ISO guide](https://blue-build.org/learn/universal-blue/#fresh-install-from-an-iso). These ISOs cannot unfortunately be
distributed on GitHub for free due to large sizes, so for public projects something else has to be used for hosting.

## Verification

These images are signed with [Sigstore](https://www.sigstore.dev/)'s [cosign](https://github.com/sigstore/cosign). You can verify
the signature by downloading the `cosign.pub` file from this repo and running the following command:

```bash
cosign verify --key cosign.pub ghcr.io/postlmc/unidentified-device
```
