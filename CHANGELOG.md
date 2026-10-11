# Changelog

## Unreleased

### Added

- Quake played in a terminal from the shareware, registered or LibreQuake files
  (`mix quake --dir path/to/quake`), its own `progs.dat` running on the QuakeC machine:
  the whole game as its QuakeC defines it, Quake's server physics, the lightmapped
  picture with sky, liquids, models, sprites, particles and the status bar, and sounds
  placed in the world.
- `--picture` (or `CAULDRON_PICTURE`): how the picture reaches a terminal that keeps
  images, by default Quake's own 320×200 (`native:1,swap`).
- `--mute` (or `CAULDRON_MUTE=1`): no sound.
