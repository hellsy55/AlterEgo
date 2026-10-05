"""Exercise the real preparation helper against local fork/upstream repositories."""
import contextlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import prepare_update as preparation


class CloudCheckoutTests(unittest.TestCase):
    def setUp(self):
        platform = patch.object(preparation, 'WINDOWS', False)
        platform.start()
        self.addCleanup(platform.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.seed = self.root / 'seed'
        self.seed.mkdir()
        self.command(self.seed, 'init', '-q', '-b', 'main')
        self.identity(self.seed)
        self.base = self.commit(self.seed, 'base.txt', 'Base')
        self.command(self.seed, 'checkout', '-qb', 'new-features')
        self.fork_head = self.commit(self.seed, 'fork.txt', 'Fork customization')
        self.fork = self.root / 'fork.git'
        self.upstream = self.root / 'upstream.git'
        self.command(self.root, 'clone', '-q', '--bare', str(self.seed), str(self.fork))
        self.command(self.seed, 'checkout', '-q', 'main')
        self.commit(self.seed, 'upstream-first.txt', 'Upstream change')
        self.command(self.seed, 'tag', 'fixture-point')
        self.upstream_head = self.commit(self.seed, 'upstream-last.txt', 'Latest upstream change')
        self.command(self.root, 'clone', '-q', '--bare', str(self.seed), str(self.upstream))
        self.repo = self.root / 'checkout'
        self.repo.mkdir()
        self.command(self.repo, 'init', '-q')
        self.identity(self.repo)
        self.command(self.repo, 'remote', 'add', 'origin', preparation.ORIGIN)
        # Keep the actual project URLs; route test traffic only to local fixtures.
        for url, path in ((preparation.ORIGIN, self.fork), (preparation.UPSTREAM, self.upstream)):
            self.command(self.repo, 'config', 'url.' + path.as_uri() + '.insteadOf', url)
        self.command(self.repo, 'config', 'protocol.file.allow', 'always')
        self.narrow = preparation.ORIGIN_REFS[0]
        self.command(self.repo, 'config', '--replace-all', 'remote.origin.fetch', self.narrow)
        self.command(self.repo, 'fetch', '-q', 'origin')
        self.command(self.repo, 'checkout', '-q', '--no-track', '-b', 'work', 'origin/new-features')
        previous = os.getcwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, previous)

    def command(self, cwd, *args):
        result = subprocess.run(['git', '-C', str(cwd), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def git(self, *args):
        return self.command(self.repo, *args)

    def identity(self, repo):
        self.command(repo, 'config', 'user.name', 'Maintenance Test')
        self.command(repo, 'config', 'user.email', 'maintenance@example.invalid')

    def commit(self, repo, filename, subject):
        (repo / filename).write_text(subject, encoding='utf-8')
        self.command(repo, 'add', filename)
        self.command(repo, 'commit', '-qm', subject)
        return self.command(repo, 'rev-parse', 'HEAD')

    def test_cloud_work_narrow_fetch_missing_branches_and_upstream(self):
        self.assertEqual(self.git('branch', '--format=%(refname:short)'), 'work')
        self.assertEqual(self.git('remote'), 'origin')
        refs = self.git('for-each-ref', '--format=%(refname)', 'refs/remotes').splitlines()
        self.assertEqual([ref for ref in refs if not ref.endswith('/HEAD')],
                         ['refs/remotes/origin/new-features'])
        self.assertEqual(self.git('status', '--porcelain'), '')
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            result = preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('branch', '--show-current'), 'new-features')
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
        self.assertEqual(self.git('rev-parse', 'new-features'), self.fork_head)
        self.assertEqual(self.git('rev-parse', 'main'), self.base)
        self.assertEqual(self.git('rev-parse', 'origin/main'), self.base)
        self.assertEqual(self.git('rev-parse', 'upstream/main'), self.upstream_head)
        self.assertEqual(self.git('config', '--get', 'remote.upstream.url'), preparation.UPSTREAM)
        self.assertEqual(self.git('config', '--get-all', 'remote.origin.fetch'), self.narrow)
        self.assertEqual(self.git('config', '--get', 'branch.main.remote'), 'origin')
        self.assertEqual(self.git('config', '--get', 'branch.main.merge'), 'refs/heads/main')
        fetches = [call.args for call in calls.call_args_list if call.args[0] == 'fetch']
        self.assertEqual(fetches, [
            ('fetch', '--quiet', '--no-tags', 'origin', self.narrow),
            ('fetch', '--quiet', '--no-tags', 'upstream', *preparation.UPSTREAM_REFS),
            ('fetch', '--quiet', '--no-tags', 'origin', preparation.ORIGIN_REFS[1]),
        ])
        self.assertEqual(result['created'], ['new-features', 'main'])
        self.assertTrue(result['work_preserved'])
        self.assertFalse(any(call.args[0] in ('push', 'reset', 'merge') for call in calls.call_args_list))

    def test_dirty_work_stops_before_fetch_or_checkout(self):
        (self.repo / 'dirty.txt').write_text('Keep this', encoding='utf-8')
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            with self.assertRaisesRegex(RuntimeError, 'dirty'):
                preparation.prepare(cloud_work=True)
        self.assertEqual([call.args[0] for call in calls.call_args_list], ['status'])
        self.assertEqual(self.git('branch', '--show-current'), 'work')
        self.assertEqual(self.git('remote'), 'origin')
        self.assertEqual((self.repo / 'dirty.txt').read_text(), 'Keep this')

    def test_staged_work_stops(self):
        (self.repo / 'base.txt').write_text('Keep staged change', encoding='utf-8')
        self.git('add', 'base.txt')
        with self.assertRaisesRegex(RuntimeError, 'dirty'):
            preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('branch', '--show-current'), 'work')
        self.assertIn('base.txt', self.git('diff', '--cached', '--name-only'))

    def test_local_windows_work_is_still_rejected(self):
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            with self.assertRaisesRegex(RuntimeError, 'Unexpected branch'):
                preparation.prepare()
        self.assertFalse(any(call.args[0] == 'fetch' for call in calls.call_args_list))
        self.assertEqual(self.git('branch', '--show-current'), 'work')

    def test_windows_rejects_cloud_flag_before_git_operations(self):
        with patch.object(preparation, 'WINDOWS', True), patch.object(preparation, 'git') as calls:
            with self.assertRaisesRegex(RuntimeError, 'unavailable on local Windows'):
                preparation.prepare(cloud_work=True)
            calls.assert_not_called()

    def test_missing_development_tracking_ref_is_recovered(self):
        self.git('update-ref', '-d', 'refs/remotes/origin/new-features')
        preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('rev-parse', 'origin/new-features'), self.fork_head)
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
        self.assertEqual(self.git('branch', '--show-current'), 'new-features')

    def test_upstream_rewrite_cannot_silently_abandon_work(self):
        self.command(self.fork, 'update-ref', 'refs/heads/new-features', self.base)
        with self.assertRaisesRegex(RuntimeError, 'unpublished/divergent'):
            preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
        self.assertEqual(self.git('branch', '--format=%(refname:short)'), 'work')

    def test_unpublished_work_commits_preserved_and_stop(self):
        head = self.commit(self.repo, 'work-only.txt', 'Unpublished work')
        self.git('update-ref', 'refs/remotes/origin/new-features', self.base)
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            with self.assertRaisesRegex(RuntimeError, 'unpublished/divergent'):
                preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('rev-parse', 'origin/new-features'), self.fork_head)
        fetches = [call.args for call in calls.call_args_list if call.args[0] == 'fetch']
        self.assertEqual(fetches, [('fetch', '--quiet', '--no-tags', 'origin', self.narrow)])
        self.assertEqual(self.git('rev-parse', 'work'), head)
        self.assertEqual(self.git('branch', '--show-current'), 'work')
        self.assertEqual(self.git('remote'), 'origin')

    def test_stale_tracking_ref_accepts_published_work(self):
        for mode in ('development', 'update'):
            with self.subTest(mode=mode):
                # The fixture server already contains work; only the local ref is stale.
                self.git('update-ref', 'refs/remotes/origin/new-features', self.base)
                self.git('checkout', '-q', 'work')
                with patch.object(preparation, 'git', wraps=preparation.git) as calls:
                    result = preparation.prepare(cloud_work=True, mode=mode)
                self.assertEqual(self.git('rev-parse', 'origin/new-features'), self.fork_head)
                self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
                self.assertEqual(self.git('branch', '--show-current'), 'new-features')
                self.assertTrue(result['work_preserved'])
                operations = [call.args for call in calls.call_args_list]
                refresh = ('fetch', '--quiet', '--no-tags', 'origin', self.narrow)
                check = ('merge-base', '--is-ancestor', 'work', 'origin/new-features')
                self.assertLess(operations.index(('status', '--porcelain')), operations.index(refresh))
                self.assertLess(operations.index(refresh), operations.index(check))

    def test_divergent_work_stops_after_refresh(self):
        head = self.commit(self.repo, 'work-only.txt', 'Divergent work')
        self.command(self.seed, 'checkout', '-q', 'new-features')
        remote_head = self.commit(self.seed, 'remote-only.txt', 'Divergent remote')
        self.command(self.seed, 'push', '-q', str(self.fork), 'HEAD:refs/heads/new-features')
        for mode in ('development', 'update'):
            with self.subTest(mode=mode):
                self.git('update-ref', 'refs/remotes/origin/new-features', self.base)
                with patch.object(preparation, 'git', wraps=preparation.git) as calls:
                    with self.assertRaisesRegex(RuntimeError, 'unpublished/divergent'):
                        preparation.prepare(cloud_work=True, mode=mode)
                self.assertEqual(self.git('rev-parse', 'origin/new-features'), remote_head)
                self.assertEqual(self.git('rev-parse', 'work'), head)
                self.assertEqual(self.git('branch', '--format=%(refname:short)'), 'work')
                fetches = [call.args for call in calls.call_args_list if call.args[0] == 'fetch']
                self.assertEqual(fetches, [('fetch', '--quiet', '--no-tags', 'origin', self.narrow)])
                self.assertEqual(self.git('remote'), 'origin')

    def test_existing_real_branches_keep_local_commits(self):
        self.git('checkout', '-qb', 'new-features')
        development = self.commit(self.repo, 'local-feature.txt', 'Unpublished development')
        self.git('checkout', '-qb', 'main', self.base)
        mirror = self.commit(self.repo, 'local-main.txt', 'Unpublished mirror change')
        self.git('checkout', '-q', 'work')
        result = preparation.prepare(cloud_work=True)
        self.assertEqual(result['created'], [])
        self.assertEqual(self.git('rev-parse', 'new-features'), development)
        self.assertEqual(self.git('rev-parse', 'main'), mirror)
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)

    def test_no_publication_from_bootstrap(self):
        snapshots = {repo: self.command(repo, 'for-each-ref', '--format=%(refname) %(objectname)')
                     for repo in (self.fork, self.upstream)}
        preparation.prepare(cloud_work=True)
        for repo, snapshot in snapshots.items():
            self.assertEqual(self.command(repo, 'for-each-ref', '--format=%(refname) %(objectname)'), snapshot)

    def test_normal_local_refs_and_branches(self):
        self.git('branch', '-m', 'new-features')
        self.git('config', '--replace-all', 'remote.origin.fetch', '+refs/heads/*:refs/remotes/origin/*')
        self.git('fetch', '-q', 'origin')
        self.git('branch', 'main', 'origin/main')
        self.git('remote', 'add', 'upstream', preparation.UPSTREAM)
        self.git('fetch', '-q', 'upstream', *preparation.UPSTREAM_REFS)
        with patch.object(preparation, 'WINDOWS', True):
            result = preparation.prepare()
        self.assertEqual(result['created'], [])
        self.assertFalse(result['work_preserved'])
        self.assertEqual(self.git('rev-parse', 'new-features'), self.fork_head)
        self.assertEqual(self.git('rev-parse', 'main'), self.base)

    def test_full_upstream_head_for_both_independent_syncs(self):
        preparation.prepare(cloud_work=True)
        self.git('merge', '--no-commit', 'upstream/main')
        self.assertEqual(self.git('rev-parse', 'MERGE_HEAD'), self.upstream_head)
        self.assertTrue((self.repo / 'upstream-last.txt').exists())
        # Production would stop for staged review/approval here. Abort the
        # fixture merge so the independent mirror fast-forward can be checked.
        self.git('merge', '--abort')
        self.git('checkout', '-q', 'main')
        self.git('merge', '--ff-only', 'upstream/main')
        self.assertEqual(self.git('rev-parse', 'main'), self.upstream_head)
        self.assertEqual(self.git('rev-parse', 'new-features'), self.fork_head)
        self.git('checkout', '-q', 'new-features')

    def test_fetch_failure_does_not_create_or_switch_branches(self):
        original = preparation.git
        def fail_fetch(*args, **kwargs):
            if args[0] == 'fetch':
                raise RuntimeError('Fixture fetch failed')
            return original(*args, **kwargs)
        with patch.object(preparation, 'git', side_effect=fail_fetch):
            with self.assertRaisesRegex(RuntimeError, 'fetch failed'):
                preparation.prepare(cloud_work=True)
        self.assertEqual(self.git('branch', '--format=%(refname:short)'), 'work')

    def test_bootstrap_has_no_installation_or_publication(self):
        source = (ROOT / 'scripts/prepare_update.py').read_text(encoding='utf-8')
        for command in ("git('push'", "git('reset'", "git('merge'", 'powershell', 'apt-get'):
            self.assertNotIn(command, source)

    def development_entrypoint(self, skill):
        instructions = (ROOT / '.agents/skills' / skill / 'SKILL.md').read_text()
        self.assertIn('direct-entrypoint development preparation', instructions)
        shared = (ROOT / '.agents/references/maintenance-runtime.md').read_text()
        self.assertIn('--mode development --cloud-work', shared)
        snapshots = {repo: self.command(repo, 'for-each-ref', '--format=%(refname) %(objectname)')
                     for repo in (self.fork, self.upstream)}
        # Development must not depend on the mirror branch or upstream access.
        self.command(self.fork, 'update-ref', '-d', 'refs/heads/main')
        snapshots[self.fork] = self.command(self.fork, 'for-each-ref', '--format=%(refname) %(objectname)')
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            result = preparation.prepare(cloud_work=True, mode='development')
        self.assertEqual(self.git('branch', '--show-current'), 'new-features')
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
        self.assertEqual(self.git('rev-parse', 'new-features'), self.fork_head)
        self.assertEqual(self.git('branch', '--format=%(refname:short)').splitlines(), ['new-features', 'work'])
        self.assertEqual(self.git('remote'), 'origin')
        self.assertEqual(self.git('config', '--get-all', 'remote.origin.fetch'), self.narrow)
        self.assertEqual(self.git('config', '--get', 'branch.new-features.remote'), 'origin')
        self.assertEqual(self.git('config', '--get', 'branch.new-features.merge'), 'refs/heads/new-features')
        self.assertEqual(result['fetched'], ['origin/new-features'])
        self.assertEqual(result['created'], ['new-features'])
        fetches = [call.args for call in calls.call_args_list if call.args[0] == 'fetch']
        self.assertEqual(fetches, [('fetch', '--quiet', '--no-tags', 'origin', self.narrow)])
        self.assertFalse(any(call.args[0] in ('push', 'reset', 'merge', 'commit') for call in calls.call_args_list))
        for repo, snapshot in snapshots.items():
            self.assertEqual(self.command(repo, 'for-each-ref', '--format=%(refname) %(objectname)'), snapshot)

    def test_check_libs_cloud_work_narrow_development_only(self):
        self.development_entrypoint('alterego-libs')

    def test_implement_pr_cloud_work_narrow_development_only(self):
        self.development_entrypoint('alterego-implement-pr')

    def test_development_dirty_work_stops_before_fetch(self):
        (self.repo / 'dirty.txt').write_text('Preserve')
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            with self.assertRaisesRegex(RuntimeError, 'dirty'):
                preparation.prepare(cloud_work=True, mode='development')
        self.assertEqual([call.args[0] for call in calls.call_args_list], ['status'])
        self.assertEqual(self.git('branch', '--show-current'), 'work')

    def test_development_unpublished_work_stops_after_fetch(self):
        head = self.commit(self.repo, 'local.txt', 'Unpublished work')
        self.git('update-ref', 'refs/remotes/origin/new-features', self.base)
        with patch.object(preparation, 'git', wraps=preparation.git) as calls:
            with self.assertRaisesRegex(RuntimeError, 'unpublished/divergent'):
                preparation.prepare(cloud_work=True, mode='development')
        fetches = [call.args for call in calls.call_args_list if call.args[0] == 'fetch']
        self.assertEqual(fetches, [('fetch', '--quiet', '--no-tags', 'origin', self.narrow)])
        self.assertEqual(self.git('rev-parse', 'origin/new-features'), self.fork_head)
        self.assertFalse(any(call.args[0] in ('checkout', 'push', 'reset', 'merge') for call in calls.call_args_list))
        self.assertEqual(self.git('rev-parse', 'work'), head)
        self.assertEqual(self.git('branch', '--show-current'), 'work')

    def test_development_rewritten_remote_preserves_work(self):
        self.command(self.fork, 'update-ref', 'refs/heads/new-features', self.base)
        with self.assertRaisesRegex(RuntimeError, 'unpublished/divergent'):
            preparation.prepare(cloud_work=True, mode='development')
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)
        self.assertEqual(self.git('branch', '--format=%(refname:short)'), 'work')

    def test_development_missing_tracking_ref_is_recovered(self):
        self.git('update-ref', '-d', 'refs/remotes/origin/new-features')
        preparation.prepare(cloud_work=True, mode='development')
        self.assertEqual(self.git('branch', '--show-current'), 'new-features')
        self.assertEqual(self.git('rev-parse', 'work'), self.fork_head)

    def test_development_windows_rejects_cloud_before_git(self):
        with patch.object(preparation, 'WINDOWS', True), patch.object(preparation, 'git') as calls:
            with self.assertRaisesRegex(RuntimeError, 'unavailable on local Windows'):
                preparation.prepare(cloud_work=True, mode='development')
            calls.assert_not_called()

    def test_development_windows_work_without_flag_is_rejected(self):
        with patch.object(preparation, 'WINDOWS', True):
            with self.assertRaisesRegex(RuntimeError, 'Unexpected branch'):
                preparation.prepare(mode='development')
        self.assertEqual(self.git('branch', '--show-current'), 'work')

    def test_preparation_has_no_release_target(self):
        source = (ROOT / 'scripts/prepare_update.py').read_text()
        self.assertNotIn('release', source.lower())


if __name__ == '__main__':
    unittest.main()
