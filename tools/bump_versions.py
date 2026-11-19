#!/usr/bin/env python3
"""Raise the `version` of every mod in <src>/*/mod.lua from the git history of the branch (default: HEAD, run it on main).

For each mod the history since the last version bump of that mod is read (the last commit that changed its `version = '...'` line; for a
mod that was never bumped, the commit that added its mod.lua):
  * any change to a non-test file of the mod                       -> patch   (1.2.3 -> 1.2.4)
  * a commit message containing  feat(<mod>)                        -> minor   (1.2.3 -> 1.3.0)
  * a commit message containing  break(<mod>)                       -> major   (1.2.3 -> 2.0.0)
The highest level wins. Without a non-test change nothing is bumped. Test files are: folders called test, tests or tools, any folder or
file whose name ends with "test"/"tests", and files called test_*. Scopes are compared trimmed, case-insensitive, with '-' and '_' alike;
`feat(a, b)` counts for both mods. Mod folders whose name ends with "test" and sector-tools are skipped like in the release.

    python tools/bump_versions.py              # show what would change
    python tools/bump_versions.py --write      # edit the mod.lua files (and refresh mod-index.json)
    python tools/bump_versions.py --commit     # --write, one commit per mod ("chore(mod): bump version a -> b"), then the index
    python tools/bump_versions.py --check      # CI: exit 1 when a bump is pending
"""
import argparse, fnmatch, os, re, subprocess, sys

VERSION_LINE = re.compile(r"^(?P<pre>[ \t]{0,4}version[ \t]*=[ \t]*)(?P<q>['\"])(?P<v>[^'\"\n]*)(?P=q)", re.M)
SCOPE = re.compile(r"\b(feat|break)\s*\(([^)\n]*)\)", re.I)
LEVELS = ['patch', 'minor', 'major']


def git(repo, *args, check=True):
    r = subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    if check and r.returncode != 0:
        sys.exit('git %s failed: %s' % (' '.join(args), r.stderr.strip()))
    return r.stdout


def norm(name):
    return re.sub(r'[\s_]+', '-', name.strip().lower()).replace('--', '-')


def is_test_path(rel):
    """rel: path inside the mod folder (forward slashes)."""
    parts = rel.lower().split('/')
    for d in parts[:-1]:
        if d in ('test', 'tests', 'tools') or d.endswith(('test', 'tests')):
            return True
    stem = os.path.splitext(parts[-1])[0]
    return stem.endswith(('test', 'tests')) or stem.startswith('test_')


def bump(version, level):
    m = re.fullmatch(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?', version.strip())
    if not m:
        return None
    major, minor, patch = (int(x or 0) for x in m.groups())
    if level == 'major':
        return '%d.0.0' % (major + 1)
    if level == 'minor':
        return '%d.%d.0' % (major, minor + 1)
    return '%d.%d.%d' % (major, minor, patch + 1)


def current_version(text):
    m = VERSION_LINE.search(text)
    return m.group('v') if m else None


def last_bump(repo, ref, lua_rel):
    """The newest commit that changed the top-level `version` line of the file (its creation counts), or None."""
    for sha in git(repo, 'log', '--format=%H', '-G', r'^[[:space:]]{0,4}version[[:space:]]*=', ref, '--', lua_rel).split():
        diff = git(repo, 'show', '--format=', '--unified=0', sha, '--', lua_rel)
        if any(l[:1] in '+-' and l[:3] not in ('+++', '---') and VERSION_LINE.match(l[1:]) for l in diff.splitlines()):
            return sha
    added = git(repo, 'log', '--diff-filter=A', '--format=%H', ref, '--', lua_rel).split()
    return added[-1] if added else None


def scopes(messages):
    """{'feat': {normalized scope}, 'break': {...}} found in the commit messages."""
    found = {'feat': set(), 'break': set()}
    for msg in messages:
        for kind, inner in SCOPE.findall(msg):
            for s in re.split(r'[,;/&]', inner):
                if s.strip():
                    found[kind.lower()].add(norm(s))
    return found


def plan_mod(repo, ref, src, folder):
    lua_rel = '%s/%s/mod.lua' % (src, folder)
    with open(os.path.join(repo, lua_rel), encoding='utf-8-sig', newline='') as fh:
        text = fh.read()
    version = current_version(text)
    base = last_bump(repo, ref, lua_rel)
    if version is None or base is None:
        return {'folder': folder, 'skip': 'no version line / not in git history'}
    rng = '%s..%s' % (base, ref)
    out = git(repo, 'log', '--no-merges', '--name-only', '--format=%x01%H', rng, '--', '%s/%s' % (src, folder))
    prefix = '%s/%s/' % (src, folder)
    changed = []
    for block in out.split('\x01')[1:]:
        lines = block.split('\n')
        files = [l[len(prefix):] for l in lines[1:] if l.startswith(prefix)]
        if any(not is_test_path(f) for f in files):
            changed.append(lines[0])
    msgs = git(repo, 'log', '--no-merges', '--format=%B%x00', rng).split('\x00')
    sc = scopes(msgs)
    me = norm(folder)
    level = 'patch' if changed else None
    if level and me in sc['feat']:
        level = 'minor'
    if level and me in sc['break']:
        level = 'major'
    return {'folder': folder, 'version': version, 'level': level, 'commits': len(changed), 'base': base[:8], 'text': text, 'lua': lua_rel}


def main(argv=None):
    a = argparse.ArgumentParser(description='Raise mod versions from the git history (patch / minor / major).')
    a.add_argument('--repo', default='.', help='the repository (default: current folder)')
    a.add_argument('--src', default='src')
    a.add_argument('--ref', default='HEAD', help='the history to read (default HEAD; run it on main)')
    a.add_argument('--only', action='append', help='only this mod folder (repeatable)')
    a.add_argument('--exclude', action='append', help='folder glob to skip (repeatable); default: names ending with "test", and sector-tools')
    a.add_argument('--write', action='store_true', help='edit the mod.lua files')
    a.add_argument('--commit', action='store_true', help='--write and one commit per mod, then refresh mod-index.json')
    a.add_argument('--check', action='store_true', help='exit 1 when a bump is pending')
    a.add_argument('--no-index', action='store_true', help='do not refresh mod-index.json')
    o = a.parse_args(argv)
    repo = os.path.abspath(git(o.repo, 'rev-parse', '--show-toplevel').strip())
    excl = o.exclude or ['*test', 'sector-tools']
    if o.commit and git(repo, 'diff', '--cached', '--name-only').strip():
        sys.exit('--commit needs an empty staging area (something is staged)')

    results = []
    for folder in sorted(os.listdir(os.path.join(repo, o.src))):
        if (o.only and folder not in o.only) or any(fnmatch.fnmatchcase(folder.lower(), g.lower()) for g in excl):
            continue
        if os.path.isfile(os.path.join(repo, o.src, folder, 'mod.lua')):
            results.append(plan_mod(repo, o.ref, o.src, folder))

    pending = []
    for r in results:
        if 'skip' in r:
            print('skip   %-28s %s' % (r['folder'], r['skip']))
        elif r['level'] is None:
            print('same   %-28s %s' % (r['folder'], r['version']))
        else:
            new = bump(r['version'], r['level'])
            if new is None:
                print('skip   %-28s version "%s" is not numeric (a.b.c)' % (r['folder'], r['version']))
                continue
            r['new'] = new
            pending.append(r)
            print('%-6s %-28s %s -> %s  (%d commit(s) since %s)' % (r['level'], r['folder'], r['version'], new, r['commits'], r['base']))
    if not pending:
        print('nothing to bump')
        return 0
    if o.check:
        return 1
    if not (o.write or o.commit):
        print('\n%d mod(s) would change; run with --write or --commit' % len(pending))
        return 0

    for r in pending:
        path = os.path.join(repo, r['lua'])
        new_text = VERSION_LINE.sub(lambda m: m.group('pre') + m.group('q') + r['new'] + m.group('q'), r['text'], count=1)
        with open(path, 'w', encoding='utf-8', newline='') as fh:
            fh.write(new_text)
        if o.commit:
            git(repo, 'add', '--', r['lua'])
            git(repo, 'commit', '-m', 'chore(%s): bump version %s -> %s (%s)' % (r['folder'], r['version'], r['new'], r['level']), '--', r['lua'])
    index = os.path.join(repo, 'mod-index.json')
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make_mod_index.py')
    if not o.no_index and os.path.isfile(index) and os.path.isfile(tool):
        subprocess.run([sys.executable, tool, '--out', index, '--src', o.src], cwd=repo, check=False)
        if o.commit and git(repo, 'status', '--porcelain', '--', 'mod-index.json').strip():
            git(repo, 'commit', '-m', 'chore: refresh mod-index.json after version bumps', '--', 'mod-index.json')
    print('%d mod(s) %s' % (len(pending), 'bumped and committed' if o.commit else 'bumped (not committed)'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
