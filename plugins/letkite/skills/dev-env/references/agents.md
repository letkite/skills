# Claude Code and OpenCode

Both install into the user's home without root. Run as the target user.

## D. Claude Code

### Install

```bash
curl -fsSL https://claude.ai/install.sh | bash
~/.local/bin/claude --version
```

- The native installer puts `claude` in `~/.local/bin` (a link into `~/.local/share/claude/versions/`). It needs no Node.js.
- If `~/.local/bin` isn't on PATH in login shells, add `export PATH="$HOME/.local/bin:$PATH"` to `~/.profile`.
- Tested: Ubuntu 24.04, installed 2.1.307.
- The installer keeps Claude Code up to date. For a fleet that should stay on a pinned version, see the `worker-pool` skill.

### Sign in: ask which

**Claude subscription** (Pro or Max account):

```
terminal_open  command="claude auth login --claudeai"  until="Paste code"
```

1. It prints `https://claude.com/cai/oauth/authorize?...` and `Paste code here if prompted >`.
2. Put the URL in a small HTML page or file, send it, and call `terminal_ask` right away ("paste the Authentication Code from the Claude page").
3. The person signs in **with the account meant for this machine** (their browser may be signed in to another), approves, and copies the code. It is about 90 characters and contains a `#`.
4. Expect `Login successful.` Check with `claude auth status`, which should show `"loggedIn": true`.
5. A bare `Login failed:` means the code was used or expired: start again.

**API key** (Anthropic Console):

1. The person creates a key in the Console and sets a spend limit on it there.
2. Best: put it in a LetKite environment variable such as `ANTHROPIC_API_KEY` (secret). Claude Code reads that variable directly, and nothing is written on the node. It only works in processes LetKite starts, same as B2 for git.
3. Or store it for this user. Have the person type it into `terminal_ask` behind `read -rs` and write it to `~/.config/claude-key` (mode 0600). Then set `apiKeyHelper` in `~/.claude/settings.json` to `cat ~/.config/claude-key`. Don't put a machine-wide `apiKeyHelper` in managed settings: it blocks subscription sign-in for everyone on the machine.
4. Judge the key by the API, not by its prefix: `claude -p 'say ok'` should answer.

### Connect Claude Code to LetKite (optional)

This lets this machine's Claude Code use LetKite's tools too, so it can reach the person's other machines.

```
terminal_open  command="claude mcp add --transport http --scope user letkite https://<gateway>/mcp && claude"  until="Welcome"
```

Then run `/mcp`, choose letkite, and Authenticate:
- Claude Code prints a sign-in URL. Send it as a page and call `terminal_ask` at once.
- The person signs in to LetKite and approves only the nodes and policy this machine should reach.
- The browser then lands on `http://localhost:<port>/callback?...`, which won't load on their side. They paste that whole address into `terminal_ask`.

Check: `claude mcp list` shows `letkite ... Connected`. The `worker-pool` skill, references/auth.md, has the details.

## E. OpenCode

### Install

```bash
curl -fsSL https://opencode.ai/install | bash
~/.opencode/bin/opencode --version
```

- The installer puts `opencode` in `~/.opencode/bin` and adds that directory to PATH in `~/.bashrc`.
- In a new non-interactive shell, call `~/.opencode/bin/opencode` by its full path, or add the same line to `~/.profile`.
- Tested: Ubuntu 24.04, installed 1.19.3.
- Alternatives the person may prefer: `npm i -g opencode-ai` (needs Node.js), or `brew install sst/tap/opencode` on macOS.

### Sign in to a provider: ask which

OpenCode works with many model providers: Anthropic, OpenAI, GitHub Copilot, OpenRouter, local models, and others. Ask which one the person uses.

```
terminal_open  command="~/.opencode/bin/opencode auth login"
```

- It shows a provider menu; move with `terminal_send` (arrow keys, Enter) as the person directs.
- An API key: `terminal_ask`. It is stored in `~/.local/share/opencode/auth.json`. Tell the person that.
- A browser sign-in (for example GitHub Copilot or a Claude subscription): send the URL as a page, and the person pastes the code into `terminal_ask`.
- Providers that read an environment variable (for example `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`) also work with a LetKite environment variable, and then nothing is stored.

Check: `opencode auth list` shows the provider, and `opencode run 'say ok'` answers.
