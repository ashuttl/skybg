#!/usr/bin/env python3
"""Write SkyKitTests/parity.json: what bin/skybg computes for a spread of
inputs, for the Swift port to be checked against.

Run it again whenever a style changes in bin/skybg; a failing Swift test then
points at what the port has yet to follow. Needs ImageMagick, as bin/skybg does.

    python3 macos/Tests/fixtures.py && (cd macos && swift test)
"""

import datetime
import importlib.machinery
import importlib.util
import json
import os
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
scratch = tempfile.mkdtemp()
os.environ["XDG_STATE_HOME"] = scratch
os.environ["XDG_CONFIG_HOME"] = scratch
os.environ["SKYBG_DATA"] = str(ROOT / "data")

loader = importlib.machinery.SourceFileLoader("skybg", str(ROOT / "bin" / "skybg"))
spec = importlib.util.spec_from_loader(loader.name, loader)
skybg = importlib.util.module_from_spec(spec)
loader.exec_module(skybg)
os.makedirs(skybg.STATE_DIR, exist_ok=True)

cases = []


def flat(value):
    if value is None:
        return []
    if isinstance(value, bool):
        return [1.0 if value else 0.0]
    if isinstance(value, (int, float)):
        return [float(value)]
    return [number for item in value for number in flat(item)]


def add(fn, out, **args):
    cases.append({"fn": fn, "args": args, "out": flat(out)})


def utc(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc)


def local(t, offset):
    return utc(t).astimezone(datetime.timezone(datetime.timedelta(seconds=offset)))


def palette(dark):
    skybg.theme_source = lambda: ("builtin", "dark" if dark else "light")
    return skybg.theme_colors()


PLACES = [(43.68, -70.37, -18000), (-33.87, 151.21, 39600), (1.35, 103.82, 28800), (69.65, 18.96, 3600)]
# Midwinter noon, a spring dusk, midsummer dawn, an autumn night, by the clock in Maine.
TIMES = [1766336400, 1774302300, 1782031800, 1791352800, 1795123000]
ELEVATIONS = [-30, -18, -13.5, -9, -6, -4.2, -3, -1, 0, 0.5, 2, 5, 7, 8, 12, 18, 25, 40, 61, 90]
PALETTE_KEYS = ["background", "foreground", "bright_foreground", "blue", "cyan", "magenta", "red", "yellow",
                "orange", "green", "bright_blue", "dark_background", "darker_background", "lighter_background"]

for lat, lon, offset in PLACES:
    for t in TIMES:
        add("solar", skybg.solar_position(lat, lon, utc(t)), lat=lat, lon=lon, t=t)
        add("moon", skybg.moon_position(lat, lon, utc(t)), lat=lat, lon=lon, t=t)
        add("sidereal", skybg.local_sidereal_angle(utc(t), lon), lon=lon, t=t)
        add("sunTimes", skybg.sun_times(lat, lon, local(t, offset)), lat=lat, lon=lon, t=t, offset=offset)
        centre = skybg.cyanotype_centre(lat, lon, local(t, offset))
        add("cyanotypeCentre", centre, lat=lat, lon=lon, t=t, offset=offset)
        add("sunWave", skybg.sun_wave(lat, lon, local(t, offset), centre)[::12],
            lat=lat, lon=lon, t=t, offset=offset, centre=centre)
        for month, day in skybg.CYANOTYPE_REFERENCE_DAYS[:1]:
            add("referenceWave", skybg.sun_wave(lat, lon, local(t, offset).replace(month=month, day=day), centre)[::24],
                lat=lat, lon=lon, t=t, offset=offset, centre=centre, month=month, day=day)

for rgb in [(0, 0, 0), (1, 1, 1), (0.2, 0.5, 0.9), (0.9, 0.3, 0.1), (0.02, 0.03, 0.01)]:
    lab = skybg.srgb_to_oklab(rgb)
    add("oklab", lab, rgb=rgb)
    add("srgb", skybg.oklab_to_srgb(lab), lab=lab)

for dark in (False, True):
    c = palette(dark)
    add("palette", [c[key] for key in PALETTE_KEYS], dark=dark, keys=PALETTE_KEYS)
    add("isLight", skybg.is_light(c), dark=dark)
    for elev in ELEVATIONS:
        add("skyStops", skybg.sky_stops(elev, c), dark=dark, elev=elev)
        column = skybg.sky_column(c, elev, 40)
        add("slitscanColumn", [column[row] for row in (0, 9, 20, 31, 39)], dark=dark, elev=elev,
            rows=[0, 9, 20, 31, 39])
    for elev, az, cloud, fog in [(-20, 10, 0, False), (-5, 250, 0.2, False), (1, 118, 0, False),
                                 (1, 242, 0.5, False), (12, 150, 0.9, False), (35, 200, 0.3, True),
                                 (62, 181, 0, False)]:
        field = skybg.sky_field(c, elev, az, cloud, fog)
        cells = [(0, 0), (63, 0), (0, 39), (63, 39), (20, 30), (40, 35), (31, 12), (50, 38)]
        add("skyField", [field[gy][gx] for gx, gy in cells], dark=dark, elev=elev, az=az, cloud=cloud,
            fog=fog, cells=cells)
    for paper, night in (skybg.BOKASHI_SHEETS, skybg.CYANOTYPE_SHEETS, skybg.GRADIENT_SHEETS, skybg.WINDOW_SHEETS):
        tint = skybg.theme_tint(c, paper, night)
        for hexcolor in ("e8809a", "2c66ae", "ece6d6", "1a2238", "808080", "f5823f", "0d1b3a", "9cc2d4"):
            lab = skybg.srgb_to_oklab(skybg.hexrgb(hexcolor))
            add("tint", tint(lab), dark=dark, paper=paper, night=night, lab=lab)
    line, washes = skybg.cyanotype_inks(c)
    add("cyanotypeInks", [line, washes], dark=dark)
    for elev in (-30, -12, -3, 0, 6, 40):
        for alt in (-60, -18, -5, 0, 10, 40, 80):
            add("cyanotypeGround", skybg.cyanotype_ground(elev, alt, *washes, line), dark=dark, elev=elev, alt=alt)

for hour in (0, 2.5, 5.1, 6.5, 7.9, 12, 16.4, 18.5, 20.2, 23.7):
    for sunrise, sunset in ((6.5, 18.5), (4.1, 20.4), (7.2, 16.1), (9.5, 14.0)):
        stops = skybg.daylight_stops(hour, sunrise, sunset)
        add("daylightStops", stops, hour=hour, sunrise=sunrise, sunset=sunset)
        ys = [0.001, 0.2, 0.45, 0.7, 0.88, 0.999]
        add("daylightColor", [skybg.daylight_color(stops, y) for y in ys], hour=hour, sunrise=sunrise,
            sunset=sunset, ys=ys)

for elev in ELEVATIONS:
    for morning in (False, True):
        for paper in (False, True):
            inks, top, horizon = skybg.bokashi_inks(elev, morning, "paper" if paper else "indigo")
            ys = [0.0, 0.1, 0.3, 0.55, 0.7, 0.85, 0.95, 1.0]
            add("bokashi", [inks, top, horizon, [skybg.bokashi_color(inks, top, horizon, y) for y in ys]],
                elev=elev, morning=morning, paper=paper, ys=ys)
        ramp = skybg.gradient_ramp(elev, morning)
        ts = [0, 0.13, 0.25, 0.4, 0.5, 0.77, 1]
        add("gradientRamp", [ramp, [skybg.cubic_ramp(ramp, t) for t in ts]], elev=elev, morning=morning, ts=ts)

for elev, az, lat in [(-25, 5, 43.68), (-3, 240, 43.68), (2, 118, 43.68), (30, 180, 43.68), (55, 200, -33.87),
                      (10, 90, 1.35)]:
    add("gradientLight", skybg.gradient_light(elev, az, lat), elev=elev, az=az, lat=lat)
    for aspect in (1.6, 0.75, 2.4):
        field = skybg.gradient_field(elev, az, lat, aspect)
        cells = [(0, 0), (63, 0), (0, len(field) - 1), (63, len(field) - 1), (20, len(field) // 2), (45, 3)]
        add("gradientField", [len(field), [field[gy][gx] for gx, gy in cells]], elev=elev, az=az, lat=lat,
            aspect=aspect, cells=cells)

add("moonOutline", skybg.moon_outline(100, 60, 20, 0.3, 0.8)[::8], cx=100, cy=60, radius=20, fraction=0.3,
    toward=0.8)
for x, y in [(0.0, 1.0), (0.5, 0.56), (0.25, 0.3)]:
    for az, alt in [(180, 0), (95, 12), (270, -20), (359, 45)]:
        add("bokashiScreen", [skybg.bokashi_screen(az, alt, 43.68), skybg.bokashi_screen(az, alt, -33.87)],
            az=az, alt=alt)
        add("cyanotypeScreen", [skybg.cyanotype_screen(az, alt, 180), skybg.cyanotype_screen(az, alt, 0)],
            az=az, alt=alt)

# The room.
for u in (-1.1, -0.6, -0.2, 0.0, 0.3, 0.75, 1.2):
    for v in (-0.49, -0.3, -0.1, 0.0, 0.12, 0.3, 0.49):
        add("roomView", skybg.window_view(u, v), u=u, v=v)
for az in (60, 100, 150, 180, 215, 290, 350):
    for lat in (43.68, -33.87):
        add("roomBearing", skybg.window_bearing(az, lat), az=az, lat=lat)
for alt, bearing in [(0.3, 0), (5, -40), (20, 30), (45, 64), (70, -10)]:
    light = skybg.window_light(alt, bearing)
    add("roomLight", light, alt=alt, bearing=bearing)
    add("roomLamps", skybg.window_lamps(light), alt=alt, bearing=bearing)
    for x, z in [(-0.4, 0.2), (0.0, 0.5), (0.44, 0.88)]:
        add("roomLanding", skybg.window_landing(x, z, light), alt=alt, bearing=bearing, x=x, z=z)
add("roomLamps", skybg.window_lamps(), alt=None, bearing=None)
for cloud in (0, 0.4, 1):
    sources = skybg.window_sources(cloud)
    add("roomSources", sources, cloud=cloud)
    for x, z, ray in [(0.0, 0.5, 1.0), (0.15, 0.39, 2.2), (-0.44, 0.15, 0.3), (0.3, 0.64, 4.0), (0.6, 0.5, 1.0)]:
        for grain in ((0.0, 0.0), (0.02, 0.05)):
            add("roomCover", skybg.window_cover(x, z, ray, sources, grain), cloud=cloud, x=x, z=z, ray=ray,
                grain=grain)
for elev, moon_alt, fraction, cloud in [(-20, 30, 0.9, 0), (-8, 5, 0.5, 0.3), (0, -10, 0.2, 0), (1.5, 20, 1, 0.6),
                                        (30, 50, 0.4, 1)]:
    add("roomStrengths", skybg.window_strengths(elev, moon_alt, fraction, cloud), elev=elev, moonAlt=moon_alt,
        fraction=fraction, cloud=cloud)


def ppm(path, depth):
    """(width, height, values 0..1) of a binary PPM."""
    with open(path, "rb") as f:
        raw = f.read()
    fields, at = [], 0
    while len(fields) < 4:
        end = at
        while raw[end:end + 1] not in (b" ", b"\n"):
            end += 1
        fields.append(raw[at:end])
        at = end + 1
    width, height, top = int(fields[1]), int(fields[2]), int(fields[3])
    body = raw[at:]
    step = 2 if top > 255 else 1
    values = [int.from_bytes(body[i:i + step], "big") / top for i in range(0, len(body), step)]
    return width, height, values


# The whole room, as bin/skybg leaves it before enlarging it.
for dark in (False, True):
    c = palette(dark)
    for t, cloud, fog in [(TIMES[0], 0.0, False), (TIMES[1], 0.3, False), (TIMES[2], 0.0, False),
                          (TIMES[3], 0.0, False), (TIMES[4], 0.7, True)]:
        lat, lon, _ = PLACES[0]
        skybg.render_window(os.path.join(scratch, "room.png"), 480, 300, utc(t), lat, lon, cloud, fog, c)
        gw, gh, values = ppm(os.path.join(skybg.STATE_DIR, "window.ppm"), 16)
        cells = [(gx, gy) for gy in range(2, gh, 9) for gx in range(3, gw, 13)]
        add("roomPicture", [[values[(gy * gw + gx) * 3 + k] for k in range(3)] for gx, gy in cells],
            dark=dark, t=t, lat=lat, lon=lon, cloud=cloud, fog=fog, width=480, height=300, cells=cells,
            grid=[gw, gh])

# The stars and the Milky Way through the camera.
stars = skybg.load_stars()
for (lat, lon, _), t in [(PLACES[0], TIMES[3]), (PLACES[1], TIMES[0]), (PLACES[3], TIMES[4])]:
    for width, height in ((2560, 1600), (1200, 1900)):
        cam, _, f, horizontal = skybg.camera(width, height, lat, utc(t), lon)
        for index in range(0, 400, 37):
            q = stars[index][:3]
            at = skybg.project(tuple(row[0] * q[0] + row[1] * q[1] + row[2] * q[2] for row in cam), f,
                               width / 2, height / 2)
            add("starProject", [at, skybg.altitude_of(q, horizontal), stars[index][3], stars[index][4]],
                lat=lat, lon=lon, t=t, width=width, height=height, index=index)
        c = palette(True)
        layer = skybg.milky_way_ppm(width, height, -30, 0.1, c, utc(t), lat, lon)
        with open(os.path.join(scratch, "milk.ppm"), "wb") as f_:
            f_.write(layer)
        gw, gh, values = ppm(os.path.join(scratch, "milk.ppm"), 8)
        cells = [(gx, gy) for gy in range(1, gh, 23) for gx in range(2, gw, 31)]
        add("milkyWay", [[values[(gy * gw + gx) * 3 + k] for k in range(3)] for gx, gy in cells],
            lat=lat, lon=lon, t=t, width=width, height=height, cells=cells, grid=[gw, gh])

for elev, cloud in [(-20, 0), (-6, 0.2), (-13, 0.4), (-3, 0), (-30, 0.7)]:
    add("visibility", [skybg.star_visibility(elev, cloud), skybg.milky_way_visibility(elev, cloud)],
        elev=elev, cloud=cloud)

out = Path(__file__).parent / "SkyKitTests" / "parity.json"
out.write_text(json.dumps(cases, separators=(",", ":")) + "\n")
print(f"wrote {out}: {len(cases)} cases")
