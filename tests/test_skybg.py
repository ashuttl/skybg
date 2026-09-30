import datetime
import importlib.machinery
import importlib.util
import io
import json
import math
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


def equatorial(ra_deg, dec_deg):
    ra, dec = math.radians(ra_deg), math.radians(dec_deg)
    return (math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec))


def screen_position(name_vector, width, height, instant, lat, lon):
    cam, _, f, _ = skybg.camera(width, height, lat, instant, lon)
    c = tuple(sum(row[k] * name_vector[k] for k in range(3)) for row in cam)
    return skybg.project(c, f, width / 2, height / 2)


class SkyDataTests(unittest.TestCase):
    def test_catalogue_is_the_bright_star_catalogue(self):
        stars = skybg.load_stars()
        self.assertEqual(len(stars), 8404)
        self.assertLess(stars[0][3], -1.4)   # Sirius first
        self.assertTrue(all(mag <= 6.5 for _, _, _, mag, _ in stars))

    def test_milky_way_raster_has_a_bright_bulge(self):
        raster = skybg.load_milky_way()
        w, h = skybg.MILKY_WAY_W, skybg.MILKY_WAY_H
        # Galactic centre: RA 266.4, Dec -29.0. Right ascension runs leftward
        # from the middle column; the celestial pole is the top row.
        col = int(w / 2 - 266.4 * w / 360) % w
        row = int((90 + 29.0) * h / 180)
        bulge = max(raster[r * w + (col + dc) % w]
                    for r in range(row - 15, row + 16) for dc in range(-15, 16))
        self.assertGreater(bulge, 150)
        # The north galactic pole, in Coma Berenices, is far from the band.
        col = int(w / 2 - 192.86 * w / 360) % w
        row = int((90 - 27.13) * h / 180)
        self.assertLess(raster[row * w + col], 20)

    def test_missing_data_is_reported(self):
        with mock.patch.dict(os.environ, {"SKYBG_DATA": "/nonexistent", "XDG_DATA_HOME": "/nonexistent"}), \
                mock.patch.object(skybg.os.path, "realpath", return_value="/nonexistent/bin/skybg"):
            with self.assertRaises(skybg.SkybgError):
                skybg.data_dir()


class CameraTests(unittest.TestCase):
    instant = datetime.datetime(2026, 9, 6, 2, 25, tzinfo=datetime.timezone.utc)

    def test_projection_round_trips(self):
        cam, inverse, f, _ = skybg.camera(2880, 1800, 43.7, self.instant, -70.4)
        for px, py in ((10.0, 10.0), (1440.0, 900.0), (2870.0, 1790.0)):
            c = skybg.unproject(px, py, f, 1440, 900)
            self.assertAlmostEqual(sum(v * v for v in c), 1.0, places=9)
            qx, qy, qz = skybg.project(c, f, 1440, 900) + (0,)
            self.assertAlmostEqual(qx, px, places=6)
            self.assertAlmostEqual(qy, py, places=6)
            q = tuple(sum(row[k] * c[k] for k in range(3)) for row in inverse)
            back = tuple(sum(row[k] * q[k] for k in range(3)) for row in cam)
            for a, b in zip(back, c):
                self.assertAlmostEqual(a, b, places=9)

    def test_polaris_keeps_the_latitude(self):
        polaris = equatorial(37.95, 89.26)
        for hour in (0, 6, 12, 18):
            instant = self.instant.replace(hour=hour)
            _, _, _, horizontal = skybg.camera(2880, 1800, 43.7, instant, -70.4)
            self.assertAlmostEqual(skybg.altitude_of(polaris, horizontal), 43.7, delta=0.8)

    def test_facing_south_puts_the_horizon_at_the_bottom(self):
        # Straight down the middle of the bottom edge lies the horizon.
        _, inverse, f, horizontal = skybg.camera(2880, 1800, 43.7, self.instant, -70.4)
        c = skybg.unproject(1440, 1800, f, 1440, 900)
        q = tuple(sum(row[k] * c[k] for k in range(3)) for row in inverse)
        self.assertAlmostEqual(skybg.altitude_of(q, horizontal), 0.0, places=6)

    def test_stars_rise_on_the_left_and_set_on_the_right(self):
        # Altair, seen from Maine on a September evening, is high and a
        # little west of south; two hours on it has moved right.
        altair = equatorial(297.7, 8.87)
        first = screen_position(altair, 2880, 1800, self.instant, 43.7, -70.4)
        later = screen_position(altair, 2880, 1800, self.instant + datetime.timedelta(hours=2),
                                43.7, -70.4)
        self.assertIsNotNone(first)
        self.assertGreater(later[0], first[0])

    def test_southern_hemisphere_faces_north(self):
        # From Sydney the same evening, Altair is in the north: on screen
        # when facing north, and east is now on the right, so it sets leftward.
        altair = equatorial(297.7, 8.87)
        instant = datetime.datetime(2026, 9, 6, 10, 0, tzinfo=datetime.timezone.utc)
        first = screen_position(altair, 2880, 1800, instant, -33.9, 151.2)
        later = screen_position(altair, 2880, 1800, instant + datetime.timedelta(hours=1),
                                -33.9, 151.2)
        self.assertIsNotNone(first)
        self.assertLess(later[0], first[0])


class MilkyWayLayerTests(unittest.TestCase):
    colors = {"bright_foreground": (0.8, 0.8, 0.8)}

    def test_waits_for_astronomical_dark(self):
        instant = datetime.datetime(2026, 9, 6, 2, 25, tzinfo=datetime.timezone.utc)
        self.assertIsNone(skybg.milky_way_ppm(120, 75, -9, 0, self.colors, instant, 43.7, -70.4))
        self.assertIsNone(skybg.milky_way_ppm(120, 75, -30, 0.7, self.colors, instant, 43.7, -70.4))
        layer = skybg.milky_way_ppm(120, 75, -30, 0, self.colors, instant, 43.7, -70.4)
        self.assertTrue(layer.startswith(b"P6\n20 12\n255\n"))
        self.assertEqual(len(layer), len(b"P6\n20 12\n255\n") + 20 * 12 * 3)
        self.assertGreater(max(layer[len(b"P6\n20 12\n255\n"):]), 30)


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


class BackgroundTests(unittest.TestCase):
    def _generate(self, directory, current):
        def render(out_path, *args):
            open(out_path, "w").close()
            return 0.0, 0.0
        with mock.patch.object(skybg, "STATE_DIR", directory), \
                mock.patch.object(skybg, "get_location", return_value=(43.677, -70.371)), \
                mock.patch.object(skybg, "get_weather", return_value=(0.0, False)), \
                mock.patch.object(skybg, "screen_size", return_value=(10, 10)), \
                mock.patch.object(skybg, "theme_colors", return_value={}), \
                mock.patch.object(skybg, "current_background", return_value=current), \
                mock.patch.object(skybg, "render_sky", side_effect=render), \
                mock.patch.object(skybg, "set_background") as set_background:
            skybg.generate_and_set()
        return set_background.call_args.args[0]

    def test_every_render_gets_a_new_name(self):
        # macOS reuses its decoded image for a path another Space still shows,
        # so no render may reuse the name of an earlier one.
        with tempfile.TemporaryDirectory() as directory:
            directory = os.path.realpath(directory)
            first = self._generate(directory, "")
            second = self._generate(directory, first)
            third = self._generate(directory, second)
            self.assertEqual(len({first, second, third}), 3)

    def test_old_renders_are_pruned(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = os.path.realpath(directory)
            for name in ("sky-a.png", "sky-b.png", "stars.mvg"):
                open(os.path.join(directory, name), "w").close()
            current = os.path.join(directory, "sky-b.png")
            new = self._generate(directory, current)
            self.assertEqual(sorted(os.listdir(directory)),
                             sorted([os.path.basename(new), "sky-b.png", "stars.mvg", "render.lock"]))


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
