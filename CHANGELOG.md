# Changelog

## Unreleased

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
