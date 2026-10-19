# Contributing a skill

1. **Pick the plugin.** Skills for people who use LetKite go in `plugins/letkite/skills/`. Start a new plugin (`plugins/<name>/` plus an entry in `.claude-plugin/marketplace.json`) only for a different audience.
2. **Create `skills/<skill-name>/SKILL.md`.** The folder name and the `name` field must match.
3. **Run `python3 tools/check.py`** (and `claude plugin validate ./plugins/<plugin> --strict` if you have Claude Code). CI runs both.
4. **Bump `version`** in the plugin's `plugin.json` when you change its skills, so installed copies update.

## Rules for SKILL.md

The same file must work as a Claude Code plugin skill and as a claude.ai upload, so it follows claude.ai's stricter rules:

- Frontmatter keys: only `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`.
- `name`: lowercase letters, digits and hyphens, at most 64 characters, and it must not contain `claude` or `anthropic`.
- `description`: at most 1024 characters, no XML tags. Say what the skill does **and when to use it**; this is all Claude sees before loading the skill.
- Body under 500 lines. Put detail in `references/*.md` and link to it from SKILL.md (one level deep).

## Content

- **Tested.** Every command and script in a skill has been run on a real machine. Say in the skill what it was tested on when that matters.
- **No secrets or private details**: no keys, tokens, passwords, real email addresses, internal hostnames or IP addresses. Use placeholders like `ccw-01`, `<your gateway>`, `example.invalid`.
- **Secrets travel safely in the instructions too**: skills tell the agent to use LetKite's `terminal_ask` for anything secret, never chat or command-line arguments.
- **Scripts**: bash with `set -euo pipefail`, idempotent, `--help` that explains every option, read-only unless the name says otherwise, shellcheck clean.
- English, plain and short.
