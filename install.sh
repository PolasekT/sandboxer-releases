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
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$AUTH_CONFIG"
  CURL_AUTH=(--config "$AUTH_CONFIG")
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

ALLOWED_SIGNERS="${SANDBOXER_RELEASE_ALLOWED_SIGNERS:-}"
if [ -n "$ALLOWED_SIGNERS" ]; then
  need ssh-keygen
  curl -fsSL "${CURL_AUTH[@]}" --retry 3 -o "$TMP/SHA256SUMS.sig" "$BASE/SHA256SUMS.sig"
  ssh-keygen -Y verify -f "$ALLOWED_SIGNERS" -I sandboxer-release -n sandboxer \
    -s "$TMP/SHA256SUMS.sig" < "$TMP/SHA256SUMS"
fi

mkdir -p "$TMP/extract" "$INSTALL_DIR"
tar -xzf "$TMP/$ASSET" -C "$TMP/extract"
BINARY="$(find "$TMP/extract" -type f -name sandboxer -perm -u+x | head -1)"
if [ -z "$BINARY" ]; then
  printf 'sandboxer installer: archive has no sandboxer binary\n' >&2
  exit 1
fi
install -m 0755 "$BINARY" "$INSTALL_DIR/sandboxer"

printf 'Installed %s\n' "$INSTALL_DIR/sandboxer"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    printf 'Add %s to PATH, for example:\n' "$INSTALL_DIR"
    printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
    ;;
esac
