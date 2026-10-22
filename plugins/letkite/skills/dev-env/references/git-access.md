# git, GitHub and other git hosts

Run everything as the target user (the node's default user in LetKite), except installing packages.

## F. Install the GitHub CLI

Needs root or sudo. Check first: `gh --version`.

Debian / Ubuntu (GitHub's official apt repository):

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update -qq && sudo apt-get install -y gh
```

- Fedora / RHEL: `sudo dnf install -y gh`.
- macOS with Homebrew: `brew install gh`.

If `sudo` wants a password you can't provide, give the person these commands to run, or skip gh and use B2 or B4, which work with plain git.

## A. git identity

Ask for the name and email; don't guess them from the account.

```bash
git config --global user.name "<name>"
git config --global user.email "<email>"
```

People who keep their email private on GitHub often use `<id>+<login>@users.noreply.github.com`.

## B1. GitHub CLI sign-in (browser + one-time code)

```
terminal_open  command="gh auth login --hostname github.com --git-protocol https --web"  until="one-time code"
```

1. gh prints a code like `ABCD-1234` and the URL `https://github.com/login/device`.
2. On a headless machine it can't open a browser; that is fine. If it asks "Press Enter to open...", send Enter with `terminal_send`.
3. Give the person the URL and the code; the code is short-lived but not a secret on its own. They approve in their browser while signed in as the account to use.
4. Wait for `Logged in as <account>`. Then make git use gh for github.com:

```bash
gh auth setup-git --hostname github.com
gh auth status
```

`gh auth setup-git` adds `credential.https://github.com.helper = !gh auth git-credential` to `~/.gitconfig`.

## B2. Token in a LetKite environment variable (nothing on disk)

1. The person creates the token on GitHub. A **fine-grained** token is best, limited to the repositories needed, with Contents read/write (plus Pull requests, Workflows and so on as needed).
2. In the LetKite console they add an environment variable for this node or one of its tags. Name it, for example, `GITHUB_TOKEN` or `GITHUB_PERSONAL`, mark it **secret**, and paste the token there. Never paste it in chat.
3. Check that it arrived, by name and length only. Variables reach commands within about a minute:
   ```bash
   [ -n "${GITHUB_TOKEN:-}" ] && echo "set, ${#GITHUB_TOKEN} characters" || echo missing
   ```
4. Copy [`scripts/git-token-helper.sh`](../scripts/git-token-helper.sh) over and run:
   ```bash
   ./git-token-helper.sh --host github.com --env GITHUB_TOKEN --gh
   ```
   - git: `~/.gitconfig` gets a helper for `https://github.com` that prints `$GITHUB_TOKEN` only when git asks. An empty helper entry first resets the list for that host, so a global `store` helper doesn't save the token to `~/.git-credentials`.
   - `--gh`: login shells export `GH_TOKEN` from the variable (snippet `~/.config/letkite/gh-token.sh`, sourced from `~/.profile` and `~/.bashrc`). gh then reports `Logged in ... (GH_TOKEN)`.
5. Check: `git ls-remote https://github.com/<owner>/<private repo> HEAD` (exit 0), and `bash -lc 'gh api user --jq .login'`.

To rotate the token, the person changes the variable in the console; nothing on the node changes. To undo: `./git-token-helper.sh --host github.com --remove --gh`.

**If there is already a `~/.git-credentials`** with a GitHub entry (an old token saved in plain text by `credential.helper=store`): the helper above bypasses it for github.com. Tell the person it is there; deleting it is their call.

## B3. Token typed once, stored by gh

```
terminal_open  command="gh auth login --hostname github.com --git-protocol https --with-token"
terminal_ask   prompt="paste the GitHub token, then press Enter and Ctrl-D"
```

Then `gh auth setup-git --hostname github.com` and `gh auth status`. The token is kept in the keyring if there is one, otherwise in `~/.config/gh/hosts.yml` (mode 0600). Tell the person that.

## B4. SSH key

```bash
test -f ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N '' -C "$(id -un)@$(hostname -s)" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

- The public key is not a secret: show it, and the person adds it at GitHub, Settings, SSH and GPG keys. If gh is already signed in with the `admin:public_key` scope, `gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname -s)"` does it.
- First contact: `ssh -T -o StrictHostKeyChecking=accept-new git@github.com`. Expect `Hi <account>!`; the exit code is 1 even on success.
- If the person wants https URLs rewritten to SSH: `git config --global url."git@github.com:".insteadOf https://github.com/`.

A key with no passphrase is only as safe as the account it's in. Offer a passphrase plus `ssh-agent` if the machine is shared.

## C. Other git hosts by token

Same as B2. The token goes into a LetKite environment variable, then:

| Host | Command | Username |
|---|---|---|
| GitLab (gitlab.com or self-hosted) | `git-token-helper.sh --host gitlab.com --env GITLAB_TOKEN --user oauth2` | `oauth2` works for personal access tokens |
| GitCode (gitcode.com) | `git-token-helper.sh --host gitcode.com --env GITCODE_TOKEN --user <account>` | the GitCode account name |
| Gitea / Forgejo | `git-token-helper.sh --host git.example.invalid --env GITEA_TOKEN --user <account>` | the account name |

Find the account name the token belongs to without showing the token:

- GitCode: `curl -s "https://api.gitcode.com/api/v5/user?access_token=$GITCODE_TOKEN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["login"])'`
- GitLab: `curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.com/api/v4/user | python3 -c 'import json,sys; print(json.load(sys.stdin)["username"])'`

Check with `git ls-remote https://<host>/<owner>/<private repo>.git HEAD` (exit 0). An empty repository prints nothing but still exits 0.
