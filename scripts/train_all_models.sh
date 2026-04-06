#!/usr/bin/env bash
set -euo pipefail

# Deprecated wrapper (kept for compatibility).
# Canonical entrypoint: `./rightlayout.sh train all`

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

quick=0
ultra=0
yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      quick=1
      shift
      ;;
    --ultra)
      ultra=1
      shift
      ;;
    --yes|-y)
      yes=1
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      echo "Usage: ./train_all_models.sh [--quick] [--ultra] [--yes]" >&2
      exit 2
      ;;
  esac
done

if [[ "${quick}" == "1" ]]; then
  # Smaller preset (still uses the same modern pipeline).
  export RightLayout_BASE_SAMPLES="${RightLayout_BASE_SAMPLES:-1500000}"
  export RightLayout_BASE_EPOCHS="${RightLayout_BASE_EPOCHS:-40}"
  export RightLayout_BASE_PATIENCE="${RightLayout_BASE_PATIENCE:-10}"
  export RightLayout_HE_QWERTY_SAMPLES="${RightLayout_HE_QWERTY_SAMPLES:-250000}"
  export RightLayout_HE_QWERTY_EPOCHS="${RightLayout_HE_QWERTY_EPOCHS:-12}"
  export RightLayout_MAX_CORPUS_WORDS="${RightLayout_MAX_CORPUS_WORDS:-800000}"
fi

args=()
[[ "${ultra}" == "1" ]] && args+=(--ultra)
[[ "${yes}" == "1" ]] && args+=(--yes)

exec "${ROOT_DIR}/rightlayout.sh" train all "${args[@]}"

