"""Tests for tools/make_mod_index.py (`recommended`): python -m unittest tools/test_make_mod_index.py"""
import contextlib, io, json, os, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_mod_index as mi

LUA = "return {\n    id = '%s',\n    name = '%s',\n    version = '1.0.0',\n%s}\n"


class Recommended(unittest.TestCase):
    def test_manifest_reads_the_list(self):
        f = mi.parse_manifest(LUA % ('a', 'A', "    requires = {'sacred-gear'},\n    recommended = {'sacred-theme', \"x>=1.2\"},\n"))
        self.assertEqual(f['recommended'], ['sacred-theme', 'x>=1.2'])
        self.assertEqual(f['requires'], ['sacred-gear'])
        self.assertNotIn('recommended', mi.parse_manifest(LUA % ('a', 'A', '')))

    def test_clean_drops_self_required_and_duplicates(self):
        got = mi.clean_recommended([' sacred-theme ', 'sacred-theme>=0.3', 'a', 'gear', 'x >= 1', ''], 'a', ['gear>=0.4.1'])
        self.assertEqual(got, ['sacred-theme', 'x >= 1'])
        self.assertIsNone(mi.clean_recommended(None, 'a', None))
        self.assertIsNone(mi.clean_recommended(['a'], 'a', None))

    def run_index(self, mods):
        with tempfile.TemporaryDirectory() as d:
            for folder, extra in mods.items():
                os.makedirs(os.path.join(d, 'src', folder))
                with open(os.path.join(d, 'src', folder, 'mod.lua'), 'w', encoding='utf-8') as fh:
                    fh.write(LUA % (folder, folder.upper(), extra))
            out = os.path.join(d, 'mod-index.json')
            old = os.getcwd()
            os.chdir(d)
            try:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    sys.argv = ['make_mod_index.py', '--src', 'src', '--out', out, '--download-url', 'https://example.com/m.zip']
                    self.assertEqual(mi.main(), 0)
            finally:
                os.chdir(old)
            with open(out, encoding='utf-8') as fh:
                return {m['id']: m for m in json.load(fh)['mods']}

    def test_index_carries_recommended_in_order_after_requires(self):
        mods = self.run_index({'ui': "    requires = {'gear'},\n    recommended = {'theme'},\n", 'plain': ''})
        self.assertEqual(mods['ui']['recommended'], ['theme'])
        self.assertNotIn('recommended', mods['plain'])
        keys = list(mods['ui'])
        self.assertLess(keys.index('requires'), keys.index('recommended'))

    def test_a_removed_recommendation_disappears_on_regeneration(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, 'src', 'ui'))
            lua = os.path.join(d, 'src', 'ui', 'mod.lua')
            out = os.path.join(d, 'mod-index.json')
            old = os.getcwd()
            os.chdir(d)
            try:
                for extra, expect in (("    recommended = {'theme'},\n", ['theme']), ('', None)):
                    with open(lua, 'w', encoding='utf-8') as fh:
                        fh.write(LUA % ('ui', 'UI', extra))
                    with contextlib.redirect_stdout(io.StringIO()):
                        sys.argv = ['make_mod_index.py', '--out', out, '--download-url', 'https://example.com/m.zip']
                        mi.main()
                    with open(out, encoding='utf-8') as fh:
                        self.assertEqual(json.load(fh)['mods'][0].get('recommended'), expect)
            finally:
                os.chdir(old)


if __name__ == '__main__':
    unittest.main()
