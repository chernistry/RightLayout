#!/usr/bin/env bash
set -euo pipefail

# Deprecated wrapper (kept for compatibility).
# Canonical entrypoint: `./rightlayout.sh train coreml`

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Quick preset: smaller dataset/epochs, usually enough for smoke-testing the pipeline.
export RightLayout_BASE_SAMPLES="${RightLayout_BASE_SAMPLES:-500000}"
export RightLayout_BASE_EPOCHS="${RightLayout_BASE_EPOCHS:-20}"
export RightLayout_BASE_PATIENCE="${RightLayout_BASE_PATIENCE:-8}"
export RightLayout_HE_QWERTY_SAMPLES="${RightLayout_HE_QWERTY_SAMPLES:-150000}"
export RightLayout_HE_QWERTY_EPOCHS="${RightLayout_HE_QWERTY_EPOCHS:-10}"
export RightLayout_MAX_CORPUS_WORDS="${RightLayout_MAX_CORPUS_WORDS:-500000}"

exec "${ROOT_DIR}/rightlayout.sh" train coreml

