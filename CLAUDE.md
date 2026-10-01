# CLAUDE.md — Top Gear Challenge (BeamMP game mode)

A multiplayer "Top Gear challenge" for BeamNG.drive via BeamMP: players buy a cheap car, drive
between events on a stock map (West Coast USA by default), race, visit workshops, and are scored on
event results plus how drivable their car still is at the end. No map files are modified.

Owner: Ryan. Prefers **iterative, working-code responses**: build it, test it, ship it, then explain
in plain language. Every change ends with a short "what changed / how to test" note.

Repo: github.com/Ryan-Shaffer-P/Beam-TopGear (default branch `main`). Developed in Claude Desktop
chats until 2026-09-30, then moved to Claude Code. Work on a branch; push/merge only when Ryan asks.

## Repository layout

```
Resources/Server/TopGear/main.lua      server plugin (~3,100 lines) - the authority on all game state
Resources/Server/TopGear/courses.json  saved course library (kept in the repo; copy back from the server)
Resources/Client/topgear.zip           client mod, BUILT from client/ (never edit the zip by hand)
client/lua/ge/extensions/topgear.lua   client GE extension (~2,000 lines): HUD, ImGui window, input locks, car work
client/scripts/topgear/modScript.lua   loads the extension (extensions.load + manual unload mode)
README.md                              player/admin documentation - keep it in sync with every feature change
MP3s/                                  sound clips, not wired into the mod yet
```

Runtime files written by the server next to main.lua: `config.json` (settings + the working course,
git-ignored), `courses.json` (saved course library, tracked). `luac.out` is git-ignored.
Install = copy `Resources/` into the BeamMP server.

## Runtimes (they differ - test against both)

- **Server:** BeamMP server Lua (treat as Lua 5.3) with `MP.*`, `Util.Json*`, `FS.*`.
  Handlers are globals named `TG_*`, registered with `MP.RegisterEvent`. Tick = `tg_tick` every 250 ms.
- **Client:** BeamNG game-engine Lua = **LuaJIT 2.1** (globals like `be`, `core_*`, `ui_imgui`, `jsonEncode`).
- **Vehicle Lua (vlua):** code sent as strings via `veh:queueLuaCommand(...)`; replies come back with
  `obj:queueGameEngineLua("extensions.topgear.onX(...)")`. Templates (`VLUA`, `CARGO_VLUA`) go through
  `string.format`, so a literal `%` inside them must be written `%%`.
- Server <-> client events: server `MP.TriggerClientEvent(pid, "tg_x", json)`; client
  `AddEventHandler("tg_x", fn)` / `TriggerServerEvent("tg_x", json)`. Every window button sends the same
  text as a chat command via `tg_ui_cmd`, so permission checks live in one place.

## Architecture

**Server phases:** `idle -> dealer -> travel -> countdown -> event -> (workshop) -> ... -> finale -> results`.
- A course is a pool of events (`cfg.events`); `/tg start` snapshots the enabled ones into `game.events`
  (the session). `game.stage` indexes the session. Course edits use `cfg.events`; game flow uses `game.events`.
- Event types: `race` (destination), `circuit` (start point = start/finish line, laps), `timetrial`,
  `speedtrap`, `parking` (multiple bays in order), `fragile`, `economy`, `slalom`, `trailer`.
  Solo (one at a time) by default: timetrial, parking, slalom (`isSolo`, overridable per event).
- Run logic: `tickRoute` / `tickSlalom` / `tickParking` / `tickSpeedtrap`; all scoring in `finalizeScore`
  (lower `score` wins; speedtrap uses `-best`). Results -> prizes/points -> workshop every
  `workshopEvery` events (never after the last) -> finale drivability inspection -> summary table.
- Economy: dealer prices (manual or imported game values), faults for cash (setup faults change config,
  physics faults run in vlua), workshop billing (parts from the client's before/after rebuild diff,
  labour once, damage-drop repairs), $1,500 overdraft (`creditLimit`), tows/respawns/unstick.
- Workshops: anywhere, or at course `workshopSpots` (imported gas stations / placed) + the dealership.
  The dealership stays a workshop after the doors close until the player drives away.

**Client:** receives `tg_state` (phase, cash, target, allow-flags, lights) and renders the HUD,
ground arrows, target beacon, ImGui window (Results / Status / Dealership / Admin tabs, Top Gear colour
theme), F1 start lights (own movable window), input locks (`core_input_actionFilter`), and does the
car-side work: faults, tow/unstick placement, trailer spawn + load measurement, fuel/damage reports,
parts snapshots/diffs, reverting refused parts.

## Hard-won rules (read before editing)

1. **Forward-declaration order.** A function defined above a `local` that it uses compiles the name as a
   *global* (nil at runtime) - this bit us ~10 times (most recently `addLog` in `onTheme`). Declare shared
   helpers/state at the top (`local copyTable, readParts, ...`) and assign later (`copyTable = function(...)`).
   Check the client with
   `luac5.3 -l topgear.lua | grep -oE '(GET|SET)TABUP.*_ENV "[A-Za-z_]+"' | grep -oE '"[A-Za-z_]+"' | sort -u`
   (only real BeamNG/BeamMP globals may appear). For the server this listing is unreliable (>255 constants):
   rely on the strict-mode simulations.
2. **Never `cond and false or x`** in Lua - it can't yield `false`. Use explicit `if`.
3. **Never return 1 from `onVehicleEdited`** for a normal edit outside a workshop: BeamMP removes the car.
   Accept it and put parts back via the client (`tg_revertparts`). Paint is just accepted.
4. **BeamMP reports a part change's rebuild as a reset.** Resets are never fined in workshops; repairs are
   billed from a real damage drop (`TG_onReport`), excused by `repairPending` / `towPending` /
   `respawnPending` / `faultEditUntil` windows.
5. **Any part/tuning change respawns the car and wipes its damage** - always bill or account for that.
6. **Part data comes in two formats:** flat `parts` or nested `partsTree` (newer BeamNG). Use
   `readParts` / `walkTree`; never assume one.
7. **Saved `config.json` overrides code defaults.** When changing a default, add a one-time migration
   (`cfg.migrations.*`) and tell Ryan if manual edits are needed.
8. **ImGui:** every style push must be popped in the same frame (count pushes as they happen); read
   constants via `imGet` (pcall); open windows with a `BoolPtr`, not nil; wrap drawing in `section()`;
   the theme switches itself off if it breaks the window (`ui.noTheme`, `/tg theme`).
9. **Lua 5.3 `%d` needs integers** - `math.floor` before formatting.
10. **Spawns/edits by the mod itself** must be allowed by the server: `spawnAllow` (trailers),
    `faultEditUntil` (setup faults, tow restores).
11. **Wrap every BeamNG/BeamMP internal in `pcall`** with a logged fallback (`warn()` on the client;
    players filter "topgear" in the game console). These APIs change between game versions.

## BeamNG/BeamMP APIs used but NOT verified in game (suspect these first)

`core_vehicle_partmgmt.setConfig/setPartsTreeConfig/setPartsConfig/setConfigVars` (faults, reverts),
`spawnNewVehicle` with a serialized config table (trailer), vlua `v.data.nodes[].partOrigin` +
`obj:getNodePosition` (trailer load %), `quatFromDir` convention + `setPositionRotation` (tow/unstick,
self-verifying), `energyStorage.getStorages` (fuel), `freeroam_facilities` (gas stations),
`getSpawnWorldOOBB` / `be:getObjectOOBB*` (trailer placement), `beamstate.activateAutoCoupling`,
ImGui draw lists / tables / style pushes (lights, theme). When Ryan reports a bug in one of these, ask
for the `/tg diag` "Client error" line or the matching `[TopGear]` server-console line.

## Testing workflow (do this for every change)

1. Syntax: `luac5.3 -p` **and** `luajit -e 'assert(loadfile("file.lua"))'` on both files.
   (As of 2026-09-30 neither is installed on this Mac - install via Homebrew before relying on this.)
2. Globals check on the client (rule 1).
3. Simulations: plain Lua scripts that stub `MP`/`Util`, fake BeamNG globals (`be`, vehicles, partmgmt,
   vlua envs), and a fake `ui_imgui` that records text/buttons/circles and lets the test "click" by label.
   They run the real server and client files together, in **strict mode** (`setmetatable(_G, ...)` errors
   on undeclared global reads/writes), under both `lua5.3` and `luajit`.
   The Desktop-era harness (`sim13` full six-event three-player regression, `sim22`/`sim30`/`sim33`
   workshop billing/overdraft/dealership, `sim31`/`sim37` trailer + lights, `sim32`/`sim36` circuits,
   `sim38`/`sim39` theme + standings) **was not carried over**. Rebuild it under `tests/` on the same
   pattern before changing gameplay code.
4. Beware harness artifacts (wrong test coordinates, sequencing): say so explicitly when a failure is the
   test's fault, not the mod's.
5. Final check is always in-game on Ryan's BeamMP server.

## Release steps

1. Bump `SERVER_VERSION` (main.lua) and `VERSION` (topgear.lua) - `/tg diag` prints both; Ryan uses them to
   confirm the right files are installed.
2. Rebuild the client zip:
   `cd client && rm -f ../Resources/Client/topgear.zip && zip -qr ../Resources/Client/topgear.zip lua scripts -x '*luac.out' '*.DS_Store'`
3. Update README.md for any behaviour change.
4. Commit on a branch. Push / open a PR / merge to `main` only when Ryan asks.
5. Tell Ryan which files changed, whether a server restart/reconnect is needed, and how to test.

## Quick command reference

Players: `/tg menu | status | dealer | ready | go | repair | fix <id> | tow | respawn | unstick | hitchup |
faults | fault take/undo <id> | quote | standings | diag | partsdiag | lights | lightstest | theme`.
Admins: `start [force] | next | stop | budget | setcash | give | workshop <min> | workshopevery <n> |
importprices | gameprices | course list/save/load/new/delete | addevent/delevent/enable/moveevent |
setstart/addcp/undocp/clearcp/settrap/addbay/undobay/clearbays/addvia/undovia/clearvia/setfinale |
settype/setlaps/settime/rename | addworkshop/undoworkshop/clearworkshops/importgas |
trailersave/trailercones/trailertest | fault test/testoff`. The ImGui window exposes all of these.

## Open items

From the last Desktop session (server 0.8.2 / client 0.8.1):
- Colour theme broke the menu on Ryan's BeamNG; fail-safe shipped - waiting for the `/tg diag` theme line.
- Start lights: fixed (window opened with a BoolPtr) - awaiting in-game confirmation.
- Trailer: save now records every slot + tuning; awaiting confirmation that straps stay removed and the
  load % reading works.
- Circuit: start point is the start/finish line; line only counts after 40 m away; course edits now
  auto-save to config.json (restarts used to lose unsaved course edits).
- Hitch checks were removed by request; players fit hitches in workshops.

**Repo vs Desktop mismatch (2026-09-30):** the GitHub upload has `SERVER_VERSION = "0.8.1"` and course
edits only `markDirty()` (no auto-save), so it appears to predate server 0.8.2. Get the 0.8.2 `main.lua`
from Ryan before building on the server.
