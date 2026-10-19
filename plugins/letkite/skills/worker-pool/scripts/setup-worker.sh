#!/usr/bin/env bash
# setup-worker.sh: prepare Claude Code worker accounts on this Linux machine (run as root; idempotent).
#
#   setup-worker.sh [options] <worker>...
#
#   --mcp-url URL          LetKite MCP endpoint (default https://mcp.letkite.com/mcp; the console's Get started card shows yours)
#   --mcp-mode MODE        managed (default): /etc/claude-code/managed-mcp.json, machine-wide, workers cannot add other MCP servers
#                          user: `claude mcp add --scope user` per worker, workers may add more servers
#                          none: leave MCP alone
#   --claude-version VER   pin Claude Code to VER (default: npm's "stable" tag at install time)
#   --git-name NAME        git user.name for the workers
#   --git-email EMAIL      git user.email for the workers
#   --hide-attribution     no "Co-Authored-By: Claude" trailer or PR footer (managed setting)
#   --claude-md FILE       worker rules for ~/.claude/CLAUDE.md (default: ../assets/worker-CLAUDE.md next to this script)
#   --with-gh              install the GitHub CLI if missing
#   --force                overwrite /etc/claude-code files that this script did not write
#
# Installs: Node.js 22 (if no Node >= 18), Claude Code in /opt/ccw-claude-<version> (auto-update off), the ccw helper,
# /usr/local/libexec/ccw-key-helper (used only after `ccw key <worker>`), and one account per worker without sudo.
# Sign-ins (Claude, LetKite MCP, GitHub) happen afterwards in a terminal; see references/auth.md.
set -euo pipefail

MCP_URL=https://mcp.letkite.com/mcp
MCP_MODE=managed
CLAUDE_VERSION=""
GIT_NAME=""; GIT_EMAIL=""
HIDE_ATTR=0; WITH_GH=0; FORCE=0
HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_MD="$HERE/../assets/worker-CLAUDE.md"
WORKERS=()
MARK=/etc/claude-code/.written-by-worker-pool

die() { echo "setup-worker: $*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }
while [[ $# -gt 0 ]]; do case "$1" in
  --mcp-url) MCP_URL="${2:?}"; shift 2 ;;
  --mcp-mode) MCP_MODE="${2:?}"; shift 2 ;;
  --claude-version) CLAUDE_VERSION="${2:?}"; shift 2 ;;
  --git-name) GIT_NAME="${2:?}"; shift 2 ;;
  --git-email) GIT_EMAIL="${2:?}"; shift 2 ;;
  --hide-attribution) HIDE_ATTR=1; shift ;;
  --claude-md) CLAUDE_MD="${2:?}"; shift 2 ;;
  --with-gh) WITH_GH=1; shift ;;
  --force) FORCE=1; shift ;;
  -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
  -*) die "unknown option $1" ;;
  *) WORKERS+=("$1"); shift ;;
esac; done
[[ $EUID -eq 0 ]] || die "run as root"
[[ ${#WORKERS[@]} -gt 0 ]] || die "name at least one worker, e.g. setup-worker.sh ccw-01"
[[ $MCP_MODE =~ ^(managed|user|none)$ ]] || die "--mcp-mode is managed, user or none"
[[ -f $HERE/ccw ]] || die "ccw must sit next to this script"
for w in "${WORKERS[@]}"; do [[ $w =~ ^[a-z][a-z0-9-]{0,30}$ ]] || die "bad worker name '$w' (lowercase, digits, -)"; done

pkg_install() {
  if command -v apt-get > /dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" > /dev/null \
      || { apt-get update -qq > /dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" > /dev/null; }
  elif command -v dnf > /dev/null; then dnf install -y -q "$@" > /dev/null
  else die "no apt-get or dnf: install $* by hand"; fi
}

log "base packages"
pkg_install curl ca-certificates git xz-utils tar
[[ $WITH_GH -eq 1 ]] && ! command -v gh > /dev/null && pkg_install gh

log "Node.js"
if ! command -v node > /dev/null || [[ $(node -p 'process.versions.node.split(".")[0]') -lt 18 ]]; then
  case "$(uname -m)" in x86_64) na=x64 ;; aarch64|arm64) na=arm64 ;; *) die "no Node build for $(uname -m)" ;; esac
  tmp="$(mktemp -d)"
  curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -o "$tmp/SHASUMS256.txt"
  tarball="$(awk -v a="linux-$na.tar.xz" '$2 ~ a"$" {print $2}' "$tmp/SHASUMS256.txt" | head -1)"
  [[ -n $tarball ]] || die "could not find the Node 22 tarball for $na"
  curl -fsSL "https://nodejs.org/dist/latest-v22.x/$tarball" -o "$tmp/$tarball"
  (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | sha256sum -c --quiet -)
  tar -xJf "$tmp/$tarball" -C /opt
  ln -sfn "/opt/${tarball%.tar.xz}" /opt/node
  for b in node npm npx; do ln -sfn "/opt/node/bin/$b" "/usr/local/bin/$b"; done
  rm -rf "$tmp"
fi
echo "    node $(node --version)"

log "Claude Code"
[[ -n $CLAUDE_VERSION ]] || CLAUDE_VERSION="$(npm view @anthropic-ai/claude-code dist-tags.stable 2> /dev/null)"
[[ -n $CLAUDE_VERSION ]] || die "could not read the stable Claude Code version from npm; pass --claude-version"
dest="/opt/ccw-claude-$CLAUDE_VERSION"
# /usr/local/bin/claude must be ours (a link into /opt/ccw-claude*) or absent: workers run whatever it points to
if [[ -e /usr/local/bin/claude || -L /usr/local/bin/claude ]] && [[ "$(readlink /usr/local/bin/claude)" != /opt/ccw-claude* ]] && [[ $FORCE -eq 0 ]]; then
  die "/usr/local/bin/claude belongs to another install ($(readlink -f /usr/local/bin/claude)); remove it or pass --force"
fi
if [[ ! -x $dest/bin/claude ]]; then
  rm -rf "$dest.tmp"
  npm install -g --silent --no-fund --no-audit --prefix "$dest.tmp" "@anthropic-ai/claude-code@$CLAUDE_VERSION"
  "$dest.tmp/bin/claude" --version | grep -q "^$CLAUDE_VERSION " || die "installed claude is not $CLAUDE_VERSION"
  mv "$dest.tmp" "$dest"
fi
ln -sfn "$dest" /opt/ccw-claude
ln -sfn /opt/ccw-claude/bin/claude /usr/local/bin/claude
echo "    $(/usr/local/bin/claude --version) at $dest"

# machine-wide Claude Code policy; files someone else wrote are left alone unless --force
write_managed() {  # $1 file, stdin content
  local f="$1" tmp; tmp="$(mktemp)"; cat > "$tmp"
  if [[ -f $f ]] && ! grep -qx "$(basename "$f")" "$MARK" 2> /dev/null && [[ $FORCE -eq 0 ]]; then
    cmp -s "$tmp" "$f" || echo "    $f exists and was not written by this script: left as is (--force to replace)"
    rm -f "$tmp"; return
  fi
  install -D -m 644 "$tmp" "$f"; rm -f "$tmp"
  grep -qx "$(basename "$f")" "$MARK" 2> /dev/null || basename "$f" >> "$MARK"
}
log "Claude Code policy (/etc/claude-code)"
install -d -m 755 /etc/claude-code
attr=""
[[ $HIDE_ATTR -eq 1 ]] && attr='
  "includeCoAuthoredBy": false,
  "attribution": {"commit": "", "pr": ""},'
write_managed /etc/claude-code/managed-settings.json <<JSON
{
  "env": {"DISABLE_AUTOUPDATER": "1"},$attr
  "permissions": {
    "deny": ["Read(~/.config/ccw/**)", "Read(~/.config/gh/**)"]
  }
}
JSON
if [[ $MCP_MODE == managed ]]; then
  write_managed /etc/claude-code/managed-mcp.json <<JSON
{
  "mcpServers": {
    "letkite": {"type": "http", "url": "$MCP_URL"}
  }
}
JSON
fi

log "ccw helper"
install -d -m 755 /etc/ccw /usr/local/libexec
install -m 755 "$HERE/ccw" /usr/local/bin/ccw
cat > /usr/local/libexec/ccw-key-helper <<'HELPER'
#!/bin/sh
# Claude Code apiKeyHelper for workers that use an API key (set up by `ccw key <worker>`)
exec cat "$HOME/.config/ccw/anthropic-key"
HELPER
chmod 755 /usr/local/libexec/ccw-key-helper
touch /etc/ccw/workers

for w in "${WORKERS[@]}"; do
  log "worker $w"
  id -u "$w" > /dev/null 2>&1 || useradd --create-home --shell /bin/bash "$w"
  h="$(getent passwd "$w" | cut -d: -f6)"
  chmod 750 "$h"
  as() { (cd "$h" && runuser -u "$w" -- env HOME="$h" "$@"); }   # from the worker's home: it may not read our cwd
  as mkdir -p "$h/src" "$h/.claude"
  [[ -n $GIT_NAME ]] && as git config --global user.name "$GIT_NAME"
  [[ -n $GIT_EMAIL ]] && as git config --global user.email "$GIT_EMAIL"
  # first run of claude: no theme picker, no onboarding (sign-in happens separately)
  [[ -f $h/.claude.json ]] || as sh -c 'printf "{\"hasCompletedOnboarding\": true, \"theme\": \"dark\"}\n" > ~/.claude.json'
  if [[ -f $CLAUDE_MD ]]; then install -m 644 -o "$w" -g "$(id -gn "$w")" "$CLAUDE_MD" "$h/.claude/CLAUDE.md"
  else echo "    no worker rules file ($CLAUDE_MD): ~/.claude/CLAUDE.md not written"; fi
  if [[ $MCP_MODE == user ]] && ! as sh -c 'cd ~ && claude mcp get letkite' > /dev/null 2>&1; then
    as sh -c "cd ~ && claude mcp add --scope user --transport http letkite '$MCP_URL'" > /dev/null
  fi
  grep -qx "$w" /etc/ccw/workers || echo "$w" >> /etc/ccw/workers
done

log "done"
ccw status || true
echo "Next, per worker (in a terminal, answers through the LetKite console):"
echo "  sign in Claude:  ccw <worker> 'claude auth login --claudeai'   (or: ccw key <worker> for an API key)"
[[ $MCP_MODE != none ]] && echo "  connect LetKite: ccw <worker> 'claude mcp login --no-browser letkite'"
echo "  GitHub (opt.):   ccw <worker> 'gh auth login --hostname github.com --git-protocol https --web'"
