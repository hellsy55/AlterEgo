"""Regression coverage for release selection and report-only baselines."""
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
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_lib_updates as checker


def listing(tags):
    root = ET.Element('lists')
    directory = ET.SubElement(root, 'list')
    for name, revision in tags:
        entry = ET.SubElement(directory, 'entry', kind='dir')
        ET.SubElement(entry, 'name').text = name
        ET.SubElement(entry, 'commit', revision=str(revision))
    return ET.tostring(root, encoding='unicode')


class ReleaseSelectionTests(unittest.TestCase):
    def select(self, tags):
        result = subprocess.CompletedProcess([], 0, listing(tags), '')
        with patch.object(checker, 'run', return_value=result):
            return checker.latest_svn_tag('https://fixture')

    def test_ace_revisions_are_numeric_despite_aliases(self):
        tags = [('Alpha', 9999), ('Beta', 9999), ('Release-r981', 981),
                ('Release-r1377', 1377), ('Release-r1403', 1403)]
        for order in (tags, list(reversed(tags))):
            self.assertEqual(self.select(order), 'Release-r1403')
        self.assertGreater(checker.version_key('r1403'), checker.version_key('r1377'))
        self.assertGreater(checker.version_key('r1377'), checker.version_key('r981'))

    def test_libdbicon_uses_history_between_tag_families(self):
        tags = [('r66-release', 66), ('v8.0.0', 67), ('v12.0.2', 161),
                ('v12.0.3', 162)]
        for order in (tags, list(reversed(tags))):
            self.assertEqual(self.select(order), 'v12.0.3')
        # A future naming transition must also follow history, not family rank.
        self.assertEqual(self.select(tags + [('r200-release', 200)]), 'r200-release')

    def test_semantic_versions_are_numeric(self):
        self.assertEqual(self.select([('v9.0.0', 9), ('v12.0.3', 12)]), 'v12.0.3')

    def test_libstub_numeric_build_suffix_is_preserved(self):
        self.assertEqual(self.select([('1.0.3', 10), ('1.0.3-50001', 11)]),
                         '1.0.3-50001')

    def test_unusable_responses_remain_unresolved(self):
        for output in ('broken XML', '<lists/>', listing([('Alpha', 1)]),
                       '<lists><list><entry kind="dir"><name>v1</name></entry></list></lists>'):
            with self.subTest(output=output), patch.object(
                    checker, 'run', return_value=subprocess.CompletedProcess([], 0, output, '')):
                self.assertIsNone(checker.latest_svn_tag('fixture'))
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'failure')):
            self.assertIsNone(checker.latest_svn_tag('fixture'))


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.previous = os.getcwd()
        os.chdir(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(os.chdir, self.previous)

    def report(self, entries, resolved, lock=None, apply=False):
        Path('.pkgmeta').write_text('externals:\n' + ''.join(
            f'  Libs/{name}:\n    url: fixture\n    {key}: {value}\n'
            for name, key, value in entries))
        if lock is not None:
            Path('.pkgmeta-lock.json').write_text(json.dumps(lock))
        before = Path('.pkgmeta-lock.json').read_bytes() if lock is not None else None
        output = io.StringIO()
        with patch.object(sys, 'argv', ['checker'] + (['--apply', 'all'] if apply else [])), \
                patch.object(checker, 'resolve_upstream_version', side_effect=resolved), \
                patch.object(checker, 'vendor_lib') as vendor, \
                patch.object(checker, 'save_lockfile') as save, contextlib.redirect_stdout(output):
            code = checker.main()
            vendor.assert_not_called()
            save.assert_not_called()
        if before is None:
            self.assertFalse(Path('.pkgmeta-lock.json').exists())
        else:
            self.assertEqual(Path('.pkgmeta-lock.json').read_bytes(), before)
        return code, output.getvalue()

    def test_missing_lock_entries_with_identical_pins_are_not_upgrades(self):
        entries = [('TaintLess', 'commit', 'a4f3'), ('CallbackHandler-1.0', 'tag', '1.0.9'),
                   ('LibDataBroker-1.1', 'commit', '1a63'), ('LiqUI', 'tag', 'v1.3.0')]
        resolved = [('git-commit' if key == 'commit' else 'git-tag', value, 'fixture')
                    for _, key, value in entries]
        for lock in (None, {}):
            with self.subTest(lock=lock):
                code, output = self.report(entries, resolved, lock, apply=True)
                self.assertEqual(code, 0)
                self.assertIn('LIBS=up_to_date', output)
                self.assertNotIn('[!]', output)

    def test_missing_lock_with_real_advance_is_pending(self):
        code, output = self.report([('AceComm', 'tag', 'Release-r1377')],
                                  [('svn-tag', 'Release-r1403', 'fixture')])
        self.assertEqual(code, 0)
        self.assertIn('LIBS=pending', output)
        self.assertIn('content not compared', output)
        self.assertIn('Release-r1377', output)
        self.assertIn('Release-r1403', output)

    def test_lock_takes_precedence_over_declared_pin(self):
        code, output = self.report([('Foo', 'tag', 'v1')], [('git-tag', 'v2', 'fixture')],
                                  {'Libs/Foo': {'kind': 'git-tag', 'value': 'v2'}})
        self.assertEqual(code, 0)
        self.assertIn('LIBS=up_to_date', output)

    def test_older_revision_is_not_an_upgrade(self):
        code, output = self.report([('AceComm', 'tag', 'Release-r1377')],
                                  [('svn-tag', 'Release-r981', 'fixture')])
        self.assertEqual(code, 0)
        self.assertNotIn('[!]', output)

    def test_lookup_failure_is_unknown_even_without_lock(self):
        code, output = self.report([('Foo', 'tag', 'v1')], [None])
        self.assertEqual(code, 1)
        self.assertIn('LIBS=unknown', output)
        self.assertIn('UNKNOWN=1', output)


if __name__ == '__main__':
    unittest.main()
