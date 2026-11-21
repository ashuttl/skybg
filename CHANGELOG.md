# Changelog

## Unreleased

- Add three styles. `gradient` is a plain gradient that turns with the sun
  like the shadow on a sundial: lit from the sun's side of the screen, in
  colours of its own that the theme tints. `window` is sunlight through a
  window, its panes thrown into a bare room by the real sun — on the far wall
  and red when it is low, on the floor and white when it is high — softened
  and put out by cloud,
  with the moon's at night; it uses the weather, as `sky` does. `slitscan` is
  the whole day at once: each column of the screen is the sky at a different
  hour, with now in the middle.
- On macOS, run the launch agent with the Python 3.11+ that installed it.
  launchd's `PATH` finds only the system's Python 3.9, which could not even
  load the new styles, so every timer tick failed silently. `skybg doctor` now
  checks the agent's Python; rerun `./install.sh` to update the agent.
- Add a fourth style, `cyanotype`: a white-on-Prussian-blue chart of the sun's
  path for today over a ruled horizon, with the solstice and equinox paths
  behind it, the sun and moon in place, and the twilights as a wash below.
- Add a third style, `bokashi`: a woodblock-print sky of wiped ink bands, with
  a flat sun placed by the real sun and the moon in its real phase. The theme
  chooses natural paper or indigo-dyed stock. It ignores the weather.
- `bokashi` and `cyanotype` take their colours from the theme: each ink keeps
  its printed lightness and turns to the hue of the matching theme colour, and
  the sheet sits on the theme's background.
- Add a second style, `daylight`, ported from Pond's Daylight wallpaper: a
  fixed twelve-moment palette blended in Oklab, paced by the real sunrise and
  sunset at the configured location. It ignores the theme and the weather.
  Choose with `skybg config style sky|daylight|bokashi|cyanotype`.
- Show the real night sky: the Yale Bright Star Catalogue to the naked-eye
  limit, each star at its magnitude and colour, and the Milky Way from NASA's
  Deep Star Maps 2020, both bundled and projected for the location and the
  hour. The Milky Way waits for astronomical dark and thins toward the horizon
  and under cloud.
- Build the sky the way linecast's sky view does: a zenith colour plus two
  horizon colours, one under the sun and one opposite it, blended by bearing,
  with a horizon band that climbs the sky as the sun does. Sunsets now warm
  low and to one side and hold the mauve of the Earth's shadow opposite;
  by day the horizon is paler than the zenith rather than darker, and the
  day sky mixes from the theme's hues toward its bright foreground rather
  than up from a dark background, then part way back toward the background
  (`DAY_BRIGHTNESS`), so it is brighter than before but quieter than linecast's.
- Run on macOS: launchd timer, wallpaper via System Events, display size via
  `system_profiler`, and a built-in palette that follows the system light/dark
  appearance (override with `~/.config/skybg/colors.toml`).
- Make the built-in macOS palettes sky-realistic — saturated hue anchors and a
  dusk-blue night background — instead of near-neutral grays that washed the
  whole cycle out.
- Key the weather cache by location, so changing location no longer serves the
  previous location's weather until the TTL expires.
- Never give a render the name of one that a Space still shows, and prune old
  ones. On macOS, when another Space still showed one of the two alternating
  names, the wallpaper agent reused the image it had decoded hours earlier, so
  every other tick put back a stale sky — daylight at night. Renders are now
  `sky-0.png` upward, skipping every name the wallpaper store records for any
  Space or display, and the last two renders, which macOS may still be
  loading or briefly holding on to. The names stay few because macOS keeps
  every image file it is given in a list it rechecks on each change: a new
  name every tick made each change take half a minute within weeks.

## 0.1.0 — 2026-08-16

- Follow solar elevation and azimuth with theme-derived sky gradients.
- React to live cloud cover and fog from Open-Meteo.
- Project a deterministic star catalog using local sidereal time.
- Retint automatically after Omarchy theme changes.
- Yield when the user selects a different background.
- Provide explicit location and weather configuration, diagnostics, previews,
  and reversible user-scoped installation.
