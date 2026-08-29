#!/usr/bin/env bash
set -euo pipefail

SEED_UVX_FROM="${SEED_UVX_FROM:-git+https://github.com/vivekhaldar/seed.git}"
PROVIDER=""
MODEL=""
NO_RUN=false
HAS_TTY=false
INTERACTIVE_SELECTION=false

die() {
    printf 'seed: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Plant and configure a seed agent in the current directory.

Usage:
  curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/install.sh | bash
  curl -fsSL URL | bash -s -- [--provider NAME] [--model ID] [--no-run]

Options:
  --provider NAME  gemini, openrouter, openai, anthropic, codex, or custom
  --model ID       Override the provider's recommended model
  --no-run         Plant the agent without starting an interactive session
  -h, --help       Show this help
EOF
}

while (($#)); do
    case "$1" in
        --provider)
            (($# >= 2)) || die "--provider requires a value"
            PROVIDER="$2"
            shift 2
            ;;
        --model)
            (($# >= 2)) || die "--model requires a value"
            MODEL="$2"
            shift 2
            ;;
        --no-run)
            NO_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

if { exec 3<>/dev/tty; } 2>/dev/null; then
    HAS_TTY=true
fi

require_tty() {
    "$HAS_TTY" || die "interactive setup needs a terminal; pass --provider and --model for unattended setup"
}

if [[ -e seed.py || -e run_seed.sh ]]; then
    die "seed.py or run_seed.sh already exists in this directory"
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v git >/dev/null 2>&1 || die "git is required"

if ! command -v uv >/dev/null 2>&1; then
    printf 'Installing uv...\n'
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    command -v uv >/dev/null 2>&1 || die "uv installed but is not available on PATH"
fi

seed_llm() {
    uvx --quiet --from llm --with "$SEED_UVX_FROM" llm "$@"
}

choose_provider() {
    require_tty
    INTERACTIVE_SELECTION=true
    cat >&3 <<'EOF'

How should this seed think?
  1) Gemini      quickest start; free tier available
  2) OpenRouter  one key, many models; usage charges vary
  3) OpenAI      OpenAI API key
  4) Anthropic   Anthropic API key
  5) Codex       existing ChatGPT/Codex subscription
  6) Custom      an already-configured llm model
EOF
    printf 'Choice [1]: ' >&3
    read -r choice <&3
    case "${choice:-1}" in
        1|gemini) PROVIDER="gemini" ;;
        2|openrouter) PROVIDER="openrouter" ;;
        3|openai) PROVIDER="openai" ;;
        4|anthropic) PROVIDER="anthropic" ;;
        5|codex) PROVIDER="codex" ;;
        6|custom) PROVIDER="custom" ;;
        *) die "invalid provider choice: $choice" ;;
    esac
}

if [[ -z "$PROVIDER" ]]; then
    if [[ -n "$MODEL" ]]; then
        PROVIDER="custom"
    else
        choose_provider
    fi
fi

KEY_NAME=""
KEY_ENV=""
KEY_URL=""
DEFAULT_MODEL=""

case "$PROVIDER" in
    gemini)
        KEY_NAME="gemini"
        KEY_ENV="LLM_GEMINI_KEY"
        KEY_URL="https://aistudio.google.com/app/apikey"
        DEFAULT_MODEL="gemini-flash-latest"
        ;;
    openrouter)
        KEY_NAME="openrouter"
        KEY_ENV="OPENROUTER_KEY"
        KEY_URL="https://openrouter.ai/keys"
        DEFAULT_MODEL="openrouter/openrouter/auto"
        ;;
    openai)
        KEY_NAME="openai"
        KEY_ENV="OPENAI_API_KEY"
        KEY_URL="https://platform.openai.com/api-keys"
        DEFAULT_MODEL="gpt-5.6-sol"
        ;;
    anthropic)
        KEY_NAME="anthropic"
        KEY_ENV="ANTHROPIC_API_KEY"
        KEY_URL="https://console.anthropic.com/settings/keys"
        DEFAULT_MODEL="claude-sonnet-5"
        ;;
    codex)
        DEFAULT_MODEL="openai-codex/gpt-5.6-sol"
        ;;
    custom)
        ;;
    *)
        die "unknown provider '$PROVIDER'; use gemini, openrouter, openai, anthropic, codex, or custom"
        ;;
esac

if [[ -z "$MODEL" ]]; then
    if [[ "$PROVIDER" == "custom" ]]; then
        require_tty
        printf 'llm model ID: ' >&3
        read -r MODEL <&3
    elif "$INTERACTIVE_SELECTION"; then
        printf 'Model [%s]: ' "$DEFAULT_MODEL" >&3
        read -r MODEL <&3
        MODEL="${MODEL:-$DEFAULT_MODEL}"
    else
        MODEL="$DEFAULT_MODEL"
    fi
fi

[[ -n "$MODEL" ]] || die "model ID cannot be empty"
[[ "$MODEL" != *$'\n'* && "$MODEL" != *$'\r'* ]] || die "model ID cannot contain a newline"

has_stored_key() {
    local configured
    while IFS= read -r configured; do
        [[ "$configured" == "$KEY_NAME" ]] && return 0
    done <<<"$CONFIGURED_KEYS"
    return 1
}

if [[ -n "$KEY_NAME" ]]; then
    CONFIGURED_KEYS="$(seed_llm keys list 2>/dev/null || true)"
    if [[ -n "${!KEY_ENV:-}" ]]; then
        printf 'Using %s from the environment (it will not be copied to disk).\n' "$KEY_ENV"
    elif has_stored_key; then
        printf 'Using the stored %s key.\n' "$KEY_NAME"
    else
        require_tty
        printf '\nCreate a %s key: %s\n' "$PROVIDER" "$KEY_URL"
        printf 'The key will be stored by llm outside this directory.\n'
        seed_llm keys set "$KEY_NAME" <&3
    fi
elif [[ "$PROVIDER" == "codex" ]]; then
    command -v codex >/dev/null 2>&1 ||
        die "Codex CLI is required for subscription access: https://github.com/openai/codex"
    if ! codex login status >/dev/null 2>&1; then
        require_tty
        codex login <&3
    fi
fi

printf 'Checking that %s is available and supports tools...\n' "$MODEL"
if ! MODEL_INFO="$(seed_llm models list --tools --model "$MODEL" --json)"; then
    die "could not inspect model '$MODEL'"
fi
case "$MODEL_INFO" in
    *'"model_id"'*) ;;
    *) die "model '$MODEL' is unavailable or does not support tool calls" ;;
esac

{
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' 'cd "$(dirname "$0")"'
    printf 'DEFAULT_MODEL=%q\n' "$MODEL"
    printf '%s\n' 'exec ./seed.py -m "${SEED_MODEL:-$DEFAULT_MODEL}" "$@"'
} >run_seed.sh
chmod +x run_seed.sh

printf 'Planting seed with %s...\n' "$MODEL"
if "$NO_RUN"; then
    uvx --quiet --from "$SEED_UVX_FROM" seed -m "$MODEL" </dev/null
    printf 'Ready. Start it with ./run_seed.sh\n'
else
    require_tty
    exec uvx --quiet --from "$SEED_UVX_FROM" seed -m "$MODEL" <&3
fi
