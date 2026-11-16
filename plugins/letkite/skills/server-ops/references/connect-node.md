# Connect a server to LetKite

The person does this once per server, as root, on the server itself (the provider's web console, or SSH if they still have it). You cannot do it for them: the server has to prove it belongs to their account, and that proof is them approving a code while signed in.

## What to tell them

1. **Create the deploy account first** if they already know they want one (Step 3 A). LetKite will then run commands as that account from the start:

   ```
   useradd --create-home --shell /bin/bash deploy
   ```

   Not decided yet? Skip it. The account can be chosen later (item 4).

2. **Run the official installer as root:**

   ```
   curl -fsSL https://get.letkite.com/install.sh | sudo sh -s -- enroll --user deploy --name web-1
   ```

   - `--name` is what the node is called in LetKite (the host name by default); `--tag web` adds a tag.
   - Leave out `--user deploy` to have commands run as the account that ran `sudo`, or as root when run as root.
   - Nothing else is needed: no key to copy, no token. The installer is served from `get.letkite.com` over HTTPS. It checks the program it downloads against the release's checksums. The program already knows the LetKite gateway (`nodes.letkite.com`) and its keys, so it refuses anything that is not LetKite.

3. **Approve the code.** The installer prints a short code and a link, `https://id.letkite.com/device`. They open the link on any device, sign in to LetKite as an owner or admin of the account the server should join, check that the code matches, and approve. The installer then installs the service (`letkite-agent`, systemd) and the server appears in the console under Nodes.

4. **Check** on the server: `sudo letkite-agent status`. It should say connected and show which account commands run as. To change that account later:

   ```
   sudo letkite-agent set-user deploy      # or: sudo letkite-agent set-user --root
   ```

5. **Your AI connection must reach the new node.** If `list_hosts` does not show it, open the console, go to Connections, and add the node, or a tag on it, to the connection the AI uses. If the node shows as unconfirmed, confirm it in Nodes first. Either way, call `list_hosts` again afterwards.

## The ceiling: what LetKite may do on this server

`/etc/letkite/ceiling.toml` is the server's own limit. The console can narrow it but never go past it. The installer writes a template that allows everything the account can do. For a server, suggest the changes below. The person runs them as root; each one keeps the rest of the file, and the agent applies it within seconds:

```
sudo letkite-agent ceiling set gui off           # a server has no desktop
sudo letkite-agent ceiling set keep_awake off    # servers do not sleep
sudo letkite-agent ceiling set files /srv/myapp /var/log /tmp /home/deploy   # what the file tools may see
sudo letkite-agent ceiling set elevate false     # after setup: nothing sent through LetKite runs as root
sudo letkite-agent ceiling show                  # check
```

Keep `elevate` on while you set the server up (accounts, packages, firewall, units), and turn it off when you are done. To work on the system again later, the person runs `sudo letkite-agent ceiling set elevate true` and turns it off again afterwards.

Two keys have no `set` command. The person edits them in the file as root, then runs `sudo systemctl restart letkite-agent`:

| Key | Suggest | Why |
|---|---|---|
| `gui_apps` | `[]` | no desktop apps to drive |
| `tunnel_targets` | `["127.0.0.1:8080"]` or `[]` | lets the person open the app's internal port through LetKite (`tunnel_http`) without opening the firewall |

## Remove a server

The person removes the node in the console (Nodes), then on the server runs:

```
sudo letkite-agent uninstall      # stops and removes the service; /etc/letkite stays
```

Deleting `/etc/letkite` afterwards removes the node's key and its ceiling.
