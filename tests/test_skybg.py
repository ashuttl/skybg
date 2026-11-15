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
            self.assertEqual(skybg.load_config(),
                             {"location": [10, 20], "weather": False, "style": "sky"})

    def test_style_is_saved_and_validated(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(skybg, "CONFIG_DIR", directory), \
                mock.patch.object(skybg, "CONFIG_FILE", os.path.join(directory, "config.json")):
            with mock.patch("sys.stdout", io.StringIO()):
                skybg.run(skybg.parser().parse_args(["config", "style", "daylight"]))
            self.assertEqual(skybg.current_style(), "daylight")
            skybg.save_config({"style": "sunny"})
            with self.assertRaisesRegex(skybg.SkybgError, "unknown style"):
                skybg.load_config()


class DaylightTests(unittest.TestCase):
    def test_palette_hours_land_on_sunrise_and_sunset(self):
        # Wherever the real sunrise and sunset fall, they show the palette's.
        for sunrise, sunset in ((6.5, 18.5), (7.2, 16.1), (4.9, 20.4)):
            self.assertAlmostEqual(skybg.daylight_palette_hour(sunrise, sunrise, sunset), 6.5)
            self.assertAlmostEqual(skybg.daylight_palette_hour(sunset, sunrise, sunset), 18.5)

    def test_anchor_hours_reproduce_the_palette(self):
        # At sunrise, whenever it is, the bands are the palette's sunrise anchor.
        stops = skybg.daylight_stops(7.2, sunrise=7.2, sunset=16.1)
        self.assertEqual([round(position, 6) for position, _ in stops][::5], [0, 1])
        for (_, color), expected in zip(stops, ["2e3b52", "4c596d", "76757f",
                                                "a6868f", "bf948a", "87717a"]):
            for got, want in zip(color, skybg.srgb_to_oklab(skybg.hexrgb(expected))):
                self.assertAlmostEqual(got, want)

    def test_the_day_is_continuous_through_midnight(self):
        before, after = skybg.daylight_stops(23.999), skybg.daylight_stops(0.001)
        for (p0, c0), (p1, c1) in zip(before, after):
            self.assertAlmostEqual(p0, p1, places=3)
            for v0, v1 in zip(c0, c1):
                self.assertAlmostEqual(v0, v1, places=3)

    def test_colors_stay_in_gamut_and_brighten_by_day(self):
        def luminance(hour):
            color = skybg.daylight_color(skybg.daylight_stops(hour), 0.5)
            self.assertTrue(all(0 <= v <= 1 for v in color))
            return sum(color)
        for hour in range(24):
            luminance(hour)
        self.assertGreater(luminance(12), luminance(6.5))
        self.assertGreater(luminance(6.5), luminance(0))

    def test_oklab_round_trips(self):
        for color in ((0.1, 0.5, 0.9), (0.74, 0.58, 0.54), (0.03, 0.04, 0.09)):
            for got, want in zip(skybg.oklab_to_srgb(skybg.srgb_to_oklab(color)), color):
                self.assertAlmostEqual(got, want, places=5)

    def test_sun_times_follow_the_season(self):
        eastern = datetime.timezone(datetime.timedelta(hours=-5))
        rise, fall = skybg.sun_times(43.677, -70.371,
                                     datetime.datetime(2026, 12, 21, 12, tzinfo=eastern))
        self.assertAlmostEqual(rise, 7.2, delta=0.2)
        self.assertAlmostEqual(fall, 16.1, delta=0.2)
        # Midnight sun: fall back to the palette's own day.
        utc = datetime.timezone.utc
        self.assertEqual(skybg.sun_times(78.2, 15.6, datetime.datetime(2026, 6, 21, 12, tzinfo=utc)),
                         (6.5, 18.5))

    def test_bokashi_bands_meet_the_ground(self):
        for stock in ("paper", "indigo"):
            for morning in (True, False):
                for elev in (-30, -9, -3, 0.5, 7, 22, 70):
                    inks, top_reach, horizon_reach = skybg.bokashi_inks(elev, morning, stock)
                    self.assertLess(top_reach + horizon_reach, 1)
                    self.assertEqual(skybg.bokashi_color(inks, top_reach, horizon_reach, 0), inks[0])
                    self.assertEqual(skybg.bokashi_color(inks, top_reach, horizon_reach, 1), inks[3])
                    middle = (top_reach + 1 - horizon_reach) / 2
                    self.assertEqual(
                        skybg.bokashi_color(inks, top_reach, horizon_reach, middle), inks[1])

    def test_bokashi_day_stock_follows_the_theme(self):
        lightness = lambda stock: skybg.bokashi_inks(40, False, stock)[0][1][0]
        self.assertGreater(lightness("paper"), 0.9)
        self.assertLess(lightness("indigo"), 0.65)
        # The twilights are the same on either stock.
        self.assertEqual(skybg.bokashi_inks(-5, True, "paper"), skybg.bokashi_inks(-5, True, "indigo"))

    def test_bokashi_sheet_faces_the_sun(self):
        # East is on the left facing south, on the right facing north.
        self.assertLess(skybg.bokashi_screen(90, 10, 43.7)[0], 0.5)
        self.assertGreater(skybg.bokashi_screen(90, 10, -33.9)[0], 0.5)
        self.assertAlmostEqual(skybg.bokashi_screen(180, 0, 43.7)[1], 1.0)
        self.assertAlmostEqual(skybg.bokashi_screen(0, 0, -33.9)[0], 0.5)

    def test_moon_phases(self):
        utc = datetime.timezone.utc
        new = skybg.moon_position(0, 0, datetime.datetime(2000, 1, 6, 18, 14, tzinfo=utc))
        full = skybg.moon_position(0, 0, datetime.datetime(2026, 11, 24, 14, 53, tzinfo=utc))
        self.assertLess(new[2], 0.01)
        self.assertGreater(full[2], 0.99)
        waxing = skybg.moon_position(0, 0, datetime.datetime(2026, 11, 14, 12, tzinfo=utc))
        self.assertTrue(waxing[3])
        self.assertAlmostEqual(waxing[2], 0.25, delta=0.06)

    def test_full_moon_stands_opposite_the_sun(self):
        instant = datetime.datetime(2026, 11, 25, 5, tzinfo=datetime.timezone.utc)  # Maine midnight
        alt, az, _, _ = skybg.moon_position(43.677, -70.371, instant)
        sun_alt, _ = skybg.solar_position(43.677, -70.371, instant)
        self.assertGreater(alt, 55)
        self.assertLess(sun_alt, -55)
        self.assertAlmostEqual(az, 180, delta=25)

    def test_moon_outline_grows_with_the_phase(self):
        def area(points):
            return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1)
                           in zip(points, points[1:] + points[:1]))) / 2
        disc = math.pi * 100
        self.assertAlmostEqual(area(skybg.moon_outline(0, 0, 10, 0.0, 1.0)), 0, delta=0.5)
        self.assertAlmostEqual(area(skybg.moon_outline(0, 0, 10, 0.5, 1.0)), disc / 2, delta=1)
        self.assertAlmostEqual(area(skybg.moon_outline(0, 0, 10, 1.0, 1.0)), disc, delta=1)
        # The lit limb is on the side the sun is on.
        lit = skybg.moon_outline(0, 0, 10, 0.2, math.pi)
        self.assertLess(sum(x for x, _ in lit) / len(lit), 0)

    def test_cyanotype_sheet_holds_the_whole_compass(self):
        self.assertEqual(skybg.cyanotype_screen(180, 0), (0.5, skybg.CYANOTYPE_HORIZON))
        self.assertAlmostEqual(skybg.cyanotype_screen(90, 0)[0], 0.25)
        self.assertAlmostEqual(skybg.cyanotype_screen(90, 0, centre=0)[0], 0.75)
        # Up is up, and the lowest the sun can be is still on the sheet.
        self.assertLess(skybg.cyanotype_screen(180, 45)[1], skybg.CYANOTYPE_HORIZON)
        self.assertLess(skybg.cyanotype_screen(0, -90)[1], 1.1)

    def test_cyanotype_faces_the_noon_sun(self):
        eastern = datetime.timezone(datetime.timedelta(hours=-5))
        sydney = datetime.timezone(datetime.timedelta(hours=11))
        singapore = datetime.timezone(datetime.timedelta(hours=8))
        day = lambda month, zone: datetime.datetime(2026, month, 21, 12, tzinfo=zone)
        self.assertEqual(skybg.cyanotype_centre(43.677, -70.371, day(12, eastern)), 180)
        self.assertEqual(skybg.cyanotype_centre(-33.87, 151.2, day(12, sydney)), 0)
        # In the tropics the noon sun changes sides with the season.
        self.assertEqual(skybg.cyanotype_centre(1.35, 103.8, day(6, singapore)), 0)
        self.assertEqual(skybg.cyanotype_centre(1.35, 103.8, day(12, singapore)), 180)

    def test_sun_wave_crosses_the_horizon_twice_and_is_higher_in_summer(self):
        eastern = datetime.timezone(datetime.timedelta(hours=-5))
        def wave(month):
            return skybg.sun_wave(43.677, -70.371, datetime.datetime(2026, month, 21, 12, tzinfo=eastern))
        winter, summer = wave(12), wave(6)
        above = [y < skybg.CYANOTYPE_HORIZON for _, _, y in winter]
        self.assertEqual(sum(a != b for a, b in zip(above, above[1:])), 2)
        self.assertLess(min(y for _, _, y in summer), min(y for _, _, y in winter))
        self.assertEqual(winter[0][0], 0)
        self.assertEqual(winter[-1][0], 24 * 60)

    def test_wave_runs_split_at_the_sheet_edge(self):
        wave = [(0, 0.90, 0.5), (10, 0.98, 0.5), (20, 0.02, 0.5), (30, 0.10, 0.5)]
        self.assertEqual([len(run) for run in skybg.wave_runs(wave)], [2, 2])
        self.assertEqual(skybg.wave_runs(wave[:1]), [])

    def test_cyanotype_ground_deepens_at_night(self):
        washes = [skybg.srgb_to_oklab(skybg.hexrgb(c)) for c in skybg.CYANOTYPE["blue"]]
        line, rest = washes[0], washes[1:]
        day = skybg.cyanotype_ground(30, 60, *rest, line)
        night = skybg.cyanotype_ground(-30, 60, *rest, line)
        self.assertGreater(day[0], night[0])
        # Twilight seeps under the horizon: lighter just below it than far below.
        self.assertGreater(skybg.cyanotype_ground(30, -2, *rest, line)[0],
                           skybg.cyanotype_ground(30, -40, *rest, line)[0])

    def theme(self, background, **hues):
        colors = {"background": background, "foreground": "#808080", "red": "#d9532f",
                  "orange": "#e08a52", "yellow": "#f0bd62", "blue": "#2c66ae",
                  "cyan": "#86c8e8", "magenta": "#a96bb4", **hues}
        return {name: skybg.hexrgb(value) for name, value in colors.items()}

    def test_theme_inks_put_the_sheet_on_the_background(self):
        paper, night = "ece6d6", "1a2238"
        for background, sheet in (("#cdd4bb", paper), ("#191724", night)):
            colors = self.theme(background)
            tinted = skybg.theme_tint(colors, paper, night)(skybg.srgb_to_oklab(skybg.hexrgb(sheet)))
            for got, want in zip(tinted, skybg.srgb_to_oklab(colors["background"])):
                self.assertAlmostEqual(got, want, places=3)

    def test_theme_inks_keep_lightness_and_take_the_theme_hue(self):
        ink = skybg.srgb_to_oklab(skybg.hexrgb("2c66ae"))
        teal = self.theme("#191724", blue="#3aa0a0")
        tinted = skybg.theme_tint(teal, "ece6d6", "1a2238")(ink)
        self.assertAlmostEqual(tinted[0], ink[0], delta=0.03)
        self.assertAlmostEqual(skybg.oklab_hue(tinted),
                               skybg.oklab_hue(skybg.srgb_to_oklab(teal["blue"])), delta=6)
        # A grey theme drains the ink rather than turning it.
        grey = self.theme("#191919", **{name: "#888888" for name in
                                        ("red", "orange", "yellow", "blue", "cyan", "magenta")})
        drained = skybg.theme_tint(grey, "ece6d6", "1a2238")(ink)
        self.assertLess(math.hypot(drained[1], drained[2]), 0.02)

    def test_theme_inks_can_be_left_as_printed(self):
        ink = skybg.srgb_to_oklab(skybg.hexrgb("d08a8a"))
        with mock.patch.object(skybg, "THEME_INKS", 0.0):
            tinted = skybg.theme_tint(self.theme("#191724", red="#00ff00"), "ece6d6", "1a2238")(ink)
        for got, want in zip(tinted, ink):
            self.assertAlmostEqual(got, want)

    def test_cyanotype_line_follows_the_theme(self):
        dark = self.theme("#191724", foreground="#e0def4")
        line, washes = skybg.cyanotype_inks(dark)
        for got, want in zip(line, skybg.srgb_to_oklab(dark["foreground"])):
            self.assertAlmostEqual(got, want)
        self.assertEqual(len(washes), 4)
        # On paper the line is ink: darker than the sheet it is drawn on.
        line, washes = skybg.cyanotype_inks(self.theme("#cdd4bb"))
        self.assertLess(line[0], washes[0][0] - 0.3)

    def test_daylight_never_asks_for_weather(self):
        with mock.patch.object(skybg, "load_config",
                               return_value={"location": "auto", "weather": True,
                                             "style": "daylight"}), \
                mock.patch.object(skybg.urllib.request, "urlopen") as urlopen:
            self.assertEqual(skybg.get_weather(43.677, -70.371), (0.0, False))
        urlopen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
