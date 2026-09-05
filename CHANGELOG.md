# Changelog

## Unreleased

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

## 0.1.0 — 2026-08-16

- Follow solar elevation and azimuth with theme-derived sky gradients.
- React to live cloud cover and fog from Open-Meteo.
- Project a deterministic star catalog using local sidereal time.
- Retint automatically after Omarchy theme changes.
- Yield when the user selects a different background.
- Provide explicit location and weather configuration, diagnostics, previews,
  and reversible user-scoped installation.
