# Top Gear Challenge for BeamMP (v0.1)

A game mode that runs on top of a stock BeamNG map. Players buy a car with $10,000, drive
between four events, race for prize money, visit the workshop twice, and finish with a
drivability inspection at every workshop and at the end. No map files are modified, so every
player already has the map.

## Install

1. Copy `Resources/Server/TopGear/` into your BeamMP server's `Resources/Server/`.
2. Copy `Resources/Client/topgear.zip` into `Resources/Client/`. BeamMP sends it to players on join.
3. In `ServerConfig.toml` set `Map = "/levels/west_coast_usa/info.json"` (or another map, see below).
   If an admin will host AI traffic, raise `MaxCars` (the plugin still stops normal players
   from spawning more than their one challenge car).
4. Start the server once. It writes `Resources/Server/TopGear/config.json`. Put your name in
   `"admins"` (while it's empty, everyone is an admin).

**No car import needed.** The mod ships with `cars.json`, a catalogue of every stock BeamNG car and truck
(986 trims of 40 models) with its game price and details, so the dealership, car classes and price
estimates work straight away. Only run `/tg importprices` for mod cars or after a BeamNG update adds cars.
Note that game prices are new-car prices (the cheapest car is $10,000; the middle one about $57,000) -
raise the budget (`/tg budget`) or use a class multiplier for cheap-car challenges.

## The in-game window

Type `/tg menu` to open or close it. Colour key: **solid blue = a button you click**; **grey box with a blue
outline = a field you can type in or change**; blue headings mark sections; the standings are a light table.
If the colours ever break the window on your BeamNG version, it switches them off by itself and
keeps working (`/tg diag` shows why); `/tg theme` (or the Settings tab) turns them on/off. It opens by itself when the dealership and workshops
open. Tabs:

- **Status**: your car, cash, points, damage, standings, and the button for whatever comes
  next (Ready, GO, Join, problem fixes in a workshop). The driver buttons are always there:
  **Repair** (workshops only, shows the price), **Tow**, **Unstick** and **Respawn**, with a grey
  line saying what's usable right now. Tow and Respawn need two clicks. Admins also get an
  **Admin controls** dropdown here with Start, Start (unfinished course), Next phase and Stop, and
  **Player cash & points**: click a player (or type a name), then **Give** / **Set** cash or
  **Award** points with an optional reason (a negative number takes cash or points away).
- **Dealership**: **Browse the cars in the vehicle selector** opens the game's own vehicle selector
  (the freeroam one: pictures, filters, search, details) showing **only today's cars at today's
  prices** - the price is in each name and in the Value filter, with "as a Beater" (the condition that would afford it) / "over
  budget" where it applies. Spawning one buys it. The usual vehicle-selector key does the same while
  the dealership is open; at any other time (and for an admin in traffic mode) it's the game's normal
  list. If the selector still shows every car, `/tg diag` has a **Vehicle selector** line (game
  version, whether today's list is ready and reached the selector) - send it to the developer. Below the button is the same list as text, every trim you could buy with a **Buy** button
  (ones that need a more worn condition say which, with no button), and **Return for a full refund** to swap.
- **Parts** (once you have a car): what fitting each part costs, with **Fit** buttons in workshops.
- **Admin** (admins only): budget and workshop timer, price import, hitch scan,
  per-player cash, and a course builder (pick an event, drive there, click Set start / Add
  checkpoint / Add route waypoint, then Save). Stop and Clear ALL need a second click.
- **Settings** (everyone, the last tab): your own **sound** on/off (only for you), Test sound and
  "Not hearing it? Try another way"; **Position / Test** the start lights and the finish flag;
  the **colour theme** on/off; and **Diagnostics** / **Parts tab diagnostics** (the results show
  in chat - include them when reporting a problem).

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

Every event runs in one of two **modes**, whatever its type:

- **Race mode** - everyone starts together on one countdown.
- **Time trial mode** - one at a time, in the order you arrived, each with your own countdown.

The winner is decided the same way in both (a destination race in time trial mode is the classic
time trial: fastest run wins). Pick the mode per event in the Admin tab's course builder (**Mode:
Race / Time trial**) or with `/tg setmode <n> race|trial`. The table shows each type's default.

| Type | Default mode | Winner | Placed with |
|---|---|---|---|
| Destination race | race | first to the finish (fastest run in time trial mode) | start + checkpoints |
| Circuit race | race | first to complete the laps | start (= start/finish line) + checkpoints round the lap + laps |
| Speed trap | time trial | highest speed on one run through the trap (passes under `minRunSpeed`, 20 m/s, don't count) | start + trap |
| Precision parking | time trial | lowest score: 10 pts/m off centre + 0.5/deg skew (every bay) + 0.1/s + 0.01/damage + 50 per bay not reached | start + bays (in order) |
| Fragile delivery | race | time + 0.01 s per point of damage picked up | start + checkpoints |
| Economy run | race | least energy used - fuel or battery (inside the time limit) | start + checkpoints |
| Slalom | time trial | time + 5 s per missed gate | start + gates |
| Trailer delivery | race | most points out of 100: 70 for the share of the load kept + 30 for speed | start + checkpoints |

- **Starting lights:** every countdown shows F1-style lights at the top of the screen - five
  reds, one per second, then all out (green) for GO. One-at-a-time runs show the runner's name.
  `/tg lightstest` plays the sequence on your screen right away (no race needed). The lights are
  their own window: `/tg lights` (or **Position the start lights** in the Settings tab) keeps the box up
  so you can drag it by its title bar wherever you like - the game remembers where - and hides it again.
- **Finish flag:** the moment your run is complete, a checkered flag with a big **FINISH**, the
  event's name and your time (best speed for a speed trap) appears for 6 seconds - so you know
  you're done even while others are still driving. It also shows when you reach the finale's finish
  line, with your drivability score. No flag if you didn't finish (DNF, DNS or towed). It's its own
  window like the start lights: `/tg flag` (or **Position the finish flag** in the Settings tab) keeps
  it up so you can drag it by its title bar - the game remembers where - and `/tg flag` again hides
  it. `/tg flagtest` shows a sample.
- **Time trial mode:** runners go in the order they arrived, each with their own countdown;
  everyone else waits at the start. The time limit is per run. An admin's `/tg next` ends just the
  current run. The mode is stored as `"solo": true/false` on the event in config.json. An event's
  mode can't be changed while that event is counting down or running.
- **Parking:** a course of one or more bays, parked in the order they were added. Add each bay by
  parking in it the way it should face (`/tg addbay <n>`, `/tg undobay <n>`, `/tg clearbays <n>`,
  or the course builder buttons). A bay counts once you've been stopped inside it (5 m) for
  1.5 s; then drive off to the next one (the HUD says "Bay 2/3"). Nose-in or reversed in are
  both "straight". Score = precision in every bay + time + damage taken during the run; bays
  you didn't reach before the time limit cost 50 each (none at all = DNF). Damage is NOT
  repaired afterwards. With several bays, raise the time limit (`/tg settime <n> <seconds>`
  or the course builder's Time limit box - available for every event).
- **Fragile delivery:** once the results are in, every car that took part gets a free full
  repair where it stands (upgrades and unfixed problems stay, like a tow).
- **Economy:** the least **energy** used wins - read from each player's own car: what's left in its
  fuel tanks *and* batteries, so petrol, diesel and electric cars compare fairly (an electric car is
  naturally efficient). Results show litres for fuel cars and kWh for electric ones, with the
  megajoules used, e.g. "0.32 L (10.9 MJ)". A car whose game reports neither is timed instead and
  ranked after the others, with the reason shown.
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
- Saved courses from before 0.8.4: "Time trial" events become destination races in time trial mode
  automatically (and `/tg settype <n> timetrial` still does that). Any race named "Hill Climb"
  without a mode set is switched to time trial mode once.

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
| Change an event's type | `/tg settype N <race\|circuit\|speedtrap\|parking\|fragile\|economy\|slalom\|trailer>` |
| Race or time trial mode | `/tg setmode N race` (everyone at once) / `/tg setmode N trial` (one at a time) |
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
  For "crowded streets", an admin buys their car first, then turns on **traffic mode** and spawns
  AI traffic or parks extra vehicles as obstacles (see "Adding traffic" below).
- **Leg 4 → The Speed Trap**: a long highway straight. One run; slow passes don't count.
- **Finale**: back to a "test track" finish, via a rough road so damage matters.

Italy is a great alternative theme (narrow villages, mountain passes, gravel): change the
`Map` line and build a course the same way. Courses are per-map, so keep a copy of
`config.json` per map.

## Running a challenge

`/tg start` → dealership phase. Players spawn a car from the normal vehicle menu. The
server charges them, rejects unlisted cars and unaffordable ones, and refunds if they
delete it. `/tg ready` from everyone (or admin `/tg next`) closes the dealership.

Each leg: drive to the event. Nothing starts until every racer has arrived; then any
racer presses the big green **GO!** button in the Status tab (or types `/tg go`; everyone must be at the start line) and a 5-second countdown runs
(`defaults.countdown` in config.json). Then: event → results/prize money → (workshop) →
next leg → … → finale → standings.
Admin `/tg next` forces the current phase to end (e.g. someone is stuck: players who
haven't arrived get a DNS). `/tg stop` cancels everything.

### Sound bites

Top Gear clips play at key moments. Who hears each one:

| Moment | Clip(s) (one picked at random) | Who hears it |
|---|---|---|
| Challenge starts | top-gear-theme-intro | everyone |
| GO (every run in time trial mode) | speed-and-power, poweeerr-jeremy-clarkson | everyone |
| You complete a run | happy-yes, grunt-yes | you |
| You win an event | jeremy-clarkson-yeeeeeesss | you |
| ...someone else wins | yes-no-yes | everyone else |
| DNF / DNS, a tow, a respawn that disqualifies you | oh-no-anyway | you |
| Someone is fined for an illegal reset | oh-for-gods-sake, jeremy-clarkson-oh-for-gods-sake | everyone |
| A crash (1,500+ damage at once) | oh-cock-james-may, clarkson-poop-shot-out | players within 100 m |
| Fastest through the speed trap so far | poweeerr-jeremy-clarkson | everyone |
| Workshop opens | james-may-says-cheese | everyone |
| Final results | clarksooon, jeremy-clarkson-yeeeeeesss | everyone |

- **`/tg sounds off`** / **`on`** (or the **Sounds** button in the Settings tab) mutes them for you.
- **`/tg soundtest [clip]`** plays one to you (even when muted) and says which way your game played it.
  **Can't hear it?** `/tg soundtest next` switches to the next way of playing sounds - there are three,
  because which one works depends on the BeamNG version. `/tg diag` shows the one in use.
- **Soundboard (admins):** the Admin tab's **Soundboard** has a button per clip, or `/tg play <clip>`;
  it plays for everyone who hasn't muted sounds. `/tg sounds list` lists the clips.
- **Change it in `config.json` under `sounds`:** each moment in `events` has `to` (`all`, `self` = the
  driver it's about, `others` = everyone but them, `near` = within `nearRadius` metres) and `clips`;
  `crashDamage` sets what counts as a crash, and `"enabled": false` switches all sounds off.
- **Adding clips:** put the `.mp3` in `MP3s/`, run `tools/convert-sounds.sh` (converts them to `.ogg`
  in the client mod with matched loudness, using Docker), add the clip's name to `sounds.clips`, and
  rebuild the client zip. The name is the file name without `.mp3` and any `_XXXXXXX` download tag.

### Server crashes and dropped connections

The running challenge is **saved to `session.json`** (next to config.json) every few seconds and at every
phase change: everyone's cash, points, results, car condition and problems, tows, the car they bought with its upgrades, and
where it was.

- **Server crash or restart:** the challenge comes back **paused**. As players reconnect the window shows
  who's back. An admin presses **Resume the challenge** (`/tg resume`) when everyone's here, or
  **Discard it** (`/tg discard`, two clicks). On resume everyone's car is brought back - upgrades and
  its problems included - where it was last seen; the dealership and workshops reopen with the time
  they had left. **An event that was running (or counting down) is run again** from its start line:
  the cars are delivered there and nobody gets a second arrival bonus. Anyone not back yet gets their
  car when they rejoin.
- **One player drops and rejoins** (same name): their car comes back automatically where they left it,
  with its upgrades. During an event they were in, they're out of it (DNF), as before.
- **Either way, the driver pays their car's repair price** for any damage it had - like a workshop
  repair - but **no tow fee and no points lost**.
- Finished challenges keep their Results tab after a restart. `/tg stop` clears the save.

### Adding traffic (admins)

`/tg traffic on` (or **Traffic mode** under Admin controls on the Status page) is a pause button on
the spawn rules, for you only: while it's on, everything you spawn - BeamNG's AI traffic, parked cars
from the vehicle menu - is non-scoring traffic, in any phase including the dealership, and your
vehicle menu is unlocked. Your HUD shows **TRAFFIC MODE** as a reminder. Your own car, cash and score
are untouched, and every other player's restrictions stay as they are. `/tg traffic off` puts the
rules back; the traffic you placed stays on the map.

- Buy your own car **before** turning it on at the dealership - while it's on, a car you spawn is
  traffic, not a purchase (the server reminds you).
- If your own car is lost, respawning it still works as a tow, even in traffic mode.
- Course-builder positions always come from your own car, never from your traffic.
- Every traffic vehicle uses one of your vehicle slots: raise `MaxCars` in ServerConfig.toml.
- `/tg start` clears everyone's vehicles, so add traffic after starting.

Player commands: `/tg menu`, `/tg go`, `/tg unstick`, `/tg tow`, `/tg respawn`, `/tg hitchup`, `/tg flag`, `/tg flagtest`, `/tg sounds on|off|list`, `/tg soundtest [clip|next]`, `/tg status`, `/tg dealer`, `/tg quote`, `/tg repair` (workshop only),
`/tg standings`, `/tg join` (late joiners during the dealership).

## Rules as implemented

- **Resets are locked** during the challenge (R, Insert/recovery, reload, home, node grabber,
  editor) because BeamNG's own resets and rewinds all repair the car. Anyone who gets round
  the lock is fined $1,000 and loses 2 points.
- **Roadside help costs the repair too.** Tow, respawn and an unstick that repairs the car all fix
  it, so they all charge the **roadside repair** = the workshop repair price x 1.25
  (`economy.roadsideMarkup`) - the workshop is always the cheapest place to get repaired. Tows and
  respawns add a service fee on top and cost **2 points each** at the final standings
  (`scoring.towPenaltyPoints`). The Status tab buttons show the current price. Examples:

  | Damage | Workshop repair | Respawn | Tow |
  |---|---|---|---|
  | 0 (just stuck) | $0 | $500 | $1,000 |
  | 2,000 (dented) | $1,250 | $2,063 | $2,563 |
  | 10,000 (wrecked) | $5,250 | $7,063 | $7,563 |
- **Stuck? `/tg unstick`** (or the Status tab button) is free: it sets the car upright in place
  and keeps all damage and problems. Only when (nearly) stopped, 15 s cooldown, not in a
  countdown. If on your BeamNG version the move repairs the car (with or without a reset), that
  roadside repair is billed once; the unstick itself stays free and costs no points.
- **`/tg respawn`** (Status tab button, click twice) respawns your car where it is: free at the
  dealership, the normal repair price in a workshop, otherwise the roadside repair + $500
  (`economy.respawnFee`) and -2 points.
  Mid-run it's a DSQ from that event; on the final leg it means 0 at the finale inspection. If your car has
  been lost or deleted, Respawn brings it back (that counts as a tow). Respawns are counted
  with tows on the final screen.
- **`/tg tow`** (Status tab button, click twice) costs the roadside repair + $1,000 (`economy.towFee`)
  and -2 points, and is a full repair that keeps
  upgrades, paid problem fixes and unfixed problems. During an event: DSQ from that event and
  delivered to the next event's start, ready to race. During a travel leg: delivered to that
  event's start (no arrival bonus). On the final leg: delivered to the finish with 0 at the
  finale inspection. Respawning a lost/deleted car counts as a tow and restores its upgrades.
  Tows and respawns are counted on the final screen.
- **How events end:** DNS = not at the start when the countdown began (only possible when an
  admin forces a start). DNF = still running when the event's time limit (`timeLimit` per
  event) runs out or the admin calls time, or the car was lost mid-event. DSQ = towed.
- **Workshops** come after every 2nd event (never after the last one - the finale inspection
  should judge the car you've got). Change it with `/tg workshopevery <n>` or in the Admin tab.
  **Where:** give a course workshop locations (Admin tab -> Workshop locations: **Import gas
  stations** reads the map's gas stations; **Add workshop here** places one where you're parked;
  `/tg importgas`, `/tg addworkshop [name]`, `/tg undoworkshop`, `/tg clearworkshops`). When a
  workshop opens, the arrows point to the nearest one, and repairs, problem fixes, parts, paint and
  tuning only work while you're within 30 m of it. A course with no locations keeps the old
  "workshop anywhere" behaviour. Locations are saved with the course.
  **The dealership is workshop mode too:** once you've bought a car, the parts menu is open until
  you drive away from the dealership after it closes (and if the course has workshop locations, the
  dealership counts as one in every workshop). Outside a workshop, paint is simply accepted and a
  part/tuning change is put back by the game (any damage that rebuild wiped is billed as a repair) -
  the server never cancels an edit, because BeamMP removes the car when it does. At the dealership - upgrades are billed like a workshop, paint is free, and returning the
  car refunds its upgrades with it. Swapping to another stock trim is priced as a trim, not as parts.
  **Parts tab (price list + Fit):** the Top Gear window's **Parts** tab lists every slot on your
  car with every part that fits it and what fitting it would cost you - the price shown is what
  you're charged. At the dealership and in a workshop each option has a **Fit** button (it installs
  the part like the game's parts menu and is billed the same way); everywhere else the tab is a
  read-only price list. Upgrades cost the difference to the part you have; a cheaper part refunds
  half the difference; looks-only parts say "free"; options beyond your overdraft limit are marked
  and can't be fitted. Parts that come with a part (an engine's own intake, say) are billed too.
  BeamNG's own parts menu still works as before. **Refresh the list** re-reads the car.
  How the bill works:
  - **Parts:** after every rebuild, your own game compares the car's parts before and after and
    tells the server exactly what changed (it reads both the old flat parts list and the newer
    parts tree). Performance parts are charged at their BeamNG value - the same "value" career
    mode's parts shop uses - the moment they're fitted (removing one refunds half). If the game
    can't read a part's price, a flat `workshop.flatPartPrice` ($500) is charged instead.
    `/tg partsdiag` shows what your game reports: how many parts it found, in which format, and
    how many have a price - and whether the Parts tab can list your car (and how).
  - **Labour:** $300, once per workshop, on your first real part change.
  - **Overdraft:** parts, labour and problem fixes can take a driver up to $1,500 into the red
    (`workshop.creditLimit`). Repairs, tows, respawns and fines have no limit - you can always get
    the car fixed and back on the road, however deep in the red that puts you. A part or problem fix that would
    go past the limit is refused - a part is taken straight back off the car, nothing charged.
    Prize money pays it all off.
  - **Free (looks only):** paint, skins/liveries, decals, plates, badges, mirrors, lights, trim,
    bumpers, lips, side skirts, fender flares, grilles, body kits, the whole interior (seats, dash,
    gauges, steering wheel...), and tuning. **Always billed:** wings, spoilers and hoods - they change
    downforce or weight - and every performance part. Decided by the part's slot.
  - **Repairs:** changing parts rebuilds the car in BeamNG, which repairs it. Whenever a car's
    damage drops to near zero in a workshop (for any reason), that repair is billed at the
    normal repair price. Paint never changes damage, so it's never billed.
  - **Resets are never fined in a workshop.** Parts, paint and tuning changes outside a
    workshop are refused.
  - Every workshop edit, rebuild and reset is logged in the server console (`[TopGear] edit by ...`),
    with the phase it happened in - check there if a charge looks wrong.
- **Scoring** - the most points wins; it's meant to feel like the show, where no one strategy
  always wins:
  - **Events:** 10 / 6 / 3 / 1 points for 1st-4th.
  - **Drivability, up to 20:** the car is **inspected on arrival at every workshop** (before any
    repair - so it scores how you drove that leg) **and at the finale**; each inspection is
    20 x (1 - damage / 20,000), and your drivability is **the average of them all**. The finale's
    is 0 if you were towed or respawned on the final leg or didn't arrive. On a course with
    workshop locations, anyone who never reaches one is inspected when the workshop closes.
  - **Penalties at the end:** -2 per illegal reset, **-2 per tow or roadside respawn**, **-3 per
    problem still unfixed** (its own penalty - a wrecked car can't hide it), and **-1 for every $500
    (or part of it) you're in debt** - so overspending, debt-funded repairs and tows all cost.
  - **Producer points:** an admin can award or dock points with a reason, like the show's
    producers: `/tg award Alice 2 best-looking wreck`, `/tg award Bob -1 got lost`.
  - **Money in the bank doesn't score** - it only breaks ties (after event wins).
  The results table shows each driver's inspections (e.g. "16.7 (20/20/10)") and how the points
  add up. Every number is in `config.json` under `scoring` (and `faults.inspectionPenaltyPoints`).

## Money and prices

- `/tg budget <amount>`: set the starting cash (saved). During the dealership everyone's
  cash moves by the same amount; it can't drop below a car someone already bought.
  Mid-challenge it applies from the next challenge. `/tg budget` alone shows the current value.
- `/tg workshop <minutes>`: set the workshop length (saved). If a workshop is open, its
  timer moves by the difference.
- `/tg setcash <name> <amount>` / `/tg give <name> <amount>`: adjust one player (also in the Status
  tab's Admin controls). Names can be typed in any case, or just the start of one name.
- **Cars and prices come built in** (`cars.json`, every stock car): nothing to import. The catalogue
  isn't copied into config.json, so a mod update can refresh it; your own prices (`/tg setprice`),
  classes and budget are saved in config.json and apply on top.
- `/tg importprices` (optional - for mod cars, or a newer BeamNG): an admin's game reads **every car
  in the game** (mods too): each stock trim's BeamNG value plus its details (country, body style,
  years, transmission... - what car classes filter on). It **replaces the built-in catalogue** on this
  server and is saved in config.json. `/tg importprices builtin` (or **Back to the built-in catalogue**
  in the Admin tab) goes back to cars.json; your prices and classes are kept.
  After a full import, **every imported car and truck is for sale** when no class is picked (the
  dealer list is only used before one). `/tg importprices covet pickup` imports specific models (new
  ones are added to the dealer list); `/tg importprices listed` re-reads just the dealer list.
  Custom/modified configs have no price and can't be bought. `/tg gameprices off|on` switches
  between game prices and the manual list.
- Trims over your budget that **a more worn condition could pay for** are listed with **"$10,200 as a Death
  Trap"** (etc.) - no Buy button until you pick that condition. **A car that's over the budget even as a
  Death Trap isn't shown at all** - not in the Dealership tab, `/tg dealer` or the vehicle selector -
  whatever class is in use. Spawning one you can't afford yet says which condition would cover it.
  `/tg dealer <model>` lists one model's trims.

## Car classes (which cars the dealership sells)

Like a Top Gear brief - "a Japanese hatchback from the 90s" - a **class** limits the dealership to
the imported trims that match its **rules**, plus any you **include** by hand, minus any you
**exclude**. Rules use the same details BeamNG's own vehicle menu filters by: `country`, `brand`,
`body` (Body Style), `type` (Car/Truck/...), `years`, `transmission`, `drivetrain`, `fuel`,
`propulsion`, `induction`, `configtype` (Factory/Police/...), `performance`, `derby`, and ranges
for `value`, `weight`, `topspeed`, `accel` (0-100 km/h) and `offroad` - and `trims base`: only each
model's **base trim** (its cheapest factory trim). A trim must match every rule.

**Ready-made classes:** `/tg class preset` lists them with how many trims each has; `/tg class preset
jdm` makes one (`/tg class preset jdm myname` under another name), or use the Admin tab's
**Ready-made classes** (Make, then Use). Once made it's an ordinary class you can edit.

| Name | Cars |
|---|---|
| `allcars` | every car and truck (what "no class" sells) |
| `basetrims` | each model's cheapest factory trim |
| `jdm` / `american` / `euro` | Japanese cars / American cars and trucks / German, Italian, French and Polish cars |
| `classics` / `retro` / `modern` | cars up to 1979 / from the 80s and 90s / 2000 and newer |
| `muscle` | American RWD coupes and sedans of the 60s and 70s |
| `hothatch` | hatchbacks doing 0-100 km/h in 9 s or less |
| `small` / `sports` | sub-compact and compact cars / sports cars |
| `offroad` / `vans` | 4WD/AWD pickups and SUVs / vans and minivans |
| `police` / `motorsport` | police builds / race, rally and drift builds |
| `specials` | derby, Gambler 500, ratrods and other custom builds |
| `commercial` | commercial trucks and buses |

1. `/tg importprices` once (the class only sells imported stock trims).
2. `/tg class new jdm`, then rules: `/tg class rule jdm country Japan`,
   `/tg class rule jdm years 1986-1999` (or `1986-` / `-1999`), `/tg class rule jdm body Hatchback,Coupe`.
   `/tg class values body` lists the values your cars have.
3. Hand-picks: `/tg class include jdm pickup` (a whole model) or `.../exclude jdm covet/sport_M` (one trim);
   `/tg class clear jdm covet/sport_M` undoes either.
   **Every car, base trims only:** `/tg class new basics base` (or **All cars, base trims** in the Admin
   tab) makes a class with `trims base` and `type Car,Truck` (so props and trailers stay out); add rules
   to narrow it, e.g. `/tg class rule basics country Japan`.
4. Prices: `/tg class price jdm covet/gtz_M 13000` (one trim; `off` = back to the game price) and
   `/tg class multiplier jdm 0.8` (every trim's game price x 0.8). Price a car just over the budget
   and it's the prize for picking a worse condition ("as a Needs work").
5. **Pick the class for each challenge**, before `/tg start`: `/tg class use jdm` (`none` = every
   imported car and truck). It isn't saved with courses. `/tg start` announces it, the Dealership tab shows it,
   and spawning anything else is refused with the reason ("not in today's class (jdm): Country is
   United States"). A class with no cars won't start.

**Props, traffic and trailers aren't imported**: anything BeamNG tags as a prop (cones, barriers, the
AI-traffic stand-ins, the walking unicycle), a trailer or a debug object is skipped, so no class can sell
one. (Configs imported by an older version are tidied the same way when the server starts.)

**Cars with no game price** (derby builds, Gambler 500 and other joke builds, mod cars) are **priced by
estimate**: the middle price of the 5 most similar cars that do have a game price, compared on
power-to-weight, 0-100 km/h, top speed, weight, year and off-road score (the same model and the same
type - car or truck - count as more similar). Tested by hiding real prices: half the estimates land
within about 10% of the game's price, 80% within about 37%. A trim with no performance figures gets the
middle price of its own model's trims; one with neither stays unpriced and can't be sold. Estimates are
redone after every import and marked "(est. price)" in the Dealership tab; class multipliers apply to
them like any price.

`/tg setprice <model/config> <amount>` (or the Admin tab's **Cars without a game price**) replaces an
estimate with a **dealership-wide price** - used in every class and in the normal dealer list (for listed models).
It also changes a priced trim's price everywhere; `off` puts it back (to the game price or the estimate).
`/tg setprice list` lists the trims with no game price and their estimates.
A class price (`/tg class price`) still wins for that class. In a class's car list the unpriced ones
are marked "(no price)" with a price box.

The Admin tab's **Car classes** section does all of this with buttons: Use / Edit per class, New
class, Add rule (pick the field, type the value), Include / Exclude, the price %, and the class's
cars each with **Leave out** and a price box. `/tg class list` and `/tg class show <name>` in chat.

## Car condition

Before buying, each player picks their car's **condition** with a slider in the Dealership tab (or
`/tg condition <name>`): **New, Used, Needs work, Beater or Death Trap**. A more worn car is cheaper on
the market - **every car's price** drops with the condition's mileage, using career mode's own used-car
formula (price x (1 - 0.25% per 1,000 km) + 5% scrap value, without career's age factor):

| Condition | Mileage | Price |
|---|---|---|
| New | - | full price |
| Used | 60,000 km | 90% (10% off) |
| Needs work | 100,000 km | 80% |
| Beater | 200,000 km | 55% |
| Death Trap | 300,000 km | **30%** |

So **a beaten-up luxury car costs what a new cheap one does**: a Death Trap ETK 800 ($34,000 new) is
$10,200, about a new Pigeon ($10,000) - while a Death Trap supercar ($180,000) is still $54,000. Prices
are rounded to $100. The Dealership tab, `/tg dealer` and the vehicle selector all show the prices for
the condition you've picked, and say what an out-of-budget car would cost in the condition that makes
it affordable ("$10,200 as a Death Trap").

- **Choose before you buy: it's locked in with the car.** Return the car to choose again.
- **Each step hides one problem in the car**, drawn at random from the ones **your car can
  actually take** when you buy it (swap or return the car at the dealership and they're drawn again).
- **The problems are hidden.** Everyone hears the condition, nobody sees the problems - until a
  **workshop finds them**: the first time you're in a workshop the mechanics tell you what you've
  got, and the Status tab lists them with a **Fix this problem** button each. The finale inspection
  names any left.
- **Fixing one costs 5% of the car's new price** (at least $500) in a workshop: `/tg fix <id>` or the
  Status tab. A luxury car is dear to keep running: a Pigeon's fix is $500, an ETK 800's $1,700.
- **Every problem still there at the end costs 3 points** (a penalty of its own).
- They come back after a tow, a respawn or a reset until they're fixed.
- **A worn car also has the mileage to match**, using BeamNG's own part-condition system - the same one
  career mode's used-car dealership uses: the odometer shows the mileage above, with the wear the game
  gives it (a little more engine, gearbox and clutch friction, a less steady idle, slower automatic
  shifts) and **faded paint** (career's paint-age scale). It stays for the whole challenge - resets,
  repairs and fixing problems don't make the car newer. `/tg diag` shows it ("Car wear (mileage):
  200,000 km, paint 0.88 - ok"). Because mileage already wears the idle, gearbox and clutch, the
  **Rough idle, Worn gearbox and Slipping clutch** problems are switched off by default.
- Everything is in `config.json` under `faults`: `mileageKm` and `paintWear` (one value per condition,
  New first), `lossPerKm` (0.0000025), `scrapValue` (0.05), `fixPercent` (0.05), `fixMin` (500).

The problems (the code and config.json call them *faults*):

| id | Problem | What it does in the game |
|---|---|---|
| tires | Worn, underinflated tires | tire pressures set to 30% of normal (`$tirepressure_*`), never below the car's minimum |
| alignment | Knocked-out alignment | front toe pushed to its limit, rear toe 40% of the way (`$toe_*`) |
| bumpers | Missing bumpers | front/rear bumper slots emptied |
| engine | Tired engine | engine output x0.8 |
| brakes | Worn brakes | brake torque x0.6 |
| ignition | Ignition problems | BeamNG's own misfire chances raised (the engine stumbles), and every 90-240 s on the road the engine dies - **restart it yourself** (never during a countdown) |
| cooling | Cooling problems | the radiator is damaged like in a front-end crash: coolant leaks and the engine overheats when pushed |
| suspension | Worn-out suspension | springs and dampers at their softest; on cars without adjustable suspension the anti-roll bars come off |
| fuelleak | Fuel leak | 0.5 litres a minute drains from the tank on the road (it matters in the economy run) |
| body | Accident damage | the car starts with 3,000 damage (repair costs, drivability) and some broken lights and glass; fixing the fault removes the dents |
| starter | Weak starter | the starter motor has a third of its strength: slow cranking before the engine catches (nasty with the ignition fault) |
| clutch | Slipping clutch | **off by default** (mileage wear already wears the clutch). The clutch's own "permanently overheated" state: drive slips away under hard acceleration (manual gearboxes) |
| synchros | Worn gearbox synchros | every gear's synchro 80% worn: gears grind and fight you on quick shifts (manual gearboxes) |
| turbo | Damaged turbo | the turbo's own damage: less boost, less power (turbo cars) |
| brakefade | Glazed brake pads | fully glazed pads: the brakes squeal, are weaker and fade more as they heat up |
| abs | ABS failure | ABS switched off: the wheels lock under hard braking |
| oilleak | Oil leak | **only on a Beater or Death Trap** (`minCondition` 3 - a lightly used car's engine doesn't blow). The engine runs hot with more friction and a little less power - and there's a **20% chance it's doomed**: a doomed engine lets go (seizes) after 1-10 minutes of hard driving (above ~54 km/h), on a leg, in an event or on the final leg. That's a tow; the leak stays, but that engine can't blow again. Nobody knows whether theirs is doomed - the workshop just says "oil leak" - and fixing it removes the risk. |
| idle | Rough idle | **off by default** (mileage wear already makes the idle hunt). The engine's idle-speed error turned way up (what engine wear does): it hunts at idle and can stall at junctions or on the start line |
| gearbox | Worn gearbox | **off by default** (mileage wear already adds gearbox friction). Three times the gearbox friction (any gearbox type): a little less power at the wheels |

**Every car is different.** If a drawn fault can't be applied to your car (no adjustable alignment,
an electric car with no fuel tank...), it's quietly swapped for another - nothing to hand back - and
the server remembers it for that car, so it isn't drawn for it again. Admins: `/tg fault caps` (or
**Which cars take which faults** in the Admin tab) lists what's been learnt per car; it's saved in
`config.json` under `faultCaps` - the start of grouping cars by what faults they support.

Per problem, in `config.json` under `faults`: `maxPerCar`, `inspectionPenaltyPoints`, and per fault `factor` (severity), `enabled` (false leaves it out of the
draw), for ignition `cutoutMin`/`cutoutMax` (seconds between cut-outs) and for the oil leak
`blowChance` (0.2) and `blowMin`/`blowMax` (seconds of hard driving before a doomed engine goes). Saved configs from before
0.8.8 get all nineteen faults automatically (custom severities and switched-off faults are kept).
Setup faults (tires, alignment, bumpers, suspension) respawn the car when applied or fixed; the
others run inside the car and are re-applied after every reset or respawn. Putting bumpers back or
re-inflating tires via the parts/tuning menus doesn't work - the faults go straight back on.

Changing any part in a workshop rebuilds the car in BeamNG, which also wipes its damage, so
that repair is now billed automatically (the same price as `/tg repair`).

**Test on your game version first:** admin `/tg fault test` (or the Admin tab's fault test)
applies every fault to the car you're in, no money involved, and reports ok / unavailable /
error for each. `/tg fault testoff` removes them. Drive it and check each fault is felt.

Commands: `/tg condition` (yours) / `/tg condition <New|Used|Needs work|Beater|Death Trap>` (dealership;
`/tg fault take [n]` still works: n steps worse), `/tg faults` (the rules and your car), `/tg fix <id>`
(workshop, once it's found the problem). Admins: `/tg fault test [id]`, `/tg fault testoff`, `/tg fault caps`.

**Check the new faults on your game version:** everything after the first five uses BeamNG
functions that couldn't be tried outside the game. `/tg fault test <id>` on your own car
reports ok / unavailable / error for each - then drive it and check you can feel it. Each **Test**
button in the Admin tab tries one fault (the previous test fault comes off); test faults act any time,
so the fuel leak drains and the ignition fault cuts the engine within 15-30 s even with no challenge running.
A test oil leak is always doomed and lets go after 20-40 s of hard driving, so you can see it happen.

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
cd client && rm -f ../Resources/Client/topgear.zip && zip -r ../Resources/Client/topgear.zip lua scripts art -x '*luac.out' '*.DS_Store'
```
