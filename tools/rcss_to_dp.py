#!/usr/bin/env python3
"""Converts a mod's stylesheet (or any text with lengths) from layout units written as px to dp, for a document loaded with {dp = true}
(see sacred-bild docs/RmlPixelDocuments.md): every px length above 1 becomes dp; a hairline (1px or less) stays a screen pixel.
    python tools/rcss_to_dp.py src/better-saveload/ui/screen.rcss        (in place)"""
import re, sys, pathlib
for name in sys.argv[1:]:
    p = pathlib.Path(name)
    s = p.read_text(encoding='utf8')
    s = re.sub(r'(?<![\w.#-])(-?\d*\.?\d+)px\b', lambda m: m.group(0) if float(m.group(1)) <= 1 else m.group(1) + 'dp', s)
    p.write_text(s, encoding='utf8', newline='')
    print('converted', p)
