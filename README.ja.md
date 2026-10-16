# herdr-pager

[English](README.md) | [한국어](README.ko.md) | 日本語 | [繁體中文](README.zh-TW.md)

[Herdr](https://herdr.dev) のエージェントが作業を終えたときや返答を待っているとき、またコマンド・スクリプト・定期ジョブが終わったときに、スマートフォンやノートPCへプッシュ通知を送るプラグインです。通知には、何が起きたか、どのペインからか、そしてそのペインに戻るためのコマンドが含まれます。配信には [ntfy](https://ntfy.sh) を使い、自分でホストするサーバーをおすすめします。

```
✅ [bot] claude 作業完了 · shop-api
📂 1 · agent › Add refresh-token rotation
💬 Rotation is in. Tests pass; the diff is on the right.
⏱ 4分12秒  📍 herdr agent w9:p1 (claude)
↩ herdr agent focus w9:p1

🙋 [bot] claude 確認が必要 · shop-api                  (優先度: 高)
📂 1 · agent › Add refresh-token rotation
❓ Bash(rm -rf build)
   Do you want to proceed?
📍 herdr agent w9:p1 (claude)
↩ herdr agent focus w9:p1

❌ [bot] backup.sh 失敗 (終了コード 7)                 (優先度: 高)
💻 ./backup.sh --full
⏱ 12分3秒  📁 ~/ops
```

上の例は設定に `lang = ja` を指定したときの表示です。デフォルトは英語で、`ko` で韓国語、`zh-TW` で繁体字中国語になります。タイトルの先頭の絵文字は通知の ntfy タグで、アプリがそのように表示します。

## 通知する内容

| イベント | 条件 | 優先度 | 内容 |
| --- | --- | --- | --- |
| エージェントの作業完了 | 作業中のエージェントが idle(または `done`)になり、`done_delay` 秒間その状態が続いたとき。前回の通知以降に新しい返答がある場合のみ(Claude Code、Codex) | 3 | セッションタイトル、エージェントの最後の返答(Claude Code と Codex の会話記録)、所要時間、ペイン |
| エージェントが返答待ち | エージェントが `blocked_delay` 秒間 `blocked` のままのとき。1 回の待機につき 1 回だけ | 4 | ペイン下部に表示された質問、ペイン |
| コマンド終了 | `herdr-pager run -- CMD`、またはシェルフックを有効にしたときの `shell_threshold` 秒を超えたコマンド | 3、失敗時は 4 | コマンドライン、終了コード、所要時間、ホストとディレクトリ、ペイン。`run` が失敗した場合はエラー出力の最後の数行も |
| その他 | cron、systemd、CI などからの `herdr-pager send` | 任意 | 自分のメッセージ |

すべてのタイトルは `label`(デフォルト: ユーザー名)で始まるので、複数のマシンやアカウントの通知が 1 つの一覧に並んでも区別できます。ロック画面で読みやすいようにタイトルは短く(エージェントとワークスペース)、本文はタブとセッションタイトルで始まり、`herdr agent <id> (<agent>)` 形式のペイン表記(エージェントのいないペインは `herdr pane`)と `herdr agent focus` コマンドで終わります(名前付きセッションでは `--session` が付きます)。この表記は [herdr-ids](https://github.com/devicki/herdr-ids) のピッカーが入力する形式と同じで、Herdr CLI の用語そのままなので、別のエージェントのプロンプトに貼り付ければ(「herdr agent w9:p1 (claude) を確認して」)どの ID を使えばよいかすぐに伝わります。スマートフォンのアプリはプレーンテキストで表示するため、返答内の Markdown は平文にして送ります。

短い瞬間的な変化は通知しません。エージェントがターンの途中で一時停止した場合や、待機時間内にすぐ答えたプロンプトでは何も送られません。Herdr が同じイベントを繰り返し送っても、1 回の完了や待機は 1 回だけ通知します。

サーバーに接続できないときは、通知をプラグインの状態ディレクトリに保存しておき、次に届いた通知と一緒に、または次のエージェントイベントのときに、本来送るはずだった時刻を付けて再送します。1 日以上前の通知は破棄します。

## 構成

```
アカウント A: herdr-pager ─(トークン A → トピック a)─┐
アカウント B: herdr-pager ─(トークン B → トピック b)─┼─▶ ntfy サーバー 1 つ ─▶ スマートフォン (読み取り専用ユーザー 1 人で
cron, systemd, スクリプト ─(herdr-pager run)─────────┘                                         トピック a, b を購読)
```

- プラグインは通知を送るだけで、サーバーは動かしません。公開サーバーの ntfy.sh を含め、どの ntfy サーバーでも使えます(ntfy.sh を使う場合、通知の内容はそのサーバーを経由します)。
- マシンやアカウントがいくつあっても、サーバーは 1 つで十分です。アカウントごとに専用のトピックと、そのトピックにだけ書き込めるトークンを用意し、スマートフォンにはすべてのトピックを読めるユーザーを 1 つ用意します。

## インストール

Linux または macOS で、`bash`(3.2 で十分です)、`jq` 1.6 以降、`curl` が必要です。

### 1. ntfy サーバー(最初に 1 回だけ)

すでにサーバーがある場合は飛ばしてください。[`docs/ntfy`](docs/ntfy) に、デフォルトですべてを拒否する個人用の設定があります。

```sh
mkdir -p ~/ntfy && cd ~/ntfy          # docs/ntfy の compose.yml と server.yml をここにコピー
docker compose run --rm ntfy user hash       # パスワードのハッシュ: スマートフォン用に 1 つ、送信するアカウントごとに 1 つ
docker compose run --rm ntfy token generate  # トークン: 送信するアカウントごとに 1 つ
# ハッシュとトークンを server.yml (auth-users, auth-access, auth-tokens) に書いてから:
docker compose up -d
curl -s http://127.0.0.1:2586/v1/health      # {"healthy":true}
```

サーバーは `127.0.0.1:2586` でのみ待ち受けます。インターネットにポートを開けずに、tailnet 経由でスマートフォンから接続するには次のようにします。

```sh
tailscale serve --bg --https=8446 http://127.0.0.1:2586   # https://<ホスト>.<tailnet>.ts.net:8446
```

サーバーとスマートフォンの両方に Tailscale が入っていて同じ tailnet にあり、MagicDNS と HTTPS 証明書が有効になっている必要があります(管理コンソール → DNS)。`tailscale serve` は root で実行するか、`sudo tailscale set --operator=$USER` を実行したあと自分のユーザーで実行します。`server.yml` の `base-url` はこのアドレスと完全に一致させてください。どちらも再起動後も維持されます。コンテナは `restart: unless-stopped` で、`tailscale serve --bg` の設定は tailscaled が保持します。あとからアカウントを追加するには、送信用ユーザー、`auth-access` の行、トークンを追加して `docker compose up -d` を実行します。

iOS で使う場合は `upstream-base-url: "https://ntfy.sh"` をそのまま残してください。iPhone は Apple のサービス経由でしか即時プッシュを受け取れず、ntfy がその経路で送るのはメッセージ ID とトピックのハッシュだけです。本文は iPhone が自分のサーバーから取得します。

### 2. プラグイン(アカウントごと)

```sh
herdr plugin install devicki/herdr-pager --ref v0.9.0
```

インストールするとすぐに動作し、再起動は不要です。初回の実行時に、スクリプト、cron、シェルフックから使えるよう `herdr-pager` コマンドを `~/.local/bin` にリンクします。

### 3. 設定

プラグインの設定ディレクトリ(`herdr plugin config-dir devicki.pager` で表示されます。プラグインがコメント付きのテンプレートを置いておきます)にある `pager.conf` を開いて、次のように記入します。

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
lang = ja
```

`#` 以降はコメントです。1 行まるごとでも、値の後ろでも使えます。ファイルは自分だけが読めるようにしてください(`chmod 600`)。トークンがコマンドラインに現れることはありません。`HERDR_PAGER_URL`、`HERDR_PAGER_TOPIC`、`HERDR_PAGER_TOKEN` を設定すると、ファイルの値より優先されます。

### 4. 動作確認

```sh
herdr plugin action invoke devicki.pager.test   # PATH にリンクされたあとは `herdr-pager test` でも可
```

### 5. スマートフォンで購読

ntfy アプリ(iOS または Android)で **+** をタップしてトピックを入力し、**Use another server** をオンにしてサーバーのアドレス(`base-url` と完全に同じもの)を入力したら、端末用のユーザーでログインします。アカウントごとのトピックも同じ手順で追加します。ログインは共通です。tailnet 内だけのサーバーの場合、スマートフォンが通知の内容を取得するには Tailscale がオンになっている必要があります。ノートPCでは同じアドレスの Web アプリが使えます。

## コマンド、スクリプト、定期ジョブ

```sh
herdr-pager run -- ./research.sh --deep        # 成功・失敗を通知し、終了コードはそのまま返します
herdr-pager run -q -t "nightly backup" -- ./backup.sh   # -q: 失敗したときだけ通知
some-command | herdr-pager send -p 4 -t "import finished"
```

cron(`herdr-pager` が `jq` と `curl` のために `PATH` を自分で補います):

```
0 3 * * * $HOME/.local/bin/herdr-pager run -q -t "nightly backup" -- /opt/backup/run.sh
```

systemd: [`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service) は、失敗したユニットをログの末尾と一緒に通知します。`~/.config/systemd/user/` にコピーし、対象のユニットに `OnFailure=herdr-pager-failure@%n.service` を追加してください。タイトルに結果と終了ステータスを表示するには systemd 251 以降が必要です。

### ラッパーなしで長いシェルコマンドを通知

```sh
# ~/.bashrc                                  ~/.zshrc
eval "$(herdr-pager shell-init bash)"        # eval "$(herdr-pager shell-init zsh)"
```

```fish
# ~/.config/fish/config.fish
herdr-pager shell-init fish | source
```

`shell_threshold` 秒(デフォルト 60)以上かかったコマンドは、終了時に終了コードと一緒に通知します。対話型ツールやエージェント(`vim`、`less`、`ssh`、`lazygit`、`claude` など)は除外されます。`shell_skip` を参照してください。fish は `fish_postexec` イベント、zsh は `preexec`/`precmd` フックを使います。bash は `DEBUG` トラップと `PROMPT_COMMAND` を使うため、ほかに `DEBUG` トラップを設定している場合は置き換えられます。

## 設定項目

| キー | デフォルト | 意味 |
| --- | --- | --- |
| `url`, `topic`, `token` | | 通知の送信先 |
| `label` | ユーザー名 | すべてのタイトルの先頭に付く名前 |
| `lang` | `en` | 通知の言語: `en`、`ko`、`ja`、`zh-TW` |
| `done_delay` | 15 | エージェントの完了状態がこの秒数続いたら通知 |
| `blocked_delay` | 10 | エージェントの待機状態がこの秒数続いたら通知 |
| `shell_threshold` | 60 | シェルフック: 通知するコマンドの最短実行時間(秒) |
| `shell_skip` | 対話型ツールとエージェント | シェルフック: 通知しないプログラム。スペースまたはカンマ区切り |
| `reply_chars` | 500 | 通知に含めるエージェントの返答の最大文字数。超えた分は `…` で切ります |
| `prompt_chars` | 600 | 同様に、返答待ちのエージェントの質問 |
| `command_chars` | 300 | 同様に、コマンドライン |
| `error_chars` | 600 | 同様に、失敗したコマンドのエラー出力 |
| `quiet_hours` | なし(終日通知) | おやすみ時間。`00:00-08:00` のように `HH:MM-HH:MM` で指定します。この時間帯は何も送りません |
| `quiet_mode` | `hold` | `hold`: おやすみ時間が終わったら、保留した通知を送ります。`drop`: 破棄します |
| `agent_skip` | なし | 通知しないエージェント。Herdr が表示する名前をスペースまたはカンマ区切りで指定します: `codex, devin` |

おやすみ時間は、スマートフォンや ntfy サーバーではなく、このマシンの時計(`date`)に従い、日付をまたいでもかまいません(`23:00-07:00`)。`hold` の場合、保留された通知はおやすみ時間が終わると `🌙 03:12 の通知です (おやすみ時間のため遅れて配信)` という表示付きで送られます。`herdr-pager test` は常に送られます。

ntfy は 4096 バイトを超えるメッセージを添付ファイルに変換し、日本語・韓国語・中国語は 1 文字 3 バイトなので、メッセージ全体をこれらの文字で 1,300 字程度以内に収めてください。

## 補足

- **Herdr 自体の通知**: `[ui.toast] delivery` が `terminal` または `system` の場合、Herdr も接続元のノートPCに通知を出します。herdr-pager の通知だけを受け取りたい場合は `herdr` または `off` に設定してください。
- **送信される内容**: エージェントの最後の返答と、待機中のペインの下部が、マシンから ntfy サーバーへ送られます。よくある認証情報の形式(API キー、トークン、`password=` の値)はマスクされ、各部分は数百文字に切り詰められますが(`reply_chars` などを参照)、エージェントが秘密情報を出力しないよう注意してください。
- **テキストでの質問**: 権限プロンプトを出さずに返答の中で質問したエージェントは、待機ではなく完了として扱われます。どちらの場合も返答は通知に含まれます。
- **エージェント**: Herdr が追跡するエージェントであれば、どれでも使えます。最後の返答は Claude Code と Codex の会話記録から読み取り、ほかのエージェントはセッションタイトルだけになります。Claude のエージェントビュー(`claude agents`)は自身のセッションを持たないため、その通知には、終了したばかりのバックグラウンドセッションの名前とその返答が入ります。
- Herdr のイベントフックにはタイムアウトがないため、遅延チェックは切り離されたプロセスで実行します。送信 1 回あたりの上限は 10 秒で、タイムアウトやサーバーエラーの場合は 2 回再試行するため、約 35 秒で送信をあきらめてキューに入れます。

## アップデートとアンインストール

Herdr にはアップデートコマンドがないため、新しいタグで再インストールします。`pager.conf` と有効/無効の状態は再インストール後も残ります。

```sh
herdr plugin install devicki/herdr-pager --ref v0.9.0 --yes
herdr plugin uninstall devicki.pager
```

アンインストールしても、設定ディレクトリの `pager.conf` と `~/.local/bin/herdr-pager` のリンクは残ります。再インストールしない場合は、シェルフックの行と一緒に削除してください。ntfy サーバーは残しておくことも、停止することもできます(`docker compose down`、`tailscale serve --https=8446 off`)。

## 開発

```sh
herdr plugin link .
./test.sh   # 隔離した Herdr と代替の ntfy で、完了、瞬間的な変化、待機、コマンド、シェルフックのフィルター、マスク、再送キュー、Claude のエージェントビュー、おやすみ時間、agent_skip を確認します
```

リリースするときは、`herdr-plugin.toml` の `version` を上げ、すべての README の `--ref` を更新してコミットしてから、`git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z` を実行します。

## ライセンス

MIT
