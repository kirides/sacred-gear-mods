"""Builds src/minimap/tiles.gpak (a ZIP, files stored: the tiles are JPEGs already) with the map tiles ui/megamap/s<S>/<row>_<col>.jpg (256 px), from the
opaque tiles of SacredEngineRemake's tools/megamap/fill_composite.py (the `--mega` render with the game's own map in the empty parts).
Sacred Gear reads a mod's `*.gpak` as part of the mod's folder (gear/vfs.h): one file to copy and to open instead of 1848.
Tiles are JPEG quality 70, progressive, 4:2:0, always encoded straight from the lossless PNG tiles (never from JPEGs): q70 is about 9% smaller than q78 with no visible difference; 4:4:4 would only add size, the render's colour is detail-poor.
Usage: python tools/make_minimap_tiles.py <dir with s1 s2 s4> [quality]"""
import io, os, sys, zipfile
from PIL import Image
root = sys.argv[1]
q = int(sys.argv[2]) if len(sys.argv) > 2 else 70
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'minimap', 'tiles.gpak')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as z:
    for s in (1, 2, 4):
        for r in range(11 * s):
            for c in range(8 * s):
                b = io.BytesIO()
                Image.open(os.path.join(root, f's{s}', f'{r:03d}_{c:03d}.png')).convert('RGB').save(b, 'JPEG', quality=q, subsampling=2, progressive=True, optimize=True)
                zi = zipfile.ZipInfo(f'ui/megamap/s{s}/{r:03d}_{c:03d}.jpg', (2026, 11, 25, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_STORED
                z.writestr(zi, b.getvalue())
print(os.path.getsize(out) / 1e6, 'MB')
