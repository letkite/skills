# Accounts, groups and the firewall

Commands are for Ubuntu and Debian (`useradd`, `ufw`); run them as root (with `elevate`). Replace `myapp` with the app's name: lowercase letters, digits and `-`.

## Why separate accounts

| Account | Can | Cannot |
|---|---|---|
| `myapp` (system account, one per service) | run the service, write `/var/lib/myapp` | log in, sudo, change its own code, read the deploy account's keys |
| `deploy` (login account, the one LetKite runs as day to day) | own the releases, fetch code, restart the app's units | read the app's secrets, change the system, become root |
| the person's admin account, or root through `elevate` | everything | (used only for setup and system changes) |

A bug in the app then only reaches the app's own data. A stolen deploy key can ship code but cannot read the database password or take over the server.

## Layouts by architecture

### One service + a web front end (the common case)

```
useradd --system --user-group --home-dir /var/lib/myapp --create-home --shell /usr/sbin/nologin myapp
useradd --create-home --shell /bin/bash deploy
install -d -m 750 -o deploy -g myapp /srv/myapp /srv/myapp/releases     # code: deploy writes, myapp reads
install -d -m 700 -o root   -g root  /etc/myapp                         # secrets: only root (systemd reads them)
install -d -m 750 -o myapp  -g myapp /var/lib/myapp                     # the service's data
usermod -aG myapp caddy        # or www-data for nginx: the web server reads the built front end
```

`deploy` is deliberately **not** in the `myapp` group. It does not need the app's data, and it should not be able to read the app's secrets.

### Several services or workers

One system account per process, so the worker cannot rewrite the API's data and the other way round. One shared group gives read access to the code:

```
groupadd --system myapp
useradd --system --gid myapp --home-dir /var/lib/myapp-api    --create-home --shell /usr/sbin/nologin myapp-api
useradd --system --gid myapp --home-dir /var/lib/myapp-worker --create-home --shell /usr/sbin/nologin myapp-worker
```

Each unit gets its own `User=` and its own `/etc/myapp/<service>.env`. `deploy` gets one sudoers line listing all the units.

### Containers

- **Rootless Podman** (recommended): `deploy` runs the containers itself (`loginctl enable-linger deploy`), and no part of it is root.
- **Docker**: anyone in the `docker` group can start a container that mounts `/` and is then root on the server. If `deploy` must be in that group, treat `deploy` as an admin account. In that case keep LetKite's `elevate` off and the deploy key read-only.
- Publish container ports on 127.0.0.1 (`-p 127.0.0.1:8080:8080`) and let the reverse proxy face the internet. Docker's own iptables rules **bypass ufw** for published ports.

### Database on the same server

- The packaged account (`postgres`, `mysql`) runs it, listening on 127.0.0.1 only. Ubuntu's PostgreSQL does this by default; check `listen_addresses`.
- The app gets its own database user that owns only its own database.
- The password goes into the app's env file or a LetKite environment variable.

## Sudo for the deploy account

One line, exact commands only, checked before it is installed:

```
cat > /etc/sudoers.d/myapp-deploy <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service, /usr/bin/systemctl status myapp.service
EOF
chmod 440 /etc/sudoers.d/myapp-deploy
visudo -cf /etc/sudoers.d/myapp-deploy
```

Never `deploy ALL=(ALL) NOPASSWD: ALL`, `systemctl *`, or an editor or shell in the list. Each of these is root in one step.

## Firewall (ufw)

Look first: `ufw status verbose`, `iptables -S`, `nft list ruleset`. If another firewall is already managing the server (firewalld, a hand-written nftables file, or the provider's agent), ask before replacing it.

A public web app (80 and 443, nothing else):

```
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose
```

SSH, the person's choice:

| Choice | Commands | Note |
|---|---|---|
| closed (recommended) | nothing: with no rule SSH stays shut. If a rule exists: `ufw delete allow OpenSSH` | LetKite is the way in, the provider's web console the emergency door |
| one admin address | `ufw allow from <their IP> to any port 22 proto tcp` | their IP must be fixed |
| open, keys only | `ufw allow OpenSSH`; in `/etc/ssh/sshd_config.d/10-hardening.conf`: `PasswordAuthentication no`, `PermitRootLogin no`; `apt install fail2ban` | test a key login before reloading sshd |

Other ports: `ufw allow <port>/<tcp|udp>`; from one network only: `ufw allow from <cidr> to any port <port> proto tcp`.

Never open a database, cache, queue or admin panel port (5432, 3306, 6379, 27017, 9200 and the like). Bind it to 127.0.0.1. To look at it, use LetKite's tunnel (`tunnel_open` or `tunnel_http`), which needs no firewall rule. The target must be listed in the ceiling's `tunnel_targets`.

**The provider's firewall** (cloud security group, panel firewall) sits in front of ufw. Mirror the same rules there. A port open in ufw but closed there is still closed, and the reverse also holds.

**Outbound**: leave it open unless the person asks. Restricting it is possible (`ufw default deny outgoing` plus rules), but it must keep:
- DNS (53);
- NTP (123/udp);
- the package mirrors;
- HTTPS (443) to `nodes.letkite.com`, or LetKite loses the server.
