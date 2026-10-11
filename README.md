# ElixirQuake

Quake, written in Elixir, played in a terminal. The renderer, the BSP world, collision
hulls and sliding moves are Cauldron's (`cauldron_3d`); this package reads Quake's files
and runs the game: the QuakeC program from `progs.dat` on a QuakeC virtual machine,
Quake's server physics and monster movement, the builtins the program calls, and the
client's screen — models, particles, the status bar, sounds.

```sh
mix deps.get
mix quake --dir path/to/quake
mix quake --dir path/to/quake --map e1m1 --skill 2
```

`--dir` is the game directory holding `pak0.pak` (or the directory above its `id1`). Set
`QUAKE_DIR` to skip it. The game starts on `start`, the hub where the episode and skill
are chosen by walking, unless `--map` says otherwise.

On a terminal that keeps images (kitty, Ghostty, WezTerm, iTerm2) the picture is drawn
at Quake's own 320×200 and the terminal scales it to the window, so a small font gives more
room without a blurrier picture; `native:2` is sharper and costs about twice the time a frame. `--picture` (or `CAULDRON_PICTURE`, or
`config :cauldron_2d_drafter, picture: "..."` in a `config/runtime.exs`) chooses
otherwise, with any of these comma separated: `native` draws at Quake's own size times
the largest whole number that fits the window, `native:N` at `N` times, `size:WxH`
sets the size itself, `png` sends each frame as a PNG (about a third smaller, for play
over ssh, at more CPU), `swap` replaces each frame without a blank between, and `none`
draws at the window's cells instead. The default is `native:1,swap`.

No game data is included. Two sources work:

* id Software's shareware `pak0.pak` (episode 1), which may be passed on unchanged; the
  registered game's paks may not
* [LibreQuake](https://github.com/lavenderdotpet/LibreQuake), a free replacement with its
  own maps, art and QuakeC under the BSD licence; both its `BSP29` and `BSP2` maps load

The view keeps Quake's vertical field of view, that of 90 degrees across a 4:3 screen,
so a wide terminal sees further to the sides rather than losing the bottom of the view
and the weapon in hand.

## Keys

| Key | Action |
| --- | --- |
| `W` `S` or `↑` `↓` | forward, back |
| `A` `D` | strafe |
| `←` `→` | turn |
| `T` `G` or `PgUp` `PgDn` | look up, down |
| `C` or `End` | look straight ahead |
| `F` | fire |
| `Space` | jump, swim up |
| `R` (held) | run |
| `Q` `E` | previous, next weapon |
| `1`–`8` | a weapon |
| `Esc` | the menu |

`Esc` opens Quake's own menu, drawn from the game's pictures and paused while open:
single player (a new game), options, help and quit. Options holds customize controls
(Enter then a key or mouse button to bind it, Backspace to clear), reset to defaults,
screen size, brightness, mouse speed, sound volume, always run, invert mouse and use
mouse; they are saved per player. The mouse is off until "use mouse" is on: then moving
it turns and looks, the left button fires, the right button runs, and the wheel changes
weapon. Multiplayer, loading and saving say they are not part of this game.

A controller works too: the left stick walks and strafes and the right stick turns and
looks, each as far as it is pushed; the right trigger fires, the left trigger (or
pressing the left stick) runs, `A` jumps, `X` looks ahead, the bumpers change weapon and
`Start` opens the menu, where the d-pad moves, `A` chooses and `B` goes back.

## What is here

* the whole game as its QuakeC defines it — weapons, monsters and their AI, doors, lifts,
  buttons, triggers, secrets, teleporters, items and power-ups, liquids, the start hub,
  level changes carrying the player's weapons and health, death and restarting
* Quake's server physics: walking with steps, friction and edge friction, air and water
  movement, water jumps, pushers that carry and block, tossed, bouncing and flying things,
  monsters stepping, flying and swimming, choosing new directions around obstacles
* the picture: lightmapped world with animated light styles, sky, rippling liquids,
  models lit from the floor below them, sprites, the held weapon with bob, particles
  (blood, puffs, explosions, lava and teleport splashes, rocket, grenade, gib and magic
  trails), lightning beams, the status bar, notify and centred messages, the
  intermission tally, the episode's closing text, and the screen washes of damage,
  bonuses, power-ups and liquid
* sounds placed in the world from the game's `.wav` files

## What is not

* ambient looping sounds (water, wind, torches) and the music: the shareware's music was
  CD audio, and LibreQuake's is Ogg Vorbis, which `TuningFork` does not read
* dynamic lights (muzzle flashes, rockets and explosions lighting the walls), coloured
  `.lit` lighting, the underwater picture warp, player colour translation
* saving and loading, demos, deathmatch and cooperative play, the console
* mission pack (`hipnotic`, `rogue`) extensions

## How it is built

Three packages shared with other games carry the engine:

* [`quake_c`](../cauldron/quake_c) (MIT) — the QuakeC virtual machine
* [`cauldron_3d_formats`](../cauldron/cauldron_3d_formats) (MIT) — the readers for paks,
  maps, models, sprites, pictures and sounds
* [`quake_server`](../quake_server) (GPL) — the running level: spawning, entities,
  collision and linking, physics, monster movement, the builtins and messages

This package is the game around them:

* `ElixirQuake.Assets` keeps each map, model, picture and sound once for every process,
  read with Quake's own conventions (hull sizes, texture kinds, the `conchars` font), and
  `ElixirQuake.Source` hands them to the server
* `ElixirQuake.Game` is the `Cauldron2D.Game`; `View`, `Effects`, `Particles` and
  `LightPoint` gather what the player sees, and `Render`, `StatusBar` and `Text` draw it
* `ElixirQuake.Menu` (with `Menu.Draw` and `Menu.Quit`) is Quake's menus, and
  `ElixirQuake.Client` the `Cauldron2D.Client.Game` that offers them as the game's own

### Speed

On one Apple M-series machine, a server frame of the shareware's first level takes about
0.4 ms, and of LibreQuake's largest about 1 ms; a 240 by 150 picture with its surfaces
made takes 20 to 40 ms. Everything is Elixir; drawing is spread over the schedulers.

## Tests

```sh
mix test
QUAKE_DIR=path/to/quake mix test
```

Without `QUAKE_DIR` the test that plays a level is skipped.

## Licence

GPL-2.0-or-later. Quake's source was released by id Software under the GPL; the server
physics, monster movement, builtins, client effects and the model normals here follow it
closely, so this package is a derivative of that source. Cauldron, which it runs on, is
MIT and contains no Quake code or data.

Quake's own data — the shareware and registered paks — is id Software's (now ZeniMax's)
and is not covered by that release; this package only reads it from files the player
supplies. LibreQuake's data is under its own licences.
