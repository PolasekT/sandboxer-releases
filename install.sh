#!/usr/bin/env bash
set -euo pipefail

REPO="${SANDBOXER_RELEASE_REPO:-${SANDBOXER_REPO:-PolasekT/sandboxer-releases}}"
STREAM="${SANDBOXER_STREAM:-release}"
VERSION="${SANDBOXER_VERSION:-}"
INSTALL_DIR="${SANDBOXER_INSTALL_DIR:-$HOME/.local/bin}"
API_BASE="${SANDBOXER_API_BASE:-https://api.github.com/repos/$REPO}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
AUTH_CONFIG=""
TMP=""
CURL_AUTH=()
cleanup() {
  rm -rf "${TMP:-}"
  if [ -n "${AUTH_CONFIG:-}" ]; then
    rm -f "$AUTH_CONFIG"
  fi
}
trap cleanup EXIT
if [ -n "$TOKEN" ]; then
  AUTH_CONFIG="$(mktemp)"
  chmod 600 "$AUTH_CONFIG"
  AUTH_TOKEN=${TOKEN//\\/\\\\}
  AUTH_TOKEN=${AUTH_TOKEN//\"/\\\"}
  AUTH_TOKEN=${AUTH_TOKEN//$'\n'/}
  AUTH_TOKEN=${AUTH_TOKEN//$'\r'/}
  printf 'header = "Authorization: Bearer %s"\n' "$AUTH_TOKEN" > "$AUTH_CONFIG"
  unset AUTH_TOKEN
  CURL_AUTH=(--config "$AUTH_CONFIG")
fi
unset TOKEN GITHUB_TOKEN GH_TOKEN
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # `curl ... | bash` has no script path; only local mode uses SCRIPT_DIR.
  SCRIPT_DIR="$PWD"
fi
LOCAL="${SANDBOXER_LOCAL:-0}"
LOCAL_BINARY="${SANDBOXER_LOCAL_BINARY:-}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'sandboxer installer: missing dependency: %s\n' "$1" >&2
    exit 1
  }
}

install_local() {
  if [ "${SANDBOXER_BUILD:-0}" = "1" ]; then
    need cargo
    (cd "$SCRIPT_DIR" && cargo build --release)
  fi
  if [ ! -x "$LOCAL_BINARY" ]; then
    printf 'sandboxer installer: local binary not executable: %s\n' "$LOCAL_BINARY" >&2
    printf '  build it with: cargo build --release\n' >&2
    printf '  or set SANDBOXER_LOCAL_BINARY=/path/to/sandboxer\n' >&2
    exit 1
  fi
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$LOCAL_BINARY" "$INSTALL_DIR/sandboxer"
  printf 'Installed local build %s\n' "$INSTALL_DIR/sandboxer"
  printf '  source: %s\n' "$LOCAL_BINARY"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      printf 'Add %s to PATH, for example:\n' "$INSTALL_DIR"
      printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
      ;;
  esac
}

case "$LOCAL" in
  1|true|yes)
    if [ -z "$LOCAL_BINARY" ]; then
      PROFILE="${SANDBOXER_LOCAL_PROFILE:-release}"
      LOCAL_BINARY="$SCRIPT_DIR/target/$PROFILE/sandboxer"
    fi
    install_local
    exit 0
    ;;
esac

if [ -n "$LOCAL_BINARY" ]; then
  install_local
  exit 0
fi

need curl
need tar
need sha256sum

case "$(uname -s)" in
  Linux) ;;
  *) printf 'sandboxer installer: only Linux is supported by this installer\n' >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) TARGET="x86_64-unknown-linux-musl" ;;
  aarch64|arm64) TARGET="aarch64-unknown-linux-musl" ;;
  *) printf 'sandboxer installer: unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

if [ -z "$VERSION" ]; then
  if [ "$STREAM" = "release" ] || [ "$STREAM" = "stable" ]; then
    VERSION="$(curl -fsSL "${CURL_AUTH[@]}" "$API_BASE/releases/latest" |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  else
    VERSION="$(curl -fsSL "${CURL_AUTH[@]}" "$API_BASE/releases?per_page=30" |
      python3 -c 'import json,sys; releases=json.load(sys.stdin); print(next(r["tag_name"] for r in releases if not r.get("draft") and r.get("prerelease")))' 2>/dev/null || true)"
  fi
fi

if [ -z "$VERSION" ]; then
  printf 'sandboxer installer: could not determine a %s release\n' "$STREAM" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?$ ]]; then
  printf 'sandboxer installer: invalid release tag: %s\n' "$VERSION" >&2
  exit 1
fi

case "$VERSION" in
  *-dev.*) STABLE=0 ;;
  *) STABLE=1 ;;
esac
ALLOWED_SIGNERS="${SANDBOXER_RELEASE_ALLOWED_SIGNERS:-}"
if [ "$STABLE" = "1" ]; then
  default_signers="${XDG_CONFIG_HOME:-$HOME/.config}/sandboxer/release_allowed_signers"
  if [ -z "$ALLOWED_SIGNERS" ]; then
    if [ -f "$default_signers" ]; then
      ALLOWED_SIGNERS="$default_signers"
    else
      need ssh-keygen
      if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        printf 'sandboxer installer: stable releases require an allowed-signers file\n' >&2
        printf '  no terminal is available to fetch it; install %s first\n' \
          "$default_signers" >&2
        printf '  or set SANDBOXER_RELEASE_ALLOWED_SIGNERS\n' >&2
        exit 1
      fi
      printf 'sandboxer installer: stable releases require an allowed-signers file.\n' >&3
      printf 'The installer can fetch %s\n' "$default_signers" >&3
      printf 'from the same release repository. This protects against corrupted or\n' >&3
      printf 'unexpectedly replaced assets, but not against a compromised release\n' >&3
      printf 'repository. Prefer a signer file you obtained and reviewed separately.\n' >&3
      printf 'Fetch the published allowed-signers file now? [y/N] ' >&3
      if ! IFS= read -r answer <&3; then
        answer=""
      fi
      exec 3>&-
      case "$answer" in
        y|Y|yes|YES) ;;
        *)
          printf 'sandboxer installer: no allowed-signers file was installed\n' >&2
          printf '  fetch %s manually, set SANDBOXER_RELEASE_ALLOWED_SIGNERS,\n' \
            "$default_signers" >&2
          printf '  or re-run this installer from a terminal and accept the prompt\n' >&2
          exit 1
          ;;
      esac
      signers_tmp="$(mktemp)"
      if ! curl -fsSL "${CURL_AUTH[@]}" --retry 3 \
        -o "$signers_tmp" \
        "https://raw.githubusercontent.com/$REPO/master/release_allowed_signers"; then
        rm -f "$signers_tmp"
        printf 'sandboxer installer: could not fetch allowed-signers file\n' >&2
        exit 1
      fi
      chmod 0644 "$signers_tmp"
      mkdir -p "$(dirname "$default_signers")"
      if ! mv -f "$signers_tmp" "$default_signers"; then
        rm -f "$signers_tmp"
        printf 'sandboxer installer: could not install allowed-signers file\n' >&2
        exit 1
      fi
      ALLOWED_SIGNERS="$default_signers"
      printf 'Installed allowed-signers file: %s\n' "$ALLOWED_SIGNERS" >&2
    fi
  fi
  if [ -z "$ALLOWED_SIGNERS" ]; then
    exit 1
  fi
  need ssh-keygen
fi

ASSET="sandboxer-${VERSION}-${TARGET}.tar.gz"
BASE="${SANDBOXER_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/$VERSION}"
TMP="$(mktemp -d)"

printf 'Installing sandboxer %s (%s)\n' "$VERSION" "$TARGET"
curl -fsSL "${CURL_AUTH[@]}" --retry 3 -o "$TMP/$ASSET" "$BASE/$ASSET"
curl -fsSL "${CURL_AUTH[@]}" --retry 3 -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS"
EXPECTED="$(awk -v name="$ASSET" '$2 == name || $2 == "*"name { print $1; exit }' "$TMP/SHA256SUMS")"
if [ -z "$EXPECTED" ]; then
  printf 'sandboxer installer: checksum for %s is missing\n' "$ASSET" >&2
  exit 1
fi
ACTUAL="$(sha256sum "$TMP/$ASSET" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  printf 'sandboxer installer: checksum mismatch\n' >&2
  exit 1
fi

if [ -n "$ALLOWED_SIGNERS" ]; then
  need ssh-keygen
  curl -fsSL "${CURL_AUTH[@]}" --retry 3 -o "$TMP/SHA256SUMS.sig" "$BASE/SHA256SUMS.sig"
  ssh-keygen -Y verify -f "$ALLOWED_SIGNERS" -I sandboxer-release -n sandboxer \
    -s "$TMP/SHA256SUMS.sig" < "$TMP/SHA256SUMS"
fi

mkdir -p "$TMP/extract" "$INSTALL_DIR"
if tar -tvzf "$TMP/$ASSET" | awk 'substr($1,1,1) != "-" && substr($1,1,1) != "d" { exit 1 }'; then
  :
else
  printf 'sandboxer installer: archive contains a link or special entry\n' >&2
  exit 1
fi
tar -xzf "$TMP/$ASSET" -C "$TMP/extract"
BINARY="$(find "$TMP/extract" -type f -name sandboxer -perm -u+x | head -1)"
if [ -z "$BINARY" ]; then
  printf 'sandboxer installer: archive has no sandboxer binary\n' >&2
  exit 1
fi
install -m 0755 "$BINARY" "$INSTALL_DIR/sandboxer"

printf 'Installed %s\n' "$INSTALL_DIR/sandboxer"

# Remember the installed stream so the first `upgrade` does not silently
# switch a dev install to the stable stream.
INSTALL_STREAM="$STREAM"
if [ -n "$VERSION" ]; then
  case "$VERSION" in
    *-dev.*) INSTALL_STREAM=dev ;;
    *) INSTALL_STREAM=release ;;
  esac
fi
CONFIG_DIR="${SANDBOXER_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sandboxer}"
mkdir -p "$CONFIG_DIR"
printf 'stream = "%s"\nversion = "%s"\n' "$INSTALL_STREAM" "$VERSION" > "$CONFIG_DIR/install.toml"
printf '  stream: %s\n' "$INSTALL_STREAM"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf 'Add %s to PATH, for example:\n' "$INSTALL_DIR"
    printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
    ;;
esac
