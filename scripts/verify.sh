#!/usr/bin/env bash
set -euo pipefail

# Deprecated wrapper (kept for compatibility).
# Canonical entrypoint: `./rightlayout.sh status` + `./rightlayout.sh test`

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 RightLayout Verification"
echo "===================="
echo ""

echo "✓ Swift:  $(swift --version | head -1)"
if command -v xcodebuild >/dev/null 2>&1; then
  echo "✓ Xcode:  $(xcodebuild -version | head -1)"
fi
echo ""

"${ROOT_DIR}/rightlayout.sh" status
echo ""
"${ROOT_DIR}/rightlayout.sh" test

echo ""
echo "✅ Verification complete."

