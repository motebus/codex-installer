# Codex Installer

Public, idempotent installation automation for a Mote Edge Ubuntu PC.

## Mote Transport canary

`install-mote-transport.sh` installs or verifies the pinned Agent-first Mote
Transport package set on Ubuntu `amd64`. The supported runtime is SSH with SFTP
file transfer. Legacy SCP, rsync, and RDP are retired.

Download the installer and checksum record from the GitHub release, verify the
script before running it, and use the native graphical authorization path only
if packages are missing:

```sh
release=mote-transport-2026.08.30-r02-canary
curl --proto '=https' --tlsv1.2 -fLO \
  "https://github.com/motebus/codex-installer/releases/download/$release/install-mote-transport.sh"
curl --proto '=https' --tlsv1.2 -fLO \
  "https://github.com/motebus/codex-installer/releases/download/$release/SHA256SUMS"
grep ' install-mote-transport.sh$' SHA256SUMS | sha256sum -c -
chmod 0755 install-mote-transport.sh
./install-mote-transport.sh
```

The installer downloads exact release assets over verified HTTPS, validates
their SHA-256 and Debian metadata, refuses implicit version changes, and skips
the package transaction when the exact versions are already present. See
[`docs/mote-transport-2026.08.30-r02-validation.md`](docs/mote-transport-2026.08.30-r02-validation.md)
for the canary evidence and open readiness findings.

Repository changes are developed through reviewed branches; `main` remains the
release authority.
