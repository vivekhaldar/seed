#!/usr/bin/env bash
# The soil around the loop: find or ask for a model and its key, then start
# seed.py — which stays credential-blind and never handles any of this.
#
# First plant, in an empty directory:
#   curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/run_seed.sh | bash
# Come back to the same agent:
#   ./run_seed.sh
#
# Model resolution order:
#   1. -m/--model flag       one session
#   2. $SEED_MODEL           one session (handy for containers)
#   3. self/model            this individual's saved choice
#   4. found credentials     Codex login, provider env vars, llm's key store
#   5. first-run picker      choose a provider, paste a key, verified + saved
set -euo pipefail
cd "$(dirname "$0")"
ARGS=("$@")

SEED_GIT="${SEED_GIT:-git+https://github.com/vivekhaldar/seed.git}"
RUNNER_URL="${SEED_RUNNER_URL:-https://raw.githubusercontent.com/vivekhaldar/seed/master/run_seed.sh}"

if ! command -v uvx >/dev/null 2>&1; then
  echo "seed needs uv. install it first:" >&2
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

# Piped from curl there is no file on disk: leave a copy behind so
# ./run_seed.sh works from now on. seed.py never overwrites it. When piped,
# stdin is the script stream — remember that so it never reaches the REPL.
STDIN_IS_SCRIPT=0
if [[ ! -f run_seed.sh ]]; then
  curl -fsSL "$RUNNER_URL" -o run_seed.sh
  chmod +x run_seed.sh
  echo "planted: run_seed.sh"
  [[ -t 0 ]] || STDIN_IS_SCRIPT=1
fi

have_tty() { (: </dev/tty) 2>/dev/null; }

launch() { # launch [-m model]: hand over to the loop; uvx plants seed.py first time
  local cmd
  if [[ -f seed.py ]]; then
    cmd=(./seed.py)
  else
    cmd=(uvx --from "$SEED_GIT" seed)
  fi
  cmd+=("$@")
  cmd+=(${ARGS[@]+"${ARGS[@]}"})
  if [[ "$STDIN_IS_SCRIPT" == 1 ]]; then
    if have_tty; then
      exec "${cmd[@]}" </dev/tty
    fi
    exec "${cmd[@]}" </dev/null
  fi
  exec "${cmd[@]}"
}

# Names people expect -> names the llm plugins actually read.
if [[ -n "${OPENROUTER_API_KEY:-}" && -z "${OPENROUTER_KEY:-}" ]]; then
  export OPENROUTER_KEY="$OPENROUTER_API_KEY"
fi
if [[ -n "${GEMINI_API_KEY:-}" && -z "${LLM_GEMINI_KEY:-}" ]]; then
  export LLM_GEMINI_KEY="$GEMINI_API_KEY"
fi

for arg in ${ARGS[@]+"${ARGS[@]}"}; do
  case "$arg" in
    -m | --model | -m=* | --model=*) launch ;;
  esac
done

if [[ -n "${SEED_MODEL:-}" ]]; then
  launch -m "$SEED_MODEL"
fi

if [[ -s self/model ]]; then
  launch -m "$(<self/model)"
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
  launch -m "$1"
}

if [[ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]]; then
  echo "model: seed.py default (Codex login found)"
  launch
elif has_key "${OPENROUTER_KEY:-}" openrouter; then
  grow_on "openrouter/openrouter/auto"
elif has_key "${ANTHROPIC_API_KEY:-}" anthropic; then
  grow_on "anthropic/claude-sonnet-5"
elif has_key "${LLM_GEMINI_KEY:-}" gemini; then
  grow_on "gemini/gemini-3.7-flash"
elif has_key "${OPENAI_API_KEY:-}" openai; then
  grow_on "gpt-5.6-sol"
fi

if [[ ! -t 0 ]] && ! have_tty; then
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
read -rp "choice [1]: " choice </dev/tty
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

read -rsp "paste your $provider API key: " key </dev/tty
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
