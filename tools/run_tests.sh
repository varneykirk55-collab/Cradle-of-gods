#!/usr/bin/env bash
# Headless simulation + powers test, then rendered screenshots + synthetic input test.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/workspace/tools/godot/godot}
"$GODOT" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT" --headless --path . --fixed-fps 30 -- --autotest | tee tools/last_autotest.log | grep -E "STAT|PASS|FAIL|DONE"
if command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x900 -- --shots \
    | tee tools/last_shots.log | grep -E "SCREENSHOT|PASS|FAIL|SHOTS"
fi
