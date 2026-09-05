#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terrarium_runtime="$(mktemp -d /tmp/terrarium-qs-test.XXXXXX)"
trap 'rm -rf -- "$terrarium_runtime"' EXIT
mkdir -p "$terrarium_runtime/runtime" "$terrarium_runtime/scripts"
mkdir -m 700 "$terrarium_runtime/run"
terrarium_test="${1:-NativeStore}"
case "$terrarium_test" in
  NativeStore) terrarium_timeout=40s ;;
  NativeLifecycle) terrarium_timeout=70s ;;
  *) printf 'Unknown store test: %s\n' "$terrarium_test" >&2;exit 2 ;;
esac
cp "tests/$terrarium_test.qml" "$terrarium_runtime/shell.qml"
cp Model.js "$terrarium_runtime/Model.js"
cp runtime/Habitat.qml runtime/ObserverLease.qml runtime/qmldir "$terrarium_runtime/runtime/"
cp scripts/collect.py "$terrarium_runtime/scripts/"
# Quickshell's scanner requires imported modules inside the config folder.
# A temporary, source-identical test config also avoids scanning UI modules.
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
  XDG_RUNTIME_DIR="$terrarium_runtime/run" env -u WAYLAND_DISPLAY -u DISPLAY \
  timeout "$terrarium_timeout" quickshell --path "$terrarium_runtime/shell.qml" --no-color
