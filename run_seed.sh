#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

has_model_flag() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m | --model) return 0 ;;
    esac
    shift
  done
  return 1
}

if [[ -f .seed-model ]] && ! has_model_flag "$@"; then
  model=$(tr -d '[:space:]' < .seed-model)
  if [[ -n "$model" ]]; then
    exec ./seed.py -m "$model" "$@"
  fi
fi
exec ./seed.py "$@"
