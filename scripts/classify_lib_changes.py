#!/usr/bin/env python3
"""Classify the exact Git range using the former PowerShell JSON contract."""
import argparse
import json
import re
import subprocess
import sys


def git(*args):
    result = subprocess.run(['git', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Git command failed: ' + result.stderr.strip())
    return result.stdout.splitlines()


def library_exists(ref, library):
    rows = git('ls-tree', '-d', '--name-only', ref, '--', library)
    if len(rows) > 1 or (rows and rows[0].casefold() != library.casefold()):
        raise RuntimeError('Unexpected Git tree output for ' + library)
    return bool(rows)


def classify(base, target):
    for ref in (base, target):
        try:
            git('cat-file', '-e', ref + '^{commit}')
        except RuntimeError:
            raise RuntimeError('Invalid commit ref: ' + ref)
    rows = git('-c', 'core.quotePath=false', 'diff', '--no-renames', '--name-status', base, target,
               '--', 'Libs/', '.pkgmeta', '.pkgmeta-lock.json')
    libraries, metadata = {}, []
    for row in rows:
        match = re.fullmatch(r'([AMD])\t(.+)', row)
        if not match:
            raise RuntimeError('Unexpected Git diff output: ' + row)
        status, path = match.groups()
        if path.casefold() in ('.pkgmeta', '.pkgmeta-lock.json'):
            metadata.append({'path': path, 'status': status})
            continue
        if not path.casefold().startswith('libs/') or path.casefold() == 'libs/':
            raise RuntimeError('Unexpected library path: ' + path)
        parts = path[5:].split('/', 1)
        library = 'Libs' if len(parts) == 1 else 'Libs/' + parts[0]
        key = library.casefold()
        libraries.setdefault(key, {'library': library, 'statuses': []})['statuses'].append(status)
    changes = []
    for key in sorted(libraries):
        library = libraries[key]['library']
        statuses = libraries[key]['statuses']
        status = 'M'
        if set(statuses) == {'A'} and not library_exists(base, library):
            status = 'A'
        elif set(statuses) == {'D'} and not library_exists(target, library):
            status = 'D'
        changes.append({'library': library, 'status': status, 'files': len(statuses)})
    # Preserve the legacy PowerShell ordering of these two recognized paths.
    return {'changes': changes, 'metadata': sorted(metadata,
            key=lambda item: 0 if item['path'].casefold() == '.pkgmeta-lock.json' else 1)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--target', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(classify(args.base, args.target), separators=(',', ':')))
        return 0
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
