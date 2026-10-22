#!/usr/bin/env bash
# What a developer environment on this machine already has: run as the user it is for. Read-only.
set -euo pipefail

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  cat <<'EOF'
Usage: probe-env.sh

Prints key=value lines about this user's developer setup, so you can offer only what is missing.
Read-only: it runs version and status commands and reads config, and changes nothing.
Never prints a secret: for environment variables it prints names only, for credentials only where
they come from.

  user, home, os, arch, sudo     who and where (sudo=yes|password|no)
  have_<tool>=<version>|no       git, gh, node, npm, claude, opencode, curl
  git_name, git_email            git identity (empty when not set)
  git_helpers                    credential helpers, with each host they apply to
  git_credentials_file=yes|no    ~/.git-credentials exists (plain-text tokens from the "store" helper)
  gh_auth=<account>|no           who gh is signed in as, and gh_auth_source (GH_TOKEN, keyring, file)
  ssh_github=<account>|no        what github.com says to this user's SSH key
  claude_auth, opencode_auth     signed in or not
  token_vars                     names of environment variables that look like tokens
EOF
  exit 0
fi

kv() { printf '%s=%s\n' "$1" "$2"; }
ver() { command -v "$1" > /dev/null 2>&1 && { "$@" 2> /dev/null | head -1 | tr -d '\r' || echo present; } || echo no; }

kv user "$(id -un)"
kv home "$HOME"
kv os "$( . /etc/os-release 2> /dev/null && echo "$PRETTY_NAME" || uname -s)"
kv arch "$(uname -m)"
if [[ $EUID -eq 0 ]]; then kv sudo root
elif sudo -n true 2> /dev/null; then kv sudo yes
elif command -v sudo > /dev/null && id -nG | grep -qwE 'sudo|wheel|admin'; then kv sudo password
else kv sudo no; fi

kv have_git "$(ver git --version)"
kv have_gh "$(ver gh --version)"
kv have_node "$(ver node --version)"
kv have_npm "$(ver npm --version)"
kv have_curl "$(ver curl --version | cut -d' ' -f1-2)"
# the installers put these in the user's own bin directories, which a non-login shell may lack
PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
kv have_claude "$(ver claude --version)"
kv have_opencode "$(ver opencode --version)"

if command -v git > /dev/null; then
  kv git_name "$(git config --global user.name || true)"
  kv git_email "$(git config --global user.email || true)"
  kv git_helpers "$(git config --global --get-regexp '^credential\..*helper$' 2> /dev/null \
    | awk '{ k=$1; sub(/^credential\./, "", k); sub(/\.?helper$/, "", k); h=$2; if (h ~ /^!/) h="(shell function)";
             printf "%s%s=%s", (n++ ? "; " : ""), (k == "" ? "*" : k), (h == "" ? "(reset)" : h) }')"
fi
kv git_credentials_file "$([[ -f "$HOME/.git-credentials" ]] && echo yes || echo no)"

if command -v gh > /dev/null; then
  out="$(gh auth status --hostname github.com 2>&1 || true)"
  acct="$(sed -nE 's/.*Logged in to github.com account ([^ ]+).*/\1/p' <<< "$out" | head -1)"
  kv gh_auth "${acct:-no}"
  [[ -n "$acct" ]] && kv gh_auth_source "$(sed -nE 's/.*account [^ ]+ \(([^)]+)\).*/\1/p' <<< "$out" | head -1)"
fi

if command -v ssh > /dev/null; then
  out="$(timeout 10 ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 git@github.com 2>&1 || true)"
  kv ssh_github "$(sed -nE 's/^Hi ([^!]+)!.*/\1/p' <<< "$out" | head -1 | grep . || echo no)"
fi

if command -v claude > /dev/null; then
  out="$(timeout 20 claude auth status 2>&1 || true)"
  if grep -q '"loggedIn": *true' <<< "$out"; then
    kv claude_auth "yes ($(sed -nE 's/.*"authMethod": *"([^"]+)".*/\1/p' <<< "$out" | head -1))"
  else kv claude_auth no; fi
fi
if command -v opencode > /dev/null; then
  out="$(timeout 20 opencode auth list 2>&1 || true)"
  n="$(grep -cE '●|✓|api|oauth' <<< "$out" || true)"
  kv opencode_auth "$([[ ${n:-0} -gt 0 ]] && echo "yes ($n)" || echo no)"
fi

kv token_vars "$(env | cut -d= -f1 | grep -E 'TOKEN|_PAT$|PERSONAL|GITHUB|GITLAB|GITCODE|GITEA|API_KEY' | sort | paste -sd, - || true)"
