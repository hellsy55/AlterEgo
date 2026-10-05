#!/usr/bin/env python3
"""Python-2-parseable bootstrap; resolve and retain one Python 3 executable."""
from __future__ import print_function

import json
import os
import subprocess
import sys

PROBE = "import json,os,sys; print(json.dumps([sys.version_info[0],os.path.abspath(sys.executable)]))"
PROBE_ERRORS = (OSError, subprocess.CalledProcessError, ValueError, TypeError,
                getattr(subprocess, 'TimeoutExpired', RuntimeError))


def candidates(windows=None):
    if windows is None:
        windows = os.name == 'nt'
    return [['py', '-3'], ['python'], ['python3']] if windows else [['python3'], ['python']]


def resolve(commands=None):
    for command in candidates() if commands is None else commands:
        try:
            options = {'stderr': subprocess.PIPE, 'universal_newlines': True}
            if sys.version_info[0] >= 3:
                options['timeout'] = 10
            result = subprocess.check_output(command + ['-c', PROBE], **options)
            major, executable = json.loads(result.strip())
            if major == 3 and os.path.isabs(executable) and os.path.isfile(executable):
                return executable
        except PROBE_ERRORS:
            continue
    raise RuntimeError('No valid Python 3 runtime found; install/configure it separately before maintenance')


class Runtime(object):
    def __init__(self, commands=None):
        self.executable = resolve(commands)

    def command(self, script, *args):
        return [self.executable, script] + list(args)


def main():
    try:
        # A known absolute bootstrap is also eligible, after the normal aliases.
        commands = candidates() + [[os.path.abspath(sys.executable)]]
        print(Runtime(commands).executable)
        return 0
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
