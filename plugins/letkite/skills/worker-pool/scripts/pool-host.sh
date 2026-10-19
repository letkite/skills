#!/usr/bin/env bash
# pool-host.sh: make worker machines on a host with Incus (layouts A and B). Run as root.
#
#   pool-host.sh init                         install Incus if missing and initialise it with defaults
#   pool-host.sh create <name> [options]      create a worker machine and make it ready for setup-worker.sh
#       --vm                 a virtual machine (layout A, needs /dev/kvm); default is a system container (layout B)
#       --cpus N             default 2
#       --memory SIZE        default 4GiB
#       --disk SIZE          default 30GiB
#       --image IMAGE        default images:ubuntu/24.04
#       --push DIR           copy DIR (e.g. the skill's scripts/ and assets/) to /root/worker-pool in the machine
#   pool-host.sh list                         worker machines (the ones this script created)
#   pool-host.sh shell <name>                 a root shell inside (use it in a terminal to enroll in LetKite)
#   pool-host.sh delete <name>                stop and delete a worker machine (asks for the name again)
#
# Worker machines get the Incus label user.worker-pool=1. Each one becomes its own LetKite node once enrolled.
set -euo pipefail
die() { echo "pool-host: $*" >&2; exit 1; }
log() { printf '==> %s\n' "$*"; }
[[ $EUID -eq 0 ]] || die "run as root"

need_incus() { command -v incus > /dev/null || die "Incus is not installed: pool-host.sh init"; }

init() {
  if ! command -v incus > /dev/null; then
    log "installing Incus"
    if command -v apt-get > /dev/null; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq > /dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq incus > /dev/null \
        || die "no incus package here; see https://linuxcontainers.org/incus/docs/main/installing/"
    elif command -v dnf > /dev/null; then dnf install -y -q incus > /dev/null || die "dnf could not install incus"
    else die "install Incus by hand: https://linuxcontainers.org/incus/docs/main/installing/"; fi
  fi
  if ! incus profile device show default 2> /dev/null | grep -q 'type: disk'; then
    log "incus admin init --minimal"
    incus admin init --minimal
  fi
  incus info > /dev/null && log "Incus ready: $(incus version 2> /dev/null | tr '\n' ' ')"
}

create() {
  local name="${1:?usage: pool-host.sh create <name> [options]}"; shift
  local vm=0 cpus=2 mem=4GiB disk=30GiB image=images:ubuntu/24.04 push=""
  while [[ $# -gt 0 ]]; do case "$1" in
    --vm) vm=1; shift ;;
    --cpus) cpus="${2:?}"; shift 2 ;;
    --memory) mem="${2:?}"; shift 2 ;;
    --disk) disk="${2:?}"; shift 2 ;;
    --image) image="${2:?}"; shift 2 ;;
    --push) push="${2:?}"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac; done
  need_incus
  [[ $name =~ ^[a-z][a-z0-9-]{0,62}$ ]] || die "bad name '$name'"
  if [[ $vm -eq 1 ]]; then [[ -c /dev/kvm ]] || die "--vm needs /dev/kvm on this host; drop --vm for a container"; fi
  if incus info "$name" > /dev/null 2>&1; then
    log "$name exists already"
  else
    log "creating $name ($([[ $vm -eq 1 ]] && echo VM || echo container), $cpus CPU, $mem, $disk)"
    local args=(launch "$image" "$name" -c "limits.cpu=$cpus" -c "limits.memory=$mem" -c user.worker-pool=1 -d "root,size=$disk")
    [[ $vm -eq 1 ]] && args+=(--vm)
    incus "${args[@]}"
  fi
  log "waiting for the network"
  local i
  for i in $(seq 1 90); do
    incus exec "$name" -- sh -c 'getent hosts get.letkite.com > /dev/null 2>&1' 2> /dev/null && break
    sleep 2
  done
  [[ $i -lt 90 ]] || die "$name has no DNS/network after 3 minutes"
  log "base packages inside"
  incus exec "$name" -- sh -c 'if command -v apt-get >/dev/null; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null &&
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates sudo >/dev/null
    elif command -v dnf >/dev/null; then dnf install -y -q curl ca-certificates sudo >/dev/null; fi'
  if [[ -n $push ]]; then
    [[ -d $push ]] || die "--push $push is not a directory"
    incus exec "$name" -- mkdir -p /root/worker-pool
    incus file push -r -p "$push"/. "$name/root/worker-pool/"
    log "copied $push to $name:/root/worker-pool"
  fi
  log "$name ready. Next: enroll it in LetKite from a terminal: pool-host.sh shell $name, then the console's install line"
}

list() { need_incus; incus list user.worker-pool=1 -c ns4tSl; }

shell() { need_incus; exec incus exec "${1:?usage: pool-host.sh shell <name>}" -- bash -l; }

delete() {
  local name="${1:?usage: pool-host.sh delete <name>}" again
  need_incus
  [[ "$(incus config get "$name" user.worker-pool 2> /dev/null)" == 1 ]] || die "$name was not created by pool-host.sh"
  read -r -p "type the name again to delete $name and everything in it: " again
  [[ $again == "$name" ]] || die "not deleted"
  incus delete --force "$name"
  log "$name deleted. Also remove its node in the LetKite console (Nodes) and sign it out of Claude and GitHub."
}

case "${1:-}" in
  init) init ;;
  create) shift; create "$@" ;;
  list) list ;;
  shell) shift; shell "$@" ;;
  delete) shift; delete "$@" ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
