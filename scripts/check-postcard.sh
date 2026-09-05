#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terrarium_postcard_test="$(mktemp -d /tmp/terrarium-postcard-test.XXXXXX)"
trap 'rm -rf -- "$terrarium_postcard_test"' EXIT
mkdir -p "$terrarium_postcard_test/runtime" "$terrarium_postcard_test/scripts" "$terrarium_postcard_test/slow-bin"
mkdir -m 700 "$terrarium_postcard_test/run"
cp tests/NativePostcard.qml "$terrarium_postcard_test/shell.qml"
cp runtime/PostcardWriter.qml "$terrarium_postcard_test/runtime/"
printf 'PostcardWriter 1.0 PostcardWriter.qml\n' > "$terrarium_postcard_test/runtime/qmldir"
cp scripts/postcard.py "$terrarium_postcard_test/scripts/"
terrarium_quickshell="$(command -v quickshell)"
terrarium_timeout="$(command -v timeout)"
terrarium_python="$(command -v python3)"
# Fault injection affects only the writer's subprocess lookup in this isolated
# test shell. The real helper is used for every normal reservation/cancel case.
printf '#!%s\n' "$terrarium_python" > "$terrarium_postcard_test/slow-bin/python3"
cat >> "$terrarium_postcard_test/slow-bin/python3" <<'PY'
import signal
import time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
time.sleep(60)
PY
chmod 700 "$terrarium_postcard_test/slow-bin/python3"

for terrarium_case in normal failed-start helper-timeout; do
  terrarium_case_directory="$terrarium_postcard_test/postcards ü $terrarium_case"
  terrarium_case_path="$PATH"
  if [[ "$terrarium_case" == failed-start ]]; then terrarium_case_path="$terrarium_postcard_test/missing-bin"; fi
  if [[ "$terrarium_case" == helper-timeout ]]; then terrarium_case_path="$terrarium_postcard_test/slow-bin"; fi
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    XDG_RUNTIME_DIR="$terrarium_postcard_test/run" TERRARIUM_POSTCARD_DIRECTORY="$terrarium_case_directory" \
    TERRARIUM_POSTCARD_SCENARIO="$terrarium_case" PATH="$terrarium_case_path" \
    /usr/bin/env -u WAYLAND_DISPLAY -u DISPLAY \
    "$terrarium_timeout" --kill-after=3s 35s "$terrarium_quickshell" --path "$terrarium_postcard_test/shell.qml" --no-color
done
"$terrarium_python" - "$terrarium_postcard_test" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
files = list(root.glob('postcards*/*.png'))
assert len(files) == 2 and all(path.stat().st_size > 0 for path in files), 'postcard test left an empty reservation or removed a completed fixture'
print('POSTCARD_FILES_PASS: only the two completed fixture files remain')
PY
