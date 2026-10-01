# Top Gear Challenge — BeamMP mod

A multiplayer game mode for BeamNG.drive via BeamMP: players buy a car on a budget, drive
legs between events, race for prize money, visit workshops, and finish with a drivability
inspection. Stock maps only. User-facing docs are in `README.md` (keep it updated when
behaviour or commands change — it is the player/admin manual).

Repo: github.com/Ryan-Shaffer-P/Beam-TopGear (default branch `main`). Development started in
Claude Desktop chats and moved to Claude Code on 2026-09-30.

## Layout

- `Resources/Server/TopGear/main.lua` — BeamMP **server** plugin (~3000 lines). Authoritative
  for all game state, money, scoring, phases, commands (`/tg ...`). Writes `config.json` and
  `courses.json` next to itself at runtime.
- `client/lua/ge/extensions/topgear.lua` — BeamNG **GE-Lua client** extension (~2000 lines).
  Displays state (HUD, ImGui window, start lights, nav arrows), blocks resets/menus, reads
  damage/parts/fuel, applies faults, moves cars for tow/unstick, spawns trailers.
- `client/scripts/topgear/modScript.lua` — loads the extension.
- `Resources/Client/topgear.zip` — **built artifact** sent to players. Rebuild after any client
  change: `cd client && rm -f ../Resources/Client/topgear.zip && zip -r ../Resources/Client/topgear.zip lua scripts -x '*luac.out' '*.DS_Store'`
- `MP3s/` — sound clips, not yet wired into the mod.
- `luac.out` (compiler output) and runtime `config.json` are git-ignored. `courses.json` (the
  saved course library) is kept in the repo — copy it back from the server after building courses.

## Architecture notes

- Server ↔ client only via BeamMP events. Server → client: `MP.TriggerClientEvent(pid, "tg_*", json)`.
  Client → server: `TriggerServerEvent("tg_*_reply"/"tg_ui_cmd", ...)`. Every UI button sends the
  same text as a chat command through `tg_ui_cmd`, so permission checks live in one place.
- Server phases: `idle → dealer → travel → countdown → event → (workshop) → … → finale → results`.
  Server ticks every 250 ms (`TICK_MS`) and polls positions.
- Vehicle-side code is sent as strings (`VLUA`, `CARGO_VLUA`) via `queueLuaCommand`; results come
  back with `obj:queueGameEngineLua("extensions.topgear.<fn>(...)")`. In those templates `%` must
  be escaped as `%%` because they pass through `string.format`.
- BeamNG internals change between versions: every call into game APIs is wrapped in `pcall`
  with a logged fallback (`warn()` on the client, filter "topgear" in the game console). Keep
  that pattern for new code.
- Don't cancel vehicle edits server-side — BeamMP deletes the car when you do. The client
  reverts disallowed part changes instead.
- Version strings: `VERSION` in the client and `SERVER_VERSION` in the server — bump both together.

## Testing

No Lua toolchain is installed locally and there are no automated tests; verification is
in-game on the user's BeamMP server. Watch for `local function` ordering in the client:
a function used before its `local` definition resolves to a nil global at runtime
(forward-declare it at the top, as done for `onPartsDiag`, `readParts`, etc.).
