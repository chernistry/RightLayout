#!/usr/bin/env bash
set -euo pipefail

# Deprecated wrapper (kept for compatibility).
# Canonical entrypoint: `./rightlayout.sh logs stream`

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${ROOT_DIR}/rightlayout.sh" logs stream

