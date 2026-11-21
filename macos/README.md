# Skybg for macOS

A native app for the same skies: every style of `bin/skybg`, drawn in Swift
with Core Graphics. It needs no Python, no ImageMagick and no terminal once it
is built.

Open it to choose a style from live previews, drag the slider to see the style
through the day, set your location, and turn the timer on. Then close it.
Nothing stays in the Dock or the menu bar: a launch agent inside the app runs
every five minutes, draws the sky, sets it as the desktop picture and leaves.

## Build

```sh
macos/build.sh        # makes macos/build/Skybg.app
macos/test.sh
```

Both need only the Xcode Command Line Tools. Move `Skybg.app` to
`/Applications` before turning the timer on, since macOS remembers the timer by
where the app is.

The app is signed to run on the Mac that built it. Handing it to someone else
needs a Developer ID signature and notarisation, which `build.sh` does not do.

## How it relates to the command line

`bin/skybg` is still the skybg for Omarchy, and the two are kept in step by
hand. `Tests/fixtures.py` runs the Python over a spread of inputs and writes
what it computes to `Tests/SkyKitTests/parity.json`; the Swift tests must come
to the same numbers. After changing a style in `bin/skybg`:

```sh
python3 macos/Tests/fixtures.py && macos/test.sh
```

A failing test names what the port has yet to follow.

On first run the app takes its style, location and weather choice from
`~/.config/skybg/config.json` if there is one, and it reads the same optional
palette, `~/.config/skybg/colors.toml`. After that its settings are its own.

The app and the command-line timer can both be installed. Each steps aside
when the desktop picture is not one of its own, so whichever was turned on
last keeps the desktop and the other stops itself within ten minutes.

## What differs from `bin/skybg`

- The desktop picture is set through `NSWorkspace`, so macOS does not ask to
  let anything control System Events.
- Location is typed in or taken once from Core Location. There is no
  `linecast` lookup.
- Fog hides the stars as heavy cloud does.
- Renders live in `~/Library/Application Support/Skybg/`, where a failed tick
  also leaves its reason in `tick.log`.

## Layout

- `Sources/SkyKit/` is everything but the window: the sun and moon, the
  styles, the renderer, the wallpaper and the timer.
- `Sources/Skybg/` is the window, and the entry point the timer shares:
  `Skybg tick`. `Skybg render STYLE WIDTHxHEIGHT OUT.png` draws a picture to a
  file without touching the desktop.
- `Support/` holds the Info.plist, the launch agent and the icon.
