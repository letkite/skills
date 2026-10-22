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

Connecting Claude Code to LetKite is piece G, below.

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

## G. Connect to LetKite (MCP)

This gives the machine's coding agent **its own** LetKite connection. Agents running here can then use LetKite's tools (`list_hosts`, `exec`, files, jobs) on the nodes the person allows. Ask:

- **Which gateway?** Production is `https://mcp.letkite.com/mcp`. A dev or self-hosted gateway uses its own domain, for example `https://mcp.dev.<domain>/mcp`.
- **Which name?** It should be easy to tell apart, for example `letkite` or `letkite-dev`.
- **Which nodes and policy** this machine should reach. The person chooses that on the approval page; suggest a tag or a few nodes and a read-only or limited policy unless they need more.

### Claude Code

Add the server, then sign in with `--no-browser`. Claude Code prints the URL and accepts the redirect address pasted back:

```
exec           claude mcp add --transport http --scope user letkite-dev https://mcp.dev.<domain>/mcp
terminal_open  command="claude mcp login letkite-dev --no-browser"  until="paste the redirect URL"
```

1. It prints `Visit this URL to authorize: https://<gateway>/oauth/authorize?...` and then `Or paste the redirect URL here:`.
2. Put the URL in a small HTML page or file, send it, and call `terminal_ask` **once, right away**: "after approving, paste the whole `http://localhost:<port>/callback?...` address".
3. The person signs in to LetKite, picks the nodes and policy, and approves. Their browser then fails to load `http://localhost:<port>/callback?code=...&state=...`; that is expected, because the address points at the machine. They copy it from the address bar and paste it into the console.
4. Expect `Authenticated with "letkite-dev". Its tools are now available in Claude Code.`
5. If the person ends up pasting twice (for example after your ask timed out and you asked again), the second paste runs in the shell. The code is single-use and already spent, but clear it anyway: in that terminal run `history -c; unset HISTFILE`, then close the terminal.

Check:
- `claude mcp get letkite-dev` shows `Status: ✔ Connected`.
- A real call works: `claude -p --allowedTools=mcp__letkite-dev__list_hosts "Call list_hosts on letkite-dev and reply with the aliases"`.

Tested: Claude Code 2.1.307 on Ubuntu 24.04 against a LetKite gateway.

**Connectors inherited from claude.ai.** When Claude Code is signed in with a claude.ai account, every connector on that account is loaded too. `claude mcp list` shows them as `claude.ai <name>`. On a machine other people or unattended agents use, that can be far more than intended: the person's own LetKite connection, cloud consoles, payments, email. Offer to turn them off for this user only:

```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
s = json.load(open(p)) if os.path.exists(p) else {}
s["disableClaudeAiConnectors"] = True
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(s, open(p, "w"), indent=2)
PY
```

Servers added with `claude mcp add` keep working (per the Claude Code MCP documentation; check `claude mcp list` afterwards). For a single session only: `ENABLE_CLAUDEAI_MCP_SERVERS=false claude`. To turn off just one connector, use `/mcp` in Claude Code and disable it.

### OpenCode

```
exec           ~/.opencode/bin/opencode mcp add letkite-dev --url https://mcp.dev.<domain>/mcp
terminal_open  command="~/.opencode/bin/opencode mcp auth letkite-dev"
```

- `opencode mcp auth` runs the same OAuth sign-in. Send the URL it prints as a page.
- If it waits on a local callback (`http://localhost:<port>/...`) and offers no paste prompt, finish the sign-in **on the machine**. In a second terminal, run `read -r u && curl -s "$u" > /dev/null && echo sent`, call `terminal_ask`, and have the person paste the redirect address there. Their browser can't reach the machine's localhost, but `curl` on the machine can.
- Check: `opencode mcp list` shows the server as connected, and `opencode mcp auth list` shows it authenticated.

The `mcp add`, `mcp auth` and `mcp list` commands are those of OpenCode 1.19.3.
