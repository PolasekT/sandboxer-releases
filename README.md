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
signature. Install the public signer once:

```sh
mkdir -p "$HOME/.config/sandboxer"
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/release_allowed_signers \
  -o "$HOME/.config/sandboxer/release_allowed_signers"
chmod 0644 "$HOME/.config/sandboxer/release_allowed_signers"
```

The installer can also offer to fetch this file interactively when run from a
terminal. Then install:

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
  SANDBOXER_VERSION=v0.2.2 bash
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

`agy` seeds existing host OAuth and presentation settings into project/shared
profiles. For API-key auth, pass the key at runtime rather than writing it to
config:

```sh
sandboxer run agy --env-from GEMINI_API_KEY
```

### Review before applying

```sh
sandboxer run opencode --mode overlay --overlay-persist review --net none
sandboxer overlay diff review --app opencode
sandboxer overlay apply review --app opencode
```

The first command leaves the workspace untouched. `overlay diff` shows the
pending changes, and `overlay apply` is the explicit write step.

Store a run as a patch, inspect it, then apply it deliberately:

```sh
sandboxer run opencode --store-patch --net proxy
sandboxer patch list
sandboxer patch apply <patch-id> --check
sandboxer patch apply <patch-id>
```

### Network modes

```sh
# Named services and explicit rules through the host proxy.
sandboxer run opencode --net-profile secure
sandboxer run opencode --service github
sandboxer run opencode --allow '*.example.com:443' --deny admin.example.com

# Public HTTP(S) through the proxy; host/private destinations stay blocked.
sandboxer run --net internet -- curl -fsS https://example.com/

# Raw public TCP/UDP/DNS/ICMP through pasta; no host/LAN/metadata access.
sandboxer run --net transparent -- ping 1.1.1.1

# Host/SNI policy for apps that ignore proxy variables.
sandboxer run --net transparent --transparent-intercept policy \
  --allow example.com -- curl -fsS https://example.com/
```

`internet` is proxy-backed and only covers clients that honor proxy settings.
`transparent` requires `pasta`/`passt`, `nft`, and `/dev/net/tun`; IPv6 and ICMP
depend on host support. The experimental `mitm-all` mode adds selective provider
TLS injection and remains opt-in.

### Detached sessions

```sh
sandboxer run opencode --detach
sandboxer session list
sandboxer session attach <run-id>
sandboxer session logs <run-id> --follow
sandboxer session stop <run-id>
```

The run continues under the supervisor after the terminal closes.

### Host services and publishing

```sh
# Reach one host TCP/UDP service through a run-private relay.
sandboxer run opencode --host-service 127.0.0.1:5432
sandboxer run opencode --host-port udp:127.0.0.1:5353

# Publish a guest loopback port on host loopback.
sandboxer run --publish 127.0.0.1:8080:3000 -- npm run dev
sandboxer run --publish 127.0.0.1:0:3000 -- npm run dev
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

### Observe and audit

Host-observation audit runs an app without containment so you can review what it
accesses before writing policy:

```sh
sandboxer audit opencode --out ~/audits/opencode.jsonl --yes
sandboxer wizard --from-audit ~/audits/opencode.jsonl
```

Run-level and filesystem audit are opt-in:

```sh
sandboxer run --audit --net proxy -- curl -fsS https://example.com/
sandboxer session audit <run-id> --json
sandboxer proxy explain example.com:443 --json

sandboxer run --fs-audit --net none -- sh -c 'echo changed > notes.txt'
sandboxer session fs-audit <run-id> --json
```

Audit does not log bodies, file contents, authorization headers, or secrets.
Filesystem audit is audit-only and rootless; it does not provide reliable
PID/exec attribution. Host-observation audit uses the bounded `strace` adapter
by default. Native `ptrace` is an explicit x86_64 opt-in with
`--engine ptrace`; aarch64 audit smoke is deferred for this release.

### Keep local rules close to the project

**What I need:** I keep a project on an external SSD under `/mnt` and want to
run it without weakening the workspace guard for every repository.

**How sandboxer delivers:** `/mnt` and `/media` themselves stay blocked, but
descendant project paths are allowed with a warning. Truly protected paths still
require the explicit run override.

**Try it:**

```sh
cd /mnt/ssd/home/me/projects/my-project
sandboxer run opencode-ei
# For an intentionally reviewed protected path:
sandboxer run --allow-unsafe-workspace opencode-ei
```

**Expected:** the first command prints a mount-root warning and starts; the
second also records the protected-workspace override in run status and the agent
manifest.

**What I need:** I want a local folder and development port available for
`opencode*` runs without repeating flags.

**How sandboxer delivers:** scoped override files add rules by app and workspace
selector. User-global and user-local rules are trusted; tracked repository rules
need explicit project trust for additive changes.

**Try it:**

```sh
mkdir -p ~/.config/sandboxer/overrides.d
cat > ~/.config/sandboxer/overrides.d/pylab.toml <<'EOF'
schema = 1
name = "pylab"

[when]
apps = ["opencode*"]

[add]
network.allow = ["127.0.0.1:5173", "pylab.internal:8443"]
mounts = [{ source = "/mnt/ssd/shared/pylab", target = "/mnt/ssd/shared/pylab", mode = "ro" }]
EOF
sandboxer config explain
sandboxer run opencode-ei
```

**Expected:** `config explain` lists the rule and sources, and the run gets the
local port and read-only folder. Tracked `.sandboxer/overrides.d/` rules require
`--trust-project-config` for additive rules; deny rules still apply with a
warning.

**What I need:** I want to silence audit noise and hide a workspace secret from
the app without changing global config.

**How sandboxer delivers:** `audit.ignore` filters wizard evidence while leaving
raw JSONL intact. `visibility.ignore` masks matching workspace paths inside the
sandbox; masks are workspace-only and currently require `rw`/`ro` mode.

**Try it:**

```sh
printf '%s\n' '**/node_modules/**' >> .sandboxer/audit.ignore
printf '%s\n' '.env' >> .sandboxer/visibility.ignore
sandboxer wizard --from-audit ~/audits/opencode.jsonl
```

**What I need:** when the agent needs a missing host or port, I want it to tell
me the exact rule instead of probing or trying to bypass the sandbox.

**How sandboxer delivers:** the generated AGENTS manifest lists user and
repository override locations and tells the agent to report a rule and stop.

**Expected:** the agent names the blocked host/port or path and points to the
appropriate `overrides.d` file; the host user reviews and applies it. Agents
never edit policy files from inside the sandbox.

### Snapshots, dashboard, and authoring

```sh
sandboxer snapshot create --app opencode --name before-refactor
sandboxer snapshot diff <a> <b> --stat
sandboxer snapshot diff <a> <b> --patch
sandboxer snapshot restore <id>
sandboxer snapshot create --app opencode --workspace --name workspace-before-refactor
sandboxer snapshot restore <id> --app opencode --workspace

sandboxer config explain
sandboxer config diff
sandboxer config migrate --dry-run
sandboxer dash
sandboxer wizard
```

`dash` opens the Overview graph and the Sessions, Apps, Services, Providers,
Mounts, Network, Profiles, Snapshots, Overlays, Patches, Audit, and Doctor views.
On Apps and Services, `n` opens the authoring wizard and `e` edits the selected
definition. `Ctrl-P` opens the command palette; `Ctrl-3` and `Ctrl-4` open
Settings and Help. `wizard` authors apps, services, providers, host services,
mounts, network rules, and network profiles, and can start from an audit.

### Diagnose the host

```sh
sandboxer doctor
sandboxer doctor --self-test
sandboxer doctor --containment
sandboxer doctor --full
```

Start with the fast default check. `--self-test` adds local probes,
`--containment` verifies the sandbox boundary, and `--full` combines them. Use
`--json` when you need a stable machine-readable report.

### Profiles and GPU

```sh
sandboxer run opencode --profile shared
sandboxer run opencode --profile name:review-2026
sandboxer run opencode --fresh
sandboxer profile reset --app agy
sandboxer run --gpu 1 -- python train.py
```

Named profiles use the explicit `name:<name>` form. GPU passthrough is limited
to the selected devices and weakens isolation.

## Upgrade

```sh
sandboxer upgrade --check
sandboxer upgrade
sandboxer upgrade --version v0.2.2
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
tag=v0.2.2
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
