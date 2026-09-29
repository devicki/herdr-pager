# herdr-pager

English | [한국어](README.ko.md)

Get a push notification on your phone or laptop when an agent in [Herdr](https://herdr.dev) finishes or needs your answer, and when a command, script or scheduled job ends. Each message says what happened and which pane it came from, with the command that takes you back there. Delivery goes through [ntfy](https://ntfy.sh), ideally one you host yourself.

```
[bot] claude done · shop-api
1 · agent › Add refresh-token rotation
Rotation is in. Tests pass; the diff is on the right.
⏱ 4m12s · w9:p1
↩ herdr agent focus w9:p1

[bot] claude needs you · shop-api          (high priority)
1 · agent › Add refresh-token rotation
Bash(rm -rf build)
Do you want to proceed?
❯ 1. Yes
  2. No
⏳ waiting for you · w9:p1

[bot] ✗ backup.sh failed (exit 7)                    (high priority)
$ ./backup.sh --full
⏱ 12m03s · isle-server:~/ops
```

## What it reports

| Event | When | Priority | Contents |
| --- | --- | --- | --- |
| Agent finished | a working agent turns idle (or `done`) and stays so for `done_delay` seconds | 3 | session title, the agent's last reply (Claude Code and Codex transcripts), duration, pane |
| Agent needs you | an agent is `blocked` for `blocked_delay` seconds; once per wait | 4 | the prompt at the bottom of the pane, pane |
| Command ended | `herdr-pager run -- CMD`, or any command over `shell_threshold` seconds with the shell hook | 3, or 4 on failure | command line, exit code, duration, host and directory, pane |
| Anything else | `herdr-pager send`, for cron, systemd, CI | your choice | your message |

Every title starts with a `label` (default: your user name) so machines and accounts stay apart in one list. Titles stay short for a lock screen (agent and workspace); the body starts with the tab and the session title, and ends with the pane id and a `herdr agent focus` command. Markdown in replies is flattened, since phone apps show plain text.

Short blips are never sent: an agent that pauses mid-turn, or a prompt you answer within the delay, produces nothing. Each finished turn or wait is sent once, even when Herdr repeats the event.

## Install

```sh
herdr plugin install devicki/herdr-pager --ref v0.1.0
```

Requires `bash` (3.2 is enough), `jq` and `curl`, on Linux or macOS. Install it in every account whose agents and jobs you want to hear about. It also puts the `herdr-pager` command in `~/.local/bin` for scripts, cron and the shell hook.

### 1. An ntfy server and a token

Any ntfy server works, including ntfy.sh. For a private one, [`docs/ntfy`](docs/ntfy) has a compose file and a server config that denies everything by default, gives each publisher write access to one topic, and your devices read access. On a tailnet, `tailscale serve --bg --https=8446 http://127.0.0.1:2586` puts it on HTTPS without opening a port to the internet.

For iOS, keep `upstream-base-url: "https://ntfy.sh"`: iPhones only get instant pushes through Apple's service, and ntfy sends just a message id and a topic hash that way; the phone fetches the message from your server.

### 2. Settings

The plugin writes a commented template to `$(herdr plugin config-dir devicki.pager)/pager.conf` the first time it runs. Fill in:

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
```

Keep the file private (`chmod 600`); the token never appears in command lines. `HERDR_PAGER_URL`, `HERDR_PAGER_TOPIC` and `HERDR_PAGER_TOKEN` override the file.

### 3. Check it

```sh
herdr-pager test
```

### 4. Subscribe

In the ntfy app (iOS, Android) or the web app, add your server with the exact `base-url`, log in as your device user, and subscribe to each topic.

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

systemd: [`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service) reports any unit that fails, with the tail of its log. Copy it to `~/.config/systemd/user/` and add `OnFailure=herdr-pager-failure@%n.service` to the units you care about.

### Long shell commands, without a wrapper

```sh
# ~/.bashrc or ~/.zshrc
eval "$(herdr-pager shell-init bash)"   # or zsh
```

Any command that runs `shell_threshold` seconds or longer (default 60) is reported when it ends, with its exit code. Interactive tools and agents (`vim`, `less`, `ssh`, `lazygit`, `claude`, ...) are skipped; see `shell_skip`. The bash version uses the `DEBUG` trap and `PROMPT_COMMAND`, so it replaces another `DEBUG` trap if you have one.

## Settings

| Key | Default | Meaning |
| --- | --- | --- |
| `url`, `topic`, `token` | | where to publish |
| `label` | user name | prefix of every title |
| `done_delay` | 15 | seconds an agent must stay finished before it is reported |
| `blocked_delay` | 10 | seconds an agent must keep waiting before it is reported |
| `shell_threshold` | 60 | shell hook: minimum command duration in seconds |
| `shell_skip` | interactive tools and agents | shell hook: programs never reported |

## Notes

- **Herdr's own notifications**: if `[ui.toast] delivery` is `terminal` or `system`, Herdr also notifies you on the laptop you are attached from. Set it to `herdr` or `off` if you only want herdr-pager.
- **What is sent**: the agent's last reply and the bottom of a waiting pane leave the machine for your ntfy server. Common credential shapes (API keys, tokens, `password=` values) are masked, and messages are cut to a few hundred characters, but keep secrets out of what agents print.
- **Questions in plain text**: an agent that asks something in its reply, without a permission prompt, counts as finished, not waiting. The reply is in the message either way.
- **Agents**: any agent Herdr tracks works. The last reply is read from Claude Code and Codex transcripts; other agents get the session title only.
- Herdr's event hooks have no timeout, so the delayed check runs detached and every request is capped at 10 seconds.

## Development

```sh
herdr plugin link .
./test.sh   # isolated Herdr + a stand-in ntfy: agent turns, blips, waits, commands, the shell hook filter, masking
```

To release, bump `version` in `herdr-plugin.toml`, update the `--ref` in both READMEs, commit, then `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.

## License

MIT
