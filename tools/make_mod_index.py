#!/usr/bin/env python3
"""Generate or refresh a Gear Mod Manager index (mod-index.json, schema 1) from <src>/*/mod.lua.

Lua is never executed: a small tolerant tokenizer reads the top-level fields of the table `mod.lua` returns.
A re-run keeps hand-written top-level fields, `indexes`, the tags/thumbnail/images/defaultEnabled of existing entries, and every entry whose `kind` is plugin or tool
(those have no mod.lua and are written by hand).
"""
import argparse, difflib, fnmatch, json, os, re, subprocess, sys

ESC = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}
ORDER = ['id', 'path', 'name', 'version', 'author', 'description', 'tags', 'thumbnail', 'images', 'changelog', 'requires', 'recommended', 'defaultEnabled']
LONG = re.compile(r'\[(=*)\[')


def tokenize(s):
    """Yield ('s', text) strings, ('w', word) names/numbers, ('p', text) punctuation; comments are dropped."""
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        m = LONG.match(s, i) if c == '[' else None
        if c.isspace():
            i += 1
        elif s.startswith('--', i):
            m = LONG.match(s, i + 2)
            e = s.find(']' + m.group(1) + ']', m.end()) if m else s.find('\n', i)
            i = n if e < 0 else e + (len(m.group(1)) + 2 if m else 0)
        elif m:
            e = s.find(']' + m.group(1) + ']', m.end())
            e = n if e < 0 else e
            yield 's', s[m.end():e].lstrip('\n')
            i = e + len(m.group(1)) + 2
        elif c in '"\'':
            i, out = i + 1, []
            while i < n and s[i] != c and s[i] != '\n':
                if s[i] == '\\' and i + 1 < n:
                    i += 1
                    d = re.compile(r'\d{1,3}').match(s, i)
                    out.append(chr(int(d.group())) if d else ESC.get(s[i], s[i]))
                    i = d.end() - 1 if d else i
                else:
                    out.append(s[i])
                i += 1
            i += 1
            yield 's', ''.join(out)
        elif s.startswith('..', i):
            yield 'p', '..'
            i += 2
        elif re.match(r'\w', c):
            m = re.compile(r'\w+(?:\.\w+)*').match(s, i)
            yield 'w', m.group()
            i = m.end()
        else:
            yield 'p', c
            i += 1


def parse_manifest(text):
    """The depth-1 `key = value` pairs of the returned table: strings, booleans, string lists. Other values are skipped."""
    toks = list(tokenize(text)) + [('p', '')] * 3
    start = next((k for k, t in enumerate(toks) if t == ('w', 'return')), -1)
    if start < 0 or toks[start + 1] != ('p', '{'):
        return {}
    res, depth, k = {}, 0, start + 1
    while k < len(toks) - 3:
        kind, v = toks[k]
        if kind == 'p' and v in ('{', '(', '['):
            depth += 1
        elif kind == 'p' and v in ('}', ')', ']'):
            depth -= 1
            if depth == 0:
                break
        elif depth == 1 and kind == 'w' and toks[k + 1] == ('p', '=') and toks[k + 2] != ('p', '='):
            key, k = v, k + 2
            kind, v = toks[k]
            if kind == 's':  # 'a' .. "b" .. [[c]]
                res[key] = v
                while toks[k + 1] == ('p', '..') and toks[k + 2][0] == 's':
                    res[key] += toks[k + 2][1]
                    k += 2
            elif kind == 'w' and v in ('true', 'false'):
                res[key] = v == 'true'
            elif (kind, v) == ('p', '{'):  # requires = {'a', 'b'}: strings at the list's own level
                lst, d, k = [], 1, k + 1
                while k < len(toks) - 3 and d:
                    d += (toks[k] == ('p', '{')) - (toks[k] == ('p', '}'))
                    if toks[k][0] == 's' and d == 1:
                        lst.append(toks[k][1])
                    k += 1
                res[key] = lst
                continue
            else:
                continue  # numbers, calls, ...: the depth tracking scans over them
        k += 1
    return res


def merge_requires(plain, extra):
    """mod.lua's plain ids, with the index-only entries of `extra` (`id` or `id>=version`) added; an entry of `extra` replaces the plain id it names.
    Sacred Gear reads mod.lua's requires as exact ids, so a minimum version can only live in the index."""
    out = list(plain or [])
    for r in extra or []:
        rid = re.split(r'\s*>=', r, maxsplit=1)[0].strip()
        out = [x for x in out if re.split(r'\s*>=', x, maxsplit=1)[0].strip() != rid]
        out.append(r)
    return out or None


def req_id(entry):
    return re.split(r'\s*>=', entry, maxsplit=1)[0].strip()


def clean_recommended(listed, mod_id, requires):
    """mod.lua's `recommended` (ids, or `id>=version`; Sacred Gear ignores the field): trimmed, without duplicates, without the mod itself and without what it already requires."""
    skip = {mod_id} | {req_id(r) for r in requires or []}
    out, seen = [], set()
    for r in listed or []:
        r = r.strip()
        if r and req_id(r) not in skip and req_id(r) not in seen:
            seen.add(req_id(r))
            out.append(r)
    return out or None


DOC_EXTRA = {'bounty': ['quests'], 'realms': ['realm-more']}   # pictures of docs/images whose name does not start with the mod's id


def doc_pictures(mod_id):
    """docs/images files of a mod, the main picture (<id>.*) first, the others by name."""
    exts = ('.png', '.jpg', '.jpeg', '.webp')
    try:
        names = sorted(os.listdir('docs/images'))
    except OSError:
        return []
    base = {os.path.splitext(n)[0]: n for n in names if n.lower().endswith(exts)}
    out = [base[mod_id]] if mod_id in base else []
    out += [n for k, n in base.items() if k.startswith(mod_id + '-') and n not in out]
    out += [base[k] for k in DOC_EXTRA.get(mod_id, []) if k in base]
    return ['docs/images/' + n for n in out]


def git_remote():
    try:
        url = subprocess.check_output(['git', 'remote', 'get-url', 'origin'], stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return None
    m = re.search(r'github\.com[:/]+(?:[^/@]*@)?([^/]+)/([^/]+?)(?:\.git)?/?$', url)
    return m.groups() if m else None


def main():
    a = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    for f in ('src', 'prefix', 'out', 'name', 'author', 'description', 'homepage', 'download-url', 'version', 'thumb-base', 'asset'):
        a.add_argument('--' + f, default={'src': 'src', 'prefix': 'mods', 'out': 'mod-index.json', 'asset': 'mods.zip'}.get(f))
    a.add_argument('--exclude', action='append', help='folder glob to skip (repeatable); default: any folder whose name ends with "test" (case-insensitive) and sector-tools')
    a.add_argument('--extra-requires', default='tools/index-requires.json', help='JSON file {"mod id": ["other-id>=1.2.0", ...]}: requirements (with minimum versions) that only the index states, merged into the mod.lua ones; skipped when missing')
    a.add_argument('--check', action='store_true', help='write nothing; exit 1 when the file differs')
    o = a.parse_args()
    excl = o.exclude or ['*test', 'sector-tools']
    old, old_text = {}, ''
    if os.path.exists(o.out):
        with open(o.out, encoding='utf-8-sig', newline='') as fh:
            old_text = fh.read()
        old = json.loads(old_text)
    remote = git_remote()
    if not o.thumb_base and remote:
        o.thumb_base = 'https://raw.githubusercontent.com/%s/%s/main' % remote
    idx = {k: v for k, v in old.items() if k not in ('schema', 'mods', 'indexes')}
    for k in ('name', 'author', 'description', 'homepage'):
        if getattr(o, k):
            idx[k] = getattr(o, k)
    dl = dict(idx.get('download') or {})
    if o.download_url:
        dl['url'] = o.download_url
    if o.version:
        dl['version'] = o.version
    if 'url' not in dl:
        if remote:
            dl['url'] = 'https://github.com/%s/%s/releases/latest/download/%s' % (remote + (o.asset,))
        else:
            dl['url'] = 'https://example.com/CHANGE-ME/' + o.asset
            print('warning: no git remote; download.url is a placeholder, pass --download-url', file=sys.stderr)
    dl.setdefault('version', 'latest')
    idx['download'] = dl
    idx.setdefault('name', remote[1] if remote else 'Mods')
    idx.setdefault('author', remote[0] if remote else 'unknown')
    old_mods = {m.get('id'): m for m in old.get('mods', [])}
    extra = {}
    if o.extra_requires and os.path.exists(o.extra_requires):
        with open(o.extra_requires, encoding='utf-8-sig') as fh:
            extra = json.load(fh)
    mods = []
    for folder in sorted(os.listdir(o.src)):
        mp = os.path.join(o.src, folder, 'mod.lua')
        if any(fnmatch.fnmatchcase(folder.lower(), g.lower()) for g in excl) or not os.path.isfile(mp):
            continue
        with open(mp, encoding='utf-8-sig') as fh:
            f = parse_manifest(fh.read())
        if not f.get('id') or not f.get('name') or not f.get('version'):
            print('warning: %s lacks id/name/version, skipped' % mp, file=sys.stderr)
            continue
        zpath = '%s/%s' % (o.prefix, folder)
        gen = {'id': f['id'], 'path': zpath, 'name': f['name'], 'version': f['version'], 'author': f.get('author'),
               'description': f.get('description'), 'requires': f.get('requires')}
        if f.get('enabled') is False:
            gen['defaultEnabled'] = False
        gen['requires'] = merge_requires(f.get('requires'), extra.get(f['id']))
        gen['recommended'] = clean_recommended(f.get('recommended'), f['id'], gen['requires'])
        e = dict(old_mods.get(f['id'], {}))
        for k in ('author', 'description', 'requires', 'recommended'):  # regenerated fields win, even by disappearing
            e.pop(k, None)
        e.update({k: v for k, v in gen.items() if v not in (None, '', [])})
        if not e.get('thumbnail'):
            local = [n for n in ('thumbnail.png', 'thumbnail.jpg', 'thumbnail.webp') if os.path.isfile(os.path.join(o.src, folder, n))]
            doc = ['docs/images/%s.%s' % (f['id'], x) for x in ('png', 'jpg', 'webp')]
            doc = [x for x in doc if os.path.isfile(x)]
            if local:
                e['thumbnail'] = '%s/%s' % (zpath, local[0])
            elif doc and o.thumb_base:
                e['thumbnail'] = o.thumb_base.rstrip('/') + '/' + doc[0]
        e.pop('changelog', None)  # regenerated: the history.md that tools/make_changelog.py writes, as a path inside the zip
        if os.path.isfile(os.path.join(o.src, folder, 'changelog', 'history.md')):
            e['changelog'] = '%s/changelog/history.md' % zpath
        if not e.get('images') and o.thumb_base:  # the docs' pictures of the mod: docs/images/<id>.*, then <id>-*.* and the DOC_EXTRA ones; more than one makes a carousel
            pics = doc_pictures(f['id'])
            if len(pics) > 1:
                e['images'] = [o.thumb_base.rstrip('/') + '/' + x for x in pics[:24]]
        if not e.get('images'):  # pictures for the viewer: <mod>/images/ or <mod>/screenshots/ (png, jpg, webp), in name order
            for sub in ('images', 'screenshots'):
                d = os.path.join(o.src, folder, sub)
                pics = sorted(n for n in os.listdir(d) if n.lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))) if os.path.isdir(d) else []
                if pics:
                    e['images'] = ['%s/%s/%s' % (zpath, sub, n) for n in pics[:24]]
                    break
        mods.append({k: e[k] for k in ORDER + [x for x in e if x not in ORDER] if k in e})
    # plugins and tools (kind other than mod) have no mod.lua: they are written by hand and kept as they are
    ids = {m['id'] for m in mods}
    for m in old.get('mods', []):
        if str(m.get('kind', 'mod')).strip().lower() != 'mod':
            if m.get('id') in ids:
                print('warning: %s is both a mod folder and a hand-written %s entry; the entry is dropped' % (m.get('id'), m.get('kind')), file=sys.stderr)
            else:
                mods.append(m)
    mods.sort(key=lambda m: m['id'])
    out = {'schema': 1}
    for k in ('name', 'author', 'description', 'homepage', 'download'):
        if k in idx:
            out[k] = idx[k]
    out.update({k: v for k, v in idx.items() if k not in out})
    out['mods'] = mods
    if 'indexes' in old:
        out['indexes'] = old['indexes']
    text = json.dumps(out, indent=2, ensure_ascii=False) + '\n'
    new = {m['id']: m for m in mods}
    add, rem = len(new.keys() - old_mods.keys()), len(old_mods.keys() - new.keys())
    chg = sum(1 for i in new.keys() & old_mods.keys() if new[i] != old_mods[i])
    print('%s: %d mods (+%d, -%d, ~%d)' % (o.out, len(mods), add, rem, chg))
    if o.check:
        if text == old_text.replace('\r\n', '\n'):
            return 0
        sys.stdout.writelines(difflib.unified_diff(old_text.splitlines(True), text.splitlines(True),
                                                   o.out + ' (on disk)', o.out + ' (generated)'))
        print('%s is out of date: run python tools/make_mod_index.py' % o.out, file=sys.stderr)
        return 1
    with open(o.out, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
