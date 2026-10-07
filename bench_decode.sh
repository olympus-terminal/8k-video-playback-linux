#!/usr/bin/env bash
# Marginal decode speed (frames/s) of a video file for each mpv hwdec mode.
#
# Runs mpv headless (--vo=null --untimed) twice per mode, with a small and a
# large frame count, and reports (N2 - N1) / (t2 - t1). Subtracting the two
# runs removes startup/seek time, which is large for huge files on slow disks.
#
# Limits: no window, no HDR/tone-mapping/scaling, so this measures decode (plus
# frame copy-back for *-copy modes) only, not full on-screen playback.
#
# Usage: ./bench_decode.sh FILE [START_SECONDS] [MODES...]
#   defaults: START_SECONDS=600, MODES="no nvdec-copy nvdec"
set -euo pipefail

file=${1:?usage: $0 FILE [START_SECONDS] [MODES...]}
start=${2:-600}
shift $(( $# >= 2 ? 2 : $# ))
modes=(no nvdec-copy nvdec)
[ $# -gt 0 ] && modes=("$@")
n1=200
n2=800

command -v mpv >/dev/null || { echo "mpv not found" >&2; exit 1; }
echo "mpv: $(mpv --version | head -1)"
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,pix_fmt,avg_frame_rate \
  -of default=nw=1 "$file"

run() {  # mode frames -> seconds
  local s e
  s=$(date +%s.%N)
  timeout 600 mpv --no-config --hwdec="$1" --vo=null --ao=null --no-audio \
    --untimed --frames="$2" --start="$start" "$file" >/dev/null 2>&1 || true
  e=$(date +%s.%N)
  echo "$e - $s" | bc -l
}

printf '%-12s %10s %10s %12s\n' hwdec "t($n1)" "t($n2)" "fps"
for mode in "${modes[@]}"; do
  t1=$(run "$mode" $n1)
  t2=$(run "$mode" $n2)
  fps=$(echo "($n2 - $n1) / ($t2 - $t1)" | bc -l)
  printf '%-12s %9.1fs %9.1fs %12.1f\n' "$mode" "$t1" "$t2" "$fps"
done
