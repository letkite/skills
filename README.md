# LetKite skills

[Agent Skills](https://agentskills.io) for working with [LetKite](https://letkite.com): run commands, move files and put AI agents to work across your own machines, from Claude or any MCP client.

| Skill | What it does |
|---|---|
| [`worker-pool`](plugins/letkite/skills/worker-pool/SKILL.md) | Build and run a pool of headless Claude Code workers on your machines: pick a layout per host (VM, container or account per worker), enroll them in LetKite, sign in Claude Code, connect each worker back to LetKite, optional GitHub, then dispatch tasks. |
| [`dev-env`](plugins/letkite/skills/dev-env/SKILL.md) | Set up a developer environment on a node after it joins LetKite, choosing each piece: git identity; GitHub by CLI sign-in, by a token in a LetKite environment variable (nothing on disk), by a stored token or by SSH key; GitLab, GitCode or Gitea tokens; Claude Code; OpenCode; connecting Claude Code or OpenCode to LetKite with their own authorization. |

## Install

**Claude Code** (plugin marketplace):

```
/plugin marketplace add letkite/skills
/plugin install letkite@letkite
```

Skills are then available as `/letkite:<skill>`, and Claude uses them on its own when a task fits. Update with `/plugin marketplace update letkite`.

**claude.ai** (Customize > Skills > Upload a skill): download `<skill>.zip` from the [latest release](https://github.com/letkite/skills/releases/latest), or build it yourself with `tools/package.sh`.

**By hand**: copy a skill folder into `~/.claude/skills/` (personal) or `.claude/skills/` in a project.

All skills expect a LetKite connection in the client that uses them: add `https://mcp.letkite.com/mcp` (or your self-hosted gateway's URL) as a custom connector in Claude, or `claude mcp add --transport http letkite https://mcp.letkite.com/mcp` in Claude Code.

## Layout

```
.claude-plugin/marketplace.json     the marketplace: one entry per plugin
plugins/<plugin>/                   a plugin groups related skills
  .claude-plugin/plugin.json        name, version, description
  skills/<skill>/SKILL.md           one skill: frontmatter + instructions
  skills/<skill>/references/        detail loaded only when needed
  skills/<skill>/scripts/           scripts the skill runs on machines
  skills/<skill>/assets/            templates and other files it copies
tools/check.py                      lint: frontmatter, links, secrets, shellcheck
tools/package.sh                    zip each skill for claude.ai
```

Plugins today: `letkite` (skills for LetKite users). New skills go into the plugin whose audience they share; a new plugin is worth it when a group of skills has a different audience or would rarely be installed together (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## License

MIT. See [LICENSE](LICENSE).
