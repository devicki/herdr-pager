# herdr-pager

[English](README.md) | 한국어

[Herdr](https://herdr.dev)의 에이전트가 작업을 마치거나 내 답을 기다릴 때, 그리고 명령·스크립트·예약 작업이 끝났을 때 폰이나 노트북으로 알림을 보내 주는 플러그인이에요. 알림마다 무슨 일이 있었는지, 어느 페인에서 일어났는지, 그리고 그 페인으로 돌아가는 명령까지 담겨요. 전송은 [ntfy](https://ntfy.sh)로 하고, 직접 호스팅하는 서버를 쓰는 걸 권해요.

```
[bot] claude done · shop-api
1 · agent › Add refresh-token rotation
Rotation is in. Tests pass; the diff is on the right.
⏱ 4m12s · w9:p1
↩ herdr agent focus w9:p1

[bot] claude needs you · shop-api          (높은 우선순위)
1 · agent › Add refresh-token rotation
Bash(rm -rf build)
Do you want to proceed?
❯ 1. Yes
  2. No
⏳ waiting for you · w9:p1

[bot] ✗ backup.sh failed (exit 7)                    (높은 우선순위)
$ ./backup.sh --full
⏱ 12m03s · isle-server:~/ops
```

## 알려 주는 것

| 상황 | 조건 | 우선순위 | 내용 |
| --- | --- | --- | --- |
| 에이전트 작업 완료 | 작업 중이던 에이전트가 idle(또는 `done`)이 되고 `done_delay`초 동안 그대로일 때 | 3 | 세션 제목, 에이전트의 마지막 답변(Claude Code·Codex 대화 기록), 걸린 시간, 페인 |
| 에이전트가 답을 기다림 | `blocked` 상태가 `blocked_delay`초 동안 이어질 때. 같은 대기에는 한 번만 | 4 | 페인 아래쪽에 뜬 질문, 페인 |
| 명령 종료 | `herdr-pager run -- 명령`, 또는 셸 훅을 켰을 때 `shell_threshold`초 넘게 걸린 명령 | 3, 실패하면 4 | 명령줄, 종료 코드, 걸린 시간, 호스트와 폴더, 페인 |
| 그 밖의 알림 | cron, systemd, CI 등에서 `herdr-pager send` | 원하는 대로 | 내 메시지 |

모든 제목은 `label`(기본값: 사용자 이름)로 시작해서, 여러 머신이나 계정의 알림이 한 목록에 섞여도 구분돼요. 잠금 화면에서 읽기 좋게 제목은 짧게(에이전트와 워크스페이스) 두고, 본문은 탭과 세션 제목으로 시작해 페인 id와 `herdr agent focus` 명령으로 끝나요. 폰 앱은 일반 텍스트로 보여 주기 때문에 답변의 Markdown 강조는 풀어서 보내요.

짧은 깜빡임은 보내지 않아요. 에이전트가 턴 중간에 잠깐 멈추거나 대기 시간 안에 바로 답한 경우에는 알림이 가지 않아요. Herdr가 같은 이벤트를 여러 번 보내도 한 번의 완료나 대기는 한 번만 알려요.

## 설치

```sh
herdr plugin install devicki/herdr-pager --ref v0.1.0
```

Linux와 macOS에서 동작하고 `bash`(3.2로 충분해요), `jq`, `curl`이 필요해요. 알림을 받고 싶은 계정마다 설치하세요. 스크립트, cron, 셸 훅에서 쓸 수 있게 `herdr-pager` 명령을 `~/.local/bin`에 연결해 둬요.

### 1. ntfy 서버와 토큰

어떤 ntfy 서버든 되고 ntfy.sh도 돼요. 개인 서버를 쓴다면 [`docs/ntfy`](docs/ntfy)에 compose 파일과 서버 설정 예시가 있어요. 기본으로 모두 막아 두고, 발행하는 쪽은 자기 토픽에만 쓰고, 내 기기는 읽기만 하게 설정돼 있어요. tailnet이라면 `tailscale serve --bg --https=8446 http://127.0.0.1:2586`으로 인터넷에 포트를 열지 않고 HTTPS로 쓸 수 있어요.

iOS에서 쓰려면 `upstream-base-url: "https://ntfy.sh"`를 유지하세요. 아이폰은 Apple 푸시로만 즉시 알림을 받는데, 이 경로로 나가는 건 메시지 id와 토픽 해시뿐이에요. 본문은 아이폰이 내 서버에서 직접 가져와요.

### 2. 설정

플러그인이 처음 실행될 때 `$(herdr plugin config-dir devicki.pager)/pager.conf`에 주석이 달린 템플릿을 만들어 둬요. 이렇게 채우세요.

```
url = https://your-host.your-tailnet.ts.net:8446
topic = work
token = tk_...
label = work
```

파일 권한은 본인만 읽게(`chmod 600`) 두세요. 토큰은 명령줄에 드러나지 않게 전달돼요. 환경 변수 `HERDR_PAGER_URL`, `HERDR_PAGER_TOPIC`, `HERDR_PAGER_TOKEN`이 있으면 파일보다 우선해요.

### 3. 확인

```sh
herdr-pager test
```

### 4. 구독

ntfy 앱(iOS, Android)이나 웹 앱에서 `base-url`과 똑같은 주소로 서버를 추가하고, 기기용 사용자로 로그인한 뒤 토픽을 구독하세요.

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

systemd: [`docs/systemd/herdr-pager-failure@.service`](docs/systemd/herdr-pager-failure@.service)는 실패한 유닛을 로그 끝부분과 함께 알려 줘요. `~/.config/systemd/user/`에 복사하고, 지켜볼 유닛에 `OnFailure=herdr-pager-failure@%n.service`를 추가하세요.

### 래퍼 없이 오래 걸린 셸 명령 알림

```sh
# ~/.bashrc 또는 ~/.zshrc
eval "$(herdr-pager shell-init bash)"   # zsh라면 zsh
```

`shell_threshold`초(기본 60초) 넘게 걸린 명령이 끝나면 종료 코드와 함께 알려 줘요. 대화형 도구와 에이전트(`vim`, `less`, `ssh`, `lazygit`, `claude` 등)는 제외해요. `shell_skip`에서 바꿀 수 있어요. bash용 훅은 `DEBUG` trap과 `PROMPT_COMMAND`를 써서, 이미 다른 `DEBUG` trap을 쓰고 있다면 대체돼요.

## 설정 항목

| 키 | 기본값 | 의미 |
| --- | --- | --- |
| `url`, `topic`, `token` | | 알림을 보낼 곳 |
| `label` | 사용자 이름 | 모든 제목 앞에 붙는 이름 |
| `done_delay` | 15 | 완료 상태가 이 시간(초) 동안 이어져야 알림 |
| `blocked_delay` | 10 | 대기 상태가 이 시간(초) 동안 이어져야 알림 |
| `shell_threshold` | 60 | 셸 훅: 알릴 최소 실행 시간(초) |
| `shell_skip` | 대화형 도구와 에이전트 | 셸 훅: 알리지 않을 프로그램 |

## 참고

- **Herdr 자체 알림:** `[ui.toast] delivery`가 `terminal`이나 `system`이면 Herdr도 접속한 노트북에 알림을 띄워요. herdr-pager 알림만 받고 싶다면 `herdr`나 `off`로 바꾸세요.
- **밖으로 나가는 내용:** 에이전트의 마지막 답변과 대기 중인 페인의 아래쪽 화면이 ntfy 서버로 가요. 흔한 인증 정보 형태(API 키, 토큰, `password=` 값)는 가리고 몇백 자로 자르지만, 에이전트가 비밀값을 출력하지 않게 주의하세요.
- **글로 된 질문:** 권한 창 없이 답변 속에서 질문하면 "대기"가 아니라 "완료"로 알려요. 어느 쪽이든 답변 내용은 알림에 들어 있어요.
- **에이전트 종류:** Herdr가 추적하는 에이전트는 모두 알려요. 마지막 답변은 Claude Code와 Codex 대화 기록에서 읽고, 다른 에이전트는 세션 제목만 보여요.
- Herdr의 이벤트 훅에는 타임아웃이 없어서, 지연 확인은 분리된 프로세스로 돌리고 모든 요청은 10초로 제한해요.

## 개발

```sh
herdr plugin link .
./test.sh   # 격리된 Herdr와 가짜 ntfy로 완료, 깜빡임, 대기, 명령, 셸 훅 필터, 비밀값 가림을 확인해요
```

릴리스할 때는 `herdr-plugin.toml`의 `version`을 올리고, 두 README의 `--ref`를 바꿔 커밋한 뒤 `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`를 실행하세요.

## 라이선스

MIT
