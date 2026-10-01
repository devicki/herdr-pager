# herdr-pager

English | [한국어](README.ko.md)

Get a push notification on your phone or laptop when an agent in [Herdr](https://herdr.dev) finishes or needs your answer, and when a command, script or scheduled job ends. Each message says what happened and which pane it came from, with the command that takes you back there. Delivery goes through [ntfy](https://ntfy.sh), ideally one you host yourself.

```
✅ [bot] claude done · shop-api
📂 1 · agent › Add refresh-token rotation
💬 Rotation is in. Tests pass; the diff is on the right.
⏱ 4m12s  📍 herdr:claude(w9:p1)
↩ herdr agent focus w9:p1

🙋 [bot] claude needs you · shop-api                    (high priority)
📂 1 · agent › Add refresh-token rotation
❓ Bash(rm -rf build)
   Do you want to proceed?
📍 herdr:claude(w9:p1)
↩ herdr agent focus w9:p1

❌ [bot] backup.sh failed (exit 7)                      (high priority)
💻 ./backup.sh --full
⏱ 12m03s  📁 ~/ops
```

Messages are in English by default; `lang = ko` switches them to Korean. The emoji in front of each title is the message's ntfy tag, which the apps show that way.

## What it reports

| Event | When | Priority | Contents |
| --- | --- | --- | --- |
| Agent finished | a working agent turns idle (or `done`) and stays so for `done_delay` seconds | 3 | session title, the agent's last reply (Claude Code and Codex transcripts), duration, pane |
| Agent needs you | an agent is `blocked` for `blocked_delay` seconds; once per wait | 4 | the prompt at the bottom of the pane, pane |
| Command ended | `herdr-pager run -- CMD`, or any command over `shell_threshold` seconds with the shell hook | 3, or 4 on failure | command line, exit code, duration, host and directory, pane; for a failed `run`, the last lines of its error output |
| Anything else | `herdr-pager send`, for cron, systemd, CI | your choice | your message |

Every title starts with a `label` (default: your user name) so machines and accounts stay apart in one list. Titles stay short for a lock screen (agent and workspace); the body starts with the tab and the session title, and ends with the pane as `herdr:<name>(<id>)` and a `herdr agent focus` command (with `--session` in a named session). The `herdr:` reference is the form [herdr-ids](https://github.com/devicki/herdr-ids)' picker types, so you can paste it into another agent's prompt ("check herdr:claude(w9:p1)"). Markdown in replies is flattened, since phone apps show plain text.

Short blips are never sent: an agent that pauses mid-turn, or a prompt you answer within the delay, produces nothing. Each finished turn or wait is sent once, even when Herdr repeats the event.

When the server cannot be reached, the message is kept in the plugin state dir and resent with the next one that gets through, or at the next agent event, marked with the time it was meant for. Messages older than a day are dropped.

## How the pieces fit

```
account A: herdr-pager ─(token A → topic a)─┐
account B: herdr-pager ─(token B → topic b)─┼─▶ one ntfy server ─▶ your phone (one read-only user,
cron, systemd, scripts ─(herdr-pager run)───┘                        subscribed to a and b)
```

- The plugin only publishes; it does not run a server. Any ntfy server works, including the public ntfy.sh (messages then pass through it).
- One server is enough for every machine and account: give each account its own topic and a token that can only write to it, and give your phone one user that can read them all.

## Install

Requires `bash` (3.2 is enough), `jq` 1.6 or newer and `curl`, on Linux or macOS.

### 1. An ntfy server (once)

Skip this if you already have one. [`docs/ntfy`](docs/ntfy) is a private setup that denies everything by default:

```sh
mkdir -p ~/ntfy && cd ~/ntfy          # copy compose.yml and server.yml from docs/ntfy here
docker compose run --rm ntfy user hash       # twice: a password for your phone, one for each publisher
docker compose run --rm ntfy token generate  # once per publishing account
# put the hashes and tokens into server.yml (auth-users, auth-access, auth-tokens), then:
docker compose up -d
curl -s http://127.0.0.1:2586/v1/health      # {"healthy":true}
```

The server listens on `127.0.0.1:2586` only. To reach it from your phone over a tailnet, without opening a port to the internet:

```sh
tailscale serve --bg --https=8446 http://127.0.0.1:2586   # https://<host>.<tailnet>.ts.net:8446
```

This needs Tailscale on the server and the phone, in the same tailnet, with MagicDNS and HTTPS certificates turned on (admin console → DNS); `tailscale serve` runs as root, or as your user after `sudo tailscale set --operator=$USER`. `base-url` in `server.yml` must be exactly that address. Both survive a reboot: the container has `restart: unless-stopped`, and `tailscale serve --bg` is kept by tailscaled. To add an account later, add a publisher user, an `auth-access` line and a token, then `docker compose up -d`.

For iOS, keep `upstream-base-url: "https://ntfy.sh"`: iPhones only get instant pushes through Apple's service, and ntfy sends just a message id and a topic hash that way; the phone fetches the message from your server.

### 2. The plugin, in each account

```sh
herdr plugin install devicki/herdr-pager --ref v0.5.0
```

It starts working at once; no restart is needed. It also links the `herdr-pager` command into `~/.local/bin` the first time it runs, for scripts, cron and the shell hook.

### 3. Settings

Open `pager.conf` in the plugin's config directory (`herdr plugin config-dir devicki.pager` prints it; the plugin leaves a commented template there) and fill in:

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
```

`#` starts a comment, on its own line or after a value. Keep the file private (`chmod 600`); the token never appears in command lines. `HERDR_PAGER_URL`, `HERDR_PAGER_TOPIC` and `HERDR_PAGER_TOKEN` override the file.

### 4. Check it

```sh
herdr plugin action invoke devicki.pager.test   # or `herdr-pager test` once it is on PATH
```

### 5. Subscribe on your phone

In the ntfy app (iOS or Android): tap **+**, enter the topic, turn on **Use another server** and enter the server address (exactly `base-url`), then log in as your device user. Repeat for each account's topic; the login is shared. With a tailnet-only server, Tailscale has to be on for the phone to fetch the message. The web app at the same address works on a laptop.

## Commands, scripts and scheduled jobs

```sh
herdr-pager run -- ./research.sh --deep        # reports success or failure; keeps the exit code
herdr-pager run -q -t "nightly backup" -- ./backup.sh   # -q: only when it fails
some-command | herdr-pager send -p 4 -t "import finished"
```

cron (`herdr-pager` fixes up `PATH` for `jq` and `curl` itself):

```
0 3 * * * $HOME/.local/bin/herdr-pager run -q -t "nightly backup" -- /opt/backup/run.sh
```

systemd: [`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service) reports any unit that fails, with the tail of its log. Copy it to `~/.config/systemd/user/` and add `OnFailure=herdr-pager-failure@%n.service` to the units you care about. The result and exit status in its title need systemd 251 or newer.

### Long shell commands, without a wrapper

```sh
# ~/.bashrc                                  ~/.zshrc
eval "$(herdr-pager shell-init bash)"        # eval "$(herdr-pager shell-init zsh)"
```

```fish
# ~/.config/fish/config.fish
herdr-pager shell-init fish | source
```

Any command that runs `shell_threshold` seconds or longer (default 60) is reported when it ends, with its exit code. Interactive tools and agents (`vim`, `less`, `ssh`, `lazygit`, `claude`, ...) are skipped; see `shell_skip`. fish uses its `fish_postexec` event and zsh its `preexec`/`precmd` hooks; bash uses the `DEBUG` trap and `PROMPT_COMMAND`, so it replaces another `DEBUG` trap if you have one.

## Settings

| Key | Default | Meaning |
| --- | --- | --- |
| `url`, `topic`, `token` | | where to publish |
| `label` | user name | prefix of every title |
| `lang` | `en` | language of the messages: `en` or `ko` |
| `done_delay` | 15 | seconds an agent must stay finished before it is reported |
| `blocked_delay` | 10 | seconds an agent must keep waiting before it is reported |
| `shell_threshold` | 60 | shell hook: minimum command duration in seconds |
| `shell_skip` | interactive tools and agents | shell hook: programs never reported |

## Notes

- **Herdr's own notifications**: if `[ui.toast] delivery` is `terminal` or `system`, Herdr also notifies you on the laptop you are attached from. Set it to `herdr` or `off` if you only want herdr-pager.
- **What is sent**: the agent's last reply and the bottom of a waiting pane leave the machine for your ntfy server. Common credential shapes (API keys, tokens, `password=` values) are masked, and messages are cut to a few hundred characters, but keep secrets out of what agents print.
- **Questions in plain text**: an agent that asks something in its reply, without a permission prompt, counts as finished, not waiting. The reply is in the message either way.
- **Agents**: any agent Herdr tracks works. The last reply is read from Claude Code and Codex transcripts; other agents get the session title only.
- Herdr's event hooks have no timeout, so the delayed check runs detached. Each attempt to publish is capped at 10 seconds; with two retries on timeouts and server errors, a send gives up after about 35 seconds and is queued.

## Update and uninstall

Herdr has no update command; reinstall at the new tag. `pager.conf` and the enabled state survive a reinstall.

```sh
herdr plugin install devicki/herdr-pager --ref v0.5.0 --yes
herdr plugin uninstall devicki.pager
```

Uninstalling leaves `pager.conf` in the config directory and the `~/.local/bin/herdr-pager` link; remove them, and the shell hook line, if you do not reinstall. The ntfy server is yours to keep or stop (`docker compose down`, `tailscale serve --https=8446 off`).

## Development

```sh
herdr plugin link .
./test.sh   # isolated Herdr + a stand-in ntfy: agent turns, blips, waits, commands, the shell hook filter, masking, the resend queue
```

To release, bump `version` in `herdr-plugin.toml`, update the `--ref` in both READMEs, commit, then `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.

## License

MIT
