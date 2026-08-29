#!/usr/bin/env bash
# Lowest-friction way to try a seed: pick a model, ingest a key, then
# exec seed.py. Designed to be piped (`curl ... | bash`) so prompts
# read /dev/tty — stdin is the script itself.
#
#   mkdir my-agent && cd my-agent
#   curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/try.sh | bash
#
# Non-interactive:
#   curl ... | bash -s -- --provider openrouter --key "$OPENROUTER_KEY"
#   SEED_PROVIDER=anthropic SEED_KEY=sk-ant-... ./try.sh --yes --no-run
set -euo pipefail

SEED_RAW_DEFAULT="https://raw.githubusercontent.com/vivekhaldar/seed/master"

# provider | default model | llm keys.json name | env vars (first wins)
# Codex has no API key — it uses the Codex CLI login.
PROVIDERS="
openrouter|openrouter/anthropic/claude-sonnet-4|openrouter|OPENROUTER_KEY OPENROUTER_API_KEY
anthropic|anthropic/claude-sonnet-4-6|anthropic|ANTHROPIC_API_KEY
openai|gpt-5.4|openai|OPENAI_API_KEY
gemini|gemini/gemini-2.5-flash|gemini|LLM_GEMINI_KEY GEMINI_API_KEY GOOGLE_API_KEY
codex|openai-codex/gpt-5.6-sol||
"

usage() {
  cat <<'EOF'
try.sh — choose a model and API key, then plant and start a seed.

Usage:
  curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/try.sh | bash
  curl ... | bash -s -- [options]
  ./try.sh [options]

Options:
  --provider NAME   openrouter | anthropic | openai | gemini | codex
  --model ID        llm model id (default depends on --provider)
  --key KEY         API key (or set SEED_KEY / the provider's env var)
  --dir DIR         plant here (created if needed)
  --source PATH|URL local checkout or raw.githubusercontent.com tree
  --yes             accept defaults; never prompt
  --no-run          configure and plant only (do not start the REPL)
  -h, --help        show this help

Keys are stored in llm's keys.json (~/.config/io.datasette.llm/) so
seed.py does not grow a key path. The chosen model is written to
.seed-model; run_seed.sh passes it as -m on later sessions.
EOF
}

# --- tty helpers (curl | bash leaves stdin as the script) ---

have_tty() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

die() {
  printf 'try.sh: %s\n' "$*" >&2
  exit 1
}

say() {
  printf '%s\n' "$*"
}

prompt_line() {
  local prompt=$1 default=${2:-}
  local reply
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
  else
    printf '%s: ' "$prompt" > /dev/tty
  fi
  IFS= read -r reply < /dev/tty || true
  if [[ -z "$reply" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$reply"
  fi
}

prompt_secret() {
  local prompt=$1
  local reply
  printf '%s' "$prompt" > /dev/tty
  IFS= read -r -s reply < /dev/tty || true
  printf '\n' > /dev/tty
  printf '%s' "$reply"
}

# --- provider table ---

provider_field() {
  local name=$1 field=$2
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "${line%%|*}" == "$name" ]]; then
      local rest=${line#*|}
      local model=${rest%%|*}
      rest=${rest#*|}
      local key_name=${rest%%|*}
      local envs=${rest#*|}
      case "$field" in
        model) printf '%s' "$model" ;;
        key_name) printf '%s' "$key_name" ;;
        envs) printf '%s' "$envs" ;;
      esac
      return 0
    fi
  done <<< "$PROVIDERS"
  return 1
}

valid_provider() {
  provider_field "$1" model >/dev/null
}

env_key_for() {
  local name=$1
  local ev
  for ev in $(provider_field "$name" envs); do
    if [[ -n "${!ev:-}" ]]; then
      printf '%s' "${!ev}"
      return 0
    fi
  done
  return 1
}

llm_user_dir() {
  if [[ -n "${LLM_USER_PATH:-}" ]]; then
    printf '%s' "$LLM_USER_PATH"
    return
  fi
  case "$(uname -s)" in
    Darwin) printf '%s' "$HOME/Library/Application Support/io.datasette.llm" ;;
    *) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/io.datasette.llm" ;;
  esac
}

stored_key_for() {
  local name=$1
  local key_name keys
  key_name=$(provider_field "$name" key_name)
  [[ -z "$key_name" ]] && return 1
  keys="$(llm_user_dir)/keys.json"
  [[ -f "$keys" ]] || return 1
  python3 - "$keys" "$key_name" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(1)
val = data.get(name)
if val:
    print(val)
    sys.exit(0)
sys.exit(1)
PY
}

has_provider_key() {
  local name=$1
  [[ "$name" == "codex" ]] && return 1
  env_key_for "$name" >/dev/null && return 0
  stored_key_for "$name" >/dev/null && return 0
  return 1
}

write_llm_key() {
  local name=$1 value=$2
  local dir keys
  [[ -z "$name" ]] && return 0
  command -v python3 >/dev/null 2>&1 || die "python3 is required to store an API key"
  dir="$(llm_user_dir)"
  mkdir -p "$dir"
  keys="$dir/keys.json"
  python3 - "$keys" "$name" "$value" <<'PY'
import json, os, sys

path, name, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        data = {}
data.setdefault("// Note", "This file stores secret API credentials. Do not share!")
data[name] = value
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PY
}

found_providers() {
  local name
  for name in openrouter anthropic openai gemini; do
    if has_provider_key "$name"; then
      printf '%s\n' "$name"
    fi
  done
}

# --- locate species files (clone vs curl | bash) ---

resolve_source() {
  local explicit=$1
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return
  fi
  local src=${BASH_SOURCE[0]:-}
  if [[ -n "$src" && -f "$src" ]]; then
    local here
    here=$(cd "$(dirname "$src")" && pwd)
    if [[ -f "$here/seed.py" ]]; then
      printf '%s' "$here"
      return
    fi
  fi
  printf '%s' "${SEED_BASE:-$SEED_RAW_DEFAULT}"
}

fetch_into() {
  local source=$1 dest=$2 name=$3
  local dest_path="$dest/$name"
  if [[ -f "$dest_path" ]]; then
    return 0
  fi
  if [[ "$source" == http://* || "$source" == https://* ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download $name"
    curl -fsSL "$source/$name" -o "$dest_path"
  else
    [[ -f "$source/$name" ]] || die "missing $source/$name"
    cp "$source/$name" "$dest_path"
  fi
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi
  say "uv not found — installing from https://astral.sh/uv"
  command -v curl >/dev/null 2>&1 || die "curl is required to install uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # shellcheck disable=SC1091
  [[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
  export PATH="$HOME/.local/bin:${PATH}"
  command -v uv >/dev/null 2>&1 || die "uv install finished but 'uv' is not on PATH"
}

dir_is_empty_enough() {
  local path=$1
  local entry
  shopt -s nullglob dotglob
  for entry in "$path"/*; do
    local base
    base=$(basename "$entry")
    case "$base" in
      . | .. | .git) continue ;;
    esac
    shopt -u nullglob dotglob
    return 1
  done
  shopt -u nullglob dotglob
  return 0
}

pick_plant_dir() {
  local requested=$1 yes=$2
  if [[ -n "$requested" ]]; then
    printf '%s' "$requested"
    return
  fi
  if [[ -f seed.py || -f .seed-model || -d self ]]; then
    printf '%s' "$PWD"
    return
  fi
  if dir_is_empty_enough "$PWD"; then
    printf '%s' "$PWD"
    return
  fi
  if [[ "$yes" == 1 ]]; then
    printf '%s' "$PWD/seed"
    return
  fi
  if ! have_tty; then
    die "cwd is not empty; pass --dir or --yes (plants ./seed)"
  fi
  local choice
  choice=$(prompt_line "cwd has files. plant here, or in ./seed?" "./seed")
  case "$choice" in
    . | here | "$PWD") printf '%s' "$PWD" ;;
    *) printf '%s' "$choice" ;;
  esac
}

choose_provider() {
  local yes=$1 preset=$2
  if [[ -n "$preset" ]]; then
    valid_provider "$preset" || die "unknown provider: $preset"
    printf '%s' "$preset"
    return
  fi

  local found=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && found+=("$p")
  done < <(found_providers)

  if [[ ${#found[@]} -eq 1 ]]; then
    if [[ "$yes" == 1 ]]; then
      printf '%s' "${found[0]}"
      return
    fi
    if have_tty; then
      local ans
      ans=$(prompt_line "found a ${found[0]} key. use ${found[0]}?" "Y")
      case "$ans" in
        Y | y | yes | "") printf '%s' "${found[0]}" ; return ;;
      esac
    fi
  elif [[ ${#found[@]} -gt 1 && "$yes" == 1 ]]; then
    printf '%s' "${found[0]}"
    return
  fi

  if [[ "$yes" == 1 ]]; then
    die "pass --provider (openrouter|anthropic|openai|gemini|codex) or set a provider env key"
  fi
  have_tty || die "no TTY; pass --provider and --key (or a provider env var)"

  if [[ ${#found[@]} -gt 0 ]]; then
    say "existing keys: ${found[*]}"
  fi
  cat > /dev/tty <<'EOF'

How should this seed reach a model?

  1) OpenRouter   one key, many models
  2) Anthropic    Claude
  3) OpenAI       API key (not a ChatGPT login)
  4) Gemini       Google
  5) Codex        ChatGPT / Codex CLI subscription

EOF
  local choice
  choice=$(prompt_line "choice" "1")
  case "$choice" in
    1 | openrouter | "") printf '%s' openrouter ;;
    2 | anthropic) printf '%s' anthropic ;;
    3 | openai) printf '%s' openai ;;
    4 | gemini) printf '%s' gemini ;;
    5 | codex) printf '%s' codex ;;
    *) die "unknown choice: $choice" ;;
  esac
}

resolve_key() {
  local provider=$1 explicit=$2 yes=$3
  local key_name
  key_name=$(provider_field "$provider" key_name)
  if [[ -z "$key_name" ]]; then
    return 0
  fi
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return
  fi
  if [[ -n "${SEED_KEY:-}" ]]; then
    printf '%s' "$SEED_KEY"
    return
  fi
  local from_env
  if from_env=$(env_key_for "$provider"); then
    printf '%s' "$from_env"
    return
  fi
  local from_store
  if from_store=$(stored_key_for "$provider"); then
    printf '%s' "$from_store"
    return
  fi
  if [[ "$yes" == 1 ]]; then
    die "no API key for $provider; pass --key or set $(provider_field "$provider" envs)"
  fi
  have_tty || die "no TTY; pass --key or set $(provider_field "$provider" envs)"
  local hint
  case "$provider" in
    openrouter) hint="OpenRouter API key (https://openrouter.ai/keys): " ;;
    anthropic) hint="Anthropic API key (https://console.anthropic.com/settings/keys): " ;;
    openai) hint="OpenAI API key (https://platform.openai.com/api-keys): " ;;
    gemini) hint="Gemini API key (https://aistudio.google.com/apikey): " ;;
    *) hint="$provider API key: " ;;
  esac
  local typed
  typed=$(prompt_secret "$hint")
  [[ -n "$typed" ]] || die "empty key"
  printf '%s' "$typed"
}

main() {
  local provider="" model="" key="" plant_dir="" source="" yes=0 no_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --provider)
        provider=${2:-}
        shift 2
        ;;
      --model)
        model=${2:-}
        shift 2
        ;;
      --key)
        key=${2:-}
        shift 2
        ;;
      --dir)
        plant_dir=${2:-}
        shift 2
        ;;
      --source)
        source=${2:-}
        shift 2
        ;;
      --yes) yes=1 ; shift ;;
      --no-run) no_run=1 ; shift ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1 (try --help)"
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -n "${SEED_PROVIDER:-}" && -z "$provider" ]]; then
    provider=$SEED_PROVIDER
  fi
  if [[ -n "${SEED_MODEL:-}" && -z "$model" ]]; then
    model=$SEED_MODEL
  fi
  if [[ -n "${SEED_DIR:-}" && -z "$plant_dir" ]]; then
    plant_dir=$SEED_DIR
  fi

  say "seed — pick a model, store a key, then start talking"
  provider=$(choose_provider "$yes" "$provider")
  if [[ -z "$model" ]]; then
    model=$(provider_field "$provider" model)
    if [[ "$yes" != 1 ]] && have_tty; then
      model=$(prompt_line "model" "$model")
    fi
  fi
  [[ -n "$model" ]] || die "empty model id"

  local resolved_key=""
  resolved_key=$(resolve_key "$provider" "$key" "$yes")
  local key_name
  key_name=$(provider_field "$provider" key_name)
  if [[ -n "$key_name" && -n "$resolved_key" ]]; then
    write_llm_key "$key_name" "$resolved_key"
    say "stored $key_name key in $(llm_user_dir)/keys.json"
  elif [[ "$provider" == "codex" ]]; then
    say "codex uses your ChatGPT login (run 'codex login' if this session fails)"
  fi

  local dest
  dest=$(pick_plant_dir "$plant_dir" "$yes")
  mkdir -p "$dest"
  dest=$(cd "$dest" && pwd)

  local origin
  origin=$(resolve_source "$source")
  fetch_into "$origin" "$dest" seed.py
  fetch_into "$origin" "$dest" run_seed.sh
  chmod +x "$dest/seed.py" "$dest/run_seed.sh"
  printf '%s\n' "$model" > "$dest/.seed-model"
  say "planted in $dest"
  say "model: $model  (saved in .seed-model; override with ./run_seed.sh -m ID)"

  if [[ "$no_run" == 1 ]]; then
    say "stopping before seed.py (--no-run)"
    return 0
  fi

  ensure_uv
  cd "$dest"
  # Model and key are already in place. seed.py only sees -m.
  exec ./seed.py -m "$model" "$@"
}

main "$@"
