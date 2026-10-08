# CLAUDE.md — Top Gear Challenge (BeamMP game mode)

A multiplayer "Top Gear challenge" for BeamNG.drive via BeamMP: players buy a cheap car, drive
between events on a stock map (West Coast USA by default), race, visit workshops, and are scored on
event results plus how drivable their car still is at the end. No map files are modified.

Owner: Ryan. Prefers **iterative, working-code responses**: build it, test it, ship it, then explain
in plain language. Every change ends with a short "what changed / how to test" note.

Repo: github.com/Ryan-Shaffer-P/Beam-TopGear (default branch `main`). Developed in Claude Desktop
chats until 2026-09-30, then moved to Claude Code. Work on a branch; push/merge only when Ryan asks.
**New work, new branch:** before the first edit of a new piece of work, check the current branch. If it has already
been merged into `main` (`git rev-list --count origin/main..HEAD` is 0 after a fetch), start a fresh branch from `main`
first (`git switch -c <name> main`) and ask Ryan for its name (a short dash-separated name; for a trivial change, pick
one and say so). Never pile new work onto a finished, merged branch.

## Repository layout

```
Resources/Server/TopGear/main.lua      server plugin (~3,100 lines) - the authority on all game state
Resources/Server/TopGear/courses.json  saved course library (kept in the repo; copy back from the server)
Resources/Server/TopGear/cars.json     built-in car catalogue (stock cars + prices + attributes; GENERATED from an import -
                                       see "Car catalogue" below; never hand-edit)
Resources/Client/topgear.zip           client mod, BUILT from client/ (never edit the zip by hand)
client/lua/ge/extensions/topgear.lua   client GE extension (~2,000 lines): HUD, ImGui window, input locks, car work
client/scripts/topgear/modScript.lua   loads the extension (extensions.load + manual unload mode)
client/art/sound/topgear/*.ogg         sound bites, GENERATED from MP3s/ by tools/convert-sounds.sh (Docker ffmpeg)
README.md                              player/admin documentation - keep it in sync with every feature change
MP3s/                                  source sound clips (see client/art/sound/topgear)
server/                                local BeamMP test server in Docker (see server/README.md)
```

Runtime files written by the server next to main.lua: `config.json` (settings + the working course,
git-ignored), `session.json` (the running challenge, for crash recovery; git-ignored), `courses.json` (saved course library, tracked). `luac.out` is git-ignored.
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
  `speedtrap` (one run through the trap by default, `runs`), `parking` (multiple bays in order), `fragile`, `economy`, `slalom`, `trailer`,
  `rpc` (Star in a reasonably priced car: always time trial; laid out like a circuit; each runner gets a fresh RPC -
  server `RPC` table: `p.rpc`, positions from the RPC's vid, `RPC.request/spawned/fresh/handOver/remove`; client `Rpc`
  table spawns + places it (`safeTeleport`) and `tg_rpc_end` puts the driver back in `getCar()`; score = best lap;
  no settle timer since 0.9.13 - `defaults.readyToGo`: every start is I'm ready (`/tg ready` = `RPC.ready`, `p.run.ready`)
  then GO; race starts need `RPC.allReady()`, time trial turns begin by themselves at allHere and the RPC comes with
  the turn; the client enters the RPC only once `MPVehicleGE.isOwn` (Ryan: no controls otherwise); fixtures: readyToGo off). Course builder positions: `adminPose` uses the car the admin is IN (client sends
  `tg_activeveh` "pid-vid" when it changes; `activeVeh[pid]`) - before 0.9.13 a parked second car put every checkpoint on
  the start line. `Course.stacked` flags checkpoints on the start / each other (addcp warning, validate error). Starts face a way (0.9.23): `e.startDir` from the admin's game at setstart, `Course.startFace/startLook` (fallback: towards the first checkpoint/trap/bay) - targets carry `face` (client draws a ground arrow); tows, restarts, quick travel, the RPC and back-to-start use it. (`local Course` is declared up by `yawFromQuat` for this.)
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
  `respawnFee` 500, and -`towPenaltyPoints` (2) each at the results; an unstick that repairs the car
  bills the roadside repair once (reset event or damage drop, `billUnstickRepair`).
- Workshops: anywhere, or at course `workshopSpots` (imported gas stations / placed) + the dealership.
  Parts/paint only in the dealer and workshop phases (0.9.13 dropped the "until you drive away" grace: it billed
  parts mid-leg); outside them the Parts box is greyed (`canFit`).

**Client:** receives `tg_state` (phase, cash, target, allow-flags, lights) and renders the HUD,
ground arrows, target beacon, ImGui window (tabs Start | Status | Dealership | Admin | Settings | Results; since the UI
overhaul every tab is a stack of `Tabs.box(title, id, fn, closed)` - a CollapsingHeader with a rounded draw-list border
(`ui.noBoxes` if AddRect fails) - and long hints sit behind `Tabs.help(text)` "(?)" tooltips (fake ImGui: always hovered,
tooltips recorded as text). Start = `Tabs.quick` (Setup box: course dropdown + Load, budget, class; Dealer box: lit-in-order
steps Start -> condition -> dealer selector -> Return this car); Dealership = Buy a car / Car condition / Today's cars (model
dropdown, `ui.dealerModel`; tests pick one with `w:showModel`) / Parts (`Tabs.parts`); Admin = Challenge + Players
(`drawAdminControls`) and folded Money & timers / Car classes / Course / Tools; Messages box (`Tabs.messages`) under every
tab; helpers `Tabs.step`/`Tabs.combo`; Top Gear colour theme), F1 start lights and the finish flag (own movable windows; the server sends `tg_finish` when a run ends), input locks (`core_input_actionFilter`), and does the
car-side work: faults, tow/unstick placement, trailer spawn + load measurement, fuel/damage reports,
parts snapshots/diffs, reverting refused parts.

Game modes (0.9.31): `cfg.modes` {freeRepair, noFaults, noQuirks, turbo}; `/tg mode` (`Course.MODES`), UI `Tabs.modes`
(Start Setup box + Admin "Game modes" box), `d.modes` (`locked` once started: noFaults/noQuirks idle-only). freeRepair
zeroes `roadsideCost`, `costNote`, `billUnstickRepair`, the repair command, damage-drop billing, `Save.restoreCar`'s
charge (DSQ and tow points stay); noFaults = `faultsOn()` false; noQuirks stops `drawQuirks`/`quirkTick`; freeRepair also drops tow/respawn POINTS (`ptNote`, `showResults`). test_gamemodes.
Turbo Mode (0.9.32, `cfg.turbo`): `Score.turboAward` (first arrival in tickTravel, `Score.turboEventPrizes` = cleanest
+ last place (good only) + most air time + biggest crash (0.9.33, starters incl. `others`) in finishEvent, first in `Score.workshop`, admin `/tg prize`) -> `p.glovebox`; `/tg use <n>
[rival]` = `Score.turboUse` -> `p.effects` {tune, headstart, penalty, horn, frbrake} (+`p.pardons`, `q.sabotagedAt`);
`Score.turboTimes` adjusts run.time before finalizeScore; horn/frbrake cleared at beginWorkshop; `state.turbo` -> client
`faults.turboTick` (horn on brake: vlua 10 Hz `tgHornB`; FR brake via wheel `name == 'FR'` `tgFRBase`; tune via engine
`outputTorqueState` `tgTuneBase`). Messages: never `string.format` a text holding a problem name (they contain "%").
Air time / crash (0.9.33): client `faults.airTick` = free fall (vertical speed dropping at ~1 g, streaks >= 0.3 s;
NOT yet tried in game) -> `air` running total in tg_report -> server `p.airTotal` (`p.airSeen` handles a client restart);
`p.crashTotal` = every damage rise in TG_onReport (not in tow/respawn/repair windows); per run `r.startAir/endAir`,
`r.startCrash/endCrash` (sampled with endDamage); thresholds `turbo.minAir` 1 s, `turbo.minCrash` 1000. Harness `w:jump(p, s)`.

Players: `game.players` is keyed by the BeamMP name (= `p.login`, used for admin checks, mutes, saves); `p.name` is what
everyone sees - an alias from `cfg.aliases[login]` (0.9.25, `/tg name`, `/tg setname`, `Score.setAlias`). Never look a
player up by `p.name` alone; `Score.findPlayer` matches either.

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
12. **Lua allows at most 200 locals per chunk.** main.lua's top level is near it (~190), and so is topgear.lua's (199 since the RPC event): group new helpers into a
    table (like `Class.*`) instead of adding many top-level `local function`s. Check with
    `luac -l -l -p Resources/Server/TopGear/main.lua | awk '/^main/{m=1} m&&/^locals \(/{print; exit}'`.
13. **Don't assign to a `for` loop variable** (`for v in ... do v = ...`) - Lua 5.5 rejects it; use a new local.
14. **Wrap every BeamNG/BeamMP internal in `pcall`** with a logged fallback (`warn()` on the client;
    players filter "topgear" in the game console). These APIs change between game versions.

## BeamNG/BeamMP APIs used but NOT verified in game (suspect these first)

`core_vehicle_partmgmt.setConfig/setPartsTreeConfig/setPartsConfig/setConfigVars` (faults, reverts),
`spawnNewVehicle` with a serialized config table (trailer), the vehicle selector override (0.9.10: `guihooks.trigger` wrapped
during the dealership; a 'sendVehicleList' payload is swapped for today's list, prefetched from the server (`tg_dealerlist`)
and built from `core_vehicles.getModel(m).configs`; re-wrapped each frame if the game replaces it; `/tg diag` "Vehicle
selector" line = game version, list ready, lists seen/replaced, vehicle UI hook names seen. 0.9.9's
`requestList` override did NOT work on Ryan's game - first in-game report 2026-10-02. Ryan runs **BeamNG 0.39.4**: its
rebuilt selector (`ui_vehicleSelector_general`, sends `VehicleSelectorDataLoaded`, never `sendVehicleList`) reads cars
via `core_vehicles.getModelsData/getModel/getConfig`; 0.9.11 wraps those during the dealership (`selWrapLookups`, priced
copies cached per list in `selector.cache`) and calls `ui_vehicleSelector_general.clearCache()`; our own code uses
`gameGetModel`. 0.39 Lua reference: github.com/wlkmanist/BeamNG_lua (lua/ge/extensions/ui/vehicleSelector/)), vlua `v.data.nodes[].partOrigin` +
`obj:getNodePosition` (trailer load %), `quatFromDir` convention + `setPositionRotation` (tow/unstick,
self-verifying), `energyStorage.getStorages` (fuel), `partCondition.initConditions` (mileage wear, vehicle Lua), `freeroam_facilities` (gas stations),
`getSpawnWorldOOBB` / `be:getObjectOOBB*` (trailer placement), `be:getSurfaceHeightBelow` (/tg bring's ground height), spectating the time trial driver (`tg_watch` {sid}: `MPVehicleGE.getGameVehicleID` + `be:enterVehicle` on another player's
car = BeamMP's spectate, like its own `focusCameraOnPlayer`; `tg_watch_end` / Back to my car = enter `getCar()`; `RPC.watch/
unwatch`, `RPC.watchOff`; harness: `p.viewing`), switching the player between their car and the RPC
(`spawnNewVehicle` autoEnter + `be:enterVehicle`, `MP.RemoveVehicle` of a car the player is driving), `beamstate.activateAutoCoupling`, vlua `hydros.hydros[]` steering mapping (`cOut`/`cIn`, alignment pull; is + steering input = right?),
ImGui draw lists / tables / style pushes (lights, theme), `BeginChild1`/`EndChild` (System messages box, `drawMessages`;
falls back to plain lines + a warn), sound playback (`Engine.Audio.playOnce` with a
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
   Tests: `test_smoke.lua` (load, dealership, theme), `test_flag.lua` (finish flag), `test_traffic.lua` (admin traffic mode), `test_modes.lua` (race/time trial mode), `test_speedtrap.lua` (one run), `test_sounds.lua` (sound bites; the fake Engine.Audio checks the .ogg exists), `test_roadside.lua` (tow/respawn/unstick pricing), `test_parts.lua` (Parts tab; fake catalogue `World.partCatalogue`, `c.partsFormat = "tree"`), `test_faults.lua` (fault revamp; `w.rolls` pins the server's random draws), `test_classes.lua` (car classes; test cars carry BeamNG attributes in `MODELS[].info/trims`), `test_selector.lua` (the vehicle selector list; fake `requestList`/`guihooks` record `c.selectorLists`), `test_persistence.lua` (crash = `World.new` from the old world's files; resume, re-run, rejoin, timers), `test_catalogue.lua` (built-in cars.json, restarts, import/builtin, dealer list bandwidth), `test_settings.lua` (Settings tab; `tab(p, name)` slices one tab's text), `test_admin.lua` (Status tab Admin controls: player cash & points; `Score.findPlayer` loose names), `test_quickstart.lua` (Quick start tab; fake `im.selectedTabs` counts forced tab selections, combo previews are `kind = "combo"` items), `test_presets.lua` (no class = every car, ready-made classes, over-budget cars listed), `test_pricing.lua` (price estimates + props dropped; uses `tests/data/game-cars.json`, a real import from Ryan's game - 122 models, 1,711 trims - and checks estimate accuracy by hiding 1 in 6 real prices), `test_scoring.lua` (inspections, debt, faults, awards), `test_economy.lua` (energy: petrol vs electric), `test_beta.lua` (0.9.20 beta fixes: unready, workshop tows, watch again, back behind the start, restartevent, admin take/dock/freerespawn, trailers at I'm ready; the harness `drive` stops when the mod moves the car), `test_rpc.lua` (Star in a reasonably priced car: turns, best lap, fresh car, spawn failure, setrpc; the harness's `drive` moves whichever car the player is in), `test_trailer.lua` (cones + prebuilt load, hitching via
   `w:hitch`/`w:dropCargo`/`w:setLoad`, 70/30 scoring) and `test_session.lua` (full 5-event session, the
   successor of `sim13` - expected cash/points are hand-calculated in its comments; if a rule change
   moves them, recompute by hand rather than pasting the new output). Still to rebuild: workshop
   parts billing/overdraft/dealership upgrades, start lights, circuits, parking/slalom, course builder.
   **Menu preview:** `luajit tools/preview.lua [idle|dealer|travel|event|workshop|results] [tab|all]` prints the real
   ImGui window as a text mock-up (harness test data; content and controls, not colours/spacing).
4. Beware harness artifacts (wrong test coordinates, sequencing): say so explicitly when a failure is the
   test's fault, not the mod's.
5. Real server: `docker compose -f server/compose.yaml restart`, then check `logs` for the
   `[TopGear] ... loaded` line and no `[LUA]` errors. The container mounts the repo's `Resources/`.
6. Final check is always in-game (Ryan joins via Direct Connect to this Mac, port 30814). Ryan runs **BeamNG 0.39.4**.
   If `/tg diag` shows an old *client mod* version after an update: copy `Resources/` again, fully quit BeamNG (a
   running game keeps the old extension), and if needed delete the cached `mods/multiplayer/topgear.zip` in the
   BeamNG user folder.

## Release steps

1. Bump `SERVER_VERSION` (main.lua) and `VERSION` (topgear.lua) - `/tg diag` prints both; Ryan uses them to
   confirm the right files are installed.
2. Rebuild the client zip:
   `cd client && rm -f ../Resources/Client/topgear.zip && zip -qr ../Resources/Client/topgear.zip lua scripts art -x '*luac.out' '*.DS_Store'`
3. Update README.md for any behaviour change.
4. Commit on a branch. Push / open a PR / merge to `main` only when Ryan asks.
5. Tell Ryan which files changed, whether a server restart/reconnect is needed, and how to test.

## Quick command reference

Players: `/tg menu | name <alias> | use <n> [rival] | status | dealer | ready | unready | go | repair | fix <id> | tow | respawn | unstick | hitchup |
condition [name] | faults | fault take [n] | quote | standings | diag | partsdiag | lights | lightstest | flag | flagtest | sounds on|off|list | soundtest [clip|next] | theme`.
Admins: `start [force] | next | stop | mode <freerepair|nofaults|noquirks|turbo> [on|off] | prize <player> [id] | restartevent | freerespawn <driver> | bring <driver> | setname <player> <name> | resume | discard | award <driver> <pts> [reason] | traffic on|off | play <clip> | budget | setcash | give | workshop <min> | workshopevery <n> |
importprices [listed|builtin|models] | gameprices | setprice | class list/use/new/preset/delete/show/rule/unrule/include/exclude/clear/price/multiplier/values |
course list/save/load/new/delete | addevent/delevent/enable/moveevent | testevent <n>|stop | quicktravel <n|finale> |
setstart/addcp/undocp/clearcp/settrap/addbay/undobay/clearbays/addvia/undovia/clearvia/setfinale |
settype/setmode/setlaps/setrpc/settime/rename | addworkshop/undoworkshop/clearworkshops/importgas |
trailersave/trailercones/trailertest | fault test [id] [as <condition>]/testoff/caps/sample <cond> [n]/fire [player]/blow [player] | quirk test <id>`. The ImGui window exposes all of these.

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
0.9.3: the import drops non-cars (`Class.notACar`: Type `Prop*`/`Trailer`/`Debug`; older configs tidied at startup by
`Class.tidyImport`), and unpriced trims get `est` (`Class.estimatePrices`: median of the 5 nearest priced trims on
log weight/power, log 0-100, top speed, year, off-road, log weight; +4 distance for another Type, x0.5 for the same
model; no figures -> median of the model; rounded to $100). `trimPrice` = `dealer.prices` > game value > `est`;
`Class.isEstimate` marks "(est. price)". Real data: median error 10% (tests/data/game-cars.json).
0.9.5: `Class.selling()` = the chosen class, else `Class.ALL` (Type Car/Truck) once `dealer.importedAll` (set by a full
import; inferred at startup for older configs), else the dealer list. `Class.PRESETS` (18, `/tg class preset`, Admin
"Ready-made classes"). (0.9.5-0.9.11 listed over-budget trims marked; since 0.9.12 `dealerOffers` DROPS a trim that's
over the budget even as a Death Trap - Ryan: "no reason to show cars we cannot buy" - window, /tg dealer and selector.)
0.9.8 - **Persistence** (`Save` table, near the BeamMP events): `Save.snapshot/write` -> `session.json` (tmp + `FS.Rename`)
every `Save.EVERY` s and at phase/stage changes (`Save.tick`); `Save.pack/unpack` keep number keys as "#n"; game timers
are stored as time remaining (`Save.TIMERS`), per-player runtime fields dropped (`Save.TRANSIENT`), `game.solo` not saved.
`Save.load` at startup -> `phase = "paused"` (`game.resumePhase`); `/tg resume` (event/countdown -> back to `travel`
for that stage, cars at the start via `towDestination`) / `/tg discard`. Car return: `Save.restoreCar` (charge =
repairQuote) -> tick sends `tg_respawn spawn` (retried) -> `TG_onVehicleSpawn` -> `Save.carBack` -> `tg_tow`
{kind="restore", config=p.lastVcf}. `p.lastPos/lastDir` from the tick. A rejoin mid-challenge uses the same path.
0.9.7 - **Car catalogue:** `cars.json` = stock cars/trucks (Source "BeamNG - Official", no props/trailers) from Ryan's
import (`tests/data/game-cars.json`). `Class.loadBuiltin` puts it in `cfg.dealer.gamePrices` when there's no import
(`dealer.catalogue = "builtin"`); `saveConfig` leaves gamePrices out of config.json while builtin. A server's own
import sets `catalogue = "import"` and is saved (a full import now REPLACES gamePrices: `imp.fresh`).
`/tg importprices builtin` goes back. To refresh cars.json after a BeamNG update: Ryan runs `/tg importprices`, copies
config.json here, regenerate with the same filter (see the 0.9.7 commit), and update tests' expected counts (986).
UI bandwidth: `sendUi(pid, haveVer)` omits `d.dealer` when the client's echoed `dealerVer` matches (`Class.sentDealer`);
a full list is ~110 KB, a refresh without it ~2-10 KB.

### 3. Fault system revamp - DONE in 0.8.8 (players see it as CAR CONDITION since 0.9.12)
0.9.12: players never read "fault": the count is the car's condition (`CONDITION` table: New, Used, Needs work, Beater,
Death Trap = 0..4), one fault is "a problem". Dealership tab = `drawCondition` slider (`/tg condition <n|name>`, the old
`/tg fault take` maps onto it); free both ways until a car is bought (`p.carVid` or drawn faults), then only worse. Code,
config keys and admin tools still say fault.
Condition PRICING (0.9.12, Ryan: "a luxury car that's been beat up should match a newer low-end car"): career's
`valueCalculator.getAdjustedVehicleBaseValue` without age: price x (max(0, 1 - lossPerKm x km) + scrapValue) =
`CONDITION.price(n, newPrice, acc)` (nearest $100; +1e-9 for float halves). Used/NW/Beater/DT = 60k/100k/200k/300k km =
90/80/55/30% for slow cars - since 0.9.13 `faults.discount` {0.25, 0.40, 0.55, 0.70} replaces that (75/60/45/30%; empty =
the formula; mileage wear unchanged) because Used's 10% unlocked ~nothing at a $15k budget; FAST CARS HOLD THEIR VALUE (Ryan drove a 4.4 s Death Trap ETK for $19,400 and it destroyed
cheap cars): the discount x `CONDITION.perfShare(acc)` = 1 at >= perfSlowSeconds (10) .. perfMinShare (0.3) at <=
perfFastSeconds (4), acc = the trim's 0-100 from gamePrices attrs (`CONDITION.accel`; unknown = full discount). No cash payout any more: `dealerOffers` shows prices in the player's chosen condition (`t.newPrice`,
`t.cond`/`t.condPrice` = the condition that makes it affordable, `CONDITION.needed`); purchase `setCar` stores
`boughtCondition` (locked; `refundCar` clears), `carNewPrice`, `conditionSaving`. Fix = `fixCost(p)` = 5% of the new
price, min $500. `playerBudget` = startingCash. Migration `conditionPricing` (old unreleased mileage defaults).
Replacing parts (0.9.12): the client's `tg_rebuild` lists `changes` {slot, from, to, from_value}; `CONDITION.systemOf(slot)`
(the slot's own name -> `CONDITION.SYSTEMS`: engine/radiator/turbo/gearbox/clutch/brakes/tires/suspension -> fault ids)
clears those problems and, if any, adds the old part's value back to the bill (scrap: no trade-in). Every changed slot
goes in `p.freshParts` (slot -> part name; reset at purchase/refund) -> `mileage.fresh` -> VLUA `initConditions(perPart,
...)` with 0 km for parts found by NAME in `v.data.activeParts` (key `tgFaults.mileage` = m|fresh list).
NO PAINT AGING (Ryan, in game: invisible at our mileages, and it broke repaints): the game ages paint via
`setMeshColor` on every flexbody, which overrides later repaints - so the visual arg is `{}` (a table without `.paint`
skips `setPaintCondition`); per-part entries use `visualState = {}`. Harness fake: a number visual sets `v.paintLocked`.
Mileage wear (0.9.12): `CONDITION.mileage(p)` (by `CONDITION.level` = condition bought, fixes don't lower it) goes in
`tg_faults` as `mileage = {m = metres, fresh}`; VLUA calls `partCondition.initConditions(perPart, m, nil, {})` (career's
`vehicleShopping` call) once per vehicle-Lua state (`tgFaults.mileage`) BEFORE the faults - it resets the engine/gearbox
damage coefs and ignition chances, so it sets `wearFresh` (oil/idle/gearbox rescale from 1, ignition re-reads its base).
The game re-applies its own snapshot on reset. Result -> `out._mileage` -> `/tg diag` "Car wear". NOT yet tried in game.
Severity (0.9.12, Ryan: "more worn cars have worse problems"): `faults.severity` = {0.5, 0.75, 1.0, 1.3} per condition
(listed factors = a Beater's); `CONDITION.scaled(f, s)` by `CONDITION.SCALE` mode (loss w/ floor, add w/ cap, mult;
starter `noWorse`), applied in `sendFaults` (admin fault tests unscaled); ignition cut-out intervals / s only when s < 1;
oil-leak doomed chance x s; names via `CONDITION.problemName` (rewrites "-20%"). Test fixtures pin severity {1,1,1,1}
(`F.config`, `allFaults`) so mechanics tests use listed values; test_faults' "worse problems" tests use the real ones.
Overlap with mileage: idle, gearbox, clutch `enabled = false` by default (migration `mileageOverlap`); a fault's
`minCondition` (oil leak = 3) keeps it out of `rollFault` below that condition (`CONDITION.level` incl. owed draws).
Taken by number (`/tg fault take [n]`; since 0.9.12 a car CONDITION that discounts the price, see below), drawn at random (`rollFault` /
`drawFaults`; owed faults wait for a car: `p.faultsOwed`) from enabled faults the car can take; hidden
until a workshop (`revealFaults`), final, fix 1.5x. Ten faults: tires, alignment, bumpers, suspension (setup:
vars `$spring*`/`$damp*` to min, else empty sway-bar slots), engine, brakes, ignition (engine
`slow/fastIgnitionErrorChance` + GE-timed `electrics.setIgnitionLevel(0)` cut-outs), cooling
(`thermals.applyDeformGroupDamageRadiator`), fuelleak (GE-timed `fuelTank:setRemainingVolume` drain), body
(`beamstate.addDamage` + `breakBreakGroup` lights/glass), starter (`starterTorque`; part of ignition since 0.9.13), clutch (frictionClutch
`damageLockTorqueCoef` x factor 0.6, scaled loss floor 0.35 - 0.9.13; `clutchPermanentlyDamaged` was a flat 25% grip), synchros (manualGearbox `synchroWear`), turbo (`turbocharger.applyDeformGroupDamage`),
brakefade (`padGlazingFactor`, GE top-up every 10 s), abs (`wheels.setABSBehavior("off")`), oilleak (engine
`damageFrictionCoef` x1.5; server rolls `p.oilDoomed` at draw = `blowChance` 0.2; a doomed engine `lockUp()`s after
blowMin-blowMax s of driving > 15 m/s, client -> `tg_engine_blown`; can't blow twice), idle (engine
`damageIdleAVReadErrorRangeCoef` x15), gearbox (every `*Gearbox` device's `damageFrictionCoef` x3) - 19 faults (17 since 0.9.13: starter merged into ignition - `ignition.starter`, VLUA item "starter", result folded into
ignition's; bumpers merged into body - SETUP_FAULTS
body, restore record still keyed "bumpers"; the fix's respawn bills only damage beyond the fault's dents, `p.dentsCredit`), all from the 0.36
game Lua, NOT yet tried in game (devices found via `powertrain.getDevices()` by `.type`). "unavailable" -> swapped silently and remembered in `cfg.faultCaps["model/config"]` (`/tg fault caps`).
Next step for "group cars by fault capability": build groups from `faultCaps`.
0.9.21 **tiers** (Ryan: some problems together made a car undriveable): each fault has `tier` (1 annoying, 2 performance,
3 can stop the car: ignition, cooling, oilleak) and `groups` (brakes, stalling, heat, gears: never two sharing one);
`faults.maxTier` per condition {1,2,3,3}, `faults.maxPerTier` {4,4,1}; `CONDITION.tierOK` in `rollFault`; `faults.tiers =
false` = off (test fixtures and test_faults pin it off - the `pin` roll indices assume the full candidate list);
migration `faultTiers` fills a saved list; `/tg fault sample <cond> [n]`; test_faulttiers.
0.9.26 fuel leak fire (Ryan): `fireChance` 0.2 rolled at draw (`p.fuelDoomed`, like `p.oilDoomed`), client ignites once after
`fireMin`-`fireMax` s of driving > 3 m/s via vlua `fire.igniteVehicle()` (NOT yet tried in game) -> `tg_car_fire` -> `p.fuelBurnt`;
`faults.fires = false` = off (fixtures pin it off: the roll is random). Harness: fake `fire` module counts `v.onFire`.
0.9.27: admin `/tg fault fire|blow [player]` (fault tester buttons) -> `tg_faultnow` -> client `faults.now`: at once, a test.
0.9.29 **quirks** (`cfg.quirks`; harmless extras, NOT faults: no condition/points): `CONDITION.drawQuirks` (in
`redrawFaults`; cleared by `refundCar`) -> `p.quirks`; server `CONDITION.quirkTick` (in TG_onTick, `QUIRK_PHASES`, moving
unless `parked`) -> `CONDITION.quirkFire`: clip -> `tg_sound` to players within nearRadius; BeamNG one-shot `events` ->
`tg_quirkfx` {sid, own, event} (each game plays it on its copy of the car: vlua `sounds.playSoundOnceFollowNode`); `action`
horn (5 beeps)/lights/hazards -> owner only (BeamMP syncs electrics); `say` -> chat (unused since 0.9.30 dropped the smell). Client `faults.quirkFx` / `faults.quirkTick`
(own clock `faults.clock`; `faults.later` second halves); squeaky brakes from `state.quirks` (wheels `squealCoef*`, kept
every 10 s, restored on fix via vlua `tgSqueal`). `/tg fix <quirk>` = `quirks.fixCost`. `/tg quirk test <id>`. Events
from the 0.39 game Lua (one-shots only - grind, rattle and turbo bov are loops there, left out). NOT yet tried in game.
Fixtures pin `quirks.enabled = false`; test_quirks.

### 4. Upgrade prices - DONE in 0.8.7
Parts tab (client `buildCatalogue` / `quote` / `fitPart` / `drawParts`): lists slots from the parts tree's
`suitablePartNames` or `jbeam/io.getAvailableSlotMap`, names from `getAvailableParts`, prices from
`getPart(...).information.value`; quotes mirror `TG_onRebuild` (difference x `partsMarkup`, refunds x
`resaleRate`, unknown price = `flatPartPrice`; server sends these in `d.shop`); Fit uses
`setPartsConfig` / `setPartsTreeConfig`, so billing is the normal rebuild diff. Free/billed = client
`isFreeSlot` only (free words anywhere in the slot path; "wing/spoiler/hood/bonnet" in the slot's own name =
billed; "mirror" always free). Needs in-game confirmation: does the tab list a real car (`/tg partsdiag`)?

## Confirmed working in game (2026-10-01)
- Vehicle selector dealership (0.9.11, 2026-10-02, BeamNG 0.39.4): only today's cars, names with prices, the class filter applied.
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

