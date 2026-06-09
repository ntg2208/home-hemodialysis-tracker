#!/usr/bin/env bash
# take_screenshots.sh — generates demo screenshots of every app screen.
#
# Usage:
#   cd flutter/
#   bash scripts/take_screenshots.sh
#
# Outputs PNGs to: test/screenshots/goldens/
#
# On first run (or after a screen changes) use --update to regenerate the
# golden files. Without the flag, the test will FAIL if any golden is missing
# or differs — useful as a regression check in CI.
#
# Requirements:
#   • Flutter SDK on PATH
#   • No device or emulator needed (widget/golden tests run headless)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$FLUTTER_DIR/test/screenshots/goldens"

cd "$FLUTTER_DIR"

UPDATE_FLAG=""
if [[ "${1:-}" == "--update" || "${1:-}" == "-u" ]]; then
  UPDATE_FLAG="--update-goldens"
  echo "→ Running in UPDATE mode — golden files will be regenerated."
else
  echo "→ Running in CHECK mode — pass --update to regenerate goldens."
fi

echo ""
echo "Flutter version:"
flutter --version 2>&1 | head -2
echo ""

echo "→ Running screenshot tests..."
flutter test test/screenshots/screenshot_test.dart $UPDATE_FLAG \
  --reporter=expanded

echo ""
echo "✓ Done. Screenshots in: $OUT_DIR"
echo ""

# List what was generated / checked.
if [[ -d "$OUT_DIR" ]]; then
  echo "Files:"
  ls -lh "$OUT_DIR"/*.png 2>/dev/null || echo "  (none yet — run with --update first)"
fi
