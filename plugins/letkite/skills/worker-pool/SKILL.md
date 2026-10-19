---
name: worker-pool
description: Build and run a pool of headless Claude Code workers on your own machines through LetKite. Covers surveying hosts and choosing a layout (one VM per worker, one container per worker, or one Unix account per worker on a shared node), enrolling workers in LetKite, installing and signing in Claude Code, connecting each worker's Claude Code back to LetKite's MCP server, optional GitHub sign-in, verifying the pool, and dispatching tasks. Use when asked to set up Claude Code workers, add or repair a worker, build an agent pool on a VPS, or offload work to headless Claude Code through LetKite.
license: MIT
compatibility: Requires a LetKite connection (MCP tools such as list_hosts, exec, write_file, job_start, terminal_open, terminal_ask). Worker hosts run Linux (Ubuntu/Debian or Fedora-family); macOS works for the account layout.
---

# Claude Code worker pool on LetKite

You are the **orchestrator**: an AI connected to LetKite. You build workers on the person's machines and then hand them tasks. A **worker** is one Unix account that runs the Claude Code CLI. The machine it runs on is the **host**.

## Done means

Every worker passes all of these checks. `ccw status` (installed in step 4) shows them in one table.

1. **Reachable through LetKite.** The worker's machine is an online, confirmed node in `list_hosts`. In layout C, its host is.
2. **Claude Code installed** at a pinned version, with auto-update off.
3. **Claude Code signed in**: `claude auth status` shows `loggedIn: true`, using a Claude subscription or an API key.
4. **Connected back to LetKite**: the worker's own Claude Code shows the LetKite MCP server as Connected in `claude mcp list`.
5. **GitHub signed in**, only if the person wants it: `gh auth status` succeeds.

## Ground rules

- **Secrets never go through chat.** That covers API keys, auth codes, OAuth redirect URLs and GitHub tokens.
  - Open a terminal on the machine with `terminal_open`, start the program, then call `terminal_ask`.
  - The person types the answer into the LetKite console. You only see the program's output.
- **Long sign-in URLs get cut or filtered in chat.** Put them in a small HTML page or file with a link, and send that.
- **Start waiting before you send a sign-in link.** Call `terminal_ask` right away. A CLI waiting for a code times out within minutes, and anything pasted after that lands in the shell.
- **Look before you change anything.** Run `host_facts` first, and don't assume root or a distro.
- **High-risk commands get stated first.** LetKite refuses them until you pass `confirm=true`. Tell the person the exact command before doing that.
- **Probe without side effects.** On Ubuntu, `lxc` may be a stub that installs the LXD snap the first time it runs. `scripts/probe-host.sh` checks for this. Don't call `lxc`, `docker` or similar tools by hand on a machine you are only surveying.

## Step 1: survey hosts and pick a layout

Copy `scripts/probe-host.sh` to each candidate host with `write_file`, then run it with `exec`. It is read-only and prints `key=value` lines plus `recommend=` and `slots=`.

LetKite allows **one agent per gateway per machine**, and a VM or container counts as its own machine. So each worker is either a separate machine (its own LetKite node) or an account on a shared node.

| What the host has | Layout | Workers are |
|---|---|---|
| Usable `/dev/kvm`, not inside a container, enough RAM | **A: VM per worker** | Incus VMs, each its own node. Strongest isolation |
| No KVM, but a real init and the host is a VM or bare metal | **B: container per worker** | Incus system containers, each its own node |
| Already an unprivileged container, OpenVZ, a tiny box, or you need to save devices | **C: account per worker** | Unix accounts on one node |
| A desktop Mac or Windows PC | **D: one machine** | That machine is one node. C also works on a Mac |

Two more things decide the layout:

- **Sizing.** Plan about 2 vCPU and 3–4 GB RAM per worker that builds code. Claude Code alone needs about 0.5–1 GB. `probe-host.sh` does this arithmetic.
- **Device limits.** Every LetKite node counts toward the plan's device limit. Layout C uses one device for N workers.
  - For many short-lived workers, Business plans can use a cluster join token. Its nodes are removed after they go offline.

Tell the person which layout you recommend for each host and why, then wait for a yes. Details for each layout are in [references/layouts.md](references/layouts.md).

## Step 2: create the worker machines (layouts A and B)

On the host, run `scripts/pool-host.sh`:

- `pool-host.sh init` installs and initializes Incus if missing.
- `pool-host.sh create ccw-01 [--vm] --cpus 2 --memory 4GiB --disk 30GiB` creates a worker machine.

Use `job_start` for anything slow. Layout C skips this step, and layout D is a machine that already exists.

## Step 3: enroll each worker machine in LetKite

Prefer the pairing-code flow, because it needs no secret:

1. The person opens the console: **Nodes → Add node → Linux** and copies the install line.
2. Append `--name ccw-01 --tag cc-worker --no-browser` to it.
3. Run it on the worker machine in a terminal. For A and B, open one on the host with `terminal_open` and run `incus exec ccw-01 -- bash`.
4. It prints a pairing code. Show the code to the person.
5. They sign in at the address it prints, click **Add this computer**, then **Confirm** the node on the Nodes page. An unconfirmed node is left out of "all nodes" and tag selections.
6. Check that the node appears in `list_hosts`.

For many machines, use the unattended install instead. The person creates a one-time install command in the same dialog. Deliver it with `terminal_ask` so they paste it straight into the worker's shell, never into chat.

In layout C, only the host needs to be a node, and it usually already is.

## Step 4: prepare worker accounts

Copy `scripts/setup-worker.sh` and `assets/worker-CLAUDE.md` to the worker machine, or to the host in layout C, and run it as root:

```
setup-worker.sh --mcp-url <LetKite MCP URL> ccw-01 [ccw-02 ...]
```

It is idempotent. It does the following:

- Installs Node and Claude Code at a pinned version (npm `stable` unless `--claude-version` is given), with auto-update off.
- Creates each worker account without sudo.
- Writes `~/.claude/CLAUDE.md` from the template.
- Registers the LetKite MCP server. By default this is machine-wide through `managed-mcp.json`.
- Installs the `ccw` helper.

Options include `--git-name/--git-email` for commit identity and `--hide-attribution`. Run with `--help` for the full list.

- **MCP URL.** The person's MCP URL is shown in the console's Get started card. It is normally `https://mcp.letkite.com/mcp`; a self-hosted gateway has its own.
- **Rules.** Edit the worker rules in `assets/worker-CLAUDE.md` before copying, if the person has rules of their own, such as commit authorship, branches workers may push, or what needs approval.

## Step 5: sign in Claude Code (per worker)

Pick one way per worker. The exact terminal sequences are in [references/auth.md](references/auth.md).

- **Claude subscription.** Run `ccw <w> 'claude auth login --claudeai'`.
  1. It prints a URL. Put the URL in a page or file and send it.
  2. Call `terminal_ask` at once.
  3. The person signs in and pastes the Authentication Code shown on the page. The whole code is about 90 characters and contains a `#`.
  - Usage counts against that account's plan.
- **API key.** Have the person create a key in the Anthropic Console with a spend limit. Store it for the worker with `terminal_ask`, never with `echo`. The details are in auth.md.

Check with `ccw <w> 'claude auth status'`. If the output just says `Login failed:` with no reason, start a fresh login. The old code is dead.

## Step 6: connect each worker back to LetKite

Run `ccw <w> 'claude mcp login --no-browser letkite'`:

1. It prints an authorize URL. Send it as a page or file, then call `terminal_ask` immediately.
2. The person signs in to LetKite. On the consent page they choose what this worker may reach.
   - **Recommend specific nodes or tags** (for example only `cc-worker` and test devices) and a restrictive **Policy**, rather than all nodes with full shell.
3. The browser ends on `http://localhost:<port>/callback?code=...`, which won't load. That is expected.
4. The person copies the full address from the address bar and pastes it at the prompt.
5. The CLI prints `Authenticated with "letkite"`.

## Step 7: GitHub (optional)

Run `ccw <w> 'gh auth login --hostname github.com --git-protocol https --web'`:

1. Answer `y` to "Authenticate Git".
2. Show the one-time code and https://github.com/login/device.
3. Wait for `Logged in as`.

Then run `ccw <w> 'gh auth setup-git'` and clone what the worker needs into `~/src`.

For tighter scope, suggest a fine-grained token instead: only the needed repos, Contents and Pull requests read and write, no Administration. The person pastes it with `gh auth login --with-token` through `terminal_ask`.

## Step 8: verify and hand over

Run `ccw status` on every machine. Every row needs auth `login` or `key`, and mcp `yes`; gh only if it was wanted.

Then do one cheap real call per worker:

```
ccw <w> 'cd ~/src && claude -p "Reply with exactly: ok" --model haiku'
```

Also run one MCP round trip, for example ask the worker to call LetKite's `list_hosts` and report the count, with `--allowedTools "mcp__letkite__list_hosts"`.

Report the pool to the person:

- each worker and where it runs;
- its auth type: which account, or a key with its spend cap;
- what its LetKite connection may reach;
- anything still missing.

## Dispatching and operating

How to send work and look after the pool is in [references/operate.md](references/operate.md). It covers:

- non-interactive `claude -p` jobs through `job_start`;
- interactive sessions through `terminal_open`;
- picking models by alias (`haiku`, `sonnet`, `opus`);
- cost control, upgrades, adding and removing workers, and teardown.

## What has been tested (v0.1)

- `probe-host.sh` on Ubuntu 24.04 in three shapes: a large VM with Incus and no nested KVM (recommended B), an unprivileged LXC container (C), and a small KVM guest (C, one worker). It never ran the LXD stub.
- `setup-worker.sh` and `ccw` on Ubuntu 24.04: fresh install, rerun (idempotent), managed MCP exclusivity, refusal of bad keys. `ccw status` was checked against workers that were already signed in.
- Sign-in flows with Claude Code 2.1.292: Claude subscription login, API key, `claude mcp login --no-browser` against a LetKite gateway, and the GitHub device flow.
- `pool-host.sh` has **not** yet been run end to end on a host. Check its output carefully the first time, and report problems at https://github.com/letkite/skills/issues.
