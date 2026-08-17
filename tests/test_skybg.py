import datetime
import importlib.machinery
import importlib.util
import json
import os
import tempfile
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

    def test_star_catalog_is_deterministic(self):
        colors = {"bright_foreground": (0.8, 0.8, 0.8)}
        instant = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        first = skybg.star_mvg(800, 600, -20, 0, colors, instant, 43, -70)
        second = skybg.star_mvg(800, 600, -20, 0, colors, instant, 43, -70)
        self.assertEqual(first, second)
        self.assertIn("fill rgba", first)


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
