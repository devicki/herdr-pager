# herdr-pager

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 繁體中文

當 [Herdr](https://herdr.dev) 裡的代理程式完成工作或需要你回答，以及指令、腳本或排程工作結束時，這個外掛會推播通知到你的手機或筆電。每則通知都會說明發生了什麼事、來自哪個窗格，並附上回到那個窗格的指令。通知透過 [ntfy](https://ntfy.sh) 傳送，最好使用你自己架設的伺服器。

```
✅ [bot] claude 工作完成 · shop-api
📂 1 · agent › Add refresh-token rotation
💬 Rotation is in. Tests pass; the diff is on the right.
⏱ 4分12秒  📍 herdr agent w9:p1 (claude)
↩ herdr agent focus w9:p1

🙋 [bot] claude 需要你確認 · shop-api                   (高優先順序)
📂 1 · agent › Add refresh-token rotation
❓ Bash(rm -rf build)
   Do you want to proceed?
📍 herdr agent w9:p1 (claude)
↩ herdr agent focus w9:p1

❌ [bot] backup.sh 失敗 (結束代碼 7)                    (高優先順序)
💻 ./backup.sh --full
⏱ 12分3秒  📁 ~/ops
```

上面的範例是在設定中加入 `lang = zh-TW` 時的樣子。預設為英文；`ko` 為韓文，`ja` 為日文。標題前的表情符號是通知的 ntfy 標籤，App 會以這種方式顯示。

## 會通知哪些事

| 事件 | 時機 | 優先順序 | 內容 |
| --- | --- | --- | --- |
| 代理程式完成工作 | 工作中的代理程式變成 idle（或 `done`），並維持 `done_delay` 秒，且自上次通知後有新的回覆（Claude Code、Codex） | 3 | 工作階段標題、代理程式的最後一則回覆（Claude Code 與 Codex 的對話紀錄）、耗時、窗格 |
| 代理程式需要你 | 代理程式處於 `blocked` 狀態達 `blocked_delay` 秒；每次等待只通知一次 | 4 | 窗格底部的提示、窗格 |
| 指令結束 | `herdr-pager run -- CMD`，或啟用 shell hook 時任何超過 `shell_threshold` 秒的指令 | 3，失敗時為 4 | 指令列、結束代碼、耗時、主機與目錄、窗格；`run` 失敗時另附錯誤輸出的最後幾行 |
| 其他 | `herdr-pager send`，用於 cron、systemd、CI | 自訂 | 你的訊息 |

每個標題都以 `label`（預設：你的使用者名稱）開頭，讓不同機器和帳號的通知在同一個清單中也能區分。標題保持簡短，方便在鎖定畫面上閱讀（代理程式與工作區）；內文以分頁和工作階段標題開頭，並以 `herdr agent <id> (<agent>)` 形式的窗格標示（沒有代理程式的窗格為 `herdr pane`）和 `herdr agent focus` 指令結尾（在具名工作階段中會加上 `--session`）。這個標示與 [herdr-ids](https://github.com/devicki/herdr-ids) 選擇器輸入的格式相同，採用 Herdr CLI 本身的用語，因此你可以把它貼到另一個代理程式的提示中（「幫我看一下 herdr agent w9:p1 (claude)」），它就知道要用哪個 ID。由於手機 App 只顯示純文字，回覆中的 Markdown 會被轉成純文字。

短暫的狀態變化一律不會送出：代理程式在一輪工作中途暫停，或你在延遲時間內就回答了提示，都不會產生通知。即使 Herdr 重複發出同一事件，每次完成或等待也只會通知一次。

無法連線到伺服器時，通知會保存在外掛的狀態目錄中，等下一則通知成功送達時或下一次代理程式事件發生時重新送出，並標註原定送出的時間。超過一天的通知會被捨棄。

## 架構

```
帳號 A: herdr-pager ─(權杖 A → 主題 a)─┐
帳號 B: herdr-pager ─(權杖 B → 主題 b)─┼─▶ 一台 ntfy 伺服器 ─▶ 你的手機 (一個唯讀使用者，
cron、systemd、腳本 ─(herdr-pager run)─┘                                 訂閱 a 和 b)
```

- 外掛只負責發布通知，不會執行伺服器。任何 ntfy 伺服器都能使用，包括公開的 ntfy.sh（這時通知內容會經過它）。
- 所有機器和帳號只需要一台伺服器：為每個帳號設定各自的主題，以及只能寫入該主題的權杖，再為手機設定一個能讀取所有主題的使用者。

## 安裝

需要 `bash`（3.2 就夠了）、`jq` 1.6 以上版本和 `curl`，支援 Linux 或 macOS。

### 1. ntfy 伺服器（只需一次）

如果已經有伺服器，可以跳過這一步。[`docs/ntfy`](docs/ntfy) 提供一套預設拒絕所有存取的私人設定：

```sh
mkdir -p ~/ntfy && cd ~/ntfy          # 將 docs/ntfy 中的 compose.yml 和 server.yml 複製到這裡
docker compose run --rm ntfy user hash       # 密碼雜湊值：手機用一個，每個發布帳號各一個
docker compose run --rm ntfy token generate  # 權杖：每個發布帳號各一個
# 將雜湊值和權杖填入 server.yml（auth-users、auth-access、auth-tokens）後：
docker compose up -d
curl -s http://127.0.0.1:2586/v1/health      # {"healthy":true}
```

伺服器只在 `127.0.0.1:2586` 上接聽。若要在不對網際網路開放連接埠的情況下，透過 tailnet 從手機連線：

```sh
tailscale serve --bg --https=8446 http://127.0.0.1:2586   # https://<主機>.<tailnet>.ts.net:8446
```

這需要伺服器和手機都安裝 Tailscale 並位於同一個 tailnet，且已開啟 MagicDNS 和 HTTPS 憑證（管理主控台 → DNS）；`tailscale serve` 需以 root 執行，或在執行 `sudo tailscale set --operator=$USER` 後以你的使用者身分執行。`server.yml` 中的 `base-url` 必須與這個位址完全相同。兩者在重新開機後都會保留：容器設有 `restart: unless-stopped`，而 `tailscale serve --bg` 由 tailscaled 保存。之後若要新增帳號，請新增一個發布用使用者、一行 `auth-access` 和一個權杖，然後執行 `docker compose up -d`。

若要在 iOS 上使用，請保留 `upstream-base-url: "https://ntfy.sh"`：iPhone 只能透過 Apple 的服務接收即時推播，而 ntfy 經由這條路徑只會傳送訊息 id 和主題雜湊值；手機會再從你的伺服器取得訊息內容。

### 2. 外掛（每個帳號各裝一次）

```sh
herdr plugin install devicki/herdr-pager --ref v0.9.0
```

安裝後立即生效，不需要重新啟動。第一次執行時，它也會把 `herdr-pager` 指令連結到 `~/.local/bin`，供腳本、cron 和 shell hook 使用。

### 3. 設定

開啟外掛設定目錄中的 `pager.conf`（`herdr plugin config-dir devicki.pager` 會顯示路徑；外掛會在那裡留下一份附註解的範本），並填入：

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
lang = zh-TW
```

`#` 之後為註解，可以獨立成行，也可以接在值後面。請將檔案設為僅限本人存取（`chmod 600`）；權杖不會出現在指令列中。`HERDR_PAGER_URL`、`HERDR_PAGER_TOPIC` 和 `HERDR_PAGER_TOKEN` 會覆寫檔案中的設定。

### 4. 確認

```sh
herdr plugin action invoke devicki.pager.test   # 加入 PATH 後也可以用 `herdr-pager test`
```

### 5. 在手機上訂閱

在 ntfy App（iOS 或 Android）中：點選 **+**，輸入主題，開啟 **Use another server** 並輸入伺服器位址（與 `base-url` 完全相同），然後以你的裝置使用者登入。每個帳號的主題都重複這個步驟；登入資訊是共用的。如果伺服器只在 tailnet 內提供，手機必須開啟 Tailscale 才能取得訊息內容。在筆電上，可以使用同一位址的網頁版 App。

## 指令、腳本與排程工作

```sh
herdr-pager run -- ./research.sh --deep        # 通知成功或失敗，並保留原本的結束代碼
herdr-pager run -q -t "nightly backup" -- ./backup.sh   # -q：只在失敗時通知
some-command | herdr-pager send -p 4 -t "import finished"
```

cron（`herdr-pager` 會自行修正 `PATH`，以找到 `jq` 和 `curl`）：

```
0 3 * * * $HOME/.local/bin/herdr-pager run -q -t "nightly backup" -- /opt/backup/run.sh
```

systemd：[`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service) 會通知任何失敗的單元，並附上其日誌的最後部分。將它複製到 `~/.config/systemd/user/`，並在你想監看的單元中加入 `OnFailure=herdr-pager-failure@%n.service`。標題中要顯示結果和結束狀態，需要 systemd 251 以上版本。

### 不用包裝指令也能通知長時間的 shell 指令

```sh
# ~/.bashrc                                  ~/.zshrc
eval "$(herdr-pager shell-init bash)"        # eval "$(herdr-pager shell-init zsh)"
```

```fish
# ~/.config/fish/config.fish
herdr-pager shell-init fish | source
```

任何執行 `shell_threshold` 秒以上（預設 60 秒）的指令結束時，都會連同結束代碼一起通知。互動式工具和代理程式（`vim`、`less`、`ssh`、`lazygit`、`claude` 等）會被略過；請參考 `shell_skip`。fish 使用 `fish_postexec` 事件，zsh 使用 `preexec`/`precmd` hook；bash 使用 `DEBUG` trap 和 `PROMPT_COMMAND`，因此如果你已經有其他 `DEBUG` trap，它會被取代。

## 設定項目

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `url`、`topic`、`token` | | 發布通知的目的地 |
| `label` | 使用者名稱 | 每個標題的前綴 |
| `lang` | `en` | 通知的語言：`en`、`ko`、`ja` 或 `zh-TW` |
| `done_delay` | 15 | 代理程式須維持完成狀態多少秒後才通知 |
| `blocked_delay` | 10 | 代理程式須持續等待多少秒後才通知 |
| `shell_threshold` | 60 | shell hook：指令的最短執行時間（秒） |
| `shell_skip` | 互動式工具和代理程式 | shell hook：一律不通知的程式，以空格或逗號分隔 |
| `reply_chars` | 500 | 通知中代理程式回覆的最大字元數；超過的部分以 `…` 結尾 |
| `prompt_chars` | 600 | 同上，適用於等待中代理程式的提示 |
| `command_chars` | 300 | 同上，適用於指令列 |
| `error_chars` | 600 | 同上，適用於失敗指令的錯誤輸出 |
| `quiet_hours` | 無（整天） | 勿擾時段，`HH:MM-HH:MM`，例如 `00:00-08:00`；這段時間內不會送出任何通知 |
| `quiet_mode` | `hold` | `hold`：勿擾時段結束時送出暫存的通知；`drop`：直接捨棄 |
| `agent_skip` | 無 | 一律不通知的代理程式，使用 Herdr 顯示的名稱，以空格或逗號分隔：`codex, devin` |

勿擾時段依照這台機器的時鐘（`date`），而不是手機或 ntfy 伺服器的時鐘，並且可以跨越午夜（`23:00-07:00`）。使用 `hold` 時，每則暫存的通知會在時段結束時送出，並標註 `🌙 03:12 的通知 (勿擾時段，延後送達)`；`herdr-pager test` 則一律會送出。

ntfy 會將超過 4096 位元組的訊息轉為附件，而韓文、日文和中文每個字佔 3 個位元組，因此整則訊息請控制在約 1,300 個這類字元以內。

## 注意事項

- **Herdr 本身的通知**：如果 `[ui.toast] delivery` 為 `terminal` 或 `system`，Herdr 也會在你連線使用的筆電上通知你。如果只想收到 herdr-pager 的通知，請將它設為 `herdr` 或 `off`。
- **會送出哪些內容**：代理程式的最後一則回覆和等待中窗格的底部畫面，會離開這台機器傳到你的 ntfy 伺服器。常見的憑證格式（API 金鑰、權杖、`password=` 的值）會被遮蔽，每個部分也會被截斷為幾百個字元（請參考 `reply_chars` 等設定），但仍請避免讓代理程式輸出機密資訊。
- **以文字提出的問題**：代理程式若在回覆中提問，而沒有跳出權限提示，會被視為完成，而不是等待。無論哪一種，回覆內容都會包含在通知中。
- **代理程式**：Herdr 追蹤的任何代理程式都能使用。最後一則回覆是從 Claude Code 和 Codex 的對話紀錄中讀取；其他代理程式只會顯示工作階段標題。Claude 的 agent view（`claude agents`）沒有自己的工作階段，因此它的通知會改為顯示剛完成的背景工作階段名稱及該工作階段的回覆。
- Herdr 的事件 hook 沒有逾時限制，因此延遲檢查會以分離的方式執行。每次發布嘗試的上限為 10 秒；遇到逾時或伺服器錯誤時會重試兩次，因此一次傳送約 35 秒後就會放棄並排入佇列。

## 更新與解除安裝

Herdr 沒有更新指令；請以新的標籤重新安裝。重新安裝後，`pager.conf` 和啟用狀態都會保留。

```sh
herdr plugin install devicki/herdr-pager --ref v0.9.0 --yes
herdr plugin uninstall devicki.pager
```

解除安裝後，設定目錄中的 `pager.conf` 和 `~/.local/bin/herdr-pager` 連結仍會保留；如果不再重新安裝，請將它們連同 shell hook 那一行一起刪除。ntfy 伺服器要保留或停止由你決定（`docker compose down`、`tailscale serve --https=8446 off`）。

## 開發

```sh
herdr plugin link .
./test.sh   # 用隔離的 Herdr 和替代用的 ntfy 測試完成、短暫狀態變化、等待、指令、shell hook 篩選、機密遮蔽、重送佇列、Claude 的 agent view、勿擾時段、agent_skip
```

發布新版本時，請更新 `herdr-plugin.toml` 中的 `version`，修改所有 README 中的 `--ref`，提交後執行 `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`。

## 授權條款

MIT
