# Changelog

## Unreleased

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
- Give every render its own file name and prune old ones. On macOS, when
  another Space still showed one of the two alternating names, the wallpaper
  agent reused the image it had decoded hours earlier, so every other tick put
  back a stale sky — daylight at night.

## 0.1.0 — 2026-08-16

- Follow solar elevation and azimuth with theme-derived sky gradients.
- React to live cloud cover and fog from Open-Meteo.
- Project a deterministic star catalog using local sidereal time.
- Retint automatically after Omarchy theme changes.
- Yield when the user selects a different background.
- Provide explicit location and weather configuration, diagnostics, previews,
  and reversible user-scoped installation.
