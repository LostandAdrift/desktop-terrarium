#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terrarium_output="${1:-/tmp/terrarium-previews}"
mkdir -p -- "$terrarium_output"
terrarium_output="$(realpath -- "$terrarium_output")"
terrarium_qt_bin="${TERRARIUM_QT_BIN:-/usr/lib/qt6/bin}"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1
"$terrarium_qt_bin/qml" tests/Render.qml -- --output "$terrarium_output/preview.png"
"$terrarium_qt_bin/qml" tests/Render.qml -- --moss --output "$terrarium_output/moss.png"
"$terrarium_qt_bin/qml" tests/Render.qml -- --dawn --output "$terrarium_output/dawn.png"
"$terrarium_qt_bin/qml" tests/Render.qml -- --compact --output "$terrarium_output/compact.png"
"$terrarium_qt_bin/qml" tests/Render.qml -- --journal --output "$terrarium_output/journal.png"
"$terrarium_qt_bin/qml" tests/Render.qml -- --guide --output "$terrarium_output/guide.png"
if [[ "${2:-}" == --video ]]; then
  command -v ffmpeg >/dev/null
  terrarium_frames="$(mktemp -d /tmp/terrarium-frames.XXXXXX)"
  trap 'rm -rf -- "$terrarium_frames"' EXIT
  "$terrarium_qt_bin/qml" tests/Record.qml -- --output "$terrarium_frames"
  ffmpeg -hide_banner -loglevel error -y -framerate 20 -i "$terrarium_frames/frame-%04d.png" \
    -c:v libvpx-vp9 -b:v 0 -crf 30 -pix_fmt yuv420p -an "$terrarium_output/terrarium.webm"
fi
printf 'Synthetic previews saved in %s\n' "$terrarium_output"
