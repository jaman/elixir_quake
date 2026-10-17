# Changelog

## [0.2.0]

### Added

- The game is drawn by the graphics card (`ElixirQuake.Gpu`) where there is one: in the
  terminal pane by default, or in a window of its own. The picture options `software`,
  `gpu` and `window` choose for one run.
- The options menu's Drawing row: auto, software, the card in the terminal, or a
  window, saved with the other settings.
- A setup page before the game starts (`Cauldron2D.Drafter.Launcher`) that finds a Quake
  game directory in Steam's usual installs, CrossOver's included, and checks the one
  you give.

## [0.1.0]

### Added

- Quake played in a terminal from the shareware, registered or LibreQuake files
  (`mix quake --dir path/to/quake`), its own `progs.dat` running on the QuakeC machine:
  the whole game as its QuakeC defines it, Quake's server physics, the lightmapped
  picture with sky, liquids, models, sprites, particles and the status bar, and sounds
  placed in the world.
- `--picture` (or `CAULDRON_PICTURE`): how the picture reaches a terminal that keeps
  images, by default Quake's own 320×200 (`native:1,swap`).
- `--mute` (or `CAULDRON_MUTE=1`): no sound.

