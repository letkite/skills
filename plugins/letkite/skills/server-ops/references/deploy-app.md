# Worked example: a backend service and its web app

The app `myapp`:
- an HTTP API (`server.py`, or a Node, Go or Java binary) listening on 127.0.0.1:8080;
- a web front end built to static files in `web/`;
- a domain `app.example.com`.

Users open the web app, and the web app calls `/api/…`. A mobile app that calls the API is the same deployment without the `web/` part.

Tested end to end on Ubuntu 24.04 with Caddy 2.6 and ufw 0.36. Every block below runs as root (`exec` with `elevate`) unless it says otherwise. Show the person each block before running it.

## 1. Accounts and directories

As in [accounts-firewall.md](accounts-firewall.md), "One service + a web front end":

```
useradd --system --user-group --home-dir /var/lib/myapp --create-home --shell /usr/sbin/nologin myapp
id deploy > /dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
install -d -m 750 -o deploy -g myapp /srv/myapp /srv/myapp/releases
install -d -m 700 -o root   -g root  /etc/myapp
install -d -m 750 -o myapp  -g myapp /var/lib/myapp
```

## 2. Secrets

Two ways. Ask which one the person wants:

- **A file only root reads** (systemd reads it as root and hands the values to the service). The person types each value through `terminal_ask`. For example, open a terminal with `terminal_open` and run `read -rs V && printf 'APP_SECRET=%s\n' "$V" >> /etc/myapp/env`, then `terminal_ask` for the value. Never put a value in a command you send.

  ```
  install -m 600 -o root -g root /dev/null /etc/myapp/env
  echo 'PORT=8080' >> /etc/myapp/env          # not secret: fine to write directly
  ```

- **LetKite environment variables**: the person adds them in the console for this node, marked secret. They reach the processes LetKite starts, not services that systemd starts. Use them for deploy-time secrets such as a GitHub token, and use the file for the service itself.

## 3. The service

```
cat > /etc/systemd/system/myapp.service <<'EOF'
[Unit]
Description=myapp API
After=network-online.target
Wants=network-online.target

[Service]
User=myapp
Group=myapp
EnvironmentFile=/etc/myapp/env
WorkingDirectory=/srv/myapp/current
ExecStart=/usr/bin/python3 /srv/myapp/current/server.py
Restart=on-failure
RestartSec=2
# sandbox: the service sees the system read-only, no home directories, its own /tmp
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/myapp
StateDirectory=myapp

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable myapp.service
```

- Change `ExecStart` for the app's runtime, for example `/usr/bin/node /srv/myapp/current/dist/server.js` or `/srv/myapp/current/bin/myapp`.
- Do not start the service yet: `current` does not exist until the first release.
- The app should listen on 127.0.0.1, not 0.0.0.0. The reverse proxy is the only thing facing the internet.

## 4. Let `deploy` restart it, and nothing else

```
cat > /etc/sudoers.d/myapp-deploy <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart myapp.service, /usr/bin/systemctl reset-failed myapp.service, /usr/bin/systemctl status myapp.service
EOF
chmod 440 /etc/sudoers.d/myapp-deploy
visudo -cf /etc/sudoers.d/myapp-deploy
```

## 5. Reverse proxy and HTTPS (Caddy)

Caddy gets and renews the certificate on its own, once DNS points at the server and ports 80 and 443 are reachable:

```
apt-get install -y caddy
cat > /etc/caddy/Caddyfile <<'EOF'
app.example.com {
	handle /api/* {
		reverse_proxy 127.0.0.1:8080
	}
	handle {
		root * /srv/myapp/current/web
		try_files {path} /index.html
		file_server
	}
}
EOF
usermod -aG myapp caddy                 # reads the built front end through the myapp group
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl restart caddy
```

- `try_files … /index.html` serves single-page apps whose routes live in the browser.
- **Before DNS is ready**, use `:80 {` instead of the domain to test over plain HTTP. Switch back once the A record points here.
- **nginx instead**: the same three parts, `location /api/ { proxy_pass http://127.0.0.1:8080; }`, `root /srv/myapp/current/web;`, and `try_files $uri /index.html;`. Certificates come from `certbot --nginx -d app.example.com`, and `www-data` goes into the `myapp` group.

## 6. Releases

Copy [scripts/deploy-release.sh](../scripts/deploy-release.sh) to `/usr/local/bin/deploy-release` (mode 0755). From here on everything runs as **deploy**, which is LetKite's day-to-day account.

1. **Get a build** into a directory. Pick one:
   - `git clone` or `git pull` into `~/src/myapp` and build there (`npm ci && npm run build`, `go build`, …);
   - unpack an artifact from CI;
   - for long builds, `job_start` with the build command, or with `claude -p "build and test ~/src/myapp; fix only build errors; report"` if Claude Code is signed in here.
2. **Put it live:**

   ```
   deploy-release --app myapp --from ~/src/myapp/build --service myapp.service --health http://127.0.0.1:8080/api/health
   ```

   It copies the build into `/srv/myapp/releases/<time>`, switches `current` in one rename, restarts the unit and waits up to 60 s for the health URL. If the health check fails, it switches back to the previous release, restarts again and exits 1. Read `journalctl -u myapp -n 50` to see why.
3. **Other commands:**
   - `deploy-release --app myapp --list` shows the releases and marks the live one;
   - `deploy-release --app myapp --rollback --service myapp.service --health …` goes back one release.
   - Five releases are kept (`--keep`).

Tested: a release whose server exits at once was rolled back automatically, and the site kept serving the previous version.

## 7. Firewall, last

Only after the site works over 127.0.0.1 and through the proxy: the rules from [accounts-firewall.md](accounts-firewall.md), with the person's SSH choice. Then mirror them in the provider's firewall.

## 8. Keep it running

- **Logs**: `journalctl -u myapp -f` through `log_open`; Caddy's in `journalctl -u caddy`.
- **Backups**: `schedule_create`, for example nightly `pg_dump` of the app's database into `/var/lib/myapp/backups`, then a copy off the server (object storage, another node).
- **Health**: `schedule_create` every 5 minutes, running `curl -fsS https://app.example.com/api/health` from another node.
- **Updates**: `unattended-upgrades` for security patches (Ubuntu has it on by default), and a reboot window the person picks.
- **Disk**: a weekly `df -h /` and `journalctl --disk-usage` check.
