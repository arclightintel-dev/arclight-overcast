#!/bin/sh
# Encode captured frames into a seamless 10s loop (see README.md).
set -e
HERE="$(dirname "$0")"
FF="$HERE/node_modules/ffmpeg-static/ffmpeg"
FR="$HERE/frames"
OUT="${1:-$HERE/../../bh-loop.mp4}"
POSTER="${2:-$HERE/../../bh-poster.jpg}"

"$FF" -y \
  -framerate 24 -i "$FR/f%04d.png" \
  -framerate 24 -i "$FR/f%04d.png" \
  -filter_complex "[0:v]trim=start_frame=240:end_frame=288,setpts=PTS-STARTPTS,fps=24,settb=AVTB[a];[1:v]trim=start_frame=0:end_frame=240,setpts=PTS-STARTPTS,fps=24,settb=AVTB[b];[a][b]xfade=transition=fade:duration=2:offset=0,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -crf 20 -preset slow -movflags +faststart -an "$OUT"

"$FF" -y -i "$OUT" -frames:v 1 -q:v 2 "$POSTER"
ls -la "$OUT" "$POSTER"
