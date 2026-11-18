#!/usr/bin/env python3
"""Reads the regions of the game and the region code of every sector from the game files.

    python tools/region_map.py "<game folder>" [out.json]

Sectors: the 0x300-byte records of World/sectors.keyx (header 0x100 bytes, u32 count at +4) hold the sector's
environment block; its byte at record offset 0x2C0 is the region code (the byte the game reads at +0xD7 of the
sector's environment, which gear.data.regions:of_sector(sector) returns as its second result). The sector's place in
the sector grid comes from RawX / RawY at +0x3C / +0x40: tile = trunc((raw + 25) / 53.66563034057617), grid cell =
tile // 64 (the game's own conversion, 0x638321).

Regions: the 0x40-byte records of bin/Balance.bin (the game copies them into its region table: +0x00 up to 16 region
codes, +0x10 name key such as UI_REGION_SOUTHKERN, +0x30 kills needed, +0x34 boss flag, +0x38 kills left, +0x3C
region id).

Output: {"regions": [{id, key, codes, kills, boss}, ...],
         "cells": [[gx, gy, code, region id (0: the code is in no region), sector id], ...]}
"""
import json, os, struct, sys

HEADER, RECORD = 0x100, 0x300
OFF_ID, OFF_X, OFF_Y, OFF_CODE = 0x24, 0x3C, 0x40, 0x2C0
UNITS_PER_TILE, BIAS = 53.66563034057617, 25
NUL = bytes([0])


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


def read_regions(path):
    data = open(path, 'rb').read()
    regions = []
    at = data.find(b'UI_REGION_')
    if at < 0x10:
        return regions
    at -= 0x10
    while at + 0x40 <= len(data) and data[at + 0x10:at + 0x1A] == b'UI_REGION_':
        rec = data[at:at + 0x40]
        codes = [b for b in rec[:0x10] if b]
        key = rec[0x10:0x30].split(NUL)[0].decode('ascii', 'replace')
        kills, boss, _left, rid = struct.unpack_from('<IIII', rec, 0x30)
        regions.append({'id': rid, 'key': key, 'codes': codes, 'kills': kills, 'boss': boss})
        at += 0x40
    return regions


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cells = read_cells(os.path.join(sys.argv[1], 'World', 'sectors.keyx'))
    regions = read_regions(os.path.join(sys.argv[1], 'bin', 'Balance.bin'))
    by_code = {}
    for r in regions:               # the game takes the first region whose codes hold the sector's (0x4254A0)
        for c in r['codes']:
            by_code.setdefault(c, r['id'])
    cells = [[gx, gy, code, by_code.get(code, 0), sid] for gx, gy, code, sid in cells]
    out = sys.argv[2] if len(sys.argv) > 2 else 'region_sectors.json'
    with open(out, 'w') as f:
        json.dump({'regions': regions, 'cells': cells}, f, separators=(',', ':'))
    print(len(regions), 'regions,', len(cells), 'sectors ->', out)
