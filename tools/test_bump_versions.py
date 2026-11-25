"""Tests for tools/bump_versions.py: python -m unittest tools/test_bump_versions.py (builds throw-away git repositories)."""
import contextlib, io, os, subprocess, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bump_versions as bv

ENV = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t',
           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
LUA = "return {\n    id = '%s',\n    name = '%s',\n    version = '%s',\n    settings = {{id = 'x', type = 'bool', default = true}},\n}\n"


class Repo:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.n = 0
        self.git('init', '-q', '-b', 'main')

    def git(self, *a):
        r = subprocess.run(['git', '-C', self.dir, *a], capture_output=True, text=True, env=ENV)
        assert r.returncode == 0, r.stderr
        return r.stdout

    def write(self, rel, text):
        p = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(text)

    def commit(self, msg, files):
        for rel, text in files.items():
            self.write(rel, text)
        self.n += 1
        self.git('add', '-A')
        self.git('commit', '-q', '-m', msg)

    def add_mod(self, name, version='1.2.3'):
        self.commit('add ' + name, {'src/%s/mod.lua' % name: LUA % (name, name, version), 'src/%s/main.lua' % name: '-- 0\n'})

    def set_version(self, name, version, msg='manual bump'):
        self.commit(msg, {'src/%s/mod.lua' % name: LUA % (name, name, version)})

    def touch(self, rel, msg):
        self.commit(msg, {rel: '-- %d\n' % self.n})

    def run(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = bv.main(['--repo', self.dir, *args])
        return code, out.getvalue()

    def read(self, rel):
        with open(os.path.join(self.dir, rel), encoding='utf-8', newline='') as f:
            return f.read()


class Tests(unittest.TestCase):
    def setUp(self):
        self.r = Repo()
        self.addCleanup(self.r.tmp.cleanup)
        self.r.add_mod('alpha')
        self.r.add_mod('beta', '0.9')

    def plan(self, *args):
        return self.r.run(*args)[1]

    def test_nothing_changed_nothing_bumped(self):
        code, out = self.r.run()
        self.assertEqual(code, 0)
        self.assertIn('nothing to bump', out)

    def test_test_files_do_not_bump(self):
        for rel in ('src/alpha/tests/a.lua', 'src/alpha/tools/x.lua', 'src/alpha/main_test.lua', 'src/alpha/test_x.lua', 'src/alpha/spec_selftest/y.lua'):
            self.r.touch(rel, 'tests only')
        self.assertIn('nothing to bump', self.plan())

    def test_non_test_change_is_patch(self):
        self.r.touch('src/alpha/main.lua', 'fix something')
        out = self.plan()
        self.assertIn('1.2.3 -> 1.2.4', out)
        self.assertIn('same   beta', out)

    def test_feat_in_the_message_is_minor_trimmed_and_case_insensitive(self):
        self.r.touch('src/alpha/main.lua', 'Feat(  ALPHA ): shiny')
        self.assertIn('1.2.3 -> 1.3.0', self.plan())

    def test_break_is_major_and_wins_over_feat(self):
        self.r.touch('src/alpha/main.lua', 'feat(alpha): a')
        self.r.touch('src/alpha/main.lua', 'break(alpha): b')
        self.assertIn('1.2.3 -> 2.0.0', self.plan())

    def test_scope_list_and_dash_underscore_alike(self):
        self.r.add_mod('auction-house')
        self.r.touch('src/alpha/main.lua', 'feat(alpha, auction_house): both')
        self.r.touch('src/auction-house/main.lua', 'touch')
        self.assertEqual(self.plan().count('1.2.3 -> 1.3.0'), 2)

    def test_feat_of_another_mod_does_not_count(self):
        self.r.touch('src/alpha/main.lua', 'feat(beta): not mine')
        out = self.plan()
        self.assertIn('patch  alpha', out)
        self.assertIn('same   beta', out)

    def test_feat_without_a_non_test_change_bumps_nothing(self):
        self.r.touch('src/alpha/tests/a.lua', 'feat(alpha): only tests')
        self.assertIn('nothing to bump', self.plan())

    def test_missing_minor_and_patch_parts_are_padded(self):
        self.r.touch('src/beta/main.lua', 'x')
        self.assertIn('0.9 -> 0.9.1', self.plan())

    def test_write_edits_the_version_only(self):
        self.r.touch('src/alpha/main.lua', 'x')
        before = self.r.read('src/alpha/mod.lua')
        self.r.run('--write', '--no-index')
        self.assertEqual(self.r.read('src/alpha/mod.lua'), before.replace("version = '1.2.3'", "version = '1.2.4'"))

    def test_crlf_files_keep_their_line_endings(self):
        self.r.commit('crlf', {'src/alpha/mod.lua': (LUA % ('alpha', 'alpha', '1.2.3')).replace('\n', '\r\n')})
        self.r.set_version('alpha', '1.2.3', 'again')
        self.r.touch('src/alpha/main.lua', 'x')
        self.r.write('src/alpha/mod.lua', (LUA % ('alpha', 'alpha', '1.2.3')).replace('\n', '\r\n'))
        self.r.run('--write', '--no-index')
        text = self.r.read('src/alpha/mod.lua')
        self.assertIn("version = '1.2.4',\r\n", text)
        self.assertNotIn('\r\r', text)

    def test_commit_makes_the_next_run_quiet_and_counts_from_the_bump(self):
        self.r.touch('src/alpha/main.lua', 'x')
        code, _ = self.r.run('--commit', '--no-index')
        self.assertEqual(code, 0)
        self.assertIn("version = '1.2.4'", self.r.read('src/alpha/mod.lua'))
        self.assertIn('chore(alpha): bump version 1.2.3 -> 1.2.4 (patch)', self.r.git('log', '-1', '--format=%s'))
        self.assertIn('nothing to bump', self.plan())
        self.r.touch('src/alpha/main.lua', 'feat(alpha): next')
        self.assertIn('1.2.4 -> 1.3.0', self.plan())

    def test_a_hand_made_version_change_is_a_bump_too(self):
        self.r.touch('src/alpha/main.lua', 'break(alpha): old news')
        self.r.set_version('alpha', '2.0.0')
        self.assertIn('nothing to bump', self.plan())

    def test_history_before_the_last_bump_does_not_count(self):
        self.r.touch('src/alpha/main.lua', 'feat(alpha): old')
        self.r.set_version('alpha', '1.3.0')
        self.r.touch('src/alpha/main.lua', 'small fix')
        self.assertIn('1.3.0 -> 1.3.1', self.plan())

    def test_check_exit_code(self):
        self.assertEqual(self.r.run('--check')[0], 0)
        self.r.touch('src/alpha/main.lua', 'x')
        self.assertEqual(self.r.run('--check')[0], 1)

    def test_test_mods_and_non_numeric_versions_are_skipped(self):
        self.r.add_mod('alpha_selftest')
        self.r.add_mod('gamma', '1.0-beta')
        self.r.touch('src/alpha_selftest/main.lua', 'x')
        self.r.touch('src/gamma/main.lua', 'x')
        out = self.plan()
        self.assertNotIn('alpha_selftest', out)
        self.assertIn('not numeric', out)

    def test_helpers(self):
        self.assertEqual(bv.bump('1.9.9', 'minor'), '1.10.0')
        self.assertEqual(bv.bump('3', 'patch'), '3.0.1')
        self.assertIsNone(bv.bump('v1', 'patch'))
        self.assertTrue(bv.is_test_path('x/Tests/a.lua'))
        self.assertTrue(bv.is_test_path('a_selftest.lua'))
        self.assertTrue(bv.is_test_path('changelog/v1.2.3.md'))
        self.assertTrue(bv.is_test_path('changelog/history.md'))
        self.assertFalse(bv.is_test_path('main.lua'))
        self.assertFalse(bv.is_test_path('latest/main.lua'.replace('latest', 'lates')))


if __name__ == '__main__':
    unittest.main()
