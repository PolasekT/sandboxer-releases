# sandboxer releases

This repository contains release artifacts and a short, task-oriented guide for
sandboxer. The source repository is private; this repository is public so
installs and upgrades can work without source access.

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

## What do you need?

These are shipped workflows, not a roadmap. Commands assume `sandboxer` is on
`PATH` after installation.

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

This mode currently covers HTTP(S) clients that honor proxy settings. Raw TCP,
SSH, UDP, ICMP, and apps that ignore proxy variables are not covered.

### “I need to know what network decisions a run made”

**How sandboxer delivers:** opt-in audit mode records network allowances, denials,
and lifecycle events without logging bodies, authorization headers, or secrets.

```sh
sandboxer run --audit --net proxy -- curl -fsS https://example.com/
sandboxer session audit <run-id> --json
```

**Expected:** the run ID has a JSONL audit trail with host, port, decision, and
reason fields.

### “I need one GPU for a local model run”

**How sandboxer delivers:** GPU access is explicit and limited to the selected
devices.

```sh
sandboxer run --gpu 1 -- python train.py
```

**Expected:** the process sees the selected GPU only; host GPU access is not
exposed unless requested.

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
