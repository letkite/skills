# Sign-ins, step by step

All of these run in a LetKite terminal on the machine that hosts the worker (`terminal_open`), as root, through `ccw`. The person answers in the LetKite console via `terminal_ask`; you never see the secret, only the program's output and how many characters were typed.

Two habits make this smooth:

- **Send long URLs as a page or file**, not in chat (they get filtered or cut). A tiny HTML file with one link and three numbered steps works well.
- **Call `terminal_ask` right after the prompt appears**, before or together with sending the link. CLIs waiting for a code time out within a few minutes; anything pasted afterwards goes to the shell as a command.

## Claude subscription (claude.ai account)

```
terminal_open  command="ccw ccw-01 'claude auth login --claudeai'"  until="Paste code"
```

1. It prints `If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?...` and `Paste code here if prompted >`.
2. Put that URL in a page/file, send it, call `terminal_ask` (prompt: "paste the Authentication Code from the Claude page").
3. The person signs in **with the account meant for this worker** (browsers are often signed in to another one), approves, copies the Authentication Code (about 90 characters, contains a `#`).
4. Expect `Login successful.` Check: `ccw ccw-01 'claude auth status'` → `"loggedIn": true, "authMethod": "claude.ai"`.

- `Login failed:` with nothing after it: start again; codes are single-use and tied to that login attempt.
- Usage counts against that account's plan limits, shared with anything else the account does.

## API key (Anthropic Console)

1. The person creates a key in the Anthropic Console and sets a spend limit for it (Console limits).
2. `terminal_open command="ccw key ccw-01"`, then `terminal_ask`. `ccw key` reads the key hidden, stores it as the worker in `~/.config/ccw/anthropic-key`, checks it against the API (`/v1/models`, free), and only then points the worker's `apiKeyHelper` at it.
3. To switch a worker back to a Claude account: `ccw key ccw-01 --remove`, then the subscription flow.

Don't judge a key by its prefix: formats change. Let the API decide (401 = not a valid API key, 403 = account not enabled or out of credit).

## LetKite MCP

With `--mcp-mode managed` (default) the server `letkite` is already configured; with `user` it was added per worker.

```
terminal_open  command="ccw ccw-01 'claude mcp login --no-browser letkite'"  until="paste the redirect URL"
```

1. It prints `Visit this URL to authorize: https://<your gateway>/oauth/authorize?...` and `Or paste the redirect URL here:`.
2. Send the URL as a page/file, call `terminal_ask` ("paste the full localhost address the browser ended on").
3. The person signs in to LetKite and, on the consent page, picks permissions, **which nodes/tags** this worker may reach and a **policy**. Suggest the narrowest set that fits the work (for example the `cc-worker` tag plus test devices, shell sandboxed) instead of all nodes with full shell.
4. The browser ends on `http://localhost:<port>/callback?code=...&state=...` and shows an error page. That is normal; the person copies the whole address from the address bar.
5. Expect `Authenticated with "letkite"`. Check: `ccw status` (mcp yes) or `ccw ccw-01 'claude mcp list'` (Connected).

The worker's connection appears on the console's **Connections** page, where it can be revoked.

## GitHub (optional)

Device flow (simplest):

```
terminal_open  command="ccw ccw-01 'gh auth login --hostname github.com --git-protocol https --web'"
```

Answer `y` to "Authenticate Git with your GitHub credentials?", press Enter at "Press Enter to open github.com" (no browser on a server, that's fine), show the person the one-time code and https://github.com/login/device, wait for `Logged in as <user>`. Then `ccw ccw-01 'gh auth setup-git'`.

Narrower: a fine-grained personal access token limited to the repos the worker needs (Contents and Pull requests read/write; no Administration): `ccw ccw-01 'gh auth login --with-token'` and `terminal_ask` for the token.

The device flow grants what the GitHub CLI asks for on that account (broad repo access). Branch protection and required reviews on GitHub are the real backstop against a worker merging what it shouldn't.
