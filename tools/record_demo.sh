#!/usr/bin/env bash
# Records the scripted gameplay demo (scripts/shots.gd::_demo) with Godot's
# movie maker, then converts it to MP4 with ffmpeg.
set -eo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$(command -v godot || command -v godot4 || echo godot)}
OUT=${1:-recordings/gameplay_demo}
mkdir -p "$(dirname "$OUT")"
RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
command -v xvfb-run >/dev/null || RUN=()
"${RUN[@]}" "$GODOT" --path . --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 \
  --write-movie "$OUT.avi" -- --demo
ffmpeg -y -loglevel error -i "$OUT.avi" -c:v libx264 -pix_fmt yuv420p -crf 23 "$OUT.mp4"
rm -f "$OUT.avi" "$OUT.wav"
echo "recorded $OUT.mp4"
