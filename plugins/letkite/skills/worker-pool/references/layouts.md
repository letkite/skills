# Layouts in detail

LetKite runs **one agent per gateway per machine**; a second agent for the same gateway on the same machine stays "connecting". A VM or a container is a machine of its own. That gives four layouts.

| | A: VM per worker | B: container per worker | C: account per worker | D: desktop |
|---|---|---|---|---|
| Needs | `/dev/kvm`, bare metal or a VM with nested virtualisation | a VM or bare metal with systemd (no KVM needed) | any Linux (or macOS) | a Mac or Windows PC |
| LetKite nodes | one per worker | one per worker | one for all | one |
| Isolation | strong (own kernel) | good (own userspace, shared kernel) | weak (Unix accounts on one OS) | the machine |
| Overhead | ~0.5 GB RAM per VM plus image | small | none | none |
| Counts against plan devices | N | N | 1 | 1 |
| Address a worker | its node, as the worker account | its node, as the worker account | the host node, `ccw <worker> ...` | the node |

## Reading probe-host.sh

- `kvm=yes` and `container=none` → A is possible. `kvm=present-no-access` means you are not root; rerun with sudo.
- `container=lxc|docker|openvz|...` → the host is itself a container. Nested containers depend on its own host (Incus `security.nesting`) and nested VMs almost never work: use C.
- `unprivileged=yes` → an unprivileged container: C.
- `tools` lists what is there. `lxc(stub:do-not-run)` is Ubuntu's LXD installer stub: running `lxc` would install the LXD snap. Use Incus (`pool-host.sh init`) or ask the person.
- `slots` is a starting point: 2 vCPU + 3 GB per VM/container worker, 1 vCPU + 2 GB per account worker, 1 GB kept for the host. Builds of large codebases (Rust, C++) want more.
- `letkite_agents` shows agents already installed (`letkite-agent.service`, or `letkite-agent-<instance>.service` for a second gateway).

## A and B with Incus

```
pool-host.sh init                                   # once per host
pool-host.sh create ccw-01 --cpus 2 --memory 4GiB --disk 30GiB --push /root/worker-pool   # container (B)
pool-host.sh create ccw-02 --vm ...                 # VM (A)
pool-host.sh shell ccw-01                           # in terminal_open: enroll, then run setup-worker.sh inside
```

- Copy the skill's `scripts/` and `assets/` to the host first (e.g. `/root/worker-pool/scripts`, `/root/worker-pool/assets`) so `--push` can hand them to each machine.
- Containers get their own LetKite node, so inside each one run the console's install line with `--name <worker> --tag cc-worker --no-browser`, approve, Confirm, then `setup-worker.sh <worker>`.
- One worker account per machine is the norm here; you can put two accounts in one VM if devices are tight, but then they share that machine's resources.
- Incus images: `images:ubuntu/24.04` (default), `images:debian/12`. Network is NAT behind the host; workers need outbound HTTPS only (LetKite, Anthropic, npm, GitHub).
- Docker can also work (the LetKite agent installs per-user when there is no systemd), but system containers or VMs behave like ordinary machines and are less surprising.

## C: accounts on one node

```
setup-worker.sh --mcp-url <url> ccw-01 ccw-02 ccw-03
ccw status
```

- The host is already a LetKite node. Workers are addressed through it: `exec` with `ccw <worker> '<command>'`, `terminal_open` with `ccw <worker> 'claude'`.
- Each worker's Claude Code still has its *own* LetKite connection (step 6), so it can be limited separately on the consent page.
- Weak isolation: workers can see each other's processes and anything world-readable. Keep secrets in each worker's home (mode 750, set by setup-worker.sh) and don't give workers sudo.

## D: desktops

- Install the agent from the console (Windows tab, or the Linux line on macOS), approve, Confirm.
- On macOS the account layout works by hand (`sysadminctl -addUser`, Claude Code via npm or the native installer); `setup-worker.sh` and `ccw` are Linux-only.
- On Windows, run Claude Code in WSL (then treat WSL as a Linux machine) or natively; LetKite's `exec` runs PowerShell by default there.

## Many short-lived workers

On Business plans the console's Nodes page has **Clusters**: a join token that many machines can use; its nodes are removed after being offline for a while. Good for workers you create and throw away often. Keep the token out of chat (`terminal_ask`).
