# Sky data

`stars.bin` is the Yale Bright Star Catalogue, 5th revised edition (Hoffleit & Warren, 1991), through visual magnitude 6.5: 8,404 stars, brightest first, one six-byte record each — right ascension and declination (J2000) in hundredths of a degree as little-endian uint16 and int16, the visual magnitude in tenths as int8, and the B−V colour index in fiftieths as int8. Source: http://tdc-www.harvard.edu/catalogs/bsc5.dat.gz.

`milkyway.bin.gz` is the Milky Way's brightness, 0–255, as a gzip-compressed 1080×540 byte raster in celestial coordinates: right ascension 0h in the middle column increasing to the left (as the sky is seen from inside), declination +90° at the top. It is the diffuse layer of NASA's Deep Star Maps 2020 (Scientific Visualization Studio, https://svs.gsfc.nasa.gov/4851, public domain), the unresolved starlight of the Galaxy drawn from Gaia with the dust lanes in it, downsampled with the sky's own floor taken off and a gamma that keeps the dust lanes legible beside the bulge.

Both files are the ones [linecast](https://github.com/ashuttl/linecast) bakes for its sky view, and `scripts/build-sky-data.py` rebuilds them here from the same sources. They are read offline; skybg never fetches them at run time.
