#!/usr/bin/env bash
# Put a new release of an app live: copy it into releases/, switch the current link, restart its
# services, check health, and switch back if the check fails. Changes the app's directory and restarts
# its services.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-release.sh --app NAME --from DIR [--service UNIT]... [--health URL] [--keep N] [--base DIR]
  deploy-release.sh --app NAME --rollback [--service UNIT]... [--health URL] [--base DIR]
  deploy-release.sh --app NAME --list [--base DIR]

Run it as the deploy account (the one that owns the app's directory). Layout under --base
(default /srv/NAME):

  releases/<UTC time>/   one directory per release, never changed after it went live
  current -> releases/…  what the services run (their WorkingDirectory / ExecStart point here)

  --app NAME       the app's name; also the default base directory /srv/NAME
  --from DIR       a built release: its contents are copied (without .git) into a new release
  --service UNIT   a systemd unit to restart after switching (repeat for several). Uses
                   `sudo -n systemctl restart UNIT`: give the deploy account a sudoers line for exactly
                   that (references/deploy-app.md). None: nothing is restarted (static files only)
  --health URL     after the restart, GET this URL until it answers 2xx (60 s at most); if it never
                   does, switch back to the release before and restart again, then exit 1
  --keep N         releases to keep, the live one included (default 5)
  --rollback       switch to the release before the current one (and restart, check health)
  --list           print the releases, marking the live one
  --base DIR       the app's directory, if not /srv/NAME

Exit codes: 0 live and healthy; 1 failed (and rolled back when --health was given); 2 usage.
EOF
}

APP="" FROM="" HEALTH="" KEEP=5 BASE="" MODE=deploy SERVICES=()
while [[ $# -gt 0 ]]; do case "$1" in
  --app) APP="${2:?}"; shift 2 ;;
  --from) FROM="${2:?}"; shift 2 ;;
  --service) SERVICES+=("${2:?}"); shift 2 ;;
  --health) HEALTH="${2:?}"; shift 2 ;;
  --keep) KEEP="${2:?}"; shift 2 ;;
  --base) BASE="${2:?}"; shift 2 ;;
  --rollback) MODE=rollback; shift ;;
  --list) MODE=list; shift ;;
  -h|--help) usage; exit 0 ;;
  *) echo "unknown option $1" >&2; usage >&2; exit 2 ;;
esac; done
[[ "$APP" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "--app: lowercase letters, digits and -" >&2; exit 2; }
[[ "$KEEP" =~ ^[0-9]+$ && "$KEEP" -ge 2 ]] || { echo "--keep: 2 or more" >&2; exit 2; }
BASE="${BASE:-/srv/$APP}"
REL="$BASE/releases"
mkdir -p "$REL"

live() { readlink -f "$BASE/current" 2> /dev/null || true; }
switch_to() {   # atomic: a new link, renamed over the old one
  ln -sfn "$1" "$BASE/.current.new"
  mv -T "$BASE/.current.new" "$BASE/current"
  echo "live: $(basename "$1")"
}
restart() {
  local u
  for u in ${SERVICES[@]+"${SERVICES[@]}"}; do
    sudo -n systemctl restart "$u" || { echo "restart $u failed (sudoers line for it?)" >&2; return 1; }
  done
}
healthy() {
  [[ -z "$HEALTH" ]] && return 0
  local _
  for _ in $(seq 1 30); do
    curl -fsS -o /dev/null --max-time 5 "$HEALTH" 2> /dev/null && { echo "healthy: $HEALTH"; return 0; }
    sleep 2
  done
  echo "not healthy after 60 s: $HEALTH" >&2
  return 1
}
previous() {   # the newest release older than the live one
  local cur; cur="$(live)"
  find "$REL" -mindepth 1 -maxdepth 1 -type d | sort | awk -v cur="$cur" '$0 == cur {print prev; exit} {prev=$0}'
}
go_live() {    # $1 release dir, $2 the one to go back to on failure (may be empty)
  switch_to "$1"
  if restart && healthy; then return 0; fi
  if [[ -n "$2" ]]; then
    echo "switching back to $(basename "$2")" >&2
    switch_to "$2"
    restart || true
    healthy || echo "the release before is not healthy either: look at journalctl" >&2
  fi
  return 1
}

case "$MODE" in
  list)
    cur="$(live)"
    find "$REL" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
      [[ "$d" == "$cur" ]] && echo "* $(basename "$d")" || echo "  $(basename "$d")"
    done
    ;;
  rollback)
    prev="$(previous)"
    [[ -n "$prev" ]] || { echo "no release before $(basename "$(live)")" >&2; exit 1; }
    go_live "$prev" "$(live)"
    ;;
  deploy)
    [[ -d "$FROM" ]] || { echo "--from: no such directory" >&2; exit 2; }
    new="$REL/$(date -u +%Y%m%dT%H%M%SZ)"
    [[ -e "$new" ]] && { echo "$new exists: wait a second and run again" >&2; exit 1; }
    mkdir "$new.tmp"
    (cd "$FROM" && tar --exclude=.git -cf - .) | tar -xf - -C "$new.tmp"
    mv "$new.tmp" "$new"
    echo "release: $(basename "$new")"
    before="$(live)"
    if ! go_live "$new" "$before"; then exit 1; fi
    # keep the newest KEEP, the live one always among them
    find "$REL" -mindepth 1 -maxdepth 1 -type d ! -name '*.tmp' | sort | head -n "-$KEEP" | while read -r d; do
      [[ "$d" == "$(live)" ]] || rm -rf -- "$d"
    done
    ;;
esac
