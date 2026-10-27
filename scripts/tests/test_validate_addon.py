"""Structural fixtures and optional real Lua 5.1 integration; no checkout writes."""
import contextlib
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import validate_addon as validation


class ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('AlterEgo.toc', 'Main.lua\n')
        self.write('Main.lua', 'local valid = true\n')
        self.write('Bindings.xml', '<Bindings><Binding name="TEST">return ...</Binding></Bindings>')
        self.calls = []

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def compiler(self, args, **kwargs):
        self.calls.append((args, kwargs))
        if '-v' in args:
            return subprocess.CompletedProcess(args, 0, '', 'Lua 5.1.5 Copyright (C) Lua.org')
        return subprocess.CompletedProcess(args, 0, b'', b'')

    def run_validator(self, compiler=None):
        before = self.snapshot()
        out, err = io.StringIO(), io.StringIO()
        with patch.object(validation.subprocess, 'run', side_effect=compiler or self.compiler), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = validation.main(['--root', str(self.root), '--luac', 'fixture-luac'])
        self.assertEqual(self.snapshot(), before)
        return code, err.getvalue()

    def snapshot(self):
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.root.rglob('*') if p.is_file()}

    def test_valid_tree(self):
        self.assertEqual(self.run_validator(), (0, ''))
        file_calls = [args for args, _ in self.calls if '--' in args]
        self.assertEqual(len(file_calls), 1)
        self.assertIn('-p', file_calls[0])

    def test_missing_compiler(self):
        code, err = self.run_validator(lambda *a, **k: (_ for _ in ()).throw(FileNotFoundError('not found')))
        self.assertEqual(code, 1)
        self.assertIn('compiler unavailable', err)

    def test_incompatible_compilers(self):
        for version in ('Lua 5.2.4', 'Lua 5.4.8', 'LuaJIT 2.1', 'Lua 5.10.1', ''):
            with self.subTest(version=version):
                code, err = self.run_validator(lambda *a, **k: subprocess.CompletedProcess([], 0, version, ''))
                self.assertEqual(code, 1)
                self.assertIn('Expected Lua 5.1', err)

    def test_compiler_timeout(self):
        code, err = self.run_validator(lambda *a, **k: (_ for _ in ()).throw(subprocess.TimeoutExpired('luac', 15)))
        self.assertEqual(code, 1)
        self.assertIn('unavailable', err)

    def test_invalid_lua_diagnostic(self):
        def compiler(args, **kwargs):
            if '-v' in args:
                return self.compiler(args, **kwargs)
            return subprocess.CompletedProcess(args, 1, b'', b'fixture:2: unexpected symbol')
        code, err = self.run_validator(compiler)
        self.assertEqual(code, 1)
        self.assertIn('Main.lua:2: Lua syntax error', err)
        self.assertIn('fixture:2', err)

    def test_missing_lua(self):
        (self.root / 'Main.lua').unlink()
        self.assertIn('Missing loaded file', self.run_validator()[1])

    def test_missing_toc(self):
        (self.root / 'AlterEgo.toc').unlink()
        self.assertEqual(self.run_validator()[0], 1)

    def test_missing_xml_reference(self):
        self.write('AlterEgo.toc', 'Absent.xml\n')
        self.assertIn('Absent.xml', self.run_validator()[1])

    def test_xml_script_missing(self):
        self.write('AlterEgo.toc', 'UI.xml')
        self.write('UI.xml', '<Ui><Script file="missing.lua"/></Ui>')
        self.assertIn('Missing loaded file', self.run_validator()[1])

    def test_capitalization(self):
        self.write('AlterEgo.toc', 'main.lua')
        self.assertIn('capitalization', self.run_validator()[1])

    def test_nested_capitalization(self):
        self.write('Libs/Thing.lua', 'return 1')
        self.write('AlterEgo.toc', 'libs/Thing.lua')
        self.assertIn('capitalization', self.run_validator()[1])

    def test_circular_include(self):
        self.write('AlterEgo.toc', 'UI.xml')
        self.write('UI.xml', '<Ui><Include file="Second.xml"/></Ui>')
        self.write('Second.xml', '<Ui><Include file="UI.xml"/></Ui>')
        self.assertIn('Circular', self.run_validator()[1])

    def test_malformed_xml(self):
        self.write('Bindings.xml', '<Bindings>')
        self.assertIn('Invalid XML', self.run_validator()[1])

    def test_bindings_required_and_compiled(self):
        self.run_validator()
        chunks = [kw['input'].decode() for args, kw in self.calls if args[-1] == '-']
        self.assertIn('return function(self, ...) return ...\nend', chunks)
        (self.root / 'Bindings.xml').unlink()
        self.assertIn('Bindings.xml', self.run_validator()[1])

    def test_paths_cannot_escape_root(self):
        for value in ('../outside.lua', 'C:\\outside.lua', '/outside.lua', '\\\\host\\share\\x.lua'):
            with self.subTest(value=value):
                self.write('AlterEgo.toc', value)
                self.assertEqual(self.run_validator()[0], 1)

    def test_xml_escape(self):
        self.write('AlterEgo.toc', 'UI.xml')
        self.write('UI.xml', '<Ui><Script file="../outside.lua"/></Ui>')
        self.assertIn('escapes addon root', self.run_validator()[1])

    def test_include_requires_file(self):
        self.write('Bindings.xml', '<Bindings><Include/></Bindings>')
        self.assertIn('requires a file', self.run_validator()[1])

    def test_inline_cdata_and_handlers(self):
        self.write('AlterEgo.toc', 'UI.xml')
        self.write('UI.xml', '<Ui><Script><![CDATA[local x = 1 < 2]]></Script><Frame><Scripts><OnLoad>return ...</OnLoad></Scripts></Frame></Ui>')
        self.assertEqual(self.run_validator(), (0, ''))
        chunks = [kw['input'].decode() for args, kw in self.calls if args[-1] == '-']
        self.assertIn('local x = 1 < 2', chunks)
        self.assertIn('return function(self, ...) return ...\nend', chunks)

    def test_backslashes_and_parent_inside_root(self):
        self.write('AlterEgo.toc', 'UI\\Root.xml')
        self.write('UI/Root.xml', '<Ui><Script file="..\\Main.lua"/></Ui>')
        self.assertEqual(self.run_validator(), (0, ''))

    def test_external_assets_and_templates_are_not_load_paths(self):
        self.write('Bindings.xml', '<Bindings><Frame inherits="GameTemplate"><Texture file="Interface\\Icons\\WoW"/></Frame></Bindings>')
        self.assertEqual(self.run_validator(), (0, ''))

    def test_doctype_rejected_without_entity_resolution(self):
        self.write('Bindings.xml', '<!DOCTYPE Bindings SYSTEM "https://example.invalid/schema"><Bindings/>')
        self.assertIn('DOCTYPE', self.run_validator()[1])

    def test_invalid_json(self):
        for name in ('.wowluarc.json', '.pkgmeta-lock.json'):
            with self.subTest(name=name):
                self.write(name, '{')
                self.assertIn('Invalid JSON', self.run_validator()[1])
                (self.root / name).unlink()

    def test_new_uncommitted_file_and_git_integrity(self):
        def git(*args):
            result = subprocess.run(['git', '-C', str(self.root), *args], capture_output=True, check=True)
            return result.stdout
        git('init', '-q')
        git('config', 'user.name', 'Validation Test')
        git('config', 'user.email', 'validation@example.invalid')
        git('add', '.')
        git('commit', '-qm', 'Fixture')
        self.write('New.lua', 'return 1')
        self.write('AlterEgo.toc', 'Main.lua\nNew.lua\n')
        git('add', 'AlterEgo.toc')
        self.write('Main.lua', 'return 2')
        before = (git('status', '--porcelain=v2'), git('show-ref'), git('diff', '--cached'), git('diff'))
        self.assertEqual(self.run_validator(), (0, ''))
        self.assertTrue(any('New.lua' in str(args) for args, _ in self.calls))
        self.assertEqual(before, (git('status', '--porcelain=v2'), git('show-ref'), git('diff', '--cached'), git('diff')))

    def test_new_runtime_file_not_yet_in_toc(self):
        self.write('Modules/New.lua', 'return 1')
        self.assertEqual(self.run_validator(), (0, ''))
        self.assertTrue(any('New.lua' in str(args) for args, _ in self.calls))

    @unittest.skipUnless(os.environ.get('ALTEREGO_LUAC51'), 'Set ALTEREGO_LUAC51 for real compiler integration')
    def test_real_lua_valid_invalid_and_inline(self):
        compiler = os.environ['ALTEREGO_LUAC51']
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(validation.main(['--root', str(self.root), '--luac', compiler]), 0)
            self.write('Main.lua', 'local = broken')
            self.assertEqual(validation.main(['--root', str(self.root), '--luac', compiler]), 1)
            self.write('Main.lua', 'return 1')
            self.write('AlterEgo.toc', 'Main.lua\nUI.xml')
            self.write('UI.xml', '<Ui><Script><![CDATA[local x = 1 < 2]]></Script></Ui>')
            self.assertEqual(validation.main(['--root', str(self.root), '--luac', compiler]), 0)
            self.write('UI.xml', '<Ui><Script><![CDATA[local = broken]]></Script></Ui>')
            self.assertEqual(validation.main(['--root', str(self.root), '--luac', compiler]), 1)
            self.write('UI.xml', '<Ui/>')
            self.write('Bindings.xml', '<Bindings><Binding name="TEST">local = broken</Binding></Bindings>')
            self.assertEqual(validation.main(['--root', str(self.root), '--luac', compiler]), 1)


if __name__ == '__main__':
    unittest.main()
