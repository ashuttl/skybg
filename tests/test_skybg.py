import datetime
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "bin" / "skybg"
loader = importlib.machinery.SourceFileLoader("skybg", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
skybg = importlib.util.module_from_spec(spec)
loader.exec_module(skybg)


class SolarTests(unittest.TestCase):
    def test_equinox_noon_is_high_near_equator(self):
        instant = datetime.datetime(2026, 3, 20, 12, tzinfo=datetime.timezone.utc)
        elevation, azimuth = skybg.solar_position(0, 0, instant)
        self.assertGreater(elevation, 87)
        self.assertTrue(0 <= azimuth < 360)

    def test_westbrook_is_dark_at_midnight_in_january(self):
        instant = datetime.datetime(2026, 1, 15, 5, tzinfo=datetime.timezone.utc)
        elevation, _ = skybg.solar_position(43.677, -70.371, instant)
        self.assertLess(elevation, -60)

    def test_phase_boundaries(self):
        self.assertEqual(skybg.phase_name(-13), "night")
        self.assertEqual(skybg.phase_name(-12), "astronomical twilight")
        self.assertEqual(skybg.phase_name(0.5), "golden hour")
        self.assertEqual(skybg.phase_name(8), "day")


class ColorTests(unittest.TestCase):
    def test_ansi_only_theme_is_normalized(self):
        theme = "\n".join([
            'background = "#101820"',
            'foreground = "#d0d0d0"',
            *[f'color{i} = "#{i:02x}{i:02x}{i:02x}"' for i in range(16)],
        ])
        with tempfile.NamedTemporaryFile("w", delete=False) as source:
            source.write(theme)
            path = source.name
        try:
            with mock.patch.object(skybg, "COLORS_TOML", path):
                colors = skybg.theme_colors()
            for name in ("blue", "bright_blue", "orange", "darker_background"):
                self.assertIn(name, colors)
        finally:
            os.unlink(path)

    def test_sky_field_channels_are_bounded(self):
        colors = {name: skybg.hexrgb(value) for name, value in skybg.HUE_DEFAULTS.items()}
        colors.update({
            "background": skybg.hexrgb("#20242b"),
            "darker_background": skybg.hexrgb("#14171c"),
            "lighter_background": skybg.hexrgb("#30343b"),
            "orange": skybg.hexrgb("#b9825a"),
        })
        pixels = skybg.sky_field(colors, 2, 105, 0.4, False)
        self.assertTrue(all(0 <= channel <= 1 for row in pixels for pixel in row for channel in pixel))

    def test_builtin_palettes_render_colorful_sunsets(self):
        # The built-in macOS palettes have no terminal theme to defer to, so
        # they should produce a genuinely colorful sky: a washed-out palette
        # collapses every stop toward gray (channel spread near zero).
        for appearance in ("light", "dark"):
            with mock.patch.object(skybg, "theme_source",
                                   return_value=("builtin", appearance)):
                colors = skybg.theme_colors()
            _, _, near = skybg.sky_stops(0, colors)  # sunset, under the sun
            self.assertGreater(max(near) - min(near), 0.15, appearance)
            zenith, _, _ = skybg.sky_stops(40, colors)  # midday
            self.assertGreater(zenith[2] - zenith[0], 0.05, appearance)  # blue > red

    def test_sky_stops_follow_the_sky(self):
        # After linecast's sky view: at sunset the horizon under the sun is
        # warmer than the horizon opposite it, and by day the horizon is
        # paler than the zenith, not darker.
        with mock.patch.object(skybg, "theme_source", return_value=("builtin", "dark")):
            colors = skybg.theme_colors()
        _, far, near = skybg.sky_stops(0, colors)
        self.assertGreater(near[0] - near[2], far[0] - far[2])  # near is redder
        zenith, far, near = skybg.sky_stops(40, colors)
        self.assertGreater(sum(far), sum(zenith))
        self.assertGreater(sum(near), sum(zenith))

    def test_sky_field_warms_toward_the_sun(self):
        with mock.patch.object(skybg, "theme_source", return_value=("builtin", "dark")):
            colors = skybg.theme_colors()
        pixels = skybg.sky_field(colors, 0, 270, 0.0, False)  # sunset in the west
        bottom = pixels[-1]
        west, east = bottom[-1], bottom[0]
        self.assertGreater(west[0] - west[2], east[0] - east[2])

    def test_star_catalog_is_deterministic(self):
        colors = {"bright_foreground": (0.8, 0.8, 0.8)}
        instant = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        first = skybg.star_mvg(800, 600, -20, 0, colors, instant, 43, -70)
        second = skybg.star_mvg(800, 600, -20, 0, colors, instant, 43, -70)
        self.assertEqual(first, second)
        self.assertIn("fill rgba", first)


class WeatherTests(unittest.TestCase):
    def _get_weather(self, directory, lat, lon, fetched_cloud=100):
        response = io.BytesIO(json.dumps(
            {"current": {"cloud_cover": fetched_cloud, "weather_code": 3}}).encode())
        with mock.patch.object(skybg, "STATE_DIR", directory), \
                mock.patch.object(skybg, "WEATHER_CACHE",
                                  os.path.join(directory, "weather.json")), \
                mock.patch.object(skybg, "load_config",
                                  return_value={"location": "auto", "weather": True}), \
                mock.patch.object(skybg.urllib.request, "urlopen", return_value=response):
            return skybg.get_weather(lat, lon)

    def test_weather_cache_is_keyed_by_location(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "weather.json"), "w") as f:
                json.dump({"ts": time.time(), "cloud": 0.01, "fog": False,
                           "lat": 33.5, "lon": 36.2}, f)
            # Same location: fresh cache wins over the (cloudier) live fetch.
            self.assertEqual(self._get_weather(directory, 33.5, 36.2), (0.01, False))
            # Moved away: the cache is stale regardless of TTL — refetch.
            self.assertEqual(self._get_weather(directory, 43.677, -70.371), (1.0, False))

    def test_pre_location_cache_is_refetched_not_crashed(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "weather.json"), "w") as f:
                json.dump({"ts": time.time(), "cloud": 0.01, "fog": False}, f)
            self.assertEqual(self._get_weather(directory, 33.5, 36.2), (1.0, False))


class ConfigAndCliTests(unittest.TestCase):
    def test_explicit_location(self):
        with mock.patch.object(skybg, "load_config", return_value={"location": [1.5, -2.5]}):
            self.assertEqual(skybg.get_location(), (1.5, -2.5))

    def test_missing_auto_location_has_actionable_error(self):
        with mock.patch.object(skybg, "load_config", return_value={"location": "auto"}), \
                mock.patch.object(skybg.subprocess, "run", side_effect=FileNotFoundError), \
                mock.patch("builtins.open", side_effect=FileNotFoundError):
            with self.assertRaisesRegex(skybg.SkybgError, "config location"):
                skybg.get_location()

    def test_preview_cloud_validation(self):
        args = skybg.parser().parse_args(["preview", "101"])
        with self.assertRaisesRegex(skybg.SkybgError, "between 0 and 100"):
            skybg.run(args)

    def test_config_round_trip(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(skybg, "CONFIG_DIR", directory), \
                mock.patch.object(skybg, "CONFIG_FILE", os.path.join(directory, "config.json")):
            skybg.save_config({"location": [10, 20], "weather": False})
            self.assertEqual(skybg.load_config(), {"location": [10, 20], "weather": False})


if __name__ == "__main__":
    unittest.main()
