#!/usr/bin/env bash
# Convert MP3s/*.mp3 into the client mod's sound folder as .ogg (what BeamNG's audio engine plays),
# with matched loudness: -9 LUFS (loud, like a TV advert - Ryan found -16 too quiet next to the game's own
# sounds). Runs ffmpeg in a throwaway container (the topgear-beammp image), so nothing is installed on this Mac. Re-run after adding or replacing clips, then rebuild the zip.
#   Clip id = file name without the extension and any trailing "_XXXXXXX" download tag,
#   lower case, "_" -> "-".   e.g. top-gear-theme-intro_I3NPtog.mp3 -> top-gear-theme-intro.ogg
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.docker/bin:$PATH"
out=client/art/sound/topgear
mkdir -p "$out"
rm -f "$out"/*.ogg
docker run --rm -v "$PWD:/repo" -w /repo --entrypoint bash topgear-beammp -c '
  set -e
  apt-get update -qq >/dev/null && apt-get install -y -qq ffmpeg >/dev/null 2>&1
  for f in MP3s/*.mp3; do
    base=$(basename "$f" .mp3)
    id=$(echo "$base" | sed -E "s/_[A-Za-z0-9]{6,8}$//" | tr "A-Z_" "a-z-")
    # two passes: measure, then exactly the gain it needs (loudnorm alone misses on short clips);
    # a limiter catches the peaks (-1.5 dBFS) so nothing crackles
    i=$(ffmpeg -nostats -i "$f" -af ebur128 -f null - 2>&1 | sed -n "s/^ *I: *\(-*[0-9.]*\) LUFS.*/\1/p" | tail -1)
    gain=$(awk -v i="$i" "BEGIN { print -9 - i }")
    ffmpeg -loglevel error -y -i "$f" -af "volume=${gain}dB,alimiter=limit=0.84:attack=1:release=50:level=false" \
      -ar 44100 -c:a libvorbis -q:a 4 "'"$out"'/$id.ogg"
    echo "  $id"
  done
'
echo "$(ls "$out"/*.ogg | wc -l | tr -d ' ') clips in $out ($(du -sh "$out" | cut -f1))"
