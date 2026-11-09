# sandboxer releases

This repository contains **release artifacts only** for sandboxer. The source
repository is private; this repository is public so installs and upgrades can
work without source access.

Each release includes:

- static musl tarballs for `x86_64` and `aarch64`;
- `SHA256SUMS`;
- an optional detached `SHA256SUMS.sig`;
- `install.sh`.

## Install

Install the latest stable release:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=release bash
```

Install the latest development prerelease:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=dev bash
```

Pin a specific tag:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_VERSION=v0.1.0-dev.2 bash
```

The installer verifies `SHA256SUMS`, installs to `~/.local/bin` by default, and
does not use `sudo` or edit shell rc files.

## Upgrade

```sh
sandboxer upgrade --check
sandboxer upgrade
sandboxer upgrade --version v0.1.0-dev.2
```

`upgrade` defaults to this public release repository. Set
`SANDBOXER_RELEASE_REPO=owner/repository` to use a mirror.

## Verification

Download the checksum files for a release and verify them against the published
allowed-signers file:

```sh
tag=v0.1.0-dev.3
base="https://github.com/PolasekT/sandboxer-releases/releases/download/$tag"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
curl -fsSLO "https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/release_allowed_signers"
ssh-keygen -Y verify \
  -f release_allowed_signers \
  -I sandboxer-release \
  -n sandboxer \
  -s SHA256SUMS.sig < SHA256SUMS
```

If a release was published without signing, `SHA256SUMS.sig` is absent and the
release notes contain a checksum-only warning.

## Security

Release artifacts are built by the tag-triggered workflow in the private source
repository. Do not report source vulnerabilities or request source access here.
Use the private source repository’s maintainer channel for security reports.
