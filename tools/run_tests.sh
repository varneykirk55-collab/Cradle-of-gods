#!/usr/bin/env bash
# 1) Headless regression suite (simulation, terrain/land tools, God Hand, religion,
#    heresy, ecosystem, all powers, speed, long-run stability).
# 2) Rendered screenshot tour + synthetic OS-level keyboard/mouse input test (needs xvfb).
# Set GODOT=/path/to/godot (4.3+) if it is not on PATH.
set -eo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$(command -v godot || command -v godot4 || echo godot)}
"$GODOT" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT" --headless --path . --fixed-fps 30 -- --autotest | tee tools/last_autotest.log | grep -E "^(STAT|PASS|FAIL|PERF)|DONE"
if command -v xvfb-run >/dev/null && [ -z "$SKIP_SHOTS" ]; then
  xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x900 -- --shots \
    | tee tools/last_shots.log | grep -E "SCREENSHOT|PASS|FAIL|SHOTS"
fi
