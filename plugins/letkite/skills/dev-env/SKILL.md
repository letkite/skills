---
name: dev-env
description: Set up a developer environment on a machine after it joins LetKite, letting the person choose each piece - git identity; GitHub access by GitHub CLI sign-in, by a token kept in a LetKite environment variable (never written to disk), by a stored token, or by SSH key; tokens for other git hosts such as GitLab, GitCode or Gitea; Claude Code; OpenCode; and connecting Claude Code or OpenCode to LetKite (MCP) with the machine's own authorization. Probes what is already there first, asks which pieces and which method, keeps secrets out of chat, and verifies each piece. Use when asked to set up git, gh, GitHub or GitCode tokens, Claude Code, OpenCode or a LetKite MCP connection on a LetKite node, to prepare a new node for development, or to fix git credentials on one.
license: MIT
compatibility: Requires a LetKite connection (MCP tools such as list_hosts, host_facts, exec, write_file, terminal_open, terminal_ask). Target machines run Linux (tested on Ubuntu 24.04) or macOS; installing the GitHub CLI needs root or sudo.
---

# Developer environment on a LetKite node

You set up one **user** on one **node** for development: git, access to git hosts, and AI coding tools. The person decides what goes on and how. Different people want different things: some sign in with the GitHub CLI, some prefer a token, some use SSH keys only. Ask, don't assume.

## Ground rules

- **Secrets never go through chat.** That covers tokens, API keys, sign-in codes and redirect URLs. Two safe ways in:
  - **LetKite environment variable** (best for tokens): the person adds it in the LetKite console (Environment variables, marked secret) for this node or its tag. The agent passes it to the commands it runs. You use only its **name**.
  - **`terminal_ask`**: run the program in `terminal_open`, call `terminal_ask`, and the person types into the LetKite console. You see the program's output, never the secret.
- **Never put a secret in a command line, a file you write, or your own output.** Check token variables by name and length only.
- **Send long sign-in URLs as a small HTML page or file**, not in chat (they get cut or filtered). Call `terminal_ask` right away, because CLIs waiting for a code time out within minutes.
- **One `terminal_ask` per prompt.** If your call times out or you lose track, first call `terminal_read` to see whether the program already got its answer, and only then ask again. Otherwise a second paste lands in the shell and runs as a command.
- **Work as the right user.** LetKite runs commands as the node's default user (agent 1.6.1 and later: `letkite-agent [--instance dev] set-user <name>`, as root). Everything here goes into that user's home. Installing system packages needs root or sudo; if `sudo` asks for a password, give the person the exact command instead.
- **Look before changing.** Run `host_facts`, then `scripts/probe-env.sh`, and only offer what is missing or broken.

## Step 1: probe

Copy [scripts/probe-env.sh](scripts/probe-env.sh) to the node with `write_file` (for example `/tmp/dev-env/probe-env.sh`, mode `0755`) and run it with `exec`. It is read-only and prints `key=value` lines:
- `user`, `sudo`;
- tool versions (`have_git`, `have_gh`, `have_claude`, `have_opencode`, ...);
- git identity and credential helpers;
- whether `~/.git-credentials` exists;
- who `gh` and SSH are signed in as;
- whether Claude Code and OpenCode are signed in;
- `token_vars`, the **names** of token-like environment variables that are already present.

Summarize it for the person in a short table: what is there, what is missing.

## Step 2: ask what to set up

Offer the pieces as a checklist; the person picks any subset. For each picked piece that has a choice of method, ask which one, using the trade-offs below. Skip what is already set up unless they want it redone.

| Piece | Choices |
|---|---|
| **A. git identity** | name and email for commits (`git config --global user.name/user.email`). Ask for both |
| **B. GitHub access** | one of B1-B4 below |
| **C. other git hosts** | GitLab, GitCode, Gitea, self-hosted: by token in an environment variable |
| **D. Claude Code** | install; then sign in with a Claude subscription or an API key; optionally connect it to LetKite |
| **E. OpenCode** | install; then sign in to a model provider |
| **F. GitHub CLI** | install `gh` (needed for B1 and B3, handy for B2) |
| **G. connect to LetKite (MCP)** | give this machine's Claude Code and/or OpenCode their **own** LetKite connection, so agents here can use LetKite's tools; ask which gateway (production or dev) and which tools |

GitHub methods: help the person choose.

| Method | Where the credential lives | Good for |
|---|---|---|
| **B1. `gh auth login`** (browser and one-time code) | gh's keyring or `~/.config/gh/hosts.yml`, OAuth token | people who use the GitHub CLI anyway; easiest |
| **B2. Token in a LetKite environment variable** | only in the LetKite console; on the node it exists in the processes LetKite starts. `~/.gitconfig` holds just the variable's name | shared or throwaway machines; rotating the token in one place; fine-grained tokens limited to some repos |
| **B3. Token typed once, stored by gh** (`gh auth login --with-token`) | `~/.config/gh/hosts.yml` (or the keyring) | a token the person already has, on a machine they own |
| **B4. SSH key** | a key pair in `~/.ssh`, public half added to GitHub | people who clone with `git@github.com:`; no token at all |

For G, explain before starting:
- The machine gets its **own** authorization. On the LetKite approval page the person picks which nodes and which policy this machine's agents may use; that can be far less than their own connection.
- If Claude Code here is signed in with the person's **own claude.ai account**, it already inherits every connector on that account. `claude mcp list` shows them as `claude.ai <name>`. That may include LetKite with the person's full access, cloud consoles, payments or email.
- Offer to turn those off for this user with `"disableClaudeAiConnectors": true` in `~/.claude/settings.json`; servers added with `claude mcp add` keep working.

With B2, git and `gh` work in shells LetKite starts (`exec`, `terminal_open`, jobs) and in the programs they start, such as Claude Code run from a LetKite terminal. A plain SSH login that bypasses LetKite has no such variable. Say so if the person also logs in that way.

## Step 3: set up each piece

Do the picked pieces in the order F, A, B, C, D, E, G. The exact commands are in the references:

- **F, A, B, C**: [references/git-access.md](references/git-access.md). For B2 and C, use [scripts/git-token-helper.sh](scripts/git-token-helper.sh):
  ```
  git-token-helper.sh --host github.com --env GITHUB_TOKEN --gh
  git-token-helper.sh --host gitcode.com --env GITCODE_TOKEN --user <their GitCode account>
  ```
  It makes git read the token from the variable when it needs it. Nothing secret is written to disk. A global `store` helper is bypassed for that host, so the token is never copied to `~/.git-credentials`.
- **D, E, G**: [references/agents.md](references/agents.md).

Use `exec` for non-interactive steps and `terminal_open` with `terminal_ask` for anything that asks for a secret or a code.

## Step 4: verify and report

Run `probe-env.sh` again, then a real check for each piece:

| Piece | Check |
|---|---|
| A | `git config --global user.name` and `user.email` print what the person gave |
| B1/B3 | `gh auth status` names the right account; `git ls-remote https://github.com/<owner>/<private repo> HEAD` exits 0 |
| B2 | the same `git ls-remote`, plus `bash -lc 'gh api user --jq .login'` |
| B4 | `ssh -T git@github.com` says `Hi <account>!`; `git ls-remote git@github.com:<owner>/<repo>.git HEAD` |
| C | `git ls-remote https://<host>/<owner>/<private repo>.git HEAD` exits 0 |
| D | `claude --version`, and `claude auth status` shows `"loggedIn": true` |
| E | `opencode --version`, and `opencode auth list` lists the provider |
| G | `claude mcp get <name>` shows `✔ Connected`, and a real call works: `claude -p --allowedTools=mcp__<name>__list_hosts "Call list_hosts on <name> and list the aliases"`. For OpenCode: `opencode mcp list` |

Check the exit code, not just the output: a pipe like `git ls-remote ... | cut` hides a failure.

A **403 from GitHub with a token that otherwise works** usually means a fine-grained token that doesn't cover that repository or organization. The person adds the repo or org to the token on GitHub. Don't create a new token for them.

Finish with a short table: each piece, the method chosen, where its credential lives, and the check result. Mention anything left for the person, for example a command that needs `sudo` with their password, or a stale `~/.git-credentials` they may want to delete.
