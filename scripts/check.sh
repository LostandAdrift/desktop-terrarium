#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/*.test.cjs
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi
terrarium_qt_bin="${TERRARIUM_QT_BIN:-/usr/lib/qt6/bin}"
if [[ -x "$terrarium_qt_bin/qmltestrunner" ]]; then
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    "$terrarium_qt_bin/qmltestrunner" -input tests -o -,txt
  bash scripts/check-postcard-scale.sh
else
  echo 'QtQuick tests require qmltestrunner. Set TERRARIUM_QT_BIN to its directory.' >&2
  exit 1
fi
