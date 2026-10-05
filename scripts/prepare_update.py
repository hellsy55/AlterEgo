#!/usr/bin/env python3
"""Prepare maintenance refs and missing tracking branches, without merging or pushing."""
import argparse
import json
import subprocess
import sys

ORIGIN = 'https://github.com/hellsy55/AlterEgo.git'
UPSTREAM = 'https://github.com/DennisRas/AlterEgo.git'
ORIGIN_REFS = ('+refs/heads/new-features:refs/remotes/origin/new-features',
               '+refs/heads/main:refs/remotes/origin/main')
UPSTREAM_REFS = ('+refs/heads/main:refs/remotes/upstream/main',)
WINDOWS = sys.platform == 'win32'


def git(*args, allow_codes=()):
    result = subprocess.run(['git', *args], capture_output=True, text=True)
    if result.returncode and result.returncode not in allow_codes:
        raise RuntimeError('Git command failed: ' + result.stderr.strip())
    return result


def exists(ref):
    return git('show-ref', '--verify', '--quiet', ref, allow_codes=(1,)).returncode == 0


def ancestor(base, target):
    return git('merge-base', '--is-ancestor', base, target, allow_codes=(1,)).returncode == 0


def verify_remote(name, expected):
    urls = git('config', '--get-all', 'remote.' + name + '.url').stdout.splitlines()
    if urls != [expected]:
        raise RuntimeError('Unexpected ' + name + ' remote URL; inspect before maintenance')


def prepare(cloud_work=False, mode='update'):
    if mode not in ('update', 'development'):
        raise RuntimeError('Unknown preparation mode')
    # --cloud-work is an explicit host-context decision, never inferred from
    # Linux or the branch name alone. Local Windows keeps its original gate.
    if cloud_work and WINDOWS:
        raise RuntimeError('Cloud work bootstrap is unavailable on local Windows')
    if git('status', '--porcelain').stdout.strip():
        raise RuntimeError('Working tree is dirty; preserve changes before maintenance')
    current = git('symbolic-ref', '--quiet', '--short', 'HEAD', allow_codes=(1,)).stdout.strip()
    is_cloud_work = cloud_work and current == 'work'
    if current != 'new-features' and not is_cloud_work:
        raise RuntimeError('Unexpected branch; maintenance requires new-features or verified Cloud work')
    verify_remote('origin', ORIGIN)
    if is_cloud_work:
        # Refresh only the required tracking ref before judging Cloud work.
        # A stale local ref cannot establish whether work is unpublished.
        git('fetch', '--quiet', '--no-tags', 'origin', *ORIGIN_REFS[:1])
        if not ancestor('work', 'origin/new-features'):
            raise RuntimeError('Cloud work has unpublished/divergent commits; preserve it and stop for review')

    if mode == 'update':
        remotes = git('remote').stdout.splitlines()
        if 'upstream' not in remotes:
            git('remote', 'add', 'upstream', UPSTREAM)
        verify_remote('upstream', UPSTREAM)
    # Explicit destinations work even if remote.origin.fetch names one branch.
    # Only remote-tracking refs may move; never reset a real local branch.
    refs = ['origin/new-features']
    branches = ('new-features',)
    if mode == 'update':
        git('fetch', '--quiet', '--no-tags', 'upstream', *UPSTREAM_REFS)
        refs = ['upstream/main', 'origin/new-features', 'origin/main']
        branches = ('new-features', 'main')
    origin_refs = ORIGIN_REFS if mode == 'update' else ORIGIN_REFS[:1]
    if is_cloud_work:
        origin_refs = origin_refs[1:]
    if origin_refs:
        git('fetch', '--quiet', '--no-tags', 'origin', *origin_refs)
    for ref in refs:
        git('cat-file', '-e', ref + '^{commit}')
    if is_cloud_work and not ancestor('work', 'origin/new-features'):
        raise RuntimeError('Fetched development history no longer contains work; preserve it and stop for review')
    if mode == 'update' and not ancestor('origin/main', 'upstream/main'):
        raise RuntimeError('origin/main is not an upstream mirror; stop for a decision')

    created = []
    for branch in branches:
        if not exists('refs/heads/' + branch):
            # --track may reject origin/main when remote.origin.fetch is narrow.
            git('branch', '--no-track', branch, 'refs/remotes/origin/' + branch)
            git('config', 'branch.' + branch + '.remote', 'origin')
            git('config', 'branch.' + branch + '.merge', 'refs/heads/' + branch)
            created.append(branch)
    if is_cloud_work:
        git('checkout', '--quiet', 'new-features')
    return {'branch': 'new-features', 'created': created,
            'fetched': refs,
            'work_preserved': is_cloud_work}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('update', 'development'), default='update',
                        help='Update prepares both branches; development prepares only new-features')
    parser.add_argument('--cloud-work', action='store_true',
                        help='Allow work only after positively identifying the Codex Cloud host')
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.cloud_work, args.mode), separators=(',', ':')))
        return 0
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
