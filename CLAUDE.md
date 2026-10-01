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
client/art/sound/topgear/*.ogg         sound bites, GENERATED from MP3s/ by tools/convert-sounds.sh (Docker ffmpeg)
README.md                              player/admin documentation - keep it in sync with every feature change
MP3s/                                  source sound clips (see client/art/sound/topgear)
server/                                local BeamMP test server in Docker (see server/README.md)
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
- Event types: `race` (destination), `circuit` (start point = start/finish line, laps),
  `speedtrap` (one run through the trap by default, `runs`), `parking` (multiple bays in order), `fragile`, `economy`, `slalom`, `trailer`.
  Every event has a **mode**: race (everyone at once) or time trial (one at a time) = `e.solo`
  (`isSolo`; nil = type default: speedtrap/parking/slalom trial, rest race). `/tg setmode`. There is no
  `timetrial` type since 0.8.4 - `migrateEvents` turns old ones into `race` + `solo = true`.
- Run logic: `tickRoute` / `tickSlalom` / `tickParking` / `tickSpeedtrap`; all scoring in `finalizeScore`
  (lower `score` wins; speedtrap uses `-best`). Results -> prizes/points -> workshop every
  `workshopEvery` events (never after the last) -> finale drivability inspection -> summary table.
- Economy: dealer prices (manual or imported game values), faults for cash (setup faults change config,
  physics faults run in vlua), workshop billing (parts from the client's before/after rebuild diff,
  labour once, damage-drop repairs), $1,500 overdraft (`creditLimit`), tows/respawns/unstick.
  Roadside help (`roadsideCost`): workshop repair price x `roadsideMarkup` (1.25) + `towFee` 1000 /
  `respawnFee` 500, and -`towPenaltyPoints` (1) each at the results; an unstick that repairs the car
  bills the roadside repair once (reset event or damage drop, `billUnstickRepair`).
- Workshops: anywhere, or at course `workshopSpots` (imported gas stations / placed) + the dealership.
  The dealership stays a workshop after the doors close until the player drives away.

**Client:** receives `tg_state` (phase, cash, target, allow-flags, lights) and renders the HUD,
ground arrows, target beacon, ImGui window (Results / Status / Dealership / Admin tabs, Top Gear colour
theme), F1 start lights and the finish flag (own movable windows; the server sends `tg_finish` when a run ends), input locks (`core_input_actionFilter`), and does the
car-side work: faults, tow/unstick placement, trailer spawn + load measurement, fuel/damage reports,
parts snapshots/diffs, reverting refused parts.

## Hard-won rules (read before editing)

1. **Forward-declaration order.** A function defined above a `local` that it uses compiles the name as a
   *global* (nil at runtime) - this bit us ~10 times (most recently `addLog` in `onTheme`). Declare shared
   helpers/state at the top (`local copyTable, readParts, ...`) and assign later (`copyTable = function(...)`).
   Check the client with
   `luac -l -p topgear.lua | grep -oE '(GET|SET)TABUP.*_ENV "[A-Za-z_][A-Za-z0-9_]*"' | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | sort -u`
   (only real BeamNG/BeamMP globals may appear). For the server this listing is unreliable (>255 constants):
   rely on the strict-mode simulations.
2. **Never `cond and false or x`** in Lua - it can't yield `false`. Use explicit `if`.
3. **Never return 1 from `onVehicleEdited`** for a normal edit outside a workshop: BeamMP removes the car.
   Accept it and put parts back via the client (`tg_revertparts`). Paint is just accepted.
4. **BeamMP reports a part change's rebuild as a reset.** Resets are never fined in workshops; repairs are
   billed from a real damage drop (`TG_onReport`), excused by `repairPending` / `towPending` /
   `respawnPending` / `faultEditUntil` windows. **Parts billing is not excused by a time window** (that let
   players fit parts free right after a fault): the client marks its own config changes (`faults.ownRebuild`,
   set before a fault / fix / upgrade restore) and doesn't report that rebuild - everything `TG_onRebuild` gets
   is the player's.
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
11. **Never repair with a bare `obj:requestReset(RESET_PHYSICS)`** - it puts the car back at its *reset point*
    (where it spawned / was last reset), i.e. it teleports it. To repair where it stands use `repairInPlace` (client):
    `spawn.safeTeleport(car, pos, quatFromDir(dir))`, BeamNG's own "reset here". A reset followed by our own placement
    (tow/unstick `startMove`) is fine. The harness models this (`requestReset` -> `v.resetPos`).
12. **Lua allows at most 200 locals per chunk.** main.lua's top level is near it (~190): group new helpers into a
    table (like `Class.*`) instead of adding many top-level `local function`s. Check with
    `luac -l -l -p Resources/Server/TopGear/main.lua | awk '/^main/{m=1} m&&/^locals \(/{print; exit}'`.
13. **Don't assign to a `for` loop variable** (`for v in ... do v = ...`) - Lua 5.5 rejects it; use a new local.
14. **Wrap every BeamNG/BeamMP internal in `pcall`** with a logged fallback (`warn()` on the client;
    players filter "topgear" in the game console). These APIs change between game versions.

## BeamNG/BeamMP APIs used but NOT verified in game (suspect these first)

`core_vehicle_partmgmt.setConfig/setPartsTreeConfig/setPartsConfig/setConfigVars` (faults, reverts),
`spawnNewVehicle` with a serialized config table (trailer), vlua `v.data.nodes[].partOrigin` +
`obj:getNodePosition` (trailer load %), `quatFromDir` convention + `setPositionRotation` (tow/unstick,
self-verifying), `energyStorage.getStorages` (fuel), `freeroam_facilities` (gas stations),
`getSpawnWorldOOBB` / `be:getObjectOOBB*` (trailer placement), `beamstate.activateAutoCoupling`,
ImGui draw lists / tables / style pushes (lights, theme), sound playback (`Engine.Audio.playOnce` with a
mod file path, `be:executeJS` HTML audio - three methods tried in order, `/tg soundtest next` cycles). When Ryan reports a bug in one of these, ask
for the `/tg diag` "Client error" line or the matching `[TopGear]` server-console line.

## Testing workflow (do this for every change)

1. Syntax on both files: server's exact Lua 5.3 via the test image
   (`docker run --rm --entrypoint luac5.3 -v "$PWD:/repo:ro" topgear-beammp -p /repo/<file>`) **and** LuaJIT
   (`luajit -e 'assert(loadfile("file.lua"))'`). Homebrew `lua`/`luac` on this Mac are 5.5 - close, not exact.
   Docker's CLI is in `~/.docker/bin` (not on the default PATH).
2. Globals check on the client (rule 1).
3. Simulations: `tests/run.sh [filter]` runs `tests/test_*.lua` under LuaJIT, Lua 5.3 (Docker image) and
   Homebrew Lua. `tests/lib/world.lua` loads the real main.lua + modScript.lua/topgear.lua in **strict**
   sandboxes (undeclared global read/write = error) with fake BeamMP (`MP`, `Util`, in-memory files),
   fake BeamNG per player (`be`, vehicles, partmgmt, `core_*`) and a fake `ui_imgui` (`tests/lib/imgui.lua`)
   that records frames, clicks buttons by label and checks push/pop balance. `w:assertClean()` fails on any
   handler error, server console error, client warn() or UI imbalance. Vehicle Lua (`queueLuaCommand`) runs
   in a per-car sandbox with fake engine/brakes/fuel/reset (`World:freshPhysics`); `queueGameEngineLua`
   replies run in the client. Trailers with a load part get simulated bed/load nodes, so CARGO_VLUA really measures the load share.
   Tests: `test_smoke.lua` (load, dealership, theme), `test_flag.lua` (finish flag), `test_traffic.lua` (admin traffic mode), `test_modes.lua` (race/time trial mode), `test_speedtrap.lua` (one run), `test_sounds.lua` (sound bites; the fake Engine.Audio checks the .ogg exists), `test_roadside.lua` (tow/respawn/unstick pricing), `test_parts.lua` (Parts tab; fake catalogue `World.partCatalogue`, `c.partsFormat = "tree"`), `test_faults.lua` (fault revamp; `w.rolls` pins the server's random draws), `test_classes.lua` (car classes; test cars carry BeamNG attributes in `MODELS[].info/trims`), `test_scoring.lua` (inspections, debt, faults, awards), `test_economy.lua` (energy: petrol vs electric), `test_trailer.lua` (cones + prebuilt load, hitching via
   `w:hitch`/`w:dropCargo`/`w:setLoad`, 70/30 scoring) and `test_session.lua` (full 5-event session, the
   successor of `sim13` - expected cash/points are hand-calculated in its comments; if a rule change
   moves them, recompute by hand rather than pasting the new output). Still to rebuild: workshop
   parts billing/overdraft/dealership upgrades, start lights, circuits, parking/slalom, course builder.
4. Beware harness artifacts (wrong test coordinates, sequencing): say so explicitly when a failure is the
   test's fault, not the mod's.
5. Real server: `docker compose -f server/compose.yaml restart`, then check `logs` for the
   `[TopGear] ... loaded` line and no `[LUA]` errors. The container mounts the repo's `Resources/`.
6. Final check is always in-game (Ryan joins via Direct Connect to this Mac, port 30814).

## Release steps

1. Bump `SERVER_VERSION` (main.lua) and `VERSION` (topgear.lua) - `/tg diag` prints both; Ryan uses them to
   confirm the right files are installed.
2. Rebuild the client zip:
   `cd client && rm -f ../Resources/Client/topgear.zip && zip -qr ../Resources/Client/topgear.zip lua scripts art -x '*luac.out' '*.DS_Store'`
3. Update README.md for any behaviour change.
4. Commit on a branch. Push / open a PR / merge to `main` only when Ryan asks.
5. Tell Ryan which files changed, whether a server restart/reconnect is needed, and how to test.

## Quick command reference

Players: `/tg menu | status | dealer | ready | go | repair | fix <id> | tow | respawn | unstick | hitchup |
faults | fault take [n] | quote | standings | diag | partsdiag | lights | lightstest | flag | flagtest | sounds on|off|list | soundtest [clip|next] | theme`.
Admins: `start [force] | next | stop | award <driver> <pts> [reason] | traffic on|off | play <clip> | budget | setcash | give | workshop <min> | workshopevery <n> |
importprices [listed|models] | gameprices | class list/use/new/delete/show/rule/unrule/include/exclude/clear/price/multiplier/values |
course list/save/load/new/delete | addevent/delevent/enable/moveevent |
setstart/addcp/undocp/clearcp/settrap/addbay/undobay/clearbays/addvia/undovia/clearvia/setfinale |
settype/setmode/setlaps/settime/rename | addworkshop/undoworkshop/clearworkshops/importgas |
trailersave/trailercones/trailertest | fault test/testoff/caps`. The ImGui window exposes all of these.

## Roadmap - Ryan's next issues (one session each, any order)

Each starts with a plain-language explanation for Ryan, then a proposal he approves before code.

### 1. Scoring rebalance - DONE in 0.9.1
Ryan's goals: feel like the show, no single dominant strategy. Points = events (10/6/3/1) + drivability /20 = average
of inspections (`Score.inspect`: on arrival at every workshop before repairs - `Score.workshop`, at close for no-shows -
and at the finale; 0 if towed/respawned on the final leg or not arrived; `Score.finishDrivability`) - penalties at
`showResults` (reset -2, tow/respawn -2, unfixed fault -3 as its own line, -1 per started $500 of debt) + producer
awards (`/tg award`). Cash in the bank only breaks ties (deliberately: no "pocket the fault money" exploit). Ideas not
taken (yet): points for every finisher (10/6/3/1 kept), a cheap-car bonus, positive cash scoring.

### 2. Dealership filters - DONE in 0.9.0 (car classes)
`/tg importprices` (no names) imports every model (`core_vehicles.getModelList`) with each trim's price + BeamNG
filter attributes (`trimAttrs`: Country, Body Style, Years {min,max}, Transmission, ...) into `dealer.gamePrices`.
Classes (`dealer.classes`, helpers in the `Class` table: rules / include / exclude / prices / multiplier) are picked
per challenge (`chosenClass`, not saved); `lookupCar` + `dealerOffers` respect the active class; `faultsNeeded` adds
"needs N faults" in every dealer mode. `/tg class ...`; Admin tab "Car classes". Unpriced trims are imported
(`noPrice`); a price comes from: class `prices` > `dealer.prices` (`/tg setprice`, `trimPrice`) > game value, then x the
class multiplier. Rule `trims base` = `Class.baseTrim` (cheapest priced factory trim); `/tg class new <n> base`.

### 3. Fault system revamp - DONE in 0.8.8
Taken by number (`/tg fault take [n]`, $2,500 each = `faults.payout`), drawn at random (`rollFault` /
`drawFaults`; owed faults wait for a car: `p.faultsOwed`) from enabled faults the car can take; hidden
until a workshop (`revealFaults`), final, fix 1.5x. Ten faults: tires, alignment, bumpers, suspension (setup:
vars `$spring*`/`$damp*` to min, else empty sway-bar slots), engine, brakes, ignition (engine
`slow/fastIgnitionErrorChance` + GE-timed `electrics.setIgnitionLevel(0)` cut-outs), cooling
(`thermals.applyDeformGroupDamageRadiator`), fuelleak (GE-timed `fuelTank:setRemainingVolume` drain), body
(`beamstate.addDamage` + `breakBreakGroup` lights/glass), starter (`starterTorque`), clutch (frictionClutch
`clutchPermanentlyDamaged`), synchros (manualGearbox `synchroWear`), turbo (`turbocharger.applyDeformGroupDamage`),
brakefade (`padGlazingFactor`, GE top-up every 10 s), abs (`wheels.setABSBehavior("off")`), oilleak (engine
`damageFrictionCoef` x1.5; server rolls `p.oilDoomed` at draw = `blowChance` 0.2; a doomed engine `lockUp()`s after
blowMin-blowMax s of driving > 15 m/s, client -> `tg_engine_blown`; can't blow twice), idle (engine
`damageIdleAVReadErrorRangeCoef` x15), gearbox (every `*Gearbox` device's `damageFrictionCoef` x3) - 19 faults, all from the 0.36
game Lua, NOT yet tried in game (devices found via `powertrain.getDevices()` by `.type`). "unavailable" -> swapped silently and remembered in `cfg.faultCaps["model/config"]` (`/tg fault caps`).
Next step for "group cars by fault capability": build groups from `faultCaps`.

### 4. Upgrade prices - DONE in 0.8.7
Parts tab (client `buildCatalogue` / `quote` / `fitPart` / `drawParts`): lists slots from the parts tree's
`suitablePartNames` or `jbeam/io.getAvailableSlotMap`, names from `getAvailableParts`, prices from
`getPart(...).information.value`; quotes mirror `TG_onRebuild` (difference x `partsMarkup`, refunds x
`resaleRate`, unknown price = `flatPartPrice`; server sends these in `d.shop`); Fit uses
`setPartsConfig` / `setPartsTreeConfig`, so billing is the normal rebuild diff. Free/billed = client
`isFreeSlot` only (free words anywhere in the slot path; "wing/spoiler/hood/bonnet" in the slot's own name =
billed; "mirror" always free). Needs in-game confirmation: does the tab list a real car (`/tg partsdiag`)?

## Confirmed working in game (2026-10-01)
- Finish flag: the checkered flag (draw list rects) and the big FINISH text (SetWindowFontScale) draw.
- Sound bites: audible (`/tg diag` shows which playback method a player's game uses).
- Unstick: on Ryan's BeamNG an unstick repairs the car, and that repair is now billed.
- Traffic mode: admins can add AI traffic and parked cars.

## Waiting for in-game confirmation
- Workshop repair / respawn stay where the car is (0.8.9 `repairInPlace`, `spawn.safeTeleport`).
- Car classes (0.9.0): `/tg importprices` reads every car with its details (`/tg class values country` shows them).
- Parts tab: lists your car's parts and Fit works (`/tg partsdiag` shows the Parts tab line).
- New faults (0.8.8): each Admin-tab Test button on a real car (manual + automatic, turbo + not) - ok, and felt?
  Cooling `factor` 0.05 and fuel leak 0.5 L/min are guesses to tune.

## Open items

From the last Desktop session (server 0.8.2 / client 0.8.1 - both now in the repo):
- Colour theme broke the menu on Ryan's BeamNG; fail-safe shipped - waiting for the `/tg diag` theme line.
- Start lights: fixed (window opened with a BoolPtr) - awaiting in-game confirmation.
- Trailer: save now records every slot + tuning; awaiting confirmation that straps stay removed and the
  load % reading works.
- Circuit: start point is the start/finish line; line only counts after 40 m away; course edits now
  auto-save to config.json (restarts used to lose unsaved course edits).
- Hitch checks were removed by request; players fit hitches in workshops.

