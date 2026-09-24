#!/usr/bin/env bash
set -euo pipefail

SEED_UVX_FROM="${SEED_UVX_FROM:-git+https://github.com/vivekhaldar/seed.git}"
PROVIDER=""
MODEL=""
NO_RUN=false
NO_VERIFY=false
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
  curl -fsSL URL | bash -s -- [--provider NAME] [--model ID] [--no-run] [--no-verify]

Options:
  --provider NAME  gemini, openrouter, openai, anthropic, codex, or custom
  --model ID       Override the provider's recommended model
  --no-run         Plant the agent without starting an interactive session
  --no-verify      Skip the live credential and model check
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
        --no-verify)
            NO_VERIFY=true
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

# Accept common provider variable names while exporting the names that the
# llm plugins consume. The generated runner repeats these mappings.
if [[ -n "${OPENROUTER_API_KEY:-}" && -z "${OPENROUTER_KEY:-}" ]]; then
    export OPENROUTER_KEY="$OPENROUTER_API_KEY"
fi
if [[ -n "${GEMINI_API_KEY:-}" && -z "${LLM_GEMINI_KEY:-}" ]]; then
    export LLM_GEMINI_KEY="$GEMINI_API_KEY"
fi

CONFIGURED_KEYS="$(seed_llm keys list 2>/dev/null || true)"

has_stored_key() {
    local wanted="$1"
    local configured
    while IFS= read -r configured; do
        [[ "$configured" == "$wanted" ]] && return 0
    done <<<"$CONFIGURED_KEYS"
    return 1
}

DETECTED_PROVIDERS=()

add_detected_provider() {
    local candidate="$1"
    local detected
    # Bash 3.2 (macOS /bin/bash) errors on "${array[@]}" when the array is
    # empty and nounset is on: DETECTED_PROVIDERS[0]: unbound variable.
    if ((${#DETECTED_PROVIDERS[@]})); then
        for detected in "${DETECTED_PROVIDERS[@]}"; do
            [[ "$detected" == "$candidate" ]] && return
        done
    fi
    DETECTED_PROVIDERS+=("$candidate")
}

if [[ -n "${OPENROUTER_KEY:-}" ]] || has_stored_key openrouter; then
    add_detected_provider openrouter
fi
if [[ -n "${ANTHROPIC_API_KEY:-}" ]] || has_stored_key anthropic; then
    add_detected_provider anthropic
fi
if [[ -n "${LLM_GEMINI_KEY:-}" ]] || has_stored_key gemini; then
    add_detected_provider gemini
fi
if [[ -n "${OPENAI_API_KEY:-}" ]] || has_stored_key openai; then
    add_detected_provider openai
fi
if [[ -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]]; then
    add_detected_provider codex
fi

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
    elif ((${#DETECTED_PROVIDERS[@]} == 1)); then
        PROVIDER="${DETECTED_PROVIDERS[0]}"
        printf 'Detected %s credentials.\n' "$PROVIDER"
    elif ((${#DETECTED_PROVIDERS[@]} > 1)); then
        if "$HAS_TTY"; then
            printf 'Found credentials for: %s\n' "${DETECTED_PROVIDERS[*]}" >&3
            choose_provider
        else
            die "multiple credentials found (${DETECTED_PROVIDERS[*]}); pass --provider to choose one"
        fi
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

NEW_KEY=""
if [[ -n "$KEY_NAME" ]]; then
    if [[ -n "${!KEY_ENV:-}" ]]; then
        printf 'Using %s from the environment (it will not be copied to disk).\n' "$KEY_ENV"
    elif has_stored_key "$KEY_NAME"; then
        printf 'Using the stored %s key.\n' "$KEY_NAME"
    else
        require_tty
        printf '\nCreate a %s key: %s\n' "$PROVIDER" "$KEY_URL"
        printf 'It will be verified before llm stores it outside this directory.\n'
        read -rsp "Paste your $PROVIDER API key: " NEW_KEY <&3
        printf '\n' >&3
        [[ -n "$NEW_KEY" ]] || die "API key cannot be empty"
        printf -v "$KEY_ENV" '%s' "$NEW_KEY"
        export "${KEY_ENV?}"
    fi
elif [[ "$PROVIDER" == "codex" ]]; then
    if [[ ! -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]]; then
        command -v codex >/dev/null 2>&1 ||
            die "Codex CLI is required for subscription access: https://github.com/openai/codex"
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

if "$NO_VERIFY"; then
    printf 'Skipping live credential verification (--no-verify).\n'
else
    printf 'Verifying credentials with one minimal model request...\n'
    if ! seed_llm prompt --no-log --model "$MODEL" \
        "Reply with only OK." >/dev/null; then
        die "live verification failed; check the key, account credit, and model access"
    fi
    printf 'Credentials and model verified.\n'
fi

if [[ -n "$NEW_KEY" ]]; then
    if ! printf '%s\n' "$NEW_KEY" | seed_llm keys set "$KEY_NAME" >/dev/null; then
        die "llm could not store the key"
    fi
    unset NEW_KEY
    unset "$KEY_ENV"
    printf 'Stored the %s key with llm.\n' "$KEY_NAME"
fi

cat >run_seed.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[[ -n "${OPENROUTER_API_KEY:-}" && -z "${OPENROUTER_KEY:-}" ]] && export OPENROUTER_KEY="$OPENROUTER_API_KEY"
[[ -n "${GEMINI_API_KEY:-}" && -z "${LLM_GEMINI_KEY:-}" ]] && export LLM_GEMINI_KEY="$GEMINI_API_KEY"
EOF
printf 'DEFAULT_MODEL=%q\n' "$MODEL" >>run_seed.sh
cat >>run_seed.sh <<'EOF'
exec ./seed.py -m "${SEED_MODEL:-$DEFAULT_MODEL}" "$@"
EOF
chmod +x run_seed.sh

printf 'Planting seed with %s...\n' "$MODEL"
if "$NO_RUN"; then
    uvx --quiet --from "$SEED_UVX_FROM" seed -m "$MODEL" </dev/null
    printf 'Ready. Start it with ./run_seed.sh\n'
else
    require_tty
    exec uvx --quiet --from "$SEED_UVX_FROM" seed -m "$MODEL" <&3
fi
