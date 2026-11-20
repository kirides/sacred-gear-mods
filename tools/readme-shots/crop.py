"""Cuts docs/images out of the shots (the BMP files in GearAutomation/<instance>/ of the game copy) as crops.json says.

    python tools/readme-shots/crop.py "B:/Games/sacred-copy" [name ...]

Needs Pillow. With names, only those images are cut."""
import json
import os
import sys

from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
images = os.path.join(os.path.dirname(os.path.dirname(here)), 'docs', 'images')
game = sys.argv[1]
only = set(sys.argv[2:])
table = json.load(open(os.path.join(here, 'crops.json'), encoding='utf-8'))
for name, c in table.items():
    if name.startswith('_') or (only and name not in only):
        continue
    src = os.path.join(game, 'GearAutomation', *c['src'].split('/')) + '.bmp'
    if not os.path.exists(src):
        print('missing', src)
        continue
    im = Image.open(src).convert('RGB').crop(tuple(c['box']))
    if c.get('scale'):
        im = im.resize((round(im.width * c['scale']), round(im.height * c['scale'])), Image.LANCZOS)
    out = os.path.join(images, name)
    if name.endswith('.png'):
        im.save(out, optimize=True)
    else:
        im.save(out, quality=88, optimize=True)
    print(name, im.size)
