# sandboxer releases

Static Linux release artifacts and a short, task-oriented guide for sandboxer.
The source repository is private; this repository is public so installation and
upgrades work without source access.

Each release includes:

- static musl tarballs for `x86_64` and `aarch64`;
- `SHA256SUMS`;
- `SHA256SUMS.sig` for stable releases (development releases may be
  checksum-only when no signing key is configured);
- `install.sh`.

## Install

Stable installs require a configured allowed-signers file and a valid detached
signature:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=release \
  SANDBOXER_RELEASE_ALLOWED_SIGNERS="$HOME/.config/sandboxer/release_allowed_signers" \
  bash
```

Development prereleases may use checksum-only bootstrap when no signers file is
configured:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=dev bash
```

Pin a tag:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_VERSION=v0.2.0 bash
```

The installer verifies `SHA256SUMS`, installs to `~/.local/bin` by default, and
does not use `sudo` or edit shell rc files. Verify the installed build:

```sh
sandboxer version
sandboxer doctor
```

Release builds report the release tag, commit, target, and profile.

## Common workflows

Commands assume `sandboxer` is on `PATH`.

### Run an agent on a real project

```sh
cd ~/src/my-project
sandboxer run opencode
# or the shipped Antigravity CLI app:
sandboxer run agy
```

The workspace is mounted at the same absolute path. Unrelated host home files,
processes, and devices stay outside the sandbox.

### Review before applying

```sh
sandboxer run opencode --mode overlay --overlay-persist review --net none
sandboxer overlay diff review --app opencode
sandboxer overlay apply review --app opencode
```

The first command leaves the workspace untouched. `overlay diff` shows the
pending changes, and `overlay apply` is the explicit write step.

### Run offline, read-only, or as a one-off

```sh
sandboxer run --net none -- cargo test
sandboxer run --mode ro --net none -- git diff
sandboxer run --net internet -- curl -fsS https://example.com/
```

`internet` mode is proxy-backed public HTTP(S). Raw TCP, SSH, UDP, ICMP, and apps
that ignore proxy variables are not covered.

### Detached sessions

```sh
sandboxer run opencode --detach
sandboxer session list
sandboxer session attach <run-id>
sandboxer session stop <run-id>
```

The run continues under the supervisor after the terminal closes.

### Hostname-aware transparent policy

```sh
sandboxer run --net transparent --transparent-intercept policy \
  --allow example.com --allow 203.0.113.0/24:443 \
  -- curl -fsS https://example.com/
```

Allowed hosts, IPs, and CIDRs connect through the interceptor; denied
destinations fail closed. Raw `--net transparent` remains available without
interception. Wildcard allow patterns and port-range rules still use the helper
resolver.

Optional dependencies for transparent modes are `pasta`/`passt`, `nft`, and
`/dev/net/tun`. IPv6 and ICMP depend on host support.

### Provider credential injection

```sh
sandboxer run --net transparent --transparent-intercept mitm-all \
  --service <provider-service> -- curl -fsS https://<provider-host>/...
```

Only selected provider hosts receive the injected header. The app must trust the
per-run CA. This mode is experimental, supports HTTP/1.1, and should be used only
with providers and workflows you have tested.

### Host services and publishing

```sh
# Reach one host TCP/UDP service through a run-private relay.
sandboxer run opencode --host-service 127.0.0.1:5432
sandboxer run opencode --host-port udp:127.0.0.1:5353

# Publish a guest loopback port on host loopback.
sandboxer run --publish 127.0.0.1:8080:3000 -- npm run dev
sandboxer run --publish 127.0.0.1:5353:5353/udp -- dns-server
```

Loopback publishes are visible to other local users. External binds require
`--publish-external` and explicit review.

### Mount a host path

```sh
sandboxer run opencode --bind /srv/data
sandboxer run opencode --bind /srv/data:ro
sandboxer run opencode --mount /srv/data:/data:ro
```

Sensitive host sources require `--mount-force`; prefer narrow paths over broad
home-directory mounts. Workspaces rooted under `~/.config`, `~/.cache`, or
`~/.local` are rejected as credential/XDG/runtime trees; use a normal project
directory instead.

### Audit changes and network decisions

```sh
sandboxer run --audit --net proxy -- curl -fsS https://example.com/
sandboxer session audit <run-id> --json

sandboxer run --fs-audit --net none -- sh -c 'echo changed > notes.txt'
sandboxer session fs-audit <run-id> --json
```

Audit is opt-in and does not log bodies, file contents, authorization headers,
or secrets. Filesystem audit is audit-only and rootless; it does not provide
reliable PID/exec attribution. Host-observation audit uses the bounded `strace`
adapter by default. Native `ptrace` is an explicit x86_64 opt-in with
`--engine ptrace`; aarch64 audit smoke is deferred for `v0.2.0`.

### Snapshots, dashboard, and authoring

```sh
sandboxer snapshot create --app opencode --name before-refactor
sandboxer snapshot diff <a> <b>
sandboxer snapshot restore <id>

sandboxer dash
sandboxer wizard
```

`dash` opens the Overview graph and the Sessions, Apps, Services, Providers,
Mounts, Network, Profiles, Snapshots, Overlays, Patches, Audit, and Doctor views.
`wizard` authors apps, services, providers, host services, mounts, network rules,
and network profiles.

### Profiles and GPU

```sh
sandboxer run opencode --profile shared
sandboxer run opencode --profile name:review-2026
sandboxer run opencode --fresh
sandboxer profile reset --app agy   # delete the current default profile
sandboxer run --gpu 1 -- python train.py
```

Named profiles use the explicit `name:<name>` form. GPU passthrough is limited
to the selected devices and weakens isolation.

## Upgrade

```sh
sandboxer upgrade --check
sandboxer upgrade
sandboxer upgrade --version v0.2.0
```

Follow development prereleases with:

```sh
sandboxer upgrade --check --stream dev
sandboxer upgrade --stream dev
```

The installer records the selected stream and version; `upgrade` follows it by
default. `upgrade` verifies checksums, replaces the binary atomically, and keeps
the previous binary for rollback. A configured signer policy also applies to
`--check` and `--dry-run`: a release without `SHA256SUMS.sig` is refused.

## Verify release assets

```sh
tag=v0.2.0
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

Development releases published without a signing key omit `SHA256SUMS.sig` and
carry a checksum-only warning in their release notes.

## Security

Release artifacts are built by the tag-triggered workflow in the private source
repository. Do not report source vulnerabilities or request source access here;
use the private source repository’s maintainer channel for security reports.

Sandboxer contains cooperative or semi-trusted tools; it is not a guarantee
against a hostile kernel exploit. Review the source repository’s usage and
security documentation for limitations, including host networking, GPU
passthrough, same-UID co-tenancy, cgroup fail-open, and experimental transparent
MITM.
