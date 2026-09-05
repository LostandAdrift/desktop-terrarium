#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terrarium_qt_bin="${TERRARIUM_QT_BIN:-/usr/lib/qt6/bin}"
for terrarium_scale in 1.25 1.5 1.75 2; do
  QT_SCALE_FACTOR="$terrarium_scale" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    "$terrarium_qt_bin/qmltestrunner" -input tests/tst_postcard.qml TerrariumPostcard::test_native_dimensions_and_complete_first_frame -o -,txt
done
