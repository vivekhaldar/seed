#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Species checkout default. A planted runner replaces this with the cap
# chosen at planting time. SEED_OUTPUT_CAP overrides one session.
PLANTED_OUTPUT_CAP=10000
exec ./seed.py --output-cap "${SEED_OUTPUT_CAP:-$PLANTED_OUTPUT_CAP}" "$@"
