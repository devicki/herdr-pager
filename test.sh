#!/usr/bin/env bash
# End-to-end check against a stand-in ntfy server that records what it receives: an isolated
# Herdr (own HOME, only this plugin linked) drives agent states through the plugin hook, and
# the CLI covers commands and the shell hook's filter. Needs jq, curl and python3.
# TEST_WORK picks the scratch dir (default: a new mktemp dir).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${TEST_WORK:-$(mktemp -d)}
herdr=$(command -v herdr)
# Unix socket paths must stay under 108 bytes, so HOME is a short symlink to the scratch dir.
home="${XDG_RUNTIME_DIR:-/tmp}/pager-test"
env_=(env -i HOME="$home" PATH="$work/bin:${herdr%/*}:/usr/local/bin:/usr/bin:/bin" LANG=en_US.UTF-8 USER=tester)
h() { "${env_[@]}" "$herdr" "$@"; }
fail=0
check() { # description, expected count, jq filter over received messages
  local n
  n=$(jq -s "[.[] | select($3)] | length" "$work/received.jsonl" 2>/dev/null || echo 0)
  if [ "$n" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: $n message(s), want $2" >&2; fail=1; fi
}
cleanup() {
  h server stop >/dev/null 2>&1 || :
  kill "${ntfy:-}" 2>/dev/null || :
  rm -f "$home"
}
trap cleanup EXIT

mkdir -p "$work/home/.config/herdr/plugins/config/devicki.pager"
ln -sfn "$work/home" "$home"
printf 'onboarding = false\n[update]\nversion_check = false\nmanifest_check = false\n' >"$work/home/.config/herdr/config.toml"
: >"$work/received.jsonl"

# The stand-in ntfy: every POST body, one JSON line each.
cat >"$work/ntfy.py" <<'EOF'
import http.server, sys
out = open(sys.argv[2], "a")
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        out.write(body.replace("\n", " ") + "\n"); out.flush()
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
port=$((20000 + RANDOM % 20000))
python3 "$work/ntfy.py" "$port" "$work/received.jsonl" &
ntfy=$!
printf 'url = http://127.0.0.1:%s\ntopic = t\nlabel = test   # a note\ndone_delay = 2\nblocked_delay = 2\n' "$port" \
  >"$work/home/.config/herdr/plugins/config/devicki.pager/pager.conf"

h plugin link "$here" >/dev/null
"${env_[@]}" "$herdr" server >/dev/null 2>&1 &
for _ in $(seq 50); do h pane list >/dev/null 2>&1 && break; sleep 0.2; done
p=$(h workspace create --cwd /tmp --label shop-api | jq -r .result.root_pane.pane_id)
say() { h pane report-agent "$p" --source test --agent claude --state "$1" >/dev/null; sleep "${2:-0.5}"; }

# A finished turn, reported once after the delay.
say working; say idle 3.5
check "finished turn is reported" 1 '.title | test("claude done · shop-api")'
check "  with the pane and the way back" 1 '.message | test("herdr agent focus '"$p"'")'
check "  and a herdr:name(id) reference to paste into an agent" 1 '.message | test("📍 herdr:claude\\('"$p"'\\)")'
# A pause mid-turn (idle, then working again within the delay) is not.
say working; say idle 0.8; say working 3
check "a blip mid-turn is not reported" 1 '.title | test("done")'
# Waiting for an answer: high priority, and only once for the same wait.
say blocked 1; say blocked 3
check "waiting for you is reported once, high priority" 1 '(.title | test("needs you")) and .priority == 4'
# Idle without a working stretch before it (Unknown -> Idle) is not a finished turn.
say idle 3
check "idle after a wait is not a finished turn" 1 '.title | test("done")'

# Claude's agent view has no session of its own: a finished turn is reported with the background
# session that just finished, by its name and reply. A session open in a pane is not that one.
mkdir -p "$work/bin" "$work/home/.claude/projects/-w"
cat >"$work/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = agents ] && [ "${2:-}" = --json ]; then
  echo '[{"kind":"background","state":"done","sessionId":"bg0","name":"older"},
    {"kind":"background","state":"done","sessionId":"bg1","name":"nightly triage"},
    {"kind":"background","state":"done","sessionId":"bg2","name":"attached"},
    {"kind":"interactive","status":"idle","sessionId":"bg2","name":"attached"}]'
  exit
fi
exec -a claude python3 -c "import time; time.sleep(1e9)" "$@"
EOF
chmod +x "$work/bin/claude"
for s in bg0 bg1 bg2; do
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"reply of %s"}]}}\n' "$s" \
    >"$work/home/.claude/projects/-w/$s.jsonl"
  sleep 1
done
v=$(h pane split "$p" --direction right --no-focus | jq -r .result.pane.pane_id)
h pane run "$v" ' claude --dangerously-skip-permissions agents' >/dev/null
sleep 1
h pane report-agent "$v" --source test --agent claude --state working >/dev/null; sleep 0.5
h pane report-agent "$v" --source test --agent claude --state idle >/dev/null; sleep 3.5
check "agent view: the background session that finished, by name and reply" 1 \
  '(.message | test("📝 nightly triage")) and (.message | test("💬 reply of bg1"))'

# Commands and jobs, through the CLI.
cli=(env HERDR_PLUGIN_CONFIG_DIR="$work/home/.config/herdr/plugins/config/devicki.pager"
  HERDR_PLUGIN_STATE_DIR="$work/state" bash "$here/bin/herdr-pager")
"${cli[@]}" run -- sh -c 'echo "boom: disk full" >&2; exit 3' 2>/dev/null
[ $? -eq 3 ] || { echo "FAIL run did not pass the exit code through" >&2; fail=1; }
"${cli[@]}" run -q -- true
"${cli[@]}" run -t "nightly backup" -- true
"${cli[@]}" shell-done 0 120 "vim notes.txt"
"${cli[@]}" shell-done 2 95 "make build"
"${cli[@]}" send -p 5 "deploy token=abc123 done"
sleep 0.5
check "a failed command, with its exit code and last error line" 1 '(.title | test("sh failed \\(exit 3\\)")) and .priority == 4 and (.message | test("⚠️ boom: disk full"))'
check "run -q stays quiet on success" 0 '.title | test("true finished")'
check "run -t sets the title, after the label" 1 '.title == "[test] nightly backup"'
check "the shell hook skips interactive tools" 0 '.message | test("vim notes")'
check "a long shell command is reported" 1 '(.title | test("make failed \\(exit 2\\)")) and (.message | test("1m35s"))'
check "secrets are masked" 1 '.message == "deploy token=[redacted] done" and .priority == 5'

# A message the server does not take is queued, then resent with the time it was meant for.
mkdir -p "$work/down"
printf 'url = http://127.0.0.1:1\ntopic = t\nlabel = test\n' >"$work/down/pager.conf"
env HERDR_PLUGIN_CONFIG_DIR="$work/down" HERDR_PLUGIN_STATE_DIR="$work/state" bash "$here/bin/herdr-pager" send -t "while down" "queued" 2>/dev/null
"${cli[@]}" send -t "back up" "next"
sleep 0.5
check "a message the server missed is resent, marked late" 1 '.title == "[test] while down" and (.message | test("delivered late"))'

# The same, in Korean (lang = ko).
mkdir -p "$work/ko"
printf 'url = http://127.0.0.1:%s\ntopic = t\nlabel = test\nlang = ko\nerror_chars = 5\n' "$port" >"$work/ko/pager.conf"
env HERDR_PLUGIN_CONFIG_DIR="$work/ko" HERDR_PLUGIN_STATE_DIR="$work/state" bash "$here/bin/herdr-pager" shell-done 3 95 "make build"
# error_chars cuts by characters, also under the C locale where awk would count bytes.
env LC_ALL=C HERDR_PLUGIN_CONFIG_DIR="$work/ko" HERDR_PLUGIN_STATE_DIR="$work/state" bash "$here/bin/herdr-pager" \
  run -- sh -c 'echo 가나다라마바사 >&2; exit 1' 2>/dev/null
sleep 0.5
check "lang = ko: Korean wording and durations" 1 '.title == "[test] make 실패 (종료 코드 3)" and (.message | test("1분 35초"))'
check "error_chars = 5: cut at five Korean characters" 1 '.message | test("⚠️ 가나다라마…")'

[ "$fail" -eq 0 ] && echo PASS
exit "$fail"
