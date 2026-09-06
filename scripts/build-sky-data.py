#!/usr/bin/env python3
"""Bake the sky data: the star catalogue and the Milky Way raster.

    python3 scripts/build-sky-data.py [--from DIR]

Downloads the Yale Bright Star Catalogue (bsc5.dat.gz) and NASA's Deep
Star Maps 2020 Milky Way layer (milkyway_2020_4k.exr, 35 MB), or reads
them from DIR, and writes data/stars.bin and data/milkyway.bin.gz. The
formats and sources are described in data/SOURCES.md. Reading the EXR
needs ImageMagick (`magick`). The output is deterministic, so this only
needs rerunning when the sources change.
"""

import gzip
import struct
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"
BSC_URL = "http://tdc-www.harvard.edu/catalogs/bsc5.dat.gz"
MILKY_WAY_URL = ("https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/"
                 "milkyway_2020_4k.exr")
LIMIT = 6.5
MW_W, MW_H = 1080, 540
# The sky's floor and the band's working ceiling, as fractions of the
# layer's full scale: below the floor is the dark sky's own glow and the
# grain of the source, above the ceiling only a few knots in the bulge.
# Between them a gamma under one lifts the faint outer band and keeps
# the dust lanes legible.
MW_FLOOR, MW_CEILING, MW_GAMMA = 0.016, 0.30, 0.6


def fetch(name, src):
    if src is not None:
        return (src / name).read_bytes()
    url = {"bsc5.dat.gz": BSC_URL, "milkyway_2020_4k.exr": MILKY_WAY_URL}[name]
    print(f"fetching {url}")
    return urllib.request.urlopen(url).read()


def parse_star(line):
    """(ra, dec, vmag, bv, hr) from a catalogue line, or None without a
    position. Fixed columns (1-based) per the catalogue's ReadMe: HR 1-4,
    RAh 76-77, RAm 78-79, RAs 80-83, DE- 84, DEd 85-86, DEm 87-88, DEs
    89-90, Vmag 103-107, B-V 110-114."""
    try:
        hr = int(line[0:4])
        ra = (int(line[75:77]) + int(line[77:79]) / 60.0
              + float(line[79:83]) / 3600.0) * 15.0
        dec = (int(line[84:86]) + int(line[86:88]) / 60.0
               + int(line[88:90]) / 3600.0)
        if line[83] == "-":
            dec = -dec
        vmag = float(line[102:107])
    except ValueError:
        return None
    try:
        bv = float(line[109:114])
    except ValueError:
        bv = 0.0
    return ra, dec, vmag, bv, hr


def bake_stars(src):
    raw = gzip.decompress(fetch("bsc5.dat.gz", src))
    stars = [s for s in map(parse_star, raw.decode("latin-1").splitlines())
             if s is not None and s[2] <= LIMIT]
    stars.sort(key=lambda s: (s[2], s[4]))
    out = DATA / "stars.bin"
    out.write_bytes(b"".join(
        struct.pack("<Hhbb", round(ra * 100) % 36000, round(dec * 100),
                    round(vmag * 10), max(-128, min(127, round(bv * 50))))
        for ra, dec, vmag, bv, _ in stars))
    print(f"wrote {out} ({out.stat().st_size} bytes, {len(stars)} stars to {LIMIT})")


def smooth(grid):
    """One pass of a 3x3 box over the raster, wrapping in right ascension:
    the layer's grain averaged away, the dust lanes kept."""
    out = [0.0] * (MW_W * MW_H)
    for r in range(MW_H):
        rows = (max(0, r - 1), r, min(MW_H - 1, r + 1))
        for x in range(MW_W):
            out[r * MW_W + x] = sum(grid[rr * MW_W + xx % MW_W]
                                    for rr in rows for xx in (x - 1, x, x + 1)) / 9.0
    return out


def bake_milky_way(src):
    exr = fetch("milkyway_2020_4k.exr", src)
    with tempfile.TemporaryDirectory() as tmp:
        exr_path, pgm_path = Path(tmp) / "milkyway.exr", Path(tmp) / "milkyway.pgm"
        exr_path.write_bytes(exr)
        # Grey, area-averaged down to the raster's size, as plain-text
        # floating point so there is nothing to decode but numbers.
        subprocess.run(["magick", str(exr_path), "-colorspace", "Gray",
                        "-define", "quantum:format=floating-point", "-depth", "32",
                        "-resize", f"{MW_W}x{MW_H}!", "-compress", "none",
                        str(pgm_path)], check=True)
        tokens = pgm_path.read_text().split()
    assert tokens[0] == "P2" and (int(tokens[1]), int(tokens[2])) == (MW_W, MW_H)
    scale = float(tokens[3])
    values = smooth([int(t) / scale for t in tokens[4:]])
    out = DATA / "milkyway.bin.gz"
    out.write_bytes(gzip.compress(bytes(
        int(round(255.0 * max(0.0, min(1.0, (v - MW_FLOOR) / (MW_CEILING - MW_FLOOR)))
                  ** MW_GAMMA))
        for v in values), 9))
    print(f"wrote {out} ({out.stat().st_size} bytes, {MW_W}x{MW_H})")


def main():
    src = None
    if len(sys.argv) == 3 and sys.argv[1] == "--from":
        src = Path(sys.argv[2])
    elif len(sys.argv) != 1:
        sys.exit(__doc__)
    DATA.mkdir(exist_ok=True)
    bake_stars(src)
    bake_milky_way(src)


if __name__ == "__main__":
    main()
