# Figure Worlds (prototype 0.1)

The second toy after Figure Shelf. His Figure Shelf animal walks around a small 3D village
with a friend animal. Everything is open from the start: no missions, no locks, no scores,
no text to read, nothing can go wrong.

Design doc: https://claude.ai/artifact/NAFhLifw7Bw6omjye7hXfU

## What's in the Cozy Village

| Place | Things to do |
|---|---|
| Square | Fountain (tap: big splash), 4 street lamps (tap: on/off), 2 benches (sit), bell (ding) |
| 3 houses | Doors open and close. Inside: bed to bounce on, lamp, toy box that pops out 3 balls |
| Playground | Swing, slide (climbs up, slides down), merry-go-round |
| Toys | 5 big balls to kick, 12 blocks in two towers, 6 flower pots, 9 small balls: carry and throw |
| Mailbox | Flag up/down |

## The map

The map button (top left) opens five big picture buttons: the Cozy Village 🏡, Forest Pond 🦆,
Snowy Hill ⛄, Robot Workshop 🤖 and Night Carnival 🎠. Tap one to go there; tap outside to close. All of them are open from the start. Each
place remembers where its toys were left, and the app opens in the last place he visited.

## Forest Pond

| Thing | What happens |
|---|---|
| Stepping stones | Hop across the pond to the other side |
| Boat | Sit in, one full loop round the pond, back to the jetty |
| Ducks, frogs | Tap from anywhere: a duck quacks and hops, a frog jumps to a free lily pad (never one next to a duck) |
| Campfire | On/off. The flames flicker and the light glows; the animal stops at the stones, facing the fire. Two logs to sit on |
| Giant mushrooms | Bounce on top, like the beds |
| Also | Tree swing, picnic with apples, pinecones to carry, two balls, fish that jump, butterflies |

## Snowy Hill

| Thing | What happens |
|---|---|
| Hill | Climb the icy steps, sled down the front |
| Ice pond | Skate a big circle, then spin |
| Snowman | Tap: waves, and the hat changes (4 hats) |
| Igloo | A snow-block tunnel with a dark doorway at the front. Walk in through it; the dome and tunnel hide while inside. Tapping the igloo from behind walks round to the door. Lantern inside |
| Snowballs | 8 to carry and throw; 2 big ones grow as they roll |
| Also | 2 benches, 2 street lamps, gently falling snow |

The camera comes in closer (or looks down from higher up) when a tree, lamp post or the igloo
would hide the animal, and it never goes outside the fence.

## Robot Workshop

| Thing | What happens |
|---|---|
| Conveyor belt | Green button: on/off. Crates on the belt ride along and tip into the blue bin |
| Crane | Red button: the magnet lowers, picks up a metal crate from the yellow pad, swings round and drops it in the green bin |
| Marble run | Purple button: a marble goes up the lift and zig-zags down three ramps (click at each turn, ding at the end) |
| Robot | Tap: waves (and the animal waves back), dances, or looks around with a light show. Chest lights change colour |
| Gear wall | Tap: four gears turn together, each the right way round |
| Big buttons | Red, yellow, blue: each lights its own lamp |
| Also | A ramp to kick balls up, wooden and metal crates to carry, workbenches with tools |

## Night Carnival

| Thing | What happens |
|---|---|
| Carousel | Climb on a horse; it turns and the horses go up and down. Lights twinkle |
| Ferris wheel | Sit in a gondola, one full turn, back at the bottom |
| Light board | Pink: string lights chase in colours. Yellow: the star signs at the gate light up. Blue: three gentle bursts of fireworks |
| Duck tub | Ducks swim round; tap one and it quacks and hops |
| Popcorn cart | Tap: the popcorn pops |
| Also | Striped tents, lamps that start lit, balls to kick, stars and a moon in the sky |

## How to play

- **Tap the ground** to walk there. Tap far away and the animal walks a bit faster.
- **Tap a thing** to walk over and use it. Big balls get kicked. Blocks, pots and small balls are
  picked up and carried over the head. **Tap the animal (or what it carries)** to throw it.
- **Tap the friend** to wave at each other. The friend follows, wanders nearby and sometimes copies dances.
- **Drag with one finger** to turn the camera, **pinch** to zoom. The camera button puts it back
  behind the animal. While walking the camera slowly comes back behind on its own (not right after he turned it,
  after a sharp turn, or during the sled, skating, boat, stones or frogs).
- **Animal button** (bottom left): the Figure Shelf chooser, for his animal or the friend (🤝).
  Accessories are the same 48 as in Figure Shelf (hats, glasses, masks, neck), including the 17 added in
  Nov 2026 (Santa, sun hat, unicorn, bunny ears, builder; googly, visor, pixel, cat-eye; beard, whiskers,
  piggy; tie, pearls, bell, fairy wings, backpack). `Shared/FigureBuilder.swift` is a straight copy of Figure Shelf's.
  30 animals: the first six, the 12 from the second batch, Shark, Mole, Bee, Parrot, Koala and
  Panda (Nov 2026), and Deer, Red Panda, Moose, Kangaroo, Giraffe and Capybara (Nov 22, 2026;
  screenshots in `screenshots-new-animals-4/`).
  The chooser also has all of Fedir's creatures, robots and animatronics (18 of each, Nov 22, 2026),
  the same as Figure Shelf: the first ten of each were copied in alongside the new ones. That is
  their `.usdz`, `_clips.json`, `_skin_*.jpg` and `_thumb.png` files, the robots' `_vehicle.usdz`
  and the vehicle and servo sounds. Resources are now about 307 MB. The 22 dinosaurs are in too
  (Nov 27, 2026, about 63 MB, 24 in all): the 12 earlier ones, Kentrosaurus and Microraptor, plus Styracosaurus, Iguanodon, Carnotaurus,
  Therizinosaurus, Gallimimus and Dilophosaurus, and the sea species Mosasaur, Elasmosaurus,
  Ichthyosaur and Megalodon. They reuse Figure Shelf's models, rigs and clips; no Meshy credits.
  - **Sea species on land:** they glide just above the ground, playing their swim loop.
  - **Water sounds:** splashes and swishes (`sfx_sea_*`) instead of footsteps and rawrs.
  - **At the Forest Pond:** when the player's figure is a sea species, the pond stops blocking the
    way (`Village.letSwimmerIn`), so tapping the water sends it swimming in. Tapping the land
    brings it back.
  - **No new limits:** nothing is gated and every tap still goes somewhere.
  - **Screenshots:** `screenshots-prehistoric/` (not committed). Fedir's second set of
  creatures (Pleatbill, Coilusk, Siftrunk, Spindlecrab, Ripplemantis, Tuftwhale, Knotcko and
  Cupspinner, Nov 22, 2026) was added the same way: its `.usdz`, `_clips.json`, `_skin_*.jpg` and
  `_thumb.png` files are in `Resources/`. Screenshots are in `screenshots-creatures-2/`.
  Fedir's second set of robots (Locomotive, Submarine, Tractor, City Bus, Forklift, Cable Car,
  Lunar Rover and Airship) is in too: the robot and `_vehicle.usdz` files, plus the new engine
  sounds in `Resources/Sounds/` (`sfx_run_train` … `sfx_run_airship`). `Shared/FigureRig.swift`
  and `Shared/RealFigure.swift` know the eight new vehicle kinds. Screenshots are in
  `screenshots-robots-2/`.
  Fedir's second set of animatronics is in too: Elephant, Pangolin, Ostrich, Lobster, Chameleon,
  Walrus, Kangaroo and Sloth. Their files are `showelephant`, `pangolin`, `skateostrich`,
  `lobster`, `chameleon`, `walrus`, `showkangaroo` and `sloth` in `Resources/`. Screenshots are in
  `screenshots-animatronics-2/`. Animals without an emoji show their little picture on the button.
  When Figure Shelf gets new animals, copy their `.usdz`, `_clips.json`, `_skin_*.jpg` and `_thumb.png`
  into `Resources/` and add them to `Shared/Model.swift` and `Shared/RealFigure.swift`.
  **Patterns** (Nov 2026): the Colors tab has a second row for the toy animals (Plain, Dots, Stripes,
  Checks, Stars, Hearts), on any color, for his animal and the friend (now all 30 animals). `Shared/PatternPainter.swift`
  is a copy of Figure Shelf's; it uses each animal's `<animal>_pos.png` and the `posBox` in
  `_clips.json` (baked by Figure Shelf's `models/bake_position_map.py`, see its README). For new
  animals, copy their `_pos.png` too. Screenshots: `screenshots-patterns/`.
- **Moves button**: dance, jump, run, spin, wave, again.
- **Sparkles button**: tidy up. Every toy floats back home. The round arrow undoes it.
- **Speaker** (top right): sounds on/off. Sounds are on by default.
- Everything stays where he left it, also after closing the app.

## Dance music

Each place has its own little dance tune (4 s, the length of the dance, so **Again** repeats it in time):

| Place | Tune |
|---|---|
| Cozy Village | bouncy plucked tune with a soft oom-pah bass and quiet claps |
| Forest Pond | wooden flute over a harp, two bird chirps and a water "plip" |
| Snowy Hill | music-box waltz with sleigh bells |
| Robot Workshop | friendly robot arpeggio on a soft synth, wood-block clanks and beep-boops |
| Night Carnival | calliope waltz (oom-pah-pah) with a glockenspiel sparkle |

They are original, synthesised by `tools/make_dance_music.py` (no samples), quiet like the other
sounds, and only play when the dance is tapped (the friend copying the dance plays it too). The
speaker button turns them off with everything else. Rebuild: `python3 tools/make_dance_music.py`.
Copies to listen to on the Mac: `dance-music/`.

In the Simulator, sounds go to the Mac's current sound output (System Settings > Sound > Output);
if that is a pair of headphones, the Simulator plays there.

## Files

- `FigureWorlds.swiftpm/World/`: the new code (village, walking, camera, taps, sounds, buttons).
- `FigureWorlds.swiftpm/Shared/`: copies of the Figure Shelf files (animals, looks, chooser, sounds),
  with small additions marked "Figure Worlds" (walking loop in FigureRig/RealFigure, a storage key
  for ShelfState). If Figure Shelf changes, copy the files again and redo those small additions.
- `FigureWorlds.swiftpm/Assets.xcassets/`: the app icon (a clay-style bunny in a party hat on a tiny round world, made
  with Figma's image generator). A copy is in `icon/AppIcon-1024.png`; the earlier in-game icon is `icon/AppIcon-1024-old.png`.
- `FigureWorlds.swiftpm/Resources/`: the 30 animals from Figure Shelf (models, clips, color textures, pattern position maps, chooser pictures)
  and the action sounds.

## How to run it

Open `FigureWorlds.swiftpm` in Xcode 16 or newer, pick your iPhone or iPad and press Run.
Team B6LBNVRNQ4 is already set. Bundle ID: `app.figureshelf.FigureWorlds`.
