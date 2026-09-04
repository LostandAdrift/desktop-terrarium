#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terrarium_runtime="$(mktemp -d /tmp/terrarium-qs-test.XXXXXX)"
trap 'rm -rf -- "$terrarium_runtime"' EXIT
mkdir -p "$terrarium_runtime/runtime" "$terrarium_runtime/scripts"
mkdir -m 700 "$terrarium_runtime/run"
cp tests/NativeStore.qml "$terrarium_runtime/shell.qml"
cp Model.js "$terrarium_runtime/Model.js"
cp runtime/Habitat.qml runtime/qmldir "$terrarium_runtime/runtime/"
cp scripts/collect.py "$terrarium_runtime/scripts/"
# Quickshell's scanner requires imported modules inside the config folder.
# A temporary, source-identical test config also avoids scanning UI modules.
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software \
  XDG_RUNTIME_DIR="$terrarium_runtime/run" env -u WAYLAND_DISPLAY -u DISPLAY \
  timeout 40s quickshell --path "$terrarium_runtime/shell.qml" --no-color
