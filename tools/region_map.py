#!/usr/bin/env python3
"""Reads the region code of every sector from the game's World/sectors.keyx.

    python tools/region_map.py "<game folder>" [out.json]

The 0x300-byte records of sectors.keyx (header 0x100 bytes, u32 count at +4) hold the sector's environment block; its
byte at record offset 0x2C0 is the region code (the byte the game reads at +0xD7 of the sector's environment, which
gear.data.regions:of_sector(sector) returns as its second result). The sector's place in the 128 x 128 grid comes from
RawX / RawY at +0x3C / +0x40: tile = trunc((raw + 25) / 53.66563034057617), grid cell = tile // 64 (the game's own
conversion, 0x638321). Output: {"cells": [[gx, gy, code, id], ...]} for every sector (code 0: no region).
Which region record a code belongs to (kills needed, name) is the game's table: of_sector gives both at run time.
"""
import json, os, struct, sys

HEADER, RECORD = 0x100, 0x300
OFF_ID, OFF_X, OFF_Y, OFF_CODE = 0x24, 0x3C, 0x40, 0x2C0
UNITS_PER_TILE, BIAS = 53.66563034057617, 25


def read_cells(path):
    data = open(path, 'rb').read()
    if data[:3] != b'WLK':
        raise SystemExit('not a sectors.keyx: ' + path)
    count = struct.unpack_from('<I', data, 4)[0]
    cells = []
    for i in range(count):
        base = HEADER + i * RECORD
        sid = struct.unpack_from('<I', data, base + OFF_ID)[0]
        rx, ry = struct.unpack_from('<ii', data, base + OFF_X)
        tx, ty = int((rx + BIAS) / UNITS_PER_TILE), int((ry + BIAS) / UNITS_PER_TILE)
        cells.append([tx // 64, ty // 64, data[base + OFF_CODE], sid])
    return cells


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cells = read_cells(os.path.join(sys.argv[1], 'World', 'sectors.keyx'))
    out = sys.argv[2] if len(sys.argv) > 2 else 'region_sectors.json'
    with open(out, 'w') as f:
        json.dump({'cells': cells}, f, separators=(',', ':'))
    print(len(cells), 'sectors ->', out)
