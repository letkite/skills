#!/usr/bin/env bash
# probe-host.sh: read-only survey of a machine that might host Claude Code workers.
# Prints key=value lines, then recommend=<A|B|C|none> and slots=<n>. Changes nothing and installs nothing.
# Run as root for an accurate /dev/kvm check:  sudo bash probe-host.sh
set -u
export LC_ALL=C

kv() { printf '%s=%s\n' "$1" "$2"; }
has() { command -v "$1" > /dev/null 2>&1; }

os="$(. /etc/os-release 2> /dev/null && echo "${ID:-unknown} ${VERSION_ID:-}" || uname -s)"
kv os "$os"
kv arch "$(uname -m)"
kv kernel "$(uname -r)"

virt="$(systemd-detect-virt 2> /dev/null || true)"; virt="${virt:-none}"
container="$(systemd-detect-virt --container 2> /dev/null || true)"; container="${container:-none}"
if [ "$container" = none ]; then
  # without systemd-detect-virt: the usual container markers
  if [ -f /.dockerenv ]; then container=docker
  elif grep -qa 'container=' /proc/1/environ 2> /dev/null; then container=other
  elif [ -d /proc/vz ] && [ ! -d /proc/bc ]; then container=openvz
  fi
fi
kv virt "$virt"
kv container "$container"
kv init "$(ps -p 1 -o comm= 2> /dev/null || echo unknown)"

# unprivileged container: uid 0 inside maps to a high uid outside
uidmap="$(awk 'NR==1{print $2}' /proc/self/uid_map 2> /dev/null)"
kv unprivileged "$([ -n "$uidmap" ] && [ "$uidmap" != 0 ] && echo yes || echo no)"

kvm=no
if [ -c /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then kvm=yes; else kvm=present-no-access; fi
fi
kv kvm "$kvm"
flags="$(grep -cwE 'vmx|svm' /proc/cpuinfo 2> /dev/null || true)"
kv cpu_virt_flags "${flags:-0}"

cpus="$(nproc 2> /dev/null || echo 1)"
mem_mb="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo 2> /dev/null || echo 0)"
disk_gb="$(df -BG --output=avail / 2> /dev/null | tail -1 | tr -dc 0-9)"
kv cpus "$cpus"
kv mem_mb "$mem_mb"
kv disk_free_gb "${disk_gb:-0}"

# Tools. Ubuntu's /usr/sbin/lxc can be a stub that installs the LXD snap on first use; never run it here.
tools=""
for t in incus docker podman virsh node npm git gh claude; do has "$t" && tools="$tools $t"; done
if [ -x /snap/bin/lxc ]; then tools="$tools lxd"
elif has lxc && grep -q lxd-installer "$(command -v lxc)" 2> /dev/null; then tools="$tools lxc(stub:do-not-run)"
fi
kv tools "${tools# }"
kv node_version "$(has node && node --version 2> /dev/null || echo none)"
kv claude_version "$(has claude && claude --version 2> /dev/null | awk '{print $1}' || echo none)"

agents="$(systemctl list-units --all --no-legend 'letkite-agent*' 2> /dev/null | awk '{print $1}' | tr '\n' ' ')"
[ -z "$agents" ] && [ -d "$HOME/.letkite-agent" ] && agents="per-user:$HOME/.letkite-agent"
agents="${agents% }"
kv letkite_agents "${agents:-none}"

# Recommendation. Per worker: 2 vCPU + 3 GB for a VM or container, 1 vCPU + 2 GB for an account; keep 1 GB for the host.
avail=$(( mem_mb - 1024 ))
machine_slots=$(( cpus / 2 )); m=$(( avail / 3072 )); [ "$m" -lt "$machine_slots" ] && machine_slots=$m
acct_slots=$cpus; m=$(( avail / 2048 )); [ "$m" -lt "$acct_slots" ] && acct_slots=$m
[ "$machine_slots" -lt 0 ] && machine_slots=0
[ "$acct_slots" -lt 0 ] && acct_slots=0

recommend=C; slots=$acct_slots; why="account per worker on this node"
if [ "$kvm" = yes ] && [ "$container" = none ] && [ "$machine_slots" -ge 1 ]; then
  recommend=A; slots=$machine_slots; why="KVM available: one VM per worker"
elif [ "$container" = none ] && [ "$machine_slots" -ge 1 ] && [ "$(ps -p 1 -o comm= 2> /dev/null)" = systemd ]; then
  recommend=B; slots=$machine_slots; why="no KVM: one system container per worker"
elif [ "$container" != none ]; then
  why="already inside a container ($container): nesting is up to its host, so use accounts"
fi
if [ "$acct_slots" -lt 1 ]; then
  if [ "$mem_mb" -ge 1500 ]; then recommend=C; slots=1; why="small machine: one account worker, light tasks only"
  else recommend=none; slots=0; why="under 1.5 GB RAM: too small for a Claude Code worker"
  fi
fi
kv recommend "$recommend"
kv slots "$slots"
kv why "$why"
