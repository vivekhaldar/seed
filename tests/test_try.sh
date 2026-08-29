#!/usr/bin/env bash
# Non-interactive checks for try.sh and run_seed.sh (.seed-model).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TRY="$ROOT/try.sh"
PASS=0
FAIL=0

assert() {
  local name=$1
  shift
  if "$@"; then
    printf 'ok  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'not ok  %s\n' "$name"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local name=$1 got=$2 want=$3
  if [[ "$got" == "$want" ]]; then
    printf 'ok  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'not ok  %s\n    got:  %s\n    want: %s\n' "$name" "$got" "$want"
    FAIL=$((FAIL + 1))
  fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
export LLM_USER_PATH="$WORKDIR/llm"
mkdir -p "$LLM_USER_PATH"

# 1. help
assert "try.sh --help" bash -c "bash '$TRY' --help >/dev/null"

# 2. plant without starting the REPL
PLANT="$WORKDIR/plant"
bash "$TRY" --yes --no-run --dir "$PLANT" --source "$ROOT" \
  --provider anthropic --key "sk-ant-test-1" >/dev/null
assert "copied seed.py" test -f "$PLANT/seed.py"
assert "copied run_seed.sh" test -x "$PLANT/run_seed.sh"
assert_eq "wrote .seed-model" "$(cat "$PLANT/.seed-model")" "anthropic/claude-sonnet-4-6"
assert "wrote keys.json" test -f "$LLM_USER_PATH/keys.json"
assert_eq "stored anthropic key" \
  "$(python3 -c "import json; print(json.load(open('$LLM_USER_PATH/keys.json'))['anthropic'])")" \
  "sk-ant-test-1"

# 3. do not overwrite an existing seed.py
KEEP="$WORKDIR/keep"
mkdir -p "$KEEP"
printf 'MARKER\n' > "$KEEP/seed.py"
bash "$TRY" --yes --no-run --dir "$KEEP" --source "$ROOT" \
  --provider openai --key "sk-openai-test" >/dev/null
assert_eq "left existing seed.py alone" "$(cat "$KEEP/seed.py")" "MARKER"

# 4. env var is enough (no --key); --yes picks provider from the env
ENVPLANT="$WORKDIR/envplant"
ENV_LLM="$WORKDIR/llm-env"
mkdir -p "$ENV_LLM"
ANTHROPIC_API_KEY="sk-ant-from-env" LLM_USER_PATH="$ENV_LLM" bash "$TRY" \
  --yes --no-run --dir "$ENVPLANT" --source "$ROOT" >/dev/null
assert_eq "env selected anthropic model" \
  "$(cat "$ENVPLANT/.seed-model")" "anthropic/claude-sonnet-4-6"
assert_eq "env key persisted" \
  "$(python3 -c "import json; print(json.load(open('$ENV_LLM/keys.json'))['anthropic'])")" \
  "sk-ant-from-env"

# 5. curl | bash style: script on stdin, args after -s
PIPE="$WORKDIR/pipe"
cat "$TRY" | bash -s -- --yes --no-run --dir "$PIPE" --source "$ROOT" \
  --provider gemini --key "gem-test" --model "gemini/gemini-2.5-flash" >/dev/null
assert_eq "piped install wrote model" "$(cat "$PIPE/.seed-model")" "gemini/gemini-2.5-flash"
assert_eq "piped install stored gemini key" \
  "$(python3 -c "import json; print(json.load(open('$LLM_USER_PATH/keys.json'))['gemini'])")" \
  "gem-test"

# 6. --yes with no provider and no env key fails
set +e
LLM_USER_PATH="$WORKDIR/llm-empty" bash "$TRY" --yes --no-run \
  --dir "$WORKDIR/fail" --source "$ROOT" >/dev/null 2>"$WORKDIR/err"
rc=$?
set -e
assert "missing provider fails" test "$rc" -ne 0

# 7. unknown provider fails
set +e
bash "$TRY" --yes --no-run --dir "$WORKDIR/fail2" --source "$ROOT" \
  --provider nope --key x >/dev/null 2>&1
rc=$?
set -e
assert "unknown provider fails" test "$rc" -ne 0

# 8. busy cwd + --yes plants ./seed
BUSY="$WORKDIR/busy"
mkdir -p "$BUSY"
printf 'hello\n' > "$BUSY/notes.txt"
(
  cd "$BUSY"
  bash "$TRY" --yes --no-run --source "$ROOT" --provider openai --key "sk-busy"
) >/dev/null
assert "busy dir created ./seed" test -f "$BUSY/seed/seed.py"
assert "busy dir did not plant on notes.txt" test ! -f "$BUSY/seed.py"

# 9. run_seed.sh injects -m from .seed-model unless overridden
WRAP="$WORKDIR/wrap"
mkdir -p "$WRAP"
cp "$ROOT/run_seed.sh" "$WRAP/run_seed.sh"
chmod +x "$WRAP/run_seed.sh"
cat > "$WRAP/seed.py" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*"
PY
chmod +x "$WRAP/seed.py"
printf 'anthropic/claude-sonnet-4-6\n' > "$WRAP/.seed-model"
assert_eq "run_seed.sh injects -m" \
  "$("$WRAP/run_seed.sh")" \
  "-m anthropic/claude-sonnet-4-6"
assert_eq "explicit -m wins" \
  "$("$WRAP/run_seed.sh" -m gpt-5.4)" \
  "-m gpt-5.4"
assert_eq "explicit --model wins" \
  "$("$WRAP/run_seed.sh" --model gpt-5.4)" \
  "--model gpt-5.4"

# 10. embedded RUN_SEED_SH stays identical to run_seed.sh
python3 - "$ROOT/seed.py" "$ROOT/run_seed.sh" <<'PY'
import pathlib, sys
seed = pathlib.Path(sys.argv[1]).read_text()
runner = pathlib.Path(sys.argv[2]).read_text()
start = seed.index('RUN_SEED_SH = """\\\n') + len('RUN_SEED_SH = """\\\n')
end = seed.index('"""', start)
embedded = seed[start:end]
if not embedded.endswith("\n"):
    raise SystemExit("embedded runner missing trailing newline")
if embedded != runner:
    raise SystemExit("RUN_SEED_SH does not match run_seed.sh")
PY
assert "RUN_SEED_SH matches run_seed.sh" true

# 11. --help mentions curl | bash
assert "help mentions curl" bash -c "bash '$TRY' --help | grep -q 'curl -fsSL'"

# 12. codex needs no key
CODEX="$WORKDIR/codex"
bash "$TRY" --yes --no-run --dir "$CODEX" --source "$ROOT" --provider codex >/dev/null
assert_eq "codex default model" "$(cat "$CODEX/.seed-model")" "openai-codex/gpt-5.6-sol"

# 13. interactive /dev/tty path (what curl | bash uses for prompts)
PTY_OUT="$WORKDIR/pty.out"
set +e
python3 - "$TRY" "$ROOT" "$WORKDIR/pty-work" "$PTY_OUT" <<'PY'
import os, pty, select, sys, time, pathlib

try_sh, root, work, out_path = sys.argv[1:]
os.makedirs(work, exist_ok=True)
plant = os.path.join(work, "plant")
os.makedirs(plant, exist_ok=True)
env = os.environ.copy()
env["LLM_USER_PATH"] = os.path.join(work, "llm")
for k in (
    "ANTHROPIC_API_KEY", "OPENROUTER_KEY", "OPENROUTER_API_KEY",
    "OPENAI_API_KEY", "LLM_GEMINI_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
    "SEED_KEY", "SEED_PROVIDER", "SEED_MODEL", "SEED_DIR",
):
    env.pop(k, None)

pid, fd = pty.fork()
if pid == 0:
    os.execve("/bin/bash", ["bash", try_sh, "--no-run", "--dir", plant, "--source", root], env)

log = []
steps = [
    (b"choice [1]:", b"1\r"),
    (b"OpenRouter API key", b"sk-or-pty-test\r"),
    (b"model [openrouter/anthropic/claude-sonnet-4]:", b"\r"),
]
step_i = 0
deadline = time.time() + 20
buf = b""
rc = 1
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        log.append(chunk)
        if step_i < len(steps) and steps[step_i][0].decode().lower() in buf.decode("utf-8", "replace").lower():
            os.write(fd, steps[step_i][1])
            step_i += 1
            buf = b""
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == 0:
        continue
    time.sleep(0.05)
    while True:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            break
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        log.append(chunk)
    rc = os.waitstatus_to_exitcode(status)
    break
pathlib.Path(out_path).write_bytes(b"".join(log))
if rc == 1:
    try:
        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid:
            rc = os.waitstatus_to_exitcode(status)
    except ChildProcessError:
        rc = 0
model = pathlib.Path(plant, ".seed-model")
keys = pathlib.Path(env["LLM_USER_PATH"], "keys.json")
ok = step_i == 3 and model.is_file() and keys.is_file()
sys.exit(0 if ok else 1)
PY
pty_rc=$?
set -e
if [[ "$pty_rc" -ne 0 && -f "$PTY_OUT" ]]; then
  printf 'PTY transcript:\n%s\n' "$(cat "$PTY_OUT")"
fi
assert "interactive PTY menu plants OpenRouter" test "$pty_rc" -eq 0

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
