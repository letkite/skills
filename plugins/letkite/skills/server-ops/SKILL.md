---
name: server-ops
description: Plan and run a deployment on a server connected to LetKite, with the person choosing at each step - whether the server is split into isolated guests (a KVM virtual machine or container per app, recommended even for one app), which accounts and groups the app gets (by its architecture), what the firewall lets in, which account LetKite runs as and whether it may become root, and how releases go live and roll back. Walks through a worked example (a backend service plus the web app its users open), then suggests extras such as signing in GitHub, Claude Code or Codex on the server so long tasks run there as jobs. Also explains how to connect a new server to LetKite. Use when asked to deploy an app or service to a server, prepare or harden a new server, isolate apps on one server, set up users, groups, sudo or a firewall for an app, or connect a server to LetKite.
license: MIT
compatibility: Requires a LetKite connection (MCP tools such as list_hosts, host_facts, exec, write_file, job_start, terminal_open, terminal_ask, schedule_create). Target servers run Linux with systemd (tested on Ubuntu 24.04); most steps need root, so the LetKite agent must allow elevate while you set the server up.
---

# Server operations on a LetKite node

You help one person put an app on one server and keep it running. They decide; you lay out the choices, recommend one, and do the work. Most people have never had to choose between account layouts or firewall postures, so explain each choice in a sentence and say which you would pick for their app and why.

## Ground rules

- **Look before changing.** `list_hosts`, `host_facts`, then [scripts/probe-server.sh](scripts/probe-server.sh). Only propose what is missing or wrong.
- **Ask before anything that is hard to undo**: deleting accounts or data, replacing a firewall that is already there, closing SSH, changing what the LetKite agent may do.
- **Secrets never go through chat**, nor into command lines, files you write, or your own output. Use a **LetKite environment variable** (the person adds it in the console, marked secret; you use only its name), or run the program in `terminal_open` and let the person type it through `terminal_ask`.
- **Root.** The agent runs commands as the account it was installed for. A step that needs root is sent with `elevate`, and only works while the agent's ceiling allows it (`elevate = true`). If it is refused, give the person the exact command to run as root on the server, or ask them to allow elevate for the setup.
- **You cannot lock LetKite out with the firewall.** The agent only connects out (HTTPS to the gateway). Closing SSH or every inbound port does not cut you off; blocking outbound HTTPS would.
- **Long work goes in `job_start`** (package installs, builds, deploys); read the result with `job_output`. `exec` is for seconds.

## Step 0: is the server connected?

Call `list_hosts`. If the server is not there, the person connects it first: [references/connect-node.md](references/connect-node.md). It is one command they run as root on the server and a code they approve in the browser. You cannot do this part for them.

## Step 1: probe

Copy [scripts/probe-server.sh](scripts/probe-server.sh) to the server with `write_file` (for example `/tmp/server-ops/probe-server.sh`, mode `0755`) and run it with `exec` and `elevate`. It is read-only and prints `key=value` lines. They cover the machine itself, the login accounts and who has sudo, and every listening port (`public_listening` is what the internet can reach unless a firewall stops it). They also show the firewall, the SSH settings, the running services, the installed runtimes, and the account the LetKite agent runs as.

Summarize it for the person in a short table. Point out anything risky right away, for example:
- a database listening on a public address;
- SSH open to the world with passwords allowed;
- no firewall at all.

## Step 2: understand the app

Ask only what the probe and the repository do not tell you:

1. **Parts.** Usually one or more backend services plus a front end. The front end is a web app (static files after a build) or a mobile or desktop app that only talks to the API. Add any workers or scheduled jobs.
2. **Runtime and build.** Node, Python, Go, Java or containers; whether it builds on the server or arrives built from CI.
3. **Who reaches it.**
   - A public domain over HTTPS, or only the person's own machines.
   - Any other port, such as WebSocket or game traffic.
4. **Data.**
   - Where it is: a database here or managed elsewhere, uploaded files.
   - What must be backed up.
5. **Who deploys.**
   - The person by hand, an AI through LetKite, or CI.
   - How often, and whether a quick rollback matters.

## Step 3: offer the options

Present each decision as a short list with your recommendation first. Ask **Z first**: it decides where everything else happens. Details and ready-made commands for A and B are in [references/accounts-firewall.md](references/accounts-firewall.md).

**Z. One server, isolated guests.** Before anything is installed, ask whether to turn the server into a host for isolated guests. The host runs only a hypervisor and a firewall. Each app, and each internet-facing part of it, gets its own KVM virtual machine; a system container is the fallback when the server has no KVM. Check that first with `ls /dev/kvm`.

**Recommend it even when there is only one app today**, and say why in a few sentences. It is the layout enterprise security reviews expect:
- a compromised app stays inside its guest, so its secrets, keys and data are out of reach of the others;
- internet-facing code gets a kernel of its own;
- the most privileged machine, the host, runs and exposes nothing;
- each workload has its own accounts, LetKite node and ceiling, so access and the audit trail are per workload;
- guests are network-segmented and resource-limited;
- snapshots give rollback in seconds, and a guest can be rebuilt or moved without touching the rest;
- a second app or a staging copy later is one more guest.

The cost is some memory and a short setup. Skip it only on a server too small to spare about 1 GiB per guest.

If the person agrees, follow [references/isolation.md](references/isolation.md) to:
1. set up the host;
2. create the first guest;
3. publish its ports;
4. connect the guest to LetKite.

Then run A to C and Step 5 **inside the guest**, not on the host.

**A. Accounts and groups, by architecture.** One account per job, so a hole in the app cannot rewrite the app or read the deploy keys:

| Architecture | Recommended layout |
|---|---|
| One service + a web front end (the common case) | `myapp` system account runs the service (no login, no sudo, writes only its data directory); `deploy` owns the code and releases, may only restart `myapp` through one sudoers line; the web server reads the front end through the `myapp` group |
| Several services or workers | one system account per service (`myapp-api`, `myapp-worker`), one shared group `myapp` for the read-only config, the same `deploy` |
| Containers (Docker or Podman) | `deploy` runs rootless Podman, or Docker with the warning that the `docker` group is as good as root |
| Database on the same server | its own packaged account (`postgres`, `mysql`), listening on 127.0.0.1 only; the app gets its own database user with only its own database |

Then ask which account **LetKite** should run as day to day. `deploy` is recommended: the AI can ship releases and read logs, but not change the system. Ask too whether `elevate` stays on after setup. Recommend turning it off, and on again only when the system itself needs work.

**B. Firewall.** Default deny inbound, allow outbound, then open only what Step 2 needs:

| Choice | When |
|---|---|
| 80 and 443 open, nothing else | a public web app or API (recommended) |
| nothing open | only reached through LetKite (tunnels, `tunnel_http`) or an outbound-only worker |
| one extra port | something that is not HTTP (game, VoIP, MQTT) |

SSH choices:
- **Closed**: LetKite is the way in, and the provider's web console is the emergency door. Recommended.
- **Open to one admin address only.**
- **Open to all, keys only**: fail2ban if so.

Databases, caches and admin panels bind to 127.0.0.1 and are never opened. If the provider has its own firewall (security group, panel firewall), mirror the same rules there.

**C. Releases.** How a new version goes live:

| Choice | Notes |
|---|---|
| **Release directories + `current` link** ([scripts/deploy-release.sh](scripts/deploy-release.sh)) | recommended. Each release in its own directory, an atomic switch, a health check, automatic rollback, `--rollback` in one command |
| `git pull` in place | simplest, no instant rollback, a half-pulled tree can serve requests |
| Containers (`compose pull && up -d`) | when the app already ships images |

## Step 4: suggest the extras

Once the choices are made, and before you start, offer the extras that make the next months easier. Each is optional:

- **GitHub on the deploy account** (`gh auth login`, a fine-grained token limited to this repository, or a read-only deploy key). The server can then fetch releases itself, so nothing is copied through chat or through you. If the person has the `dev-env` skill, it does this step by step.
- **Claude Code or Codex on the server**, signed in on the deploy account. You can then hand whole tasks to the server as a job: `job_start` with `claude -p "<task>"`, then read only the summary with `job_output`. Examples are building, running the test suite, reading a 50 MB log, or fixing a failing build. Only the result comes back instead of every file and every line of output, which saves the person's tokens, and the job keeps running if the conversation ends.
- **Secrets as LetKite environment variables** instead of files on the server. They can be rotated in one place.
- **Schedules** (`schedule_create`) for the database backup, certificate and disk checks, and a health probe.
- **Approvals** in the LetKite console for high-risk commands on this server, if other people's AI connections reach it.

## Step 5: do it

If Z was chosen, the host and the guest come first ([references/isolation.md](references/isolation.md)); everything below runs in the guest. Follow [references/deploy-app.md](references/deploy-app.md). It is the worked example for "one service + a web front end", in order:
1. accounts and directories;
2. secrets;
3. the systemd unit (sandboxed);
4. the sudoers line for `deploy`;
5. the reverse proxy with HTTPS;
6. the first release;
7. the firewall last, after you have checked the site works.

Adapt names and ports to the person's app. Show each command before running anything that changes the system, and run long steps as jobs.

## Step 6: verify and report

Check each of these, and look at the exit code, not just the output:

| What | Check |
|---|---|
| service | `systemctl is-active <unit>`; `journalctl -u <unit> -n 50` has no errors |
| health | `curl -fsS http://127.0.0.1:<port>/<health path>` on the server, then the public URL from outside (`https://<domain>/…`) |
| front end | the public URL serves the new build (a version string or a changed file) |
| isolation | `sudo -u deploy sudo -n systemctl stop <unit>` is refused; `sudo -u deploy cat /etc/<app>/env` is refused |
| firewall | `ufw status verbose`; `probe-server.sh` shows nothing in `public_listening` beyond what was agreed |
| rollback | `deploy-release.sh --app <app> --list` shows the live release; offer to try `--rollback` once while nobody is using it |
| LetKite | the agent runs as the account agreed, and elevate is as agreed (`probe-server.sh` `letkite_agent`) |
| guests (Z) | on the host, `incus list` shows each guest running; from one guest, another guest's address does not answer; the host has nothing in `public_listening` except what forwards to guests |

Finish with a short table showing each decision, what was done, and the check result. Then list what is left for the person:
- the DNS record;
- the provider's firewall;
- turning elevate off;
- signing in GitHub or Claude Code, if they chose to.
