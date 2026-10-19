# Running the pool

## Sending work

Non-interactive, one task, structured result (the usual way):

```
ccw ccw-01 'cd myrepo && claude -p "<task>" --model sonnet --permission-mode acceptEdits --output-format json'
```

- Use `job_start` for anything longer than a minute or two, then `job_output`; `exec` waits only for short work.
- On layouts A, B and D the worker is its own node: run `ccw` there (or `runuser -l <worker> -c '...'` where `ccw` isn't installed).
- `--output-format json` returns `result`, `is_error`, `total_cost_usd` (API-key workers), `num_turns` and `session_id`; `--resume <session_id>` continues the same conversation.
- Write the task like an issue: goal, repo and branch, constraints, how to verify, what to report. Workers know nothing about your conversation.

Interactive, when a task needs back-and-forth:

```
terminal_open command="ccw ccw-01 'cd myrepo && claude'"      # then terminal_send / terminal_read
```

Several workers at once: give each its own branch or `git worktree`; never two workers in one working tree.

## Models and cost

- Pick models by alias: `--model haiku` (cheap, quick), `sonnet` (most coding), `opus` (hard problems). Full model IDs that the installed CLI doesn't know are rejected and replaced by the default, so prefer aliases.
- A minimal `claude -p` call already costs a few cents on an API key because of the system prompt; long agentic tasks cost dollars. API-key workers: set a spend limit in the Anthropic Console and watch it. Subscription workers: usage counts against that plan's limits.
- `--max-turns N` caps runaway tasks.

## Permissions

- `--permission-mode acceptEdits` lets the worker edit files without asking; shell commands still follow its permission rules.
- `--dangerously-skip-permissions` removes all prompts. Use it only when the worker's account, its LetKite consent scope and its GitHub access are all narrow enough that the worst case is acceptable.
- Pre-approve common commands per repo with `.claude/settings.json` (`permissions.allow`), or per call with `--allowedTools`.

## Health

- `ccw status` on each machine: auth, mcp, gh, running claude processes.
- A worker whose Claude login expired shows `auth no`: redo the sign-in from references/auth.md.
- `mcp no` after it was yes: the LetKite connection was revoked or expired; redo `claude mcp login`.

## Upgrades

`setup-worker.sh --claude-version <new> <workers...>` installs the new version beside the old one and switches `/usr/local/bin/claude`; the old `/opt/ccw-claude-<old>` stays for rollback (`ln -sfn /opt/ccw-claude-<old> /opt/ccw-claude`). Auto-update is off on purpose so a pool doesn't change under running tasks.

## Adding and removing workers

- Add: create the machine (A/B) or just run `setup-worker.sh <new-worker>` (C), then sign-ins.
- Remove, in this order:
  1. stop its running tasks (`pgrep -u <worker> -af claude`);
  2. push or save any unpushed work in its `~/src`;
  3. revoke its access: LetKite console **Connections** (its MCP connection), `claude auth logout` or revoke the API key, `gh auth logout` or revoke the token;
  4. delete it: `pool-host.sh delete <name>` and remove the node in the console (A/B), or `userdel -r <worker>` and drop it from `/etc/ccw/workers` (C).
  Say the exact delete command to the person first; LetKite will ask for `confirm=true`.
