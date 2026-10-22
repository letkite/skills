#!/usr/bin/env bash
# Point git (and optionally gh) at a token kept in an environment variable, for one HTTPS git host.
# Run as the user who will use git, not root. Changes only that user's ~/.gitconfig and shell profile.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: git-token-helper.sh --host HOST --env VAR [--user NAME] [--gh] [--remove]

Makes git answer HTTPS credential requests for HOST with the token in $VAR, read at the moment git
needs it. The token is never written to disk: ~/.gitconfig only holds the variable's name.
Use it when the token reaches the machine as an environment variable (for example a LetKite
console environment variable, which the agent passes to the commands it runs).

  --host HOST   git host, e.g. github.com, gitcode.com, gitlab.com
  --env VAR     name of the environment variable that holds the token (not the token)
  --user NAME   username sent with the token. Default: x-access-token (GitHub's convention).
                GitLab accepts oauth2; GitCode and Gitea want your account name.
  --gh          also make the GitHub CLI use it: login shells export GH_TOKEN from $VAR
                (only with --host github.com)
  --remove      undo this host's setup (and the GH_TOKEN line with --gh)
  -h, --help    this help

The host's helper list is reset first (an empty helper entry), so a global "store" helper never
saves the token to ~/.git-credentials for this host.
Check afterwards: git ls-remote https://HOST/OWNER/PRIVATE-REPO HEAD
EOF
}

HOST=""; VAR=""; USERNAME="x-access-token"; GH=0; REMOVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:?--host needs a value}"; shift 2 ;;
    --env) VAR="${2:?--env needs a value}"; shift 2 ;;
    --user) USERNAME="${2:?--user needs a value}"; shift 2 ;;
    --gh) GH=1; shift ;;
    --remove) REMOVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
done
[[ -n "$HOST" ]] || { echo "--host is required (see --help)" >&2; exit 2; }
[[ "$HOST" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || { echo "--host: a host name like github.com" >&2; exit 2; }
[[ $REMOVE -eq 1 || "$VAR" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "--env: a variable name like GITHUB_TOKEN" >&2; exit 2; }
[[ "$USERNAME" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "--user: letters, digits and . _ @ - only" >&2; exit 2; }
[[ $GH -eq 0 || "$HOST" == github.com ]] || { echo "--gh only goes with --host github.com" >&2; exit 2; }
[[ $EUID -ne 0 ]] || echo "note: running as root; this sets up git for root only" >&2

KEY="credential.https://$HOST.helper"
SNIPPET="$HOME/.config/letkite/gh-token.sh"
SOURCE_LINE='[ -f ~/.config/letkite/gh-token.sh ] && . ~/.config/letkite/gh-token.sh'

git config --global --unset-all "$KEY" 2> /dev/null || true
if [[ $REMOVE -eq 1 ]]; then
  if [[ $GH -eq 1 ]]; then
    rm -f "$SNIPPET"
    for f in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
      [[ -f "$f" ]] && grep -qF "$SOURCE_LINE" "$f" && grep -vF "$SOURCE_LINE" "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
    done
  fi
  echo "removed the token helper for $HOST"
  exit 0
fi

# '' resets the list for this host; the helper prints the credentials only when asked to "get"
git config --global "$KEY" ''
git config --global --add "$KEY" \
  "!f() { test \"\$1\" = get && test -n \"\$$VAR\" && printf 'username=%s\\npassword=%s\\n' '$USERNAME' \"\$$VAR\"; }; f"
echo "git: https://$HOST uses \$$VAR (user $USERNAME)"

if [[ $GH -eq 1 ]]; then
  mkdir -p "$(dirname "$SNIPPET")"
  printf '%s\n' "# git-token-helper.sh: the GitHub CLI uses \$$VAR when GH_TOKEN is not set" \
    "[ -n \"\${$VAR:-}\" ] && [ -z \"\${GH_TOKEN:-}\" ] && export GH_TOKEN=\"\$$VAR\"" > "$SNIPPET"
  for f in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$f" || "$f" == "$HOME/.profile" ]] || continue
    grep -qF "$SOURCE_LINE" "$f" 2> /dev/null || printf '\n%s\n' "$SOURCE_LINE" >> "$f"
  done
  echo "gh: login shells export GH_TOKEN from \$$VAR"
fi

if [[ -z "${!VAR:-}" ]]; then
  echo "warning: \$$VAR is not set in this shell. git finds it only in processes that have it" >&2
  echo "         (for LetKite console variables: commands the agent runs, and their children)." >&2
fi
