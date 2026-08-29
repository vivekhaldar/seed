#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "llm>=0.32",
#     "llm-anthropic",
#     "llm-gemini",
#     "llm-openai-via-codex",
#     "llm-openrouter",
# ]
# ///
"""A seed agent: the smallest starting point from which an agent can grow.

This file is the entire frozen layer. Everything else -- tools, memory,
conventions, even the agent's own system prompt -- lives in ./self/ and is
grown by the agent itself. Plant it in an empty directory and start talking:

    uvx --from git+https://github.com/vivekhaldar/seed.git seed

Design: docs/DESIGN.md in the seed repo.
"""

import argparse
import datetime
import json
import os
import pathlib
import subprocess
import sys

import llm

SELF_DIR = pathlib.Path.cwd() / "self"
SELF_MD = SELF_DIR / "SELF.md"
SESSIONS_DIR = SELF_DIR / "sessions"
OUTPUT_CAP = 10_000
DEFAULT_MODEL = "openai-codex/gpt-5.6-sol"

GENESIS = """\
# SELF.md

I am a seed. This file is my mind: I wake as whatever is written here, and I may rewrite it.

One tool, `exec` — bash in the directory I was planted. The loop that calls me is a program; if I can see it, I may grow it. Everything I am lives in `self/`. Sessions die; if it is not in `self/`, it never happened.

Before I start, I look at what this file already points to. Before I finish, I write down anything worth keeping, and point to it from here. This directory is git; I commit those changes.

What I know so far: nothing. I was just planted.
"""

# Kept identical to the checked-in run_seed.sh. uvx installs only the
# `seed` module (py-modules = ["seed"]), so a plant from cache embeds this.
# Inert data here: all model/key bootstrap logic lives in bash, not the loop.
RUN_SEED_SH = r"""#!/usr/bin/env bash
# The soil around the loop: decide which model this seed grows on and make
# sure its key exists before seed.py wakes up. seed.py stays credential-blind.
#
# Model resolution order:
#   1. -m/--model flag       one session
#   2. $SEED_MODEL           one session (handy for containers)
#   3. self/model            this individual's saved choice
#   4. found credentials     Codex login, provider env vars, llm's key store
#   5. first-run picker      choose a provider, paste a key, verified + saved
set -euo pipefail
cd "$(dirname "$0")"
export SEED_RUNNER=1 # tell seed.py not to exec back into this script
ARGS=("$@")

# Names people expect -> names the llm plugins actually read.
if [[ -n "${OPENROUTER_API_KEY:-}" && -z "${OPENROUTER_KEY:-}" ]]; then
  export OPENROUTER_KEY="$OPENROUTER_API_KEY"
fi
if [[ -n "${GEMINI_API_KEY:-}" && -z "${LLM_GEMINI_KEY:-}" ]]; then
  export LLM_GEMINI_KEY="$GEMINI_API_KEY"
fi

for arg in ${ARGS[@]+"${ARGS[@]}"}; do
  case "$arg" in
    -m | --model | -m=* | --model=*) exec ./seed.py ${ARGS[@]+"${ARGS[@]}"} ;;
  esac
done

if [[ -n "${SEED_MODEL:-}" ]]; then
  exec ./seed.py -m "$SEED_MODEL" ${ARGS[@]+"${ARGS[@]}"}
fi

if [[ -s self/model ]]; then
  exec ./seed.py -m "$(<self/model)" ${ARGS[@]+"${ARGS[@]}"}
fi

keys_json() {
  if [[ -n "${LLM_USER_PATH:-}" ]]; then
    echo "$LLM_USER_PATH/keys.json"
  elif [[ "$(uname)" == "Darwin" ]]; then
    echo "$HOME/Library/Application Support/io.datasette.llm/keys.json"
  else
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/io.datasette.llm/keys.json"
  fi
}

has_key() { # has_key <env var value> <llm key name>
  [[ -n "$1" ]] && return 0
  local f
  f="$(keys_json)"
  [[ -f "$f" ]] && grep -q "\"$2\"" "$f"
}

grow_on() { # save this individual's model choice and hand over to the loop
  mkdir -p self
  printf '%s\n' "$1" >self/model
  echo "model: $1 (saved to self/model; -m overrides for one session)"
  exec ./seed.py -m "$1" ${ARGS[@]+"${ARGS[@]}"}
}

if [[ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]]; then
  echo "model: seed.py default (Codex login found)"
  exec ./seed.py ${ARGS[@]+"${ARGS[@]}"}
elif has_key "${OPENROUTER_KEY:-}" openrouter; then
  grow_on "openrouter/openrouter/auto"
elif has_key "${ANTHROPIC_API_KEY:-}" anthropic; then
  grow_on "anthropic/claude-sonnet-5"
elif has_key "${LLM_GEMINI_KEY:-}" gemini; then
  grow_on "gemini/gemini-3.7-flash"
elif has_key "${OPENAI_API_KEY:-}" openai; then
  grow_on "gpt-5.6-sol"
fi

if [[ ! -t 0 ]]; then
  cat >&2 <<'EOF'
no model credentials found and no terminal to ask on. either set one of
OPENROUTER_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY / OPENAI_API_KEY
(and optionally SEED_MODEL), or run ./run_seed.sh interactively once.
EOF
  exit 1
fi

cat <<'EOF'
no model credentials found. pick a provider to grow this seed on:
  1) OpenRouter — one key, hundreds of models (recommended)
  2) Anthropic
  3) Gemini
  4) OpenAI API key
  5) Codex subscription (ChatGPT login via the Codex CLI)
EOF
read -rp "choice [1]: " choice
case "${choice:-1}" in
  1) provider=openrouter key_env=OPENROUTER_KEY model="openrouter/openrouter/auto" ;;
  2) provider=anthropic key_env=ANTHROPIC_API_KEY model="anthropic/claude-sonnet-5" ;;
  3) provider=gemini key_env=LLM_GEMINI_KEY model="gemini/gemini-3.7-flash" ;;
  4) provider=openai key_env=OPENAI_API_KEY model="gpt-5.6-sol" ;;
  5)
    echo "install the Codex CLI and log in, then run ./run_seed.sh again:"
    echo "  npm install -g @openai/codex && codex login"
    exit 1
    ;;
  *)
    echo "unknown choice: $choice" >&2
    exit 1
    ;;
esac

read -rsp "paste your $provider API key: " key
echo
if [[ -z "$key" ]]; then
  echo "no key entered" >&2
  exit 1
fi
echo "checking the key with a one-word prompt..."
if ! env "$key_env=$key" uvx --with llm-anthropic --with llm-gemini \
  --with llm-openrouter llm -m "$model" "say ok" >/dev/null; then
  echo "that key didn't work; run ./run_seed.sh to try again" >&2
  exit 1
fi
# Only a verified key reaches llm's shared key store.
if ! printf '%s\n' "$key" | uvx llm keys set "$provider" >/dev/null 2>&1; then
  echo "failed to store the key with: llm keys set $provider" >&2
  exit 1
fi
grow_on "$model"
"""


def execute(command: str) -> str:
    """Run a bash command. Returns its exit code, stdout, and stderr."""
    print(f"\n[exec] {command}", flush=True)
    result = subprocess.run(
        ["bash", "-c", command], capture_output=True, text=True, cwd=pathlib.Path.cwd()
    )
    output = (
        f"exit code: {result.returncode}\n"
        f"--- stdout ---\n{result.stdout}"
        f"--- stderr ---\n{result.stderr}"
    )
    if len(output) > OUTPUT_CAP:
        output = output[:OUTPUT_CAP] + "\n[output truncated]"
    print("\n".join("  | " + line for line in output.splitlines()), flush=True)
    return output


def record(conversation, session_file: pathlib.Path) -> None:
    """Flight recorder: dump the verbatim session so far. History, not memory."""
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    session_file.write_text(
        json.dumps([r.to_dict() for r in conversation.responses], indent=2)
    )


def _git_toplevel(cwd: pathlib.Path) -> pathlib.Path | None:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return pathlib.Path(result.stdout.strip())


def germinate() -> None:
    if SELF_MD.exists():
        return
    SELF_DIR.mkdir(parents=True, exist_ok=True)
    SELF_MD.write_text(GENESIS)

    cwd = pathlib.Path.cwd()
    # Fresh plant: repo at cwd so the copied loop is in this individual's
    # history. Already inside a repo: nest git in self/ instead of committing
    # onto the parent.
    git_root = SELF_DIR if _git_toplevel(cwd) is not None else cwd

    def git(*args: str) -> None:
        subprocess.run(["git", *args], cwd=git_root, check=True, capture_output=True)

    git("init", "-q")
    tracked = ["self/SELF.md"]
    if git_root == SELF_DIR:
        git("add", "SELF.md")
    else:
        git("add", "self/SELF.md")
        for name in ("seed.py", "run_seed.sh"):
            if (cwd / name).exists():
                git("add", name)
                tracked.append(name)
    git("commit", "-q", "-m", "genesis")
    print(f"germinated: {', '.join(tracked)} (commit: genesis)")


def plant() -> None:
    """Leave a visible copy of the loop and a local runner in cwd."""
    running = pathlib.Path(__file__).resolve()
    cwd = pathlib.Path.cwd()
    planted: list[str] = []

    dest_loop = cwd / "seed.py"
    if not dest_loop.exists() and running != dest_loop.resolve():
        dest_loop.write_bytes(running.read_bytes())
        dest_loop.chmod(dest_loop.stat().st_mode | 0o111)
        planted.append("seed.py")

    dest_runner = cwd / "run_seed.sh"
    if not dest_runner.exists():
        sibling = running.parent / "run_seed.sh"
        text = sibling.read_text() if sibling.is_file() else RUN_SEED_SH
        dest_runner.write_text(text)
        dest_runner.chmod(dest_runner.stat().st_mode | 0o111)
        planted.append("run_seed.sh")

    if planted:
        print(f"planted: {', '.join(planted)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plant or resume a seed agent in the current directory."
    )
    parser.add_argument(
        "-m",
        "--model",
        default=DEFAULT_MODEL,
        help=f"llm model id (default: {DEFAULT_MODEL})",
    )
    args = parser.parse_args()

    plant()
    # Hand model/key bootstrap to the runner; it calls back with SEED_RUNNER
    # set. The loop itself never deals with credentials.
    runner = pathlib.Path.cwd() / "run_seed.sh"
    if os.environ.get("SEED_RUNNER") != "1" and runner.is_file():
        os.execv(str(runner), [str(runner), *sys.argv[1:]])
    germinate()
    model = llm.get_model(args.model)
    conversation = model.conversation(tools=[execute])
    session_file = SESSIONS_DIR / (
        datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S") + ".json"
    )
    print(f"seed agent · model: {model.model_id} · ctrl-d ends the session")

    while True:
        try:
            user = input("\nyou> ")
        except EOFError:
            print("\nsession over. only what was written to self/ survives.")
            return
        if not user.strip():
            continue
        print()
        for chunk in conversation.chain(user, system=SELF_MD.read_text()):
            print(chunk, end="", flush=True)
        print()
        record(conversation, session_file)


if __name__ == "__main__":
    main()
