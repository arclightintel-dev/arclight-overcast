#!/bin/sh
# Encode captured frames into a seamless 10s loop (see README.md).
# Produces BOTH page sources (webm first in the <video>, mp4 fallback) plus the
# poster, so a regeneration can never leave the formats out of sync.
set -e
HERE="$(dirname "$0")"
FF="$HERE/node_modules/ffmpeg-static/ffmpeg"
FR="$HERE/frames"
OUT="${1:-$HERE/../../bh-loop.mp4}"
WEBM="${OUT%.mp4}.webm"
POSTER="${2:-$HERE/../../bh-poster.jpg}"

LOOP_FILTER="[0:v]trim=start_frame=240:end_frame=288,setpts=PTS-STARTPTS,fps=24,settb=AVTB[a];[1:v]trim=start_frame=0:end_frame=240,setpts=PTS-STARTPTS,fps=24,settb=AVTB[b];[a][b]xfade=transition=fade:duration=2:offset=0,format=yuv420p[v]"

"$FF" -y \
  -framerate 24 -i "$FR/f%04d.png" \
  -framerate 24 -i "$FR/f%04d.png" \
  -filter_complex "$LOOP_FILTER" \
  -map "[v]" -c:v libx264 -crf 20 -preset slow -movflags +faststart -an "$OUT"

"$FF" -y \
  -framerate 24 -i "$FR/f%04d.png" \
  -framerate 24 -i "$FR/f%04d.png" \
  -filter_complex "$LOOP_FILTER" \
  -map "[v]" -c:v libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -an "$WEBM"

"$FF" -y -i "$OUT" -frames:v 1 -q:v 2 "$POSTER"
ls -la "$OUT" "$WEBM" "$POSTER"
