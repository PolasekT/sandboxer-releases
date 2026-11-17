# sandboxer releases

Static Linux release artifacts and a short, task-oriented guide for sandboxer.
The source repository is private; this repository is public so installs and
upgrades work without source access.

Each release includes:

- static musl tarballs for `x86_64` and `aarch64`;
- `SHA256SUMS`;
- a detached `SHA256SUMS.sig` for stable releases (dev releases may be
  checksum-only when no signing key is configured);
- `install.sh`.

## Install

Install the current stable release (stable installs require an allowed-signers
file and a valid detached signature):

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=release \
  SANDBOXER_RELEASE_ALLOWED_SIGNERS="$HOME/.config/sandboxer/release_allowed_signers" \
  bash
```

Install the current development prerelease:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_STREAM=dev bash
```

Pin a specific tag:

```sh
curl -fsSL https://raw.githubusercontent.com/PolasekT/sandboxer-releases/master/install.sh |
  SANDBOXER_VERSION=v0.1.0-dev.8 bash
```

The installer verifies `SHA256SUMS`, installs to `~/.local/bin` by default, and
does not use `sudo` or edit shell rc files. Stable releases require detached
signature verification with an allowed-signers file; development prereleases
may use checksum-only bootstrap when no signers file is configured. Confirm the
installed build with:

```sh
sandboxer version
```

Release builds print the release tag, commit, target, and profile. Stable
releases use `SANDBOXER_STREAM=release` when available; development prereleases
use `SANDBOXER_STREAM=dev`.

## What do you need?

Commands assume `sandboxer` is on `PATH` after installation.

### “I need to run an agent on a real project without exposing my home directory”

**How sandboxer delivers:** the workspace is mounted at the same absolute path,
while the rest of the host home, host processes, and unrelated host files stay
outside.

```sh
cd ~/src/my-project
sandboxer run opencode
```

**Expected:** OpenCode starts at the same absolute workspace path as the host,
and unrelated host files outside that workspace are unavailable.

### “I need to review an agent’s changes before they touch my workspace”

**How sandboxer delivers:** overlay mode writes to a copy-on-write layer; nothing
is applied until you ask for it.

```sh
sandboxer run opencode --mode overlay --overlay-persist review --net none
sandboxer overlay diff review --app opencode
sandboxer overlay apply review --app opencode
```

**Expected:** the workspace is unchanged by the run, `overlay diff` shows the
pending changes, and `overlay apply` is the explicit step that writes them.

### “I need to run a command with no network”

**How sandboxer delivers:** `--net none` removes network access for that run.

```sh
sandboxer run --net none -- cargo test
```

**Expected:** the command runs at the workspace path with no network access.

### “I need a background agent I can reconnect to”

**How sandboxer delivers:** detached runs keep a supervisor and session
metadata; attach reconnects to the running app.

```sh
sandboxer run opencode --detach
sandboxer session list
sandboxer session attach <run-id>
```

**Expected:** the run continues under the supervisor after the terminal closes;
`session attach` reconnects to it, and `session stop` ends it.

### “I need public web access without giving the app the host network”

**How sandboxer delivers:** proxy-backed `internet` mode permits public HTTP(S)
while private, loopback, and link-local destinations remain blocked.

```sh
sandboxer run --net internet -- curl -fsS https://example.com/
```

**Expected:** the request succeeds through the proxy; host and private network
destinations remain unreachable.

This mode covers HTTP(S) clients that honor proxy settings. Raw TCP, SSH, UDP,
ICMP, and apps that ignore proxy variables are not covered.

### “I need hostname-aware policy for tools that ignore proxy settings”

**How sandboxer delivers:** opt-in transparent interception parses HTTP `Host`
and TLS SNI inside the pasta namespace, applies the existing allow/deny policy,
and blocks UDP 443 and non-DNS UDP.

```sh
sandboxer run --net transparent --transparent-intercept policy \
  --allow example.com --allow 203.0.113.0/24:443 \
  -- curl -fsS https://example.com/
```

**Expected:** allowed hosts, IPs, and CIDRs connect through the interceptor;
denied destinations fail closed. IPv4 and IPv6 use the same policy path; IPv6
fails closed when the host has no usable route. Raw `--net transparent` remains
unchanged when interception is not selected.

Explicit hosts, IPs, CIDRs, and service endpoints are resolved before entering
the pasta namespace. Wildcard allow patterns and port-range rules still depend
on the helper resolver.

OpenCode’s default `all` network profile is broad. Use `--net-profile secure` or
explicit `--service`/`--allow` rules when you want a narrower interception
policy.

### “I need injected provider credentials only for selected APIs”

**How sandboxer delivers:** the experimental `mitm-all` mode terminates HTTPS
with a per-run CA and injects configured provider headers only for explicitly
selected provider hosts. Non-provider TLS passes through end-to-end.

```sh
sandboxer run --net transparent --transparent-intercept mitm-all \
  --service <provider-service> -- curl -fsS https://<provider-host>/...
```

**Expected:** only the selected provider host receives the injected header. The
app must trust the per-run CA. Chunked MITM request bodies fail closed, and
HTTP/2-only clients are not supported. This mode is experimental; use it only
with providers and workflows you have tested.

### “I need to reach a local service without host networking”

**How sandboxer delivers:** explicit TCP, UDP, HTTP, or Unix host-service relays
expose only the selected endpoint through a run-private socket.

```sh
sandboxer run opencode --host-service 127.0.0.1:5432
```

**Expected:** the app can reach that loopback service through a run-private
guest relay; the relay path is exposed in `SANDBOXER_HOST_SERVICE_<NAME>`. Other
host network destinations remain unavailable. Non-loopback targets require
explicit approval.

### “I need to know what network decisions a run made”

**How sandboxer delivers:** opt-in audit mode records network allowances,
denials, and lifecycle events without logging bodies, authorization headers, or
secrets.

```sh
sandboxer run --audit --net proxy -- curl -fsS https://example.com/
sandboxer session audit <run-id> --json
```

**Expected:** the run ID has a JSONL audit trail with host, port, decision, and
reason fields.

### “I need to know which files an agent changed”

**How sandboxer delivers:** opt-in rootless filesystem audit records workspace
and selected-profile path/operation events without logging file contents or
secrets. It works in rw, ro, ephemeral overlay, and persistent overlay modes.

```sh
sandboxer run --fs-audit --net none -- sh -c 'echo changed > notes.txt'
sandboxer session fs-audit <run-id>
sandboxer session fs-audit <run-id> --json
```

Add `--fs-audit-reads` to include open/read/access events. Events include
create, write, attrib, rename, unlink, and explicit overflow/unavailable
degradation markers. Overlay events report the guest workspace path.

**Expected:** the run produces `runs/<id>/fs.audit.jsonl`; the text/JSON view
shows what changed, and file contents are never recorded. This is audit-only,
rootless, and does not provide PID or reliable exec attribution.

### “I need one GPU for a local model run”

**How sandboxer delivers:** GPU access is explicit and limited to the selected
devices.

```sh
sandboxer run --gpu 1 -- python train.py
```

**Expected:** the process sees the selected GPU only; host GPU access is not
exposed unless requested.

### “I need to run on an SELinux-enforcing host”

**How sandboxer delivers:** `doctor` probes Bubblewrap’s `/proc` mask mounts and
reports whether SELinux blocks them. If blocked, it recommends a narrow policy
or AVC-generated policy instead of asking you to disable SELinux. It also warns
when Bubblewrap is older than 0.13 instead of treating overlay support as a hard
failure.

```sh
sandboxer doctor
```

**Expected:** the report identifies host, SELinux, namespace, overlay, and
sandbox readiness issues with an actionable next step. Sandboxer never runs
`sudo`, `semodule`, or `setenforce` itself.

### “I need OpenCode’s terminal identity and colors to survive”

**How sandboxer delivers:** OpenCode runs preserve the host terminal identity
(`TERM_PROGRAM`, `TERM_PROGRAM_VERSION`) and color preferences without
forwarding unrelated terminal variables.

```sh
sandboxer run opencode
```

**Expected:** OpenCode recognizes the host terminal and color settings inside
the sandbox, while unrelated terminal environment values stay outside.

## Upgrade

```sh
sandboxer upgrade --check
sandboxer upgrade
sandboxer upgrade --version v0.1.0-dev.8
```

To follow development prereleases:

```sh
sandboxer upgrade --check --stream dev
sandboxer upgrade --stream dev
```

The installer records the selected stream and version; `upgrade` follows that
stream by default, and an explicit `-dev.N` version selects the dev stream
automatically. `upgrade` defaults to this public release repository. Set
`SANDBOXER_RELEASE_REPO=owner/repository` to use a mirror.

## Verification

Download the checksum files for a release and verify them against the published
allowed-signers file:

```sh
tag=v0.1.0-dev.8
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
