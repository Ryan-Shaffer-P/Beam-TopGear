#!/usr/bin/env bash
# Run the test suite under every Lua that matches a real runtime:
#   LuaJIT  - the BeamNG game client
#   Lua 5.3 - the BeamMP server (inside the topgear-beammp Docker image, if it's built)
#   lua     - whatever Homebrew installed (5.5 here; close to 5.3, catches most of the same things)
# Usage: tests/run.sh [filter]      (from anywhere; filter = part of a test or file name)
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.docker/bin:$PATH"
filter="${1:-}"
status=0
ran=0

run() {   # label, command...
  local label="$1"; shift
  echo "=== $label"
  if "$@" tests/run.lua $filter; then :; else status=1; fi
  ran=$((ran + 1))
  echo
}

command -v luajit >/dev/null && run "LuaJIT (game client runtime)" luajit
if command -v docker >/dev/null && docker image inspect topgear-beammp >/dev/null 2>&1; then
  echo "=== Lua 5.3 (BeamMP server runtime, in Docker)"
  if docker run --rm --entrypoint lua5.3 -v "$PWD:/repo:ro" -w /repo topgear-beammp tests/run.lua $filter; then :; else status=1; fi
  ran=$((ran + 1))
  echo
else
  echo "=== Lua 5.3 skipped: build the server image first (docker compose -f server/compose.yaml build)"
  echo
fi
command -v lua >/dev/null && run "$(lua -v 2>&1 | cut -d' ' -f1-2) (Homebrew)" lua

if [ "$ran" -eq 0 ]; then echo "No Lua interpreter found."; exit 1; fi
[ "$status" -eq 0 ] && echo "ALL PASSED" || echo "FAILURES - see above"
exit $status
