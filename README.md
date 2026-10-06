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

Type `/tg menu` to open or close it. It opens by itself when the dealership and workshops open.
Tabs: **Start | Status | Dealership | Admin | Settings | Results**. **Every tab is a short stack of boxes**:
each box has a rounded border and a title; click the title (its arrow) to fold the box away or open it
again. Longer explanations hide behind a dim **(?)** - hover the mouse over it to read them. Colour key:
**solid blue = a button you click**; **grey box with a blue outline = a field you can type in or change**;
the standings are a light table. If the colours ever break the window on your BeamNG version, it
switches them off by itself and keeps working (`/tg diag` shows why); `/tg theme` (or the Settings tab)
turns them on/off. At the bottom of every tab, the **Messages** box keeps the mod's last 6 messages,
newest at the bottom and brightest.

- **Start** (far left; the menu opens on it before and during the dealership):
  - **Setup** (admins): three questions - **which course** (dropdown of saved courses, then **Load**),
    **the budget**, and **what type of cars** (dropdown: any car, your classes, or a ready-made class,
    which is made for you). Players see "Waiting for an admin" until the challenge starts.
  - **Dealer**: the steps, each lit green only once the one before is done: **Start the challenge** (lit
    when a finished course is loaded) -> **Car condition** (a dropdown, every player, after Start) ->
    **Go to the dealer** (opens the game's vehicle selector with today's cars; spawning one buys it) ->
    **Return this car** (red, two clicks: a full refund, so you can pick another) -> **I'm ready** (locks
    your car in - Return is locked from then on). Done steps say "(done)". The box's top right shows how
    many are ready ("2/3 players are ready"); once **everyone** is, a 5 s countdown ("Starting in 5...")
    closes the dealership and the first leg starts (`defaults.readyCountdown`, 0 = straight away). If
    anyone returns their car or a new player joins, the countdown stops. An admin's Next phase skips it.
- **Status** (the window switches to it once the challenge starts - when the dealership closes):
  - **My car**: your car, cash, points, damage, the button for whatever comes next (Ready, GO, Join,
    problem fixes in a workshop) and the driver buttons **Repair** (workshops only, shows the price),
    **Tow**, **Unstick** and **Respawn** - the (?) says what's usable right now. Tow and Respawn need two clicks.
  - **Standings** (the table) and, after a server restart mid-challenge, **Challenge saved** (Resume).
- **Dealership**:
  - **Buy a car**: your budget, **Browse the cars in the vehicle selector** (the game's own selector -
    pictures, filters, search - showing **only the cars you can buy in the condition you've picked**, at
    those prices: the price is in each name and in the Value filter; move the condition slider and the
    selector follows - a more worn condition opens up more cars; the usual vehicle-selector key does the
    same while the dealership is open), and **Return it for a full refund**.
    If the selector still shows every car, `/tg diag` has a **Vehicle selector** line - send it to the developer.
  - **Car condition**: the New .. Death Trap slider (see Car condition below). **Each condition has a colour** -
    blue New, green Used, dark yellow Needs work, orange Beater, red Death Trap: the slider takes the colour of
    the one you've picked, with the colour key under it.
  - **Today's cars**: a dropdown of the models on sale (with the cheapest price), then that model's trims,
    each with a **Buy** button (ones that need a more worn condition say which, with no button). Every model in
    the dropdown and every trim is **coloured by the condition you need to afford it** (a blue one you can
    buy new, a red one only as a Death Trap). The Start tab's condition dropdown uses the same colours.
  - **Parts** (once you have a car; folded): what fitting each part costs, with **Fit** buttons in workshops.
- **Admin** (admins only): **Challenge** (Start, Start (unfinished course), Next phase, Stop, Traffic mode)
  open; folded: **Players** (click a player or type a name, then **Give** / **Set** cash or **Award** points
  with an optional reason - a negative number takes cash or points away), **Money & timers** (budget,
  workshop timer, workshop frequency, price import), **Car classes**, **Course** - the course builder, as
  boxes: **Pick a course** (load / save as / new), **Event type** (the selected event's type buttons + rename),
  **Events** (always open: each event tagged **RACE** - everyone at once - or **TIME TRIAL** - one at a time;
  under the checkpoint buttons, **Next checkpoint: 5 m / 10 m / 20 m / Line** sets the size of the next one you
  add - a Line is a 20 m gate across the road (`defaults.lineWidth`), at right angles to the way from the point
  before it, and counts when you cross it; `/tg addcp <n> [5|10|20|line]`. **Set start here** moves the start -
  your checkpoints stay;
  pick the one to edit, **Delete event**; under it big **Set start here / Add
  checkpoint / Undo / Clear** buttons and **# of laps** for laps events - drive to the spot first, the (?)
  explains; under them **Test event** - that event on its own, from its countdown, with everyone who's in a car
  taking part in it (no money, workshop, finale, reset fines or saving; results, then back to normal) - **Quick
  travel** - the car you're in to the event's start, facing its first checkpoint - and **Stop event**; for a
  trailer delivery, Test event first brings everyone's trailer to hitch up, and the next GO starts it (in time
  trial mode: the first driver's run, then each driver's own GO); Test event
  and Quick travel only work when no challenge is going: `/tg testevent <n>`, `/tg testevent stop`,
  `/tg quicktravel <n|finale>`), **Waypoints** (the route on the drive to the event: Add / Undo / Clear route), **Event options**
  (the reasonably priced car, race or time trial, **Time to complete event (s)** + Set Time) and **Save course**
  (big Save / Revert / Clear buttons); then workshop locations and the session's events - and **Tools**
  (soundboard, fault tests). Stop and Clear ALL need a second click.
- **Settings** (everyone): **Sound** (your own sound on/off - only for you - Test sound, "Not hearing it?
  Try another way"), **Lights & flag** (Position / Test the start lights and the finish flag), **Window**
  (the colour theme on/off) and **Troubleshooting** (**Diagnostics** / **Parts diagnostics** - the results
  show in chat; include them when reporting a problem).

If the window ever gets squashed or lost off-screen, `/tg menu reset` puts it back.

When the challenge ends, the window opens on the **Results** tab (the last one): **Winner**, then a
**Results** table with one row per
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
| Star in a reasonably priced car | time trial (always) | fastest single lap of 3, everyone in the same car | start (= start/finish line) + checkpoints round the lap + laps + the car |

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
  everyone else waits at the start. **Every start is I'm ready, then GO** (`defaults.readyToGo`): at a **race**
  start everyone presses **I'm ready** (Status tab) and once everyone is, anyone's **GO** starts the countdown;
  in a **time trial** the turns begin by themselves once everyone's there, and each driver presses **I'm ready**,
  then **GO** (them or an admin) - the same for Test event. **Workshops** too: when you're done, press **I'm
  ready** (Status tab); once everyone is, anyone's **GO** closes the workshop and starts the next leg (the
  workshop timer still closes it at the end). With `readyToGo` false, the older starts below apply.
  **Each driver starts with a GO:** the event's GO button says who goes
  first ("GO: Bob") and starts their countdown; after that, every driver waits until **their** GO is pressed
  - the button on their Status tab reads "GO: Alice" - by them, or by an admin (Admin tab, Challenge box),
  and everyone else sees "Waiting for Alice to press GO". In Star in a reasonably priced car, that GO is what
  brings their car. (`defaults.soloGo`: false = the next driver starts by themselves.) **Everyone else watches:**
  when a driver's countdown starts, every other player's camera switches to that driver's car (for the reasonably
  priced car, the RPC itself) - BeamMP's own spectating: you can look, not drive. When the run ends you're back in
  your own car. **Back to my car** (Status tab) leaves early; **Watch the driver on track** in the Settings tab (or
  `/tg watch off` / `on`) turns it off for you; `defaults.watchRunner` false turns it off for everyone. The time limit is per run. An admin's `/tg next` ends just the
  current run. The mode is stored as `"solo": true/false` on the event in config.json. An event's
  mode can't be changed while that event is counting down or running.
- **Parking:** the bay is drawn on the ground as a car-sized box lined up the way the bay runs (from the car
  you parked there when you added it), so drivers can see which way to park. An arrow on its centre line
  points the way the car faced when the bay was added. (Scoring still counts nose in or backed in as straight.)
  Bays added before 0.9.19 show as a plain marker - add them again (`/tg clearbays`, then park and add)
  for the box and arrow.
  A course of one or more bays, parked in the order they were added. Add each bay by
  parking in it the way it should face (`/tg addbay <n>`, `/tg undobay <n>`, `/tg clearbays <n>`,
  or the course builder buttons). A bay counts once you've been stopped inside it (5 m) for
  1.5 s; then drive off to the next one (the HUD says "Bay 2/3"). Nose-in or reversed in are
  both "straight". Score = precision in every bay + time + damage taken during the run; bays
  you didn't reach before the time limit cost 50 each (none at all = DNF). Damage is NOT
  repaired afterwards. With several bays, raise the time limit (`/tg settime <n> <seconds>`
  or the course builder's Time limit box - available for every event).
- **Fragile delivery:** damage costs time *and* stays on the car - there's no free repair
  afterwards, so the dents count at the next inspection unless you pay for a repair at a workshop.
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
- **Star in a reasonably priced car:** a lap of the same track as a circuit, but in the **same car for
  everyone** and always one at a time. Everyone drives to the start in their own car and parks
  beside the line. Once everyone's there the turns begin: on your turn a fresh **reasonably priced car**
  appears on the start line and the game puts you in it (once BeamMP has confirmed it's yours - `/tg diag`
  shows "Reasonably priced car: in it / yours per BeamMP"). Start it and settle in, press **I'm ready**, then
  **GO** (you or an admin) starts the normal 5 s lights - no timer. You get the event's laps (3 by default) and
  **your fastest single lap counts** - every lap time is announced. After the last lap you have 3
  seconds to stop (`eventTypes.rpc.stopSeconds`), then the car is removed and you're back in your own
  car, exactly as you left it - same damage, problems, parts and fuel (it isn't touched: you get a
  second car rather than a swap). Crashed or stuck? **`/tg respawn`** (or `/tg unstick`) gives you a
  fresh one on the start line, free - the lap you were on counts as one of your laps but gets no time
  (on your last lap it ends your turn). No tows in the RPC; it costs nothing and its damage is never
  billed. Out of time? Your best timed lap still counts. **The car:** an Ibishu Covet DXi (automatic)
  unless the event picks another - `/tg setrpc <n> <model> [config]`, `/tg setrpc <n> mine` (the car
  you're sitting in), `/tg setrpc <n> default`, or **Use the car I'm in** in the course builder.
  Parked traffic cars (`simple_traffic`, `*_parked`) can't be driven, so they're refused (a course
  that already has one uses the default car).
  **The server needs `MaxCars` of at least 2** (the runner has their own car plus the RPC for a
  moment); if the car doesn't appear within 20 s that driver can't run (the chat says why) and the
  next one goes.
- **Slalom vs race:** a slalom runs one at a time, its gates are tight (4 m, vs 5 m race
  checkpoints - `defaults.cpRadius`; 12 m until 0.9.13), and a missed gate costs 5 s but you carry on; in a race you must hit every
  checkpoint in order or turn back. Place slalom gates close together in a weave.
- **Trailer, prebuilt load (recommended):** build the trailer once in game - spawn the small
  flatbed (`tsfb`), pick a load in the parts menu's Load slot and remove the straps - then, while
  it's your current vehicle, type `/tg trailersave`. It saves the trailer exactly as built - every
  slot (so removed straps stay removed) and its tuning values (e.g. the crate's mass). Custom builds
  from the garage are fine. Every trailer event then spawns that exact
  trailer for everyone, with the load as part of it. Each player's game measures how much of the
  load is still on the bed; the results show e.g. "72% of the load". `/tg trailertest` spawns it
  behind you and reports the load reading;
  `/tg trailercones` goes back to the empty trailer + loose cones below. The course builder's Event options
  for a trailer event show which trailer is set and have **Set trailer (the one I'm in)** next to Test / Remove.
- **Trailer with no load (a caravan, a travel trailer):** save it the same way - `/tg trailersave` or **Set
  trailer** while you're in it. With nothing in a load slot it's **delivered in one piece**: the 70 load points
  become how undamaged it arrives - 1 - its damage / `eventTypes.trailer.wreckDamage` (10,000), so a trailer
  at 4,000 damage is 60% intact = 42 points. The results say e.g. "trailer 60% intact". It still has to be
  hitched to you at the finish.
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
| Change an event's type | `/tg settype N <race\|circuit\|speedtrap\|parking\|fragile\|economy\|slalom\|trailer\|rpc>` |
| The reasonably priced car (rpc events) | `/tg setrpc N <model> [config]`, `/tg setrpc N mine`, `/tg setrpc N default` |
| Race or time trial mode | `/tg setmode N race` (everyone at once) / `/tg setmode N trial` (one at a time) |
| Forced waypoints on the drive TO event N | `/tg addvia N` |
| Finale finish + its route | `/tg setfinale`, `/tg addvia finale` |
| Rename | `/tg rename N The Hill Climb` |
| (Positions come from **the car you're sitting in**. A checkpoint on top of the start or of the one before it is flagged when you add it, and `/tg start` refuses the course until it's moved.) | |
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

Changed your mind? Every **I'm ready** can be taken back with **Not ready - undo** (`/tg unready`)
until what it was waiting for starts: the dealership's countdown (it stops), a race start's or the
workshop's GO, or your GO in a time trial. A trailer event's trailer is dropped behind you when you
press I'm ready (one driver at a time, so they don't land on each other) - hitch up, then GO.

In a time trial, a driver whose run is over sees "Back to the start in 5..." and then their car - as
it is, no repairs - is moved to a spot behind the start line, before the next driver goes
(`defaults.backToStartSeconds`; not for the reasonably priced car or a trailer event). Watching the
driver on track: **Back to my car** puts you in your own car and leaves a **Watch <name>** button to
go back to watching.

Stuck or beyond repair in workshop time? `/tg tow` (or the Tow button) takes the car to the nearest
workshop location (side by side if several arrive), at the normal tow price.

Admin tools (Admin tab): **Restart event** (two clicks, `/tg restartevent`) brings every car back to
the start line as it is and wipes the runs (nothing's scored yet) - then I'm ready and GO again.
Players box: **Give / Take** cash, **Award / Dock** points, and **Free respawn**
(`/tg freerespawn <driver>`: their car fixed where it stands, or a lost car back where it was - no
cost, no points, no DSQ).

### Sound bites

Top Gear clips play at key moments. Who hears each one:

| Moment | Clip(s) (one picked at random) | Who hears it |
|---|---|---|
| Challenge starts | top-gear-theme-intro | everyone |
| GO - the start lights go out (every run in time trial mode) | lights-out | everyone |
| You complete a run | happy-yes, grunt-yes | you |
| You win an event | jeremy-clarkson-yeeeeeesss | you |
| ...someone else wins | yes-no-yes | everyone else |
| DNF / DNS, a tow, a respawn that disqualifies you | oh-no-anyway | you |
| Someone is fined for an illegal reset | oh-for-gods-sake, jeremy-clarkson-oh-for-gods-sake | everyone |
| A crash (1,500+ damage at once) | oh-cock-james-may, clarkson-poop-shot-out | players within 100 m |
| Fastest through the speed trap so far | poweeerr-jeremy-clarkson | everyone |
| Precision parking: a bay measured (not the last - that's the finish) | grunt-yes | players within 100 m |
| Workshop opens | workshop-intro | everyone |
| The overall winner is announced | top-gear-theme-intro | everyone |

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
  in the client mod, all at the same loud level (-9 LUFS), using Docker), add the clip's name to `sounds.clips`, and
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
- **Either way, the driver pays their car's repair price** for any damage it had (the full price,
  without the workshop discount) - but **no tow fee and no points lost**.
- Finished challenges keep their Results tab after a restart. `/tg stop` clears the save.

### Adding traffic (admins)

`/tg traffic on` (or **Traffic mode** in the Admin tab's Challenge box) is a pause button on
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
  it, so they all charge the **roadside repair** = the full repair price x 1.25
  (`economy.roadsideMarkup`) - the workshop is always the cheapest place to get repaired: it takes 15% off
  the full price (`economy.workshopDiscount`). Tows and
  respawns add a service fee on top and cost **2 points each** at the final standings
  (`scoring.towPenaltyPoints`). The Status tab buttons show the current price. Examples:

  | Damage | Workshop repair | Respawn | Tow |
  |---|---|---|---|
  | 0 (just stuck) | $0 | $500 | $1,000 |
  | 2,000 (dented) | $1,063 | $2,063 | $2,563 |
  | 10,000 (wrecked) | $4,463 | $7,063 | $7,563 |
- **Stuck? `/tg unstick`** (or the Status tab button) is free: it sets the car upright in place
  and keeps all damage and problems. Only when (nearly) stopped, 15 s cooldown, not in a
  countdown. If on your BeamNG version the move repairs the car (with or without a reset), that
  roadside repair is billed once; the unstick itself stays free and costs no points.
- **`/tg respawn`** (Status tab button, click twice) respawns your car where it is: free at the
  dealership, the workshop repair price (15% off) in a workshop, otherwise the roadside repair + $500
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
  **The dealership is workshop mode too:** once you've bought a car, the parts menu is open until the
  dealership closes (and if the course has workshop locations, the dealership counts as one in every
  workshop). Parts only work in the dealership and workshop phases - at any other time the Parts box
  is greyed out (prices shown, Fit does nothing). Outside a workshop, paint is simply accepted and a
  part/tuning change is put back by the game (any damage that rebuild wiped is billed as a repair) -
  the server never cancels an edit, because BeamMP removes the car when it does. At the dealership - upgrades are billed like a workshop, paint is free, and returning the
  car refunds its upgrades with it. Swapping to another stock trim is priced as a trim, not as parts.
  **Parts box (price list + Fit):** the Dealership tab's **Parts** box lists every slot on your
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
    how many have a price - and whether the Parts box can list your car (and how).
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
    workshop repair price (15% off). Paint never changes damage, so it's never billed.
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
  tab's Players box). Names can be typed in any case, or just the start of one name.
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
the market - **every car's price** drops with the condition:

| Condition | Mileage | Price |
|---|---|---|
| New | - | full price |
| Used | 60,000 km | 75% (25% off) |
| Needs work | 100,000 km | 60% (40% off) |
| Beater | 200,000 km | 45% (55% off) |
| Death Trap | 300,000 km | **30%** (70% off) |

**Problem tiers** (0.9.21): so a worn car is never undriveable, every problem has a tier - **1** annoying
(accident damage, worn suspension, worn tires, alignment, ABS failure), **2** hurts performance (tired engine,
damaged turbo, worn brakes, glazed pads, worn synchros, fuel leak; slipping clutch, rough idle and worn gearbox
when switched on), **3** can stop the car (ignition problems, cooling problems, oil leak). A **Used** car draws
tier 1 only, **Needs work** up to tier 2, a **Beater** or **Death Trap** up to tier 3 - one tier 3 at most. And a
car never gets two problems from the same **group**: brakes (worn brakes, glazed pads, ABS), stalling (ignition,
fuel leak, oil leak, rough idle), heat (cooling, oil leak), gears (synchros, clutch, gearbox). In `config.json`:
each problem's `tier` and `groups`, `faults.maxTier` (worst tier per condition, Used .. Death Trap: 1, 2, 3, 3),
`faults.maxPerTier` (per car, tiers 1-3: 4, 4, 1), `faults.tiers: false` switches the rules off. Admins:
`/tg fault sample <condition> [n]` (or **Example problem sets** in the Admin tab's fault tester) shows example
cars drawn by the rules.

The discounts are `faults.discount` in `config.json` (0.25, 0.40, 0.55, 0.70 - steeper early steps since 0.9.13,
because BeamNG's car values are high: at a $15,000 budget only 7 cars are affordable new, and the old 10% off for
Used unlocked just 3 more - now it's 20 more, Needs work 49 in all, Beater 103, Death Trap 238). Set it to `[]` to
use career mode's own used-car formula instead (price x (1 - 0.25% per 1,000 km) + 5% scrap: 90/80/55/30%).

**Fast cars hold their value**: the discount above is for ordinary cars (0-100 km/h in 10 s or slower); the
quicker a car, the smaller its share of it, down to 30% of the discount at 4 s or quicker. So a Death Trap ETK
844 (8.5 s, $34,000 new) is $14,400 - about a new Covet - but a Death Trap ETK 856ttx 340 (4.4 s, $64,700) is
still $49,000, not $19,400. (`perfFastSeconds` 4, `perfSlowSeconds` 10, `perfMinShare` 0.3 in `config.json`
under `faults`; a car with no 0-100 time gets the full discount.) Prices
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
- **Or replace the part.** Fitting a different part in a workshop (the Dealership tab's Parts box) takes that part's problems
  with it - a new engine sorts the tired engine, oil leak and ignition problems. **A part with
  problems is scrap**: there's no trade-in, so the new part costs its **full price** (not the usual
  difference) plus labour. Healthy parts are still traded in as before. Which part holds which problems:

  | Part replaced | Sorts |
  |---|---|
  | Engine | tired engine, oil leak (and its doomed-engine risk), ignition problems (incl. the weak starter) (rough idle) |
  | Radiator | cooling |
  | Turbo | damaged turbo |
  | Gearbox / transmission | worn synchros (worn gearbox) |
  | Clutch | slipping clutch |
  | Brakes / pads | worn brakes, glazed pads |
  | Tires / wheels | worn tires |
  | Springs, dampers, coilovers, anti-roll bars | worn-out suspension |

  So fixing is cheapest for one or two problems; a new engine cures them all at once (and may add
  power). On a Death Trap Hirochi Sunburst 1.6, three engine problems cost $3,900 to fix (3 x $1,300),
  a 2.0L engine $6,300 to fit.
- **Every part bought new starts at 0 km** - the rest of the car keeps its mileage (`/tg diag`: "... ok, 1
  new part(s) at 0 km").
- **More worn, worse problems.** Each problem's strength scales with the condition - the table below lists a
  Beater's; a Used car's are half as bad, Needs work x0.75, a Death Trap's x1.3. A tired engine is -10% power on a
  Used car, -26% on a Death Trap; worn brakes -20% / -52%; a fuel leak 0.5 / 1.3 litres a minute; and a Death
  Trap's oil leak is likelier to be the doomed kind. Never past sane limits (tyres at least 15% pressure, at
  least half the engine, 30% of the brakes), and the weak starter never gets harsher than listed - a less worn car
  just cranks easier. Ignition cut-outs come further apart on a less worn car and closer together on a Death Trap. The names say how bad yours is ("Tired
  engine (about -26% power)"). `config.json`: `faults.severity` (Used, Needs work, Beater, Death Trap).
- **Every problem still there at the end costs 3 points** (a penalty of its own).
- They come back after a tow, a respawn or a reset until they're fixed or replaced.
- **A worn car also has the mileage to match**, using BeamNG's own part-condition system - the same one
  career mode's used-car dealership uses: the odometer shows the mileage above, with the wear the game
  gives it (a little more engine, gearbox and clutch friction, a less steady idle, slower automatic
  shifts). The paint is left alone: the game ages paint by locking each body panel's colour, which stops
  repaints from showing (and only the owner would see it). It stays for the whole challenge - resets,
  repairs and fixing problems don't make the car newer. `/tg diag` shows it ("Car wear (mileage):
  200,000 km - ok"). Because mileage already wears the idle, gearbox and clutch, the
  **Rough idle, Worn gearbox and Slipping clutch** problems are switched off by default.
- Everything is in `config.json` under `faults`: `mileageKm` (one value per condition,
  New first), `lossPerKm` (0.0000025), `scrapValue` (0.05), `fixPercent` (0.05), `fixMin` (500).

The problems (the code and config.json call them *faults*):

| id | Problem | What it does in the game |
|---|---|---|
| tires | Worn, underinflated tires | tire pressures set to 30% of normal (`$tirepressure_*`), never below the car's minimum |
| alignment | Knocked-out alignment | **pulls to the left or right** (picked per car; the name says which): the steering's straight ahead is moved 2.8% of full steering (`pull`; Used half that, Death Trap x1.3 = 3.64%) - hold a little opposite lock. Also front toe pushed to its limit, rear toe 40% of the way (`$toe_*`, cars that have it). `/tg diag`: "Alignment pull" |
| engine | Tired engine | engine output x0.8 |
| brakes | Worn brakes | brake torque x0.6 |
| ignition | Ignition problems (misfires, cuts out, slow to start) | BeamNG's own misfire chances raised a little (+0.05: the engine stumbles), every 2-4 minutes on the road (a Beater; Used 4-8, Death Trap about 1.5-3) the engine dies - **restart it yourself** (never during a countdown) - and a **weak starter**: the starter motor at 60% of its strength (`starter`; Used 80%, never weaker than listed), slow, labouring cranking before the engine catches. (Until 0.9.13 the weak starter was a problem of its own; saved configs and challenges move over by themselves, a custom starter strength included.) |
| cooling | Cooling problems | the radiator is damaged like in a front-end crash: coolant leaks and the engine overheats when pushed |
| suspension | Worn-out suspension | springs and dampers at their softest; on cars without adjustable suspension the anti-roll bars come off |
| fuelleak | Fuel leak | 1 litre a minute drains from the tank on the road (it matters in the economy run) |
| body | Accident damage (missing bumpers, dents, broken lights) | the front and rear bumpers are gone, and the car starts with 3,000 damage (repair costs, drivability) and some broken lights and glass. Fixing it puts the bumpers back and removes its dents - any other crash damage that goes with them is billed as a repair. Its own dents are never billed as a repair (a repair can't keep them out - they come straight back): Repair, tows and respawns only charge for damage beyond them, and if they're all there is, the Repair button says "Nothing to repair". (Until 0.9.13 missing bumpers was a problem of its own; saved configs and challenges move over by themselves.) |
| clutch | Slipping clutch | **off by default** (mileage wear already wears the clutch). The clutch keeps 60% of its grip (`factor`; Used 80%, Death Trap 48%, never under 35%): it slips when you floor it - pulling away, at peak torque - but every gear still drives (manual gearboxes). (Until 0.9.13 it used BeamNG's "permanently overheated" clutch, a flat 25% that made whole gears useless.) |
| synchros | Worn gearbox synchros | every gear's synchro 80% worn (Used 40%, Death Trap 90% - never 100%, where BeamNG breaks the gear): gears grind and fight you on quick shifts, but grinding adds no more wear while the problem is there, so a gear never dies (manual gearboxes) |
| turbo | Damaged turbo | the turbo's own damage: less boost, less power (turbo cars) |
| brakefade | Glazed brake pads | fully glazed pads, kept glazed (re-glazed every 0.5 s - hard braking would otherwise scrub it off): the brakes squeal and lose up to 20% when hot (that's BeamNG's own glazing effect, at its maximum) |
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
0.8.8 get every fault automatically (custom severities and switched-off faults are kept) - seventeen since 0.9.13.
Setup faults (tires, alignment, accident damage's bumpers, suspension) respawn the car when applied or fixed; the
others run inside the car and are re-applied after every reset or respawn. Putting bumpers back or
re-inflating tires via the parts/tuning menus doesn't work - the faults go straight back on.

Changing any part in a workshop rebuilds the car in BeamNG, which also wipes its damage, so
that repair is now billed automatically (the same price as `/tg repair`).

**Test on your game version first:** admin `/tg fault test` (or the Admin tab's fault test)
applies every fault to the car you're in, no money involved, and reports ok / unavailable /
error for each. `/tg fault testoff` removes them. Drive it and check each fault is felt.
**Test as a condition:** problems get worse on more worn cars, so the test can use a condition's strengths -
`/tg fault test ignition as used` (or `as needs work`, `as beater`, `as death trap`), or the **Test as**
dropdown above the Test buttons in the Admin tab (Tools; Beater by default, shown with its strength,
e.g. "Death Trap (x1.3)"). Without "as" the listed values are used (a Beater's). A test alignment always
pulls right; a test oil leak always blows.

Commands: `/tg condition` (yours) / `/tg condition <New|Used|Needs work|Beater|Death Trap>` (dealership;
`/tg fault take [n]` still works: n steps worse), `/tg faults` (the rules and your car), `/tg fix <id>`
(workshop, once it's found the problem). Admins: `/tg fault test [id] [as <condition>]`, `/tg fault testoff`, `/tg fault caps`.

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
