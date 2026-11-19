# Fills a Save folder of a COPY of the game with many savegames, for testing screens that list them (Better SaveLoad
# with more than 100 of them). Every file is a copy of one real savegame with its header patched: the name, the hero
# (name, class, level), the local time it was saved and the file's write time, so that searching, filtering and the
# orders have something to tell apart. The copies load like the original (only those fields differ).
#
#   python tools/make_test_saves.py <Save folder> [count] [first_slot] [fill_to]
#   python tools/make_test_saves.py "B:\DevDrive\sacred-savelimit\Save" 300 100 509
#
# Extra numbers far beyond 509 are made too (1000, 12345, 32766) to check that nothing stops there. `fill_to`: every
# other free number from 1 up to it gets a hard link to one of the originals (no disk space), so that the first free
# number the game picks is beyond 509.
# Never run it on the game folder you play with.
import os, struct, sys, random, shutil, glob

HEROES = ['Aldric', 'Brienne', 'Cael', 'Dorn', 'Elowen', 'Fenris', 'Gwyn', 'Halric', 'Ilsa', 'Jorund', 'Kestrel', 'Mira']
WORDS = ['Cave', 'Bridge', 'Before the boss', 'Town', 'Quest done', 'Goblins', 'Camp', 'Swamp', 'Tower', 'Crypt']


def chunk_table(data):
    count = struct.unpack_from('<I', data, 4)[0]
    out = {}
    for i in range(count):
        t, off, size = struct.unpack_from('<III', data, 0x100 + 12 * i)
        out.setdefault(t, (off, size))
    return out


def patch(src, slot, rnd):
    data = bytearray(src)
    ch = chunk_table(data)
    hero = HEROES[slot % len(HEROES)]
    name = '%s %s %d' % (WORDS[(slot * 7) % len(WORDS)], hero, slot)
    off, size = ch[0x83]
    raw = name.encode('cp1252')[:size - 1]
    data[off:off + size] = raw + b'\0' * (size - len(raw))
    off, size = ch[0xC3]
    level = 1 + (slot * 13) % 80
    cls = 1 + slot % 8
    struct.pack_into('<ii', data, off, level, cls)
    wide = hero.encode('utf-16-le')
    data[off + 8:off + 8 + 128] = wide + b'\0' * (128 - len(wide))
    # The local time the game wrote into the header (+0x5C): int32 year, month, day, day of week, hour, minute, second, ms.
    days = rnd.randint(0, 400)
    year, month, day = 2025 + (days // 365), 1 + (days % 365) // 31, 1 + (days % 365) % 28
    struct.pack_into('<8i', data, 0x5C, year, min(month, 12), day, 0, rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59), 0)
    return bytes(data), (year, min(month, 12), day)


def main():
    folder = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    first = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    sources = sorted(glob.glob(os.path.join(folder, 'GAME0[1-6].PAK')))
    if not sources:
        sys.exit('no GAME01..06.PAK in ' + folder + ' to copy')
    if 'sacred-savelimit' not in folder.lower() and '--force' not in sys.argv:
        sys.exit('refusing: the path does not look like a test copy (add --force)')
    rnd = random.Random(7)
    slots = list(range(first, first + count)) + [1000, 12345, 32766]
    for n, slot in enumerate(slots):
        src = open(sources[n % len(sources)], 'rb').read()
        data, (y, m, d) = patch(src, slot, rnd)
        path = os.path.join(folder, 'GAME%02d.PAK' % slot)
        with open(path, 'wb') as f:
            f.write(data)
        import datetime
        t = datetime.datetime(y, m, d, 12, 0).timestamp()
        os.utime(path, (t, t))
    spare = os.path.join(folder, 'filler.dat')
    shutil.copyfile(sources[0], spare)
    fill_to = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else 0
    filled = 0
    for slot in range(1, fill_to + 1):
        path = os.path.join(folder, 'GAME%02d.PAK' % slot)
        if os.path.exists(path):
            continue
        # Hard links to a spare file, never to a savegame the tests write to (a save overwrites the file in place, which
        # would change every link of it); numbers up to 99 (the autosave mod's) get a copy of their own.
        try:
            if slot >= 97 and slot <= 99:
                raise OSError()
            os.link(spare, path)
        except OSError:
            shutil.copyfile(spare, path)
        filled += 1
    print('filled %d numbers up to %d' % (filled, fill_to))
    print('wrote %d savegames, %d..%d and 1000, 12345, 32766' % (len(slots), first, first + count - 1))


if __name__ == '__main__':
    main()
