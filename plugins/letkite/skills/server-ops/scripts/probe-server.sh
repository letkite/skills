#!/usr/bin/env bash
# What a server already has before you deploy to it: accounts, open ports, firewall, services. Read-only.
set -euo pipefail

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  cat <<'EOF'
Usage: probe-server.sh

Prints key=value lines about this server, so you can propose accounts, firewall rules and a deploy
layout that fit what is there. Read-only: it reads system files and runs status commands. Run it as
root (or with sudo) for the full picture; as another user some lines say "unknown".

  os, arch, cpus, mem_mb, disk_free_gb   the machine
  run_as, root=yes|no, sudo=yes|password|no   who runs this, and whether they can become root
  login_users        accounts with a login shell (name:uid:groups)
  sudo_users         members of sudo/wheel/admin, and files in /etc/sudoers.d
  listening          TCP/UDP sockets in LISTEN state (address:port/proto program), loopback marked
  public_listening   the ones NOT bound to loopback: what the internet can reach unless a firewall stops it
  firewall           ufw | firewalld | nftables | iptables | none, then its rules
  ssh                sshd's port, PermitRootLogin, PasswordAuthentication, AllowUsers
  services           running systemd services that are not part of the base system
  runtimes           node, python3, java, go, docker, podman, caddy, nginx, postgres, mysql, redis versions
  letkite_agent      the LetKite agent's instances, the account commands run as, and elevate in its ceiling
EOF
  exit 0
fi

kv() { printf '%s=%s\n' "$1" "$2"; }
have() { command -v "$1" > /dev/null 2>&1; }
ROOT=no; [[ $EUID -eq 0 ]] && ROOT=yes

kv os "$( . /etc/os-release 2> /dev/null && echo "$PRETTY_NAME" || uname -s)"
kv arch "$(uname -m)"
kv cpus "$(nproc 2> /dev/null || echo unknown)"
kv mem_mb "$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2> /dev/null || echo unknown)"
kv disk_free_gb "$(df -BG --output=avail / 2> /dev/null | tail -1 | tr -dc 0-9 || echo unknown)"
kv run_as "$(id -un)"
kv root "$ROOT"
if [[ $ROOT == yes ]]; then kv sudo yes
elif sudo -n true 2> /dev/null; then kv sudo yes
elif have sudo && id -nG | grep -qwE 'sudo|wheel|admin'; then kv sudo password
else kv sudo no; fi

kv login_users "$(awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ {print $1}' /etc/passwd \
  | while read -r u; do printf '%s:%s:%s ' "$u" "$(id -u "$u")" "$(id -nG "$u" | tr ' ' ',')"; done)"
kv sudo_users "$(getent group sudo wheel admin 2> /dev/null | cut -d: -f4 | tr '\n' ',' | sed 's/,,*/,/g; s/^,//; s/,$//') \
sudoers.d=$( (ls /etc/sudoers.d 2> /dev/null || echo unknown) | grep -v README | tr '\n' ',' | sed 's/,$//')"

if have ss; then
  sockets="$(ss -H -lntup 2> /dev/null | awk '{
    proc=$7; sub(/.*\(\("/, "", proc); sub(/".*/, "", proc); if (proc == $7) proc="?";
    print $5 "/" $1 " " proc }' | sort -u)"
  kv listening "$(tr '\n' ';' <<< "$sockets" | sed 's/;$//')"
  kv public_listening "$(grep -vE '^(127\.|\[::1\]|::1|localhost)' <<< "$sockets" | tr '\n' ';' | sed 's/;$//')"
else
  kv listening unknown
fi

if have ufw && [[ $ROOT == yes ]]; then
  kv firewall "ufw $(ufw status | head -1 | awk '{print $2}')"
  ufw status numbered 2> /dev/null | grep -E '^\[' | sed 's/^/  /'
elif have firewall-cmd && firewall-cmd --state > /dev/null 2>&1; then
  kv firewall "firewalld $(firewall-cmd --list-all 2> /dev/null | tr -s ' \n' ' ')"
elif have nft && [[ $ROOT == yes ]] && [[ -n "$(nft list ruleset 2> /dev/null)" ]]; then
  kv firewall "nftables ($(nft list ruleset | grep -c ' accept\| drop\| reject') rules)"
elif [[ $ROOT == no ]]; then
  kv firewall unknown
else
  kv firewall none
fi

if have sshd && [[ $ROOT == yes ]]; then
  install -d -m 755 /run/sshd 2> /dev/null || true
  kv ssh "$(sshd -T 2> /dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|allowusers) ' \
    | tr '\n' ' ')"
else
  kv ssh "$(have sshd && echo unknown || echo none)"
fi

if have systemctl; then
  kv services "$(systemctl list-units --type=service --state=running --no-legend --plain 2> /dev/null \
    | awk '{print $1}' | grep -vE '^(systemd-|dbus|cron|getty|serial-getty|user@|polkit|rsyslog|ssh|snapd|unattended|multipathd|networkd|chrony|ModemManager|udisks|packagekit|fwupd|irqbalance|qemu-guest|cloud-|apport|atd|lxd-agent|incus-agent)' \
    | tr '\n' ',' | sed 's/,$//')"
fi

rt=""
for t in node python3 java go docker podman caddy nginx psql mysql redis-server; do
  have "$t" || continue
  case "$t" in
    java) v="$(java -version 2>&1 | head -1)" ;;
    go) v="$(go version 2> /dev/null)" ;;
    caddy) v="$(caddy version 2> /dev/null | head -1)" ;;
    *) v="$("$t" --version 2> /dev/null | head -1 || echo present)" ;;
  esac
  rt+="$t=${v//[$'\t\r\n']/ }; "
done
kv runtimes "${rt%; }"

agents=""
for d in /etc/letkite /etc/letkite-*; do
  [[ -f "$d/agent.toml" ]] || continue
  ra="$(sed -n 's/^run_as *= *"\(.*\)"/\1/p' "$d/agent.toml" 2> /dev/null)"
  el="$(sed -n 's/^elevate *= *\([a-z]*\).*/\1/p' "$d/ceiling.toml" 2> /dev/null)"
  agents+="${d#/etc/}(run_as=${ra:-root},elevate=${el:-true}) "
done
if [[ -z "$agents" && $ROOT == no ]] && have letkite-agent; then agents="present (run as root to see details)"; fi
kv letkite_agent "${agents:-none}"
