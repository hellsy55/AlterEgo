"""Maintenance regressions: isolated repositories, no network or installation."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import maintenance_runtime as runtime
import classify_lib_changes as classifier
import check_lib_updates as checker


@contextlib.contextmanager
def directory(path):
    previous = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class RuntimeTests(unittest.TestCase):
    def test_candidate_order(self):
        self.assertEqual(runtime.candidates(True), [['py', '-3'], ['python'], ['python3']])
        self.assertEqual(runtime.candidates(False), [['python3'], ['python']])

    def test_each_alias(self):
        for command in (['py', '-3'], ['python3'], ['python']):
            with self.subTest(command=command), patch.object(runtime.subprocess, 'check_output',
                    return_value=json.dumps([3, sys.executable])) as probe:
                self.assertEqual(runtime.resolve([command]), sys.executable)
                self.assertEqual(probe.call_args.args[0], command + ['-c', runtime.PROBE])

    def test_python2_rejected(self):
        with patch.object(runtime.subprocess, 'check_output', return_value=json.dumps([2, sys.executable])):
            with self.assertRaises(RuntimeError):
                runtime.resolve([['python']])

    def test_missing(self):
        with patch.object(runtime.subprocess, 'check_output', side_effect=FileNotFoundError):
            with self.assertRaises(RuntimeError):
                runtime.resolve()

    def test_timeout_falls_back(self):
        with patch.object(runtime.subprocess, 'check_output', side_effect=[
                subprocess.TimeoutExpired('python3', 10), json.dumps([3, sys.executable])]):
            self.assertEqual(runtime.resolve(runtime.candidates(False)), sys.executable)

    def test_invalid_output_and_failed_alias_fall_back(self):
        with patch.object(runtime.subprocess, 'check_output', side_effect=[
                subprocess.CalledProcessError(1, 'py'), 'not JSON', json.dumps([3, sys.executable])]):
            self.assertEqual(runtime.resolve(runtime.candidates(True)), sys.executable)

    def test_absolute_existing_executable_required(self):
        for executable in ('python', str(ROOT / 'missing-python')):
            with patch.object(runtime.subprocess, 'check_output', return_value=json.dumps([3, executable])):
                with self.assertRaises(RuntimeError):
                    runtime.resolve([['python']])

    def test_resolve_once_and_reuse(self):
        with patch.object(runtime, 'resolve', return_value=sys.executable) as resolve:
            selected = runtime.Runtime()
            self.assertEqual(selected.command('classifier.py')[0], sys.executable)
            self.assertEqual(selected.command('checker.py', '--apply', 'Foo')[0], sys.executable)
            resolve.assert_called_once()

    def test_real_bootstrap(self):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/maintenance_runtime.py')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path(result.stdout.strip()).is_absolute())


class ClassifierTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cwd = directory(self.temp.name)
        self.cwd.__enter__()
        self.addCleanup(self.cwd.__exit__, None, None, None)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Maintenance Test')
        self.git('config', 'user.email', 'maintenance@example.invalid')
        self.write('Libs/Alpha/a.lua', 'old')
        self.write('Libs/Keep/a.lua', 'old')
        self.write('Libs/root.lua', 'old')
        self.write('.pkgmeta', 'old')
        self.write('.pkgmeta-lock.json', '{}')
        self.base = self.commit()

    def git(self, *args):
        result = subprocess.run(['git', *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def write(self, name, content):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        return self.git('rev-parse', 'HEAD')

    def compare(self, target, expected):
        actual = classifier.classify(self.base, target)
        self.assertEqual(actual, expected)
        # These expectations were checked against the original PowerShell
        # implementation before removing it; no second implementation is kept.

    def test_no_changes(self):
        self.compare(self.base, {'changes': [], 'metadata': []})

    def test_one_library(self):
        self.write('Libs/Alpha/a.lua', 'new')
        self.write('Libs/Alpha/b.lua', 'new')
        self.compare(self.commit(), {'changes': [{'library': 'Libs/Alpha', 'status': 'M', 'files': 2}], 'metadata': []})

    def test_metadata(self):
        self.write('.pkgmeta', 'new')
        self.write('.pkgmeta-lock.json', '{"new":1}')
        self.compare(self.commit(), {'changes': [], 'metadata': [
            {'path': '.pkgmeta-lock.json', 'status': 'M'}, {'path': '.pkgmeta', 'status': 'M'}]})

    def test_multiple_add_remove_and_root(self):
        Path('Libs/Alpha/a.lua').unlink()
        self.write('Libs/New/a.lua', 'new')
        self.write('Libs/Keep/b.lua', 'new')
        self.write('Libs/root.lua', 'new')
        self.compare(self.commit(), {'changes': [
            {'library': 'Libs', 'status': 'M', 'files': 1},
            {'library': 'Libs/Alpha', 'status': 'D', 'files': 1},
            {'library': 'Libs/Keep', 'status': 'M', 'files': 1},
            {'library': 'Libs/New', 'status': 'A', 'files': 1}], 'metadata': []})

    def test_rename_is_add_and_delete(self):
        Path('Libs/Alpha/a.lua').rename('Libs/Alpha/b.lua')
        self.compare(self.commit(), {'changes': [{'library': 'Libs/Alpha', 'status': 'M', 'files': 2}], 'metadata': []})

    def test_unrelated_ignored(self):
        self.write('Modules/Foo.lua', 'new')
        self.compare(self.commit(), {'changes': [], 'metadata': []})

    def test_invalid_ref_nonzero(self):
        for script, args in [('classify_lib_changes.py', ['--base', self.base, '--target', 'invalid'])]:
            result = subprocess.run([sys.executable, str(ROOT / 'scripts' / script), *args], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertIn('Invalid commit ref', result.stderr)

    def test_git_error(self):
        with patch.object(classifier.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'failure')):
            with self.assertRaises(RuntimeError):
                classifier.git('diff')

    def test_bad_diff_output(self):
        with patch.object(classifier, 'git', side_effect=[[], [], ['T\tLibs/Alpha/a.lua']]):
            with self.assertRaisesRegex(RuntimeError, 'Unexpected Git diff'):
                classifier.classify('base', 'target')

    def test_case_insensitive_grouping_matches_powershell(self):
        with patch.object(classifier, 'git', side_effect=[[], [], [
                'M\tLibs/Alpha/a.lua', 'M\tLibs/alpha/b.lua']]):
            self.assertEqual(classifier.classify('base', 'target')['changes'],
                             [{'library': 'Libs/Alpha', 'status': 'M', 'files': 2}])


class CheckerTests(unittest.TestCase):
    def setUp(self):
        output = contextlib.redirect_stdout(io.StringIO())
        output.__enter__()
        self.addCleanup(output.__exit__, None, None, None)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cwd = directory(self.temp.name)
        self.cwd.__enter__()
        self.addCleanup(self.cwd.__exit__, None, None, None)
        Path('.pkgmeta').write_text('externals:\n  Libs/Foo:\n    url: https://example.invalid/foo\n    tag: v1\n')
        self.old = '{"Libs/Foo": {"kind": "git-tag", "value": "v1"}}\n'
        Path('.pkgmeta-lock.json').write_text(self.old)
        Path('Libs/Foo').mkdir(parents=True)
        Path('Libs/Foo/old.lua').write_text('old')
        self.info = {'name': 'Foo', 'kind': 'git-tag', 'new': 'v2', 'export_url': 'fixture'}

    def main(self, args=(), vendor=None):
        with patch.object(sys, 'argv', ['checker', *args]), patch.object(checker, 'resolve_upstream_version',
                return_value=('git-tag', 'v2', 'fixture')), patch.object(checker, 'vendor_lib', vendor) if vendor else contextlib.nullcontext(), contextlib.redirect_stdout(io.StringIO()):
            return checker.main()

    def assert_lock_preserved(self):
        self.assertEqual(Path('.pkgmeta-lock.json').read_text(encoding="utf-8"), self.old)

    def test_report_only(self):
        with patch.object(checker, 'vendor_lib') as vendor:
            self.assertEqual(self.main(), 0)
            vendor.assert_not_called()
        self.assert_lock_preserved()

    def test_success_updates_lock_after_vendor(self):
        def vendor(path, info):
            self.assert_lock_preserved()
        self.assertEqual(self.main(['--apply', 'Foo'], vendor), 0)
        self.assertEqual(json.loads(Path('.pkgmeta-lock.json').read_text(encoding="utf-8"))['Libs/Foo']['value'], 'v2')

    def test_vendor_failure_preserves_lock(self):
        def fail(*args):
            raise RuntimeError('vendor failed')
        with self.assertRaises(RuntimeError):
            self.main(['--apply', 'Foo'], fail)
        self.assert_lock_preserved()

    def test_batch_failure_preserves_entire_lock(self):
        with Path('.pkgmeta').open('a') as f:
            f.write('  Libs/Bar:\n    url: fixture\n    tag: v1\n')
        calls = []
        def vendor(path, info):
            calls.append(path)
            if len(calls) == 2:
                raise RuntimeError('second vendor failed')
        with self.assertRaises(RuntimeError):
            self.main(['--apply', 'all'], vendor)
        self.assertEqual(len(calls), 2)
        self.assert_lock_preserved()

    def test_lock_write_failure_preserves_previous(self):
        with patch.object(checker.os, 'replace', side_effect=OSError('write failure')):
            with self.assertRaises(OSError):
                checker.save_lockfile({'new': 'data'})
        self.assert_lock_preserved()

    def test_svn_export_failure(self):
        self.info['kind'] = 'svn-tag'
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'failed')):
            with self.assertRaisesRegex(RuntimeError, 'SVN export failed'):
                checker.vendor_lib('Libs/Foo', self.info)
        self.assert_lock_preserved()
        self.assertTrue(Path('Libs/Foo/old.lua').exists())

    def test_clone_failure(self):
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'failed')):
            with self.assertRaisesRegex(RuntimeError, 'Git clone failed'):
                checker.vendor_lib('Libs/Foo', self.info)
        self.assert_lock_preserved()

    def test_checkout_failure(self):
        with patch.object(checker, 'run', side_effect=[subprocess.CompletedProcess([], 0, '', ''),
                subprocess.CompletedProcess([], 1, '', 'failed')]):
            with self.assertRaisesRegex(RuntimeError, 'Git checkout failed'):
                checker.vendor_lib('Libs/Foo', self.info)
        self.assert_lock_preserved()
        self.assertTrue(Path('Libs/Foo/old.lua').exists())

    def test_copy_failure(self):
        self.info['kind'] = 'svn-tag'
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')), \
                patch.object(checker.shutil, 'copytree', side_effect=OSError('copy failed')):
            with self.assertRaises(OSError):
                checker.vendor_lib('Libs/Foo', self.info)
        self.assert_lock_preserved()

    def test_unknown_nonzero(self):
        with patch.object(sys, 'argv', ['checker']), patch.object(checker, 'resolve_upstream_version', return_value=None), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(checker.main(), 1)
        self.assert_lock_preserved()

    def test_apply_with_unknown_preserves_lock_and_skips_vendor(self):
        with Path('.pkgmeta').open('a') as f:
            f.write('  Libs/Bar:\n    url: fixture\n    tag: v1\n')
        for target in ('Foo', 'all'):
            with self.subTest(target=target), patch.object(sys, 'argv', ['checker', '--apply', target]), \
                    patch.object(checker, 'resolve_upstream_version', side_effect=[('git-tag', 'v2', 'fixture'), None]), \
                    patch.object(checker, 'vendor_lib') as vendor, contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'lookups are unresolved'):
                    checker.main()
                vendor.assert_not_called()
                self.assert_lock_preserved()

    def test_real_cli_vendor_failure_nonzero(self):
        # Resolve a tag successfully, then fail both clones through __main__.
        code = "import runpy,sys; sys.path.insert(0,sys.argv[1]); import subprocess; subprocess.run=lambda cmd,**k: subprocess.CompletedProcess(cmd,0,'abc refs/tags/v2\\n','') if cmd[1]=='ls-remote' else subprocess.CompletedProcess(cmd,1,'','fixture clone failure'); sys.argv=['checker','--apply','Foo']; runpy.run_module('check_lib_updates',run_name='__main__')"
        result = subprocess.run([sys.executable, '-c', code, str(ROOT / 'scripts')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Git clone failed', result.stderr)
        self.assert_lock_preserved()

    def test_real_cli_lookup_failure_nonzero(self):
        code = "import runpy,sys; sys.path.insert(0,sys.argv[1]); import subprocess; subprocess.run=lambda *a,**k: subprocess.CompletedProcess([],1,'','lookup failed'); sys.argv=['checker']; runpy.run_module('check_lib_updates',run_name='__main__')"
        result = subprocess.run([sys.executable, '-c', code, str(ROOT / 'scripts')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('UNKNOWN=1', result.stdout)
        self.assert_lock_preserved()

    def test_svn_vendor_success(self):
        self.info['kind'] = 'svn-tag'
        def export(cmd, **kwargs):
            Path(cmd[-1]).mkdir()
            Path(cmd[-1], 'new.lua').write_text('new')
            return subprocess.CompletedProcess(cmd, 0, '', '')
        with patch.object(checker, 'run', side_effect=export), contextlib.redirect_stdout(io.StringIO()):
            checker.vendor_lib('Libs/Foo', self.info)
        self.assertTrue(Path('Libs/Foo/new.lua').exists())
        self.assertTrue(Path('.pkgmeta-cache/Foo/v2/new.lua').exists())

    def test_git_vendor_success_checks_commit(self):
        commands = []
        def run(cmd, **kwargs):
            commands.append(cmd)
            if cmd[1] == 'clone':
                Path(cmd[-1]).mkdir()
                Path(cmd[-1], 'new.lua').write_text('new')
            return subprocess.CompletedProcess(cmd, 0, '', '')
        self.info.update(kind='git-commit', new='deadbeef')
        with patch.object(checker, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            checker.vendor_lib('Libs/Foo', self.info)
        self.assertIn(['git', 'checkout', 'deadbeef'], commands)
        self.assertTrue(Path('Libs/Foo/new.lua').exists())
        self.assertFalse(Path('Libs/Foo/old.lua').exists())
        self.assert_lock_preserved()

    def test_tag_and_commit_resolution_unchanged(self):
        with patch.object(checker, 'latest_git_tag', return_value='v2'):
            self.assertEqual(checker.resolve_upstream_version({'url': 'git', 'tag': 'v1'})[:2], ('git-tag', 'v2'))
        with patch.object(checker, 'latest_git_commit', return_value='abc'):
            self.assertEqual(checker.resolve_upstream_version({'url': 'git', 'commit': 'old'})[:2], ('git-commit', 'abc'))
        with patch.object(checker, 'latest_svn_tag', return_value='Release-r2'):
            self.assertEqual(checker.resolve_upstream_version({'url': 'https://repos.wowace.com/wow/ace3/trunk/AceDB-3.0', 'tag': 'Release-r1'}),
                ('svn-tag', 'Release-r2', 'https://repos.wowace.com/wow/ace3/tags/Release-r2/AceDB-3.0'))


class WorkflowContractTests(unittest.TestCase):
    def test_full_head_and_independent_branches(self):
        sync = (ROOT / '.agents/skills/alterego-update/references/branch-sync.md').read_text(encoding="utf-8")
        self.assertIn('git merge --no-commit upstream/main', sync)
        self.assertIn('then from `upstream/main`', sync)
        self.assertIn('never merge them into each other', sync)
        self.assertIn('fast-forward-only', sync)
        self.assertNotIn('release_target', sync)
        self.assertFalse((ROOT / 'scripts/release_target.py').exists())

    def test_preflight_before_branch_modification(self):
        sync = (ROOT / '.agents/skills/alterego-update/references/branch-sync.md').read_text(encoding="utf-8")
        self.assertLess(sync.index('maintenance preflight'), sync.index('Check the current branch'))
        for name in ('alterego-update', 'alterego-libs', 'alterego-implement-pr'):
            self.assertIn('maintenance preflight', (ROOT / '.agents/skills' / name / 'SKILL.md').read_text(encoding="utf-8"))

    def test_install_environment_contract(self):
        skill = (ROOT / '.agents/skills/alterego-install/SKILL.md').read_text(encoding="utf-8")
        self.assertIn('On Cloud/Linux, stop without invoking PowerShell or offering an install menu', skill)
        self.assertIn('On local Windows, verify', skill)
        self.assertIn('powershell -NoProfile -ExecutionPolicy Bypass -File', skill)
        self.assertIn('new-features', skill)
        self.assertIn('without a second confirmation', skill)

    def test_default_designation_and_aliases(self):
        agents = (ROOT / 'AGENTS.md').read_text(encoding="utf-8")
        for alias in ('`update`', '`atualizar`', '`update AlterEgo`', '`atualizar AlterEgo`', '`update com libs`', '`check libs`', '`verificar libs`'):
            self.assertIn(alias, agents)
        self.assertIn('`new-features` is the intended GitHub default branch', agents)
        self.assertIn('`main` is the upstream mirror', agents)
        self.assertIn('complete staged diff', agents)
        self.assertIn('Wait for explicit approval immediately before', agents)


if __name__ == '__main__':
    unittest.main()
