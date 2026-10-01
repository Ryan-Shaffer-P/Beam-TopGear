# Top Gear Challenge for BeamMP (v0.1)

A game mode that runs on top of a stock BeamNG map. Players buy a car with $10,000, drive
between four events, race for prize money, visit the workshop twice, and finish with a
drivability inspection. No map files are modified, so every player already has the map.

## Install

1. Copy `Resources/Server/TopGear/` into your BeamMP server's `Resources/Server/`.
2. Copy `Resources/Client/topgear.zip` into `Resources/Client/`. BeamMP sends it to players on join.
3. In `ServerConfig.toml` set `Map = "/levels/west_coast_usa/info.json"` (or another map, see below).
   If an admin will host AI traffic, raise `MaxCars` (the plugin still stops normal players
   from spawning more than their one challenge car).
4. Start the server once. It writes `Resources/Server/TopGear/config.json`. Put your name in
   `"admins"` (while it's empty, everyone is an admin).

## The in-game window

Type `/tg menu` to open or close it. Colour key: **solid blue = a button you click**; **grey box with a blue
outline = a field you can type in or change**; blue headings mark sections; the standings are a light table.
If the colours ever break the window on your BeamNG version, it switches them off by itself and
keeps working (`/tg diag` shows why); `/tg theme` turns them on/off. It opens by itself when the dealership and workshops
open. Tabs:

- **Status**: your car, cash, points, damage, standings, and the button for whatever comes
  next (Ready, GO, Join, fault fixes in a workshop). The driver buttons are always there:
  **Repair** (workshops only, shows the price), **Tow**, **Unstick** and **Respawn**, with a grey
  line saying what's usable right now. Tow and Respawn need two clicks. Admins also get an
  **Admin controls** dropdown here with Start, Start (unfinished course), Next phase and Stop.
- **Dealership**: every affordable trim with a **Buy** button that spawns it for you, and
  **Return for a full refund** to swap.
- **Admin** (admins only): budget and workshop timer, price import, hitch scan,
  per-player cash, and a course builder (pick an event, drive there, click Set start / Add
  checkpoint / Add route waypoint, then Save). Stop and Clear ALL need a second click.

If the window ever gets squashed or lost off-screen, `/tg menu reset` puts it back.

When the challenge ends, the window opens on a **Results** tab: the winner, then one row per
driver with the car (and what it cost), placement and time/speed in every event, total
repairs, upgrades, tows/resets, drivability, final points (with the breakdown) and cash left.
`/tg menu` brings it back any time until the next `/tg start`.

Every button runs the same command as chat, with the same permission checks. The chat
commands below still work.

## Sessions: picking the events

A course is a pool of events. Admin tab -> **Session**: Turn on / Turn off each event, move it
Up / Down, or **Remove** it from the course entirely (two clicks); the events that are on run top to bottom when you `/tg start`. Add new
events with the type buttons underneath. A workshop follows every 2nd event of the
session (`workshopEvery`). The session is saved with the course. Chat: `/tg enable <n> on|off`,
`/tg moveevent <n> up|down`, `/tg addevent <type> [name]`, `/tg delevent <n>`.

## Event types

| Type | How it runs | Winner | Placed with |
|---|---|---|---|
| Destination race | everyone at once | first to the finish | start + checkpoints |
| Circuit race | everyone at once | first to complete the laps | start (= start/finish line) + checkpoints round the lap + laps |
| Time trial | one at a time | fastest run | start + checkpoints |
| Speed trap | everyone at once | highest speed through the trap | start + trap |
| Precision parking | one at a time | lowest score: 10 pts/m off centre + 0.5/deg skew (every bay) + 0.1/s + 0.01/damage + 50 per bay not reached | start + bays (in order) |
| Fragile delivery | everyone at once | time + 0.01 s per point of damage picked up | start + checkpoints |
| Economy run | everyone at once | least fuel used (inside the time limit) | start + checkpoints |
| Slalom | one at a time | time + 5 s per missed gate | start + gates |
| Trailer delivery | everyone at once | most points out of 100: 70 for the share of the load kept + 30 for speed | start + checkpoints |

- **Starting lights:** every countdown shows F1-style lights at the top of the screen - five
  reds, one per second, then all out (green) for GO. One-at-a-time runs show the runner's name.
  `/tg lightstest` plays the sequence on your screen right away (no race needed). The lights are
  their own window: `/tg lights` (or **Position the start lights** on the Status page) keeps the box up
  so you can drag it by its title bar wherever you like - the game remembers where - and hides it again.
- **One at a time:** runners go in the order they arrived, each with their own countdown;
  everyone else waits at the start. An admin's `/tg next` ends just the current run.
  Any event can be forced either way with `"solo": true/false` on the event in config.json.
- **Parking:** a course of one or more bays, parked in the order they were added. Add each bay by
  parking in it the way it should face (`/tg addbay <n>`, `/tg undobay <n>`, `/tg clearbays <n>`,
  or the course builder buttons). A bay counts once you've been stopped inside it (5 m) for
  1.5 s; then drive off to the next one (the HUD says "Bay 2/3"). Nose-in or reversed in are
  both "straight". Score = precision in every bay + time + damage taken during the run; bays
  you didn't reach before the time limit cost 50 each (none at all = DNF). Damage is NOT
  repaired afterwards. With several bays, raise the time limit (`/tg settime <n> <seconds>`
  or the course builder's Time limit box - available for every event).
- **Fragile delivery:** once the results are in, every car that took part gets a free full
  repair where it stands (upgrades and unfixed faults stay, like a tow).
- **Economy:** fuel is read from each player's own car. If a car's fuel can't be read, its
  run falls back to time and says so.
- **Circuit race:** the event's start point is the start/finish line; checkpoints are the waypoints
  round the lap, in order. Each lap is every checkpoint and then back across the start line (which
  only counts once you've been at least 40 m away from it that lap); you loop until you've done the laps (`/tg setlaps <n> <laps>`,
  or the Laps box in the course builder, default 3). The HUD shows "Lap 2/3". A **destination
  race** is the original point-to-point race.
- **Slalom vs race:** a slalom runs one at a time, its gates are tight (4 m, vs 12 m race
  checkpoints), and a missed gate costs 5 s but you carry on; in a race you must hit every
  checkpoint in order or turn back. Place slalom gates close together in a weave.
- **Trailer, prebuilt load (recommended):** build the trailer once in game - spawn the small
  flatbed (`tsfb`), pick a load in the parts menu's Load slot and remove the straps - then, while
  it's your current vehicle, type `/tg trailersave`. It saves the trailer exactly as built - every
  slot (so removed straps stay removed) and its tuning values (e.g. the crate's mass). Custom builds
  from the garage are fine. Every trailer event then spawns that exact
  trailer for everyone, with the load as part of it. Each player's game measures how much of the
  load is still on the bed; the results show e.g. "72% of the load". `/tg trailertest` spawns it
  behind you and reports the load reading;
  `/tg trailercones` goes back to the empty trailer + loose cones below.
- **Trailer (cones):** when you arrive at the start, a trailer (default `tsfb`, the small flatbed)
  appears 7 m behind your car with loose cargo on it (default 5 x `cones`). Reverse up and
  hitch it before `/tg go`: your car is put into auto-couple mode, so reversing onto the
  trailer latches it, or press **Hitch up** in the Status tab (`/tg hitchup`), which toggles the
  couplers like the game's own coupler key. Anyone whose trailer isn't with them at the start
  gets a warning. **Tow hitches are the players' job:** fit one from the parts menu in a workshop
  (it's billed like any other part). So a trailer event should come after at least one workshop
  in the session order - `/tg start` warns you if it doesn't. The mod doesn't check or fit
  hitches itself. At the finish, cargo within 5 m of your trailer counts, and the
  trailer must still be with you. Everything is cleaned up after the event. **Each player
  needs 7 vehicle slots for this, so raise `MaxCars` in ServerConfig.toml.** Check the model
  names on your BeamNG version with the course builder's **Test trailer spawn** button
  (`/tg trailertest`, `/tg trailertest off`) and change them in `eventTypes.trailer` if needed.
- **Trailer scoring:** out of 100 points, highest wins. **Load (70):** the share of the load still
  with you at the finish - 72% of the load is 50.4 points (with cones: cones kept / cones given; a
  trailer left behind keeps nothing). **Speed (30):** the fastest finisher's time divided by yours -
  the fastest driver gets all 30, someone who takes twice as long gets 15. The results show both
  parts, e.g. "3:05.20, 72% of the load: load 50.4 + speed 25.5 = 75.9 pts". Change the split with
  `loadWeight` / `speedWeight` in `eventTypes.trailer` (they're scaled to 100 whatever they add up to).
- All the scoring weights live in `config.json` under `eventTypes`.
- Saved courses: any race named "Hill Climb" is converted to a time trial once, automatically.

## Build the course (one-time, in game)

Drive to each spot and type the command. Positions come from your current vehicle.

| Step | Command |
|---|---|
| Start line of event N | `/tg setstart N` |
| Race checkpoints, in order (last one = finish) | `/tg addcp N` (repeat), `/tg undocp N` |
| Speed trap gate (event 4 by default) | `/tg settrap 4` |
| Parking bays, in order (park in each, facing the right way) | `/tg addbay N`, `/tg undobay N`, `/tg clearbays N` |
| Event time limit (per run for one-at-a-time events) | `/tg settime N <seconds>` |
| Slalom gates, in order (last = finish) | `/tg addcp N` |
| Change an event's type | `/tg settype N <race\|timetrial\|speedtrap\|parking\|fragile\|economy\|slalom\|trailer>` |
| Forced waypoints on the drive TO event N | `/tg addvia N` |
| Finale finish + its route | `/tg setfinale`, `/tg addvia finale` |
| Rename | `/tg rename N The Hill Climb` |
| Check and save | `/tg courses`, `/tg course save <name>` |
| Undo the last route waypoint | `/tg undovia N`, `/tg undovia finale` |
| Start over (one event, the finale, or everything) | `/tg clearcourse N`, `/tg clearcourse finale`, `/tg clearcourse all` |
| Undo unsaved changes | `/tg reload` |

### Course library

Save as many courses as you like and switch between them. They're stored in
`Resources/Server/TopGear/courses.json`; the loaded one also stays in `config.json`.

- `/tg course save <name>`: save the current course under that name (overwrites). `save` alone re-saves the loaded course.
- `/tg course load <name>` / `new <name>` / `delete <name>` / `list`
- In the window's Course builder: a dropdown of saved courses (with complete / N-to-set and
  save time) plus Load and Delete, a name box with Save as, Save and New course, and
  Revert to saved.
- Loading or starting a new course keeps any unsaved changes as `~ unsaved backup`, so
  nothing is lost. Loading and New are blocked while a challenge is running.

The `via` waypoints are how you force players through different environments. A suggested
West Coast USA layout:

- **Leg 1 → The Drag Race**: start near the spawn, a straight stretch of highway or an industrial road.
- **Leg 2 → The Hill Climb** (via the dirt trails in the hills): race up a twisting mountain road.
- **Workshop 1** after the drag race, **Workshop 2** after Rush Hour.
- **Leg 3 → Rush Hour** (via a gravel/back-road detour): checkpoints zig-zag across downtown.
  For "crowded streets", an admin buys their car first, then spawns AI traffic or parks
  extra vehicles as obstacles (admins' extra vehicles are allowed and don't score).
- **Leg 4 → The Speed Trap**: a long highway straight. Three runs; slow passes don't count.
- **Finale**: back to a "test track" finish, via a rough road so damage matters.

Italy is a great alternative theme (narrow villages, mountain passes, gravel): change the
`Map` line and build a course the same way. Courses are per-map, so keep a copy of
`config.json` per map.

## Running a challenge

`/tg start` → dealership phase. Players spawn a car from the normal vehicle menu. The
server charges them, rejects unlisted cars and unaffordable ones, and refunds if they
delete it. `/tg ready` from everyone (or admin `/tg next`) closes the dealership.

Each leg: drive to the event. Nothing starts until every racer has arrived; then any
racer types `/tg go` (everyone must be at the start line) and a 5-second countdown runs
(`defaults.countdown` in config.json). Then: event → results/prize money → (workshop) →
next leg → … → finale → standings.
Admin `/tg next` forces the current phase to end (e.g. someone is stuck: players who
haven't arrived get a DNS). `/tg stop` cancels everything.

Player commands: `/tg menu`, `/tg go`, `/tg unstick`, `/tg tow`, `/tg respawn`, `/tg hitchup`, `/tg status`, `/tg dealer`, `/tg quote`, `/tg repair` (workshop only),
`/tg standings`, `/tg join` (late joiners during the dealership).

## Rules as implemented

- **Resets are locked** during the challenge (R, Insert/recovery, reload, home, node grabber,
  editor) because BeamNG's own resets and rewinds all repair the car. Anyone who gets round
  the lock is fined $1,000 and loses 2 points.
- **Stuck? `/tg unstick`** (or the Status tab button) is free: it sets the car upright in place
  and keeps all damage and faults. Only when (nearly) stopped, 15 s cooldown, not in a
  countdown. If on your BeamNG version the move turns out to reset the car, the repair it
  caused is billed (the unstick itself stays free).
- **`/tg respawn`** (Status tab button, click twice) respawns your car where it is: free at the
  dealership, the normal repair price in a workshop, otherwise $2,000 (`economy.respawnFee`).
  Mid-run it's a DSQ from that event; on the final leg it means 0 drivability. If your car has
  been lost or deleted, Respawn brings it back (that counts as a tow). Respawns are counted
  with tows on the final screen.
- **`/tg tow`** (Status tab button, click twice) costs $2,000 and is a full repair that keeps
  upgrades, paid fault fixes and unfixed faults. During an event: DSQ from that event and
  delivered to the next event's start, ready to race. During a travel leg: delivered to that
  event's start (no arrival bonus). On the final leg: delivered to the finish with 0
  drivability. Respawning a lost/deleted car counts as a tow and restores its upgrades.
  Tows don't cost points; they're counted on the final screen.
- **How events end:** DNS = not at the start when the countdown began (only possible when an
  admin forces a start). DNF = still running when the event's time limit (`timeLimit` per
  event) runs out or the admin calls time, or the car was lost mid-event. DSQ = towed.
- **Workshops** come after every 2nd event (never after the last one - the finale inspection
  should judge the car you've got). Change it with `/tg workshopevery <n>` or in the Admin tab.
  **Where:** give a course workshop locations (Admin tab -> Workshop locations: **Import gas
  stations** reads the map's gas stations; **Add workshop here** places one where you're parked;
  `/tg importgas`, `/tg addworkshop [name]`, `/tg undoworkshop`, `/tg clearworkshops`). When a
  workshop opens, the arrows point to the nearest one, and repairs, fault fixes, parts, paint and
  tuning only work while you're within 30 m of it. A course with no locations keeps the old
  "workshop anywhere" behaviour. Locations are saved with the course.
  **The dealership is workshop mode too:** once you've bought a car, the parts menu is open until
  you drive away from the dealership after it closes (and if the course has workshop locations, the
  dealership counts as one in every workshop). Outside a workshop, paint is simply accepted and a
  part/tuning change is put back by the game (any damage that rebuild wiped is billed as a repair) -
  the server never cancels an edit, because BeamMP removes the car when it does. At the dealership - upgrades are billed like a workshop, paint is free, and returning the
  car refunds its upgrades with it. Swapping to another stock trim is priced as a trim, not as parts.
  How the bill works:
  - **Parts:** after every rebuild, your own game compares the car's parts before and after and
    tells the server exactly what changed (it reads both the old flat parts list and the newer
    parts tree). Performance parts are charged at their BeamNG value - the same "value" career
    mode's parts shop uses - the moment they're fitted (removing one refunds half). If the game
    can't read a part's price, a flat `workshop.flatPartPrice` ($500) is charged instead.
    `/tg partsdiag` shows what your game reports: how many parts it found, in which format, and
    how many have a price.
  - **Labour:** $300, once per workshop, on your first real part change.
  - **Overdraft:** workshop and dealership spending (parts, labour, repairs, fault fixes) can take
    a driver up to $1,500 into the red (`workshop.creditLimit`). Anything that would go further is
    refused - a part is taken straight back off the car, nothing charged. Prize money pays it off.
  - **Free:** paint, skins/liveries, decals, plates, mirrors, lights, trim, interior, and tuning.
  - **Repairs:** changing parts rebuilds the car in BeamNG, which repairs it. Whenever a car's
    damage drops to near zero in a workshop (for any reason), that repair is billed at the
    normal repair price. Paint never changes damage, so it's never billed.
  - **Resets are never fined in a workshop.** Parts, paint and tuning changes outside a
    workshop are refused.
  - Every workshop edit, rebuild and reset is logged in the server console (`[TopGear] edit by ...`),
    with the phase it happened in - check there if a charge looks wrong.
- **Scoring**: placement points (10/6/3/1) per event + up to 10 drivability points at the
  finale (scaled by damage; cars that don't arrive score 0) − 2 per tow/reset.
  Ties break on event wins, then cash. Every number is in `config.json`.

## Money and prices

- `/tg budget <amount>`: set the starting cash (saved). During the dealership everyone's
  cash moves by the same amount; it can't drop below a car someone already bought.
  Mid-challenge it applies from the next challenge. `/tg budget` alone shows the current value.
- `/tg workshop <minutes>`: set the workshop length (saved). If a workshop is open, its
  timer moves by the difference.
- `/tg setcash <name> <amount>` / `/tg give <name> <amount>`: adjust one player.
- `/tg importprices`: an admin's game reads the BeamNG value of every stock trim of the
  listed models and saves them to config.json; from then on each trim costs its game price.
  `/tg importprices covet pickup` imports specific models (new ones are added to the dealer).
  Custom/modified configs have no price and can't be bought. `/tg gameprices off|on` switches
  between game prices and the manual list.
- Trims over the budget are hidden from `/tg dealer` (and refused if spawned). Raising the
  budget reveals them without re-importing. `/tg dealer <model>` lists one model's trims.

## Problem cars (faults for cash)

At the dealership each player can take up to 3 faults. Each pays out immediately and raises
that player's dealership limit by the same amount, so the extra cash can buy a better car. Faults belong to the player, not a specific car: they
carry over if you swap cars and come back after a tow. Hand one back before the dealership
closes for free (the payout is returned). In a workshop, `/tg fix <id>` removes a fault for
1.5x what it paid. Every unfixed fault costs 1 drivability point at the finale.

| id | Fault | How it's done | Default payout |
|---|---|---|---|
| tires | Worn, underinflated tires | tire pressures set to 30% of normal (`$tirepressure_*`), never below the car's minimum | $2,400 |
| alignment | Knocked-out alignment | front toe pushed to its limit, rear toe 40% of the way (`$toe_*`, factor 1.4) | $2,100 |
| bumpers | Missing bumpers | front/rear bumper slots emptied | $1,500 |
| engine | Tired engine | engine output x0.8 | $6,000 |
| brakes | Worn brakes | brake torque x0.6 | $3,600 |

Everything is in `config.json` under `faults`: payouts, `factor` (severity), `maxPerCar`,
`fixMultiplier`, `inspectionPenaltyPoints`, and `enabled`. If a fault can't be applied to a
car (e.g. no adjustable alignment), it's removed and the payout handed back automatically.
Setup faults (tires, alignment, bumpers) respawn the car when applied or fixed; physics
faults (engine, brakes) are re-applied after every reset or respawn. Putting bumpers back or
re-inflating tires via the parts/tuning menus doesn't work - the faults go straight back on.

Changing any part in a workshop rebuilds the car in BeamNG, which also wipes its damage, so
that repair is now billed automatically (the same price as `/tg repair`).

**Test on your game version first:** admin `/tg fault test` (or the Admin tab's fault test)
applies every fault to the car you're in, no money involved, and reports ok / unavailable /
error for each. `/tg fault testoff` removes them. Drive it and check each fault is felt.

Commands: `/tg faults` (list), `/tg fault take <id>`, `/tg fault undo <id>`, `/tg fix <id>`.

## Calibrating

The dealer prices are the challenge's own, not BeamNG's values. Two things to tune after
a test drive:

- **Damage scale**: `/tg status` shows your car's damage number. Crash a car to "barely
  drivable" and set `scoring.damageForZeroDrivability` near that value, and tune
  `economy.repairCostPerDamage` so a typical repair eats a sensible chunk of prize money.
- **Similar caliber** (manual price list only - with imported game prices every trim is
  already priced individually): by default any stock config of a listed model costs the model
  price. For tighter control, set `"debugSpawns": true`, spawn the configs you want
  (the server console prints the model and config name), add entries like
  `{ "model": "covet", "config": "base_M", "name": "Covet base", "price": 4500 }`,
  and set `dealer.strictConfigs` to `true`.

## Things to verify on your BeamNG/BeamMP version

The server uses standard BeamMP server APIs. The client relies on some BeamNG
internals that change between game versions; each is wrapped so failure is logged
(`topgear` in the game log) rather than breaking the mod:

- Input locking via `core_input_actionFilter` (if resets aren't blocked, check this first).
- Navigation arrows via `core_groundMarkers.setPath` / `setFocus`.
- Damage via `map.objects[id].damage`; repair via `obj:requestReset(RESET_PHYSICS)`.
- Parts value via `core_vehicle_manager.getVehicleData` — if unavailable, workshop
  upgrades bill labour only.
- BeamMP spawn/edit data parsing (`jbm`, `vcf.partConfigFilename`) — `debugSpawns` shows the raw data.

## No arrows?

- There's no destination during the dealership. Arrows start with leg 1, after `/tg ready`.
- The event (or finale) needs a start point: `/tg courses` shows what's missing.
- Arrows follow the AI road network, so off-road targets may get no route. The tall orange
  beacon at the target and the compass arrow in the HUD line always work.
- Open the game console (`~`) and filter for `topgear`. Each new target logs a line like
  `target 'Checkpoint 1/3' at ..., arrows via core_groundMarkers.setPath`. `NONE` means your
  game version has none of the route functions this mod knows. Send me that log.

## Rebuilding the client zip

```
cd client && rm -f ../Resources/Client/topgear.zip && zip -r ../Resources/Client/topgear.zip lua scripts -x '*luac.out' '*.DS_Store'
```
