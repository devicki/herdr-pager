# herdr-pager

[English](README.md) | 한국어

[Herdr](https://herdr.dev)의 에이전트가 작업을 마치거나 내 답을 기다릴 때, 그리고 명령·스크립트·예약 작업이 끝났을 때 폰이나 노트북으로 알림을 보내 주는 플러그인이에요. 알림마다 무슨 일이 있었는지, 어느 페인에서 일어났는지, 그리고 그 페인으로 돌아가는 명령까지 담겨요. 전송은 [ntfy](https://ntfy.sh)로 하고, 직접 호스팅하는 서버를 쓰는 걸 권해요.

```
✅ [bot] claude 작업 완료 · shop-api
📂 1 · agent › Add refresh-token rotation
💬 Rotation is in. Tests pass; the diff is on the right.
⏱ 4분 12초  📍 w9:p1
↩ herdr agent focus w9:p1

🙋 [bot] claude 확인 필요 · shop-api                    (높은 우선순위)
📂 1 · agent › Add refresh-token rotation
❓ Bash(rm -rf build)
   Do you want to proceed?
📍 w9:p1  ↩ herdr agent focus w9:p1

❌ [bot] backup.sh 실패 (종료 코드 7)                   (높은 우선순위)
💻 ./backup.sh --full
⏱ 12분 3초  📁 ~/ops
```

위 예시는 설정에 `lang = ko`를 넣었을 때의 모습이에요. 기본값은 영어예요. 제목 앞의 이모지는 알림의 ntfy 태그를 앱이 그렇게 보여 주는 거예요.

## 알려 주는 것

| 상황 | 조건 | 우선순위 | 내용 |
| --- | --- | --- | --- |
| 에이전트 작업 완료 | 작업 중이던 에이전트가 idle(또는 `done`)이 되고 `done_delay`초 동안 그대로일 때 | 3 | 세션 제목, 에이전트의 마지막 답변(Claude Code·Codex 대화 기록), 걸린 시간, 페인 |
| 에이전트가 답을 기다림 | `blocked` 상태가 `blocked_delay`초 동안 이어질 때. 같은 대기에는 한 번만 | 4 | 페인 아래쪽에 뜬 질문, 페인 |
| 명령 종료 | `herdr-pager run -- 명령`, 또는 셸 훅을 켰을 때 `shell_threshold`초 넘게 걸린 명령 | 3, 실패하면 4 | 명령줄, 종료 코드, 걸린 시간, 호스트와 폴더, 페인. `run`이 실패하면 에러 출력의 마지막 몇 줄도 |
| 그 밖의 알림 | cron, systemd, CI 등에서 `herdr-pager send` | 원하는 대로 | 내 메시지 |

모든 제목은 `label`(기본값: 사용자 이름)로 시작해서, 여러 머신이나 계정의 알림이 한 목록에 섞여도 구분돼요. 잠금 화면에서 읽기 좋게 제목은 짧게(에이전트와 워크스페이스) 두고, 본문은 탭과 세션 제목으로 시작해 페인 id와 `herdr agent focus` 명령으로 끝나요(named session에서는 `--session`이 붙어요). 폰 앱은 일반 텍스트로 보여 주기 때문에 답변의 Markdown 강조는 풀어서 보내요.

짧은 깜빡임은 보내지 않아요. 에이전트가 턴 중간에 잠깐 멈추거나 대기 시간 안에 바로 답한 경우에는 알림이 가지 않아요. Herdr가 같은 이벤트를 여러 번 보내도 한 번의 완료나 대기는 한 번만 알려요.

서버에 연결할 수 없으면 알림을 플러그인 상태 폴더에 보관했다가, 다음 알림이 전달될 때나 다음 에이전트 이벤트 때 원래 보내려던 시각을 붙여 다시 보내요. 하루가 지난 알림은 버려요.

## 구성

```
계정 A: herdr-pager ─(토큰 A → 채널 a)─┐
계정 B: herdr-pager ─(토큰 B → 채널 b)─┼─▶ ntfy 서버 하나 ─▶ 내 폰 (읽기 전용 사용자 하나로
cron, systemd, 스크립트 ─(herdr-pager run)┘                     채널 a, b 구독)
```

- 플러그인은 알림을 보내기만 하고 서버를 띄우지 않아요. 공개 서버인 ntfy.sh를 포함해 어떤 ntfy 서버든 쓸 수 있어요(ntfy.sh를 쓰면 알림 내용이 그 서버를 거쳐요).
- 머신이나 계정이 여러 개여도 서버는 하나면 돼요. 계정마다 채널 하나와 그 채널에만 쓸 수 있는 토큰을 주고, 폰에는 모든 채널을 읽을 수 있는 사용자 하나를 주면 돼요.

## 설치

Linux와 macOS에서 동작하고 `bash`(3.2로 충분해요), `jq` 1.6 이상, `curl`이 필요해요.

### 1. ntfy 서버 (한 번만)

이미 서버가 있다면 건너뛰세요. [`docs/ntfy`](docs/ntfy)에 기본으로 모두 막아 둔 개인 서버 설정이 있어요.

```sh
mkdir -p ~/ntfy && cd ~/ntfy          # docs/ntfy의 compose.yml, server.yml을 여기로 복사
docker compose run --rm ntfy user hash       # 비밀번호 해시: 폰용 하나, 알림 보낼 계정마다 하나
docker compose run --rm ntfy token generate  # 토큰: 알림 보낼 계정마다 하나
# 해시와 토큰을 server.yml(auth-users, auth-access, auth-tokens)에 넣은 뒤:
docker compose up -d
curl -s http://127.0.0.1:2586/v1/health      # {"healthy":true}
```

서버는 `127.0.0.1:2586`에서만 요청을 받아요. 인터넷에 포트를 열지 않고 tailnet으로 폰에서 접속하려면:

```sh
tailscale serve --bg --https=8446 http://127.0.0.1:2586   # https://<호스트>.<tailnet>.ts.net:8446
```

서버와 폰 모두 같은 tailnet에 Tailscale이 설치돼 있어야 하고, 관리 콘솔(DNS 메뉴)에서 MagicDNS와 HTTPS 인증서가 켜져 있어야 해요. `tailscale serve`는 root로 실행하거나, `sudo tailscale set --operator=$USER`로 내 계정에 권한을 준 뒤 실행하세요. `server.yml`의 `base-url`은 이 주소와 정확히 같아야 해요. 둘 다 재부팅해도 유지돼요. 컨테이너는 `restart: unless-stopped`이고, `tailscale serve --bg` 설정은 tailscaled가 보관해요. 나중에 계정을 추가하려면 알림 보낼 사용자, `auth-access` 한 줄, 토큰을 추가하고 `docker compose up -d`를 실행하세요.

iOS에서 쓰려면 `upstream-base-url: "https://ntfy.sh"`를 유지하세요. 아이폰은 Apple 푸시로만 즉시 알림을 받는데, 이 경로로 나가는 건 메시지 id와 채널 해시뿐이에요. 본문은 아이폰이 내 서버에서 직접 가져와요.

### 2. 플러그인 (계정마다)

```sh
herdr plugin install devicki/herdr-pager --ref v0.4.0
```

설치하면 바로 동작해요. 재시작할 필요 없어요. 처음 실행될 때 스크립트, cron, 셸 훅에서 쓸 수 있게 `herdr-pager` 명령을 `~/.local/bin`에 연결해 둬요.

### 3. 설정

플러그인 설정 폴더(`herdr plugin config-dir devicki.pager`로 확인)의 `pager.conf`를 열어 채우세요. 플러그인이 주석 달린 템플릿을 만들어 둬요.

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
lang = ko
```

`#` 뒤는 주석이에요. 한 줄 전체로 써도 되고 값 뒤에 붙여도 돼요. 파일은 본인만 읽게(`chmod 600`) 두세요. 토큰은 명령줄에 드러나지 않게 전달돼요. 환경 변수 `HERDR_PAGER_URL`, `HERDR_PAGER_TOPIC`, `HERDR_PAGER_TOKEN`이 있으면 파일보다 우선해요.

### 4. 확인

```sh
herdr plugin action invoke devicki.pager.test   # PATH에 연결된 뒤에는 `herdr-pager test`도 돼요
```

### 5. 폰에서 구독

ntfy 앱(iOS, Android)에서 **+**를 누르고 채널 이름을 입력한 뒤, **다른 서버 사용(Use another server)**을 켜고 서버 주소(`base-url`과 똑같이)를 넣고 기기용 사용자로 로그인하세요. 계정마다 채널을 같은 방법으로 추가하면 되고, 로그인은 한 번이면 돼요. tailnet 전용 서버라면 폰의 Tailscale이 켜져 있어야 알림 내용을 가져와요. 노트북에서는 같은 주소의 웹 앱을 쓰면 돼요.

## 명령, 스크립트, 예약 작업

```sh
herdr-pager run -- ./research.sh --deep        # 성공·실패를 알리고 종료 코드는 그대로 돌려줘요
herdr-pager run -q -t "nightly backup" -- ./backup.sh   # -q: 실패할 때만 알림
some-command | herdr-pager send -p 4 -t "import finished"
```

cron에서도 그대로 써요(`jq`, `curl`을 찾도록 `herdr-pager`가 `PATH`를 직접 보완해요).

```
0 3 * * * $HOME/.local/bin/herdr-pager run -q -t "nightly backup" -- /opt/backup/run.sh
```

systemd: [`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service)는 실패한 유닛을 로그 끝부분과 함께 알려 줘요. `~/.config/systemd/user/`에 복사하고, 지켜볼 유닛에 `OnFailure=herdr-pager-failure@%n.service`를 추가하세요. 제목에 실패 이유와 종료 코드가 나오려면 systemd 251 이상이 필요해요.

### 래퍼 없이 오래 걸린 셸 명령 알림

```sh
# ~/.bashrc                                  ~/.zshrc
eval "$(herdr-pager shell-init bash)"        # eval "$(herdr-pager shell-init zsh)"
```

```fish
# ~/.config/fish/config.fish
herdr-pager shell-init fish | source
```

`shell_threshold`초(기본 60초) 넘게 걸린 명령이 끝나면 종료 코드와 함께 알려 줘요. 대화형 도구와 에이전트(`vim`, `less`, `ssh`, `lazygit`, `claude` 등)는 제외해요. `shell_skip`에서 바꿀 수 있어요. fish는 `fish_postexec` 이벤트, zsh는 `preexec`/`precmd` 훅을 써요. bash용 훅은 `DEBUG` trap과 `PROMPT_COMMAND`를 써서, 이미 다른 `DEBUG` trap을 쓰고 있다면 대체돼요.

## 설정 항목

| 키 | 기본값 | 의미 |
| --- | --- | --- |
| `url`, `topic`, `token` | | 알림을 보낼 곳 |
| `label` | 사용자 이름 | 모든 제목 앞에 붙는 이름 |
| `lang` | `en` | 알림 언어: `en` 또는 `ko` |
| `done_delay` | 15 | 완료 상태가 이 시간(초) 동안 이어져야 알림 |
| `blocked_delay` | 10 | 대기 상태가 이 시간(초) 동안 이어져야 알림 |
| `shell_threshold` | 60 | 셸 훅: 알릴 최소 실행 시간(초) |
| `shell_skip` | 대화형 도구와 에이전트 | 셸 훅: 알리지 않을 프로그램 |

## 참고

- **Herdr 자체 알림:** `[ui.toast] delivery`가 `terminal`이나 `system`이면 Herdr도 접속한 노트북에 알림을 띄워요. herdr-pager 알림만 받고 싶다면 `herdr`나 `off`로 바꾸세요.
- **밖으로 나가는 내용:** 에이전트의 마지막 답변과 대기 중인 페인의 아래쪽 화면이 ntfy 서버로 가요. 흔한 인증 정보 형태(API 키, 토큰, `password=` 값)는 가리고 몇백 자로 자르지만, 에이전트가 비밀값을 출력하지 않게 주의하세요.
- **글로 된 질문:** 권한 창 없이 답변 속에서 질문하면 "대기"가 아니라 "완료"로 알려요. 어느 쪽이든 답변 내용은 알림에 들어 있어요.
- **에이전트 종류:** Herdr가 추적하는 에이전트는 모두 알려요. 마지막 답변은 Claude Code와 Codex 대화 기록에서 읽고, 다른 에이전트는 세션 제목만 보여요.
- Herdr의 이벤트 훅에는 타임아웃이 없어서, 지연 확인은 분리된 프로세스로 돌려요. 전송 시도 한 번은 10초로 제한하고, 시간 초과나 서버 오류일 때 두 번 다시 시도해서 최대 35초쯤 뒤에 포기하고 보관해 둬요.

## 업데이트와 삭제

Herdr에는 업데이트 명령이 없어서, 새 태그로 다시 설치하면 돼요. 다시 설치해도 `pager.conf`와 켜짐/꺼짐 상태는 그대로 남아요.

```sh
herdr plugin install devicki/herdr-pager --ref v0.4.0 --yes
herdr plugin uninstall devicki.pager
```

삭제해도 설정 폴더의 `pager.conf`와 `~/.local/bin/herdr-pager` 링크는 남아요. 다시 설치하지 않을 거라면 셸 훅 줄과 함께 지우세요. ntfy 서버는 따로 두거나 멈추면 돼요(`docker compose down`, `tailscale serve --https=8446 off`).

## 개발

```sh
herdr plugin link .
./test.sh   # 격리된 Herdr와 가짜 ntfy로 완료, 깜빡임, 대기, 명령, 셸 훅 필터, 비밀값 가림, 재전송 대기열을 확인해요
```

릴리스할 때는 `herdr-plugin.toml`의 `version`을 올리고, 두 README의 `--ref`를 바꿔 커밋한 뒤 `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`를 실행하세요.

## 라이선스

MIT
