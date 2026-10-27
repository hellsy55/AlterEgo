#!/usr/bin/env python3
"""Read-only structural and Lua 5.1 syntax checks for the working tree."""
import argparse
import json
import os
from pathlib import Path, PureWindowsPath
import re
import subprocess
import sys
from xml.parsers import expat


class Validator:
    def __init__(self, root, luac):
        self.root = Path(root).resolve()
        self.luac = str(luac)
        self.errors = []
        self.visited = set()
        self.active = set()
        self.lua_count = 0
        self.inline_count = 0

    def error(self, path, line, message):
        try:
            path = Path(path).relative_to(self.root)
        except ValueError:
            pass
        self.errors.append(f"{path}:{line}: {message}")

    def compiler(self):
        try:
            result = subprocess.run([self.luac, '-v'], capture_output=True,
                                    text=True, encoding='utf-8', errors='replace', timeout=15)
        except (OSError, subprocess.TimeoutExpired) as error:
            self.error('compiler', 1, f"Lua 5.1 compiler unavailable: {error}")
            return False
        version = (result.stdout + result.stderr).strip()
        if result.returncode or not re.match(r'^Lua 5\.1(?:\.\d+)?\s', version):
            self.error('compiler', 1, f"Expected Lua 5.1 luac; received {version!r}")
            return False
        print(f"Compiler: {version}")
        return True

    def reference(self, source, line, value):
        normalized = value.replace('\\', '/')
        if (not normalized or PureWindowsPath(value).drive
                or normalized.startswith('/') or ':' in normalized):
            self.error(source, line, f"Invalid local load path: {value!r}")
            return None
        candidate = Path(source).parent / normalized
        try:
            candidate.resolve().relative_to(self.root)
            relative = Path(os.path.abspath(candidate)).relative_to(self.root)
        except (ValueError, OSError, RuntimeError):
            self.error(source, line, f"Load path escapes addon root: {value!r}")
            return None
        # Resolve every component by directory listing: Windows exists() alone
        # would silently accept casing that fails on the Linux CI runner.
        current = self.root
        try:
            for part in relative.parts:
                names = [entry.name for entry in current.iterdir()]
                if part not in names:
                    hint = next((name for name in names if name.casefold() == part.casefold()), None)
                    reason = f"Incorrect path capitalization ({part!r}; expected {hint!r})" if hint else 'Missing loaded file'
                    self.error(source, line, f"{reason}: {value}")
                    return None
                current /= part
                if current.is_symlink():
                    self.error(source, line, f"Symlink load paths are unsupported: {value}")
                    return None
            if not current.is_file():
                self.error(source, line, f"Loaded path is not a file: {value}")
                return None
        except OSError as error:
            self.error(source, line, f"Cannot inspect {value!r}: {error}")
            return None
        return current

    def compile(self, path, code=None, line=1, handler=False):
        # stdin avoids scratch files and bytecode. Handlers run as functions
        # in WoW, so wrap them to support return and varargs correctly.
        if code is None:
            args, data = [self.luac, '-p', '--', str(path)], None
        else:
            chunk = ('return function(self, ...) ' + code + '\nend') if handler else code
            args, data = [self.luac, '-p', '-'], chunk.encode('utf-8')
        try:
            result = subprocess.run(args, input=data, capture_output=True, timeout=30)
            if result.returncode:
                detail = (result.stderr + result.stdout).decode('utf-8', errors='replace').strip()
                location = re.search(r':(\d+):', detail)
                if location:
                    line = (line - 1 if code is not None else 0) + int(location.group(1))
                self.error(path, line, f"Lua syntax error: {detail}")
        except (OSError, subprocess.TimeoutExpired) as error:
            self.error(path, line, f"Lua compiler failed: {error}")

    def load(self, path):
        if path in self.active:
            self.error(path, 1, 'Circular load inclusion')
            return
        if path in self.visited:
            return
        self.visited.add(path)
        self.active.add(path)
        try:
            suffix = path.suffix.lower()
            if suffix == '.lua':
                self.compile(path)
                self.lua_count += 1
            elif suffix == '.xml':
                self.xml(path)
            else:
                self.error(path, 1, 'Unsupported loaded file type (expected .lua or .xml)')
        finally:
            self.active.remove(path)

    def xml(self, path):
        parser = expat.ParserCreate(namespace_separator='}')
        stack = []

        def start(name, attrs):
            tag = name.rsplit('}', 1)[-1]
            line = parser.CurrentLineNumber
            parent = stack[-1]['tag'] if stack else None
            inline = (tag == 'Script' and 'file' not in attrs
                      or tag == 'Binding' and parent == 'Bindings'
                      or parent == 'Scripts')
            stack.append(dict(tag=tag, line=line, text=[], inline=inline,
                              handler=tag != 'Script'))
            if tag in ('Include', 'Script') and 'file' in attrs:
                target = self.reference(path, line, attrs['file'])
                if target is not None:
                    self.load(target)
            elif tag == 'Include':
                self.error(path, line, 'Include requires a file attribute')

        def end(name):
            node = stack.pop()
            code = ''.join(node['text'])
            if node['inline'] and code.strip():
                self.compile(path, code, node['line'], node['handler'])
                self.inline_count += 1

        def data(text):
            if stack:
                stack[-1]['text'].append(text)

        def reject_doctype(*args):
            raise ValueError('DOCTYPE is unsupported; external entities are never loaded')

        parser.StartElementHandler = start
        parser.EndElementHandler = end
        parser.CharacterDataHandler = data
        parser.StartDoctypeDeclHandler = reject_doctype
        try:
            parser.Parse(path.read_bytes(), True)
        except (OSError, ValueError, expat.ExpatError) as error:
            self.error(path, getattr(error, 'lineno', parser.CurrentLineNumber), f"Invalid XML: {error}")

    def run(self):
        if not self.compiler():
            for error in self.errors:
                print(error, file=sys.stderr)
            return 1
        toc = self.root / 'AlterEgo.toc'
        try:
            for line, text in enumerate(toc.read_text(encoding='utf-8-sig').splitlines(), 1):
                text = text.strip()
                if text and not text.startswith('#'):
                    target = self.reference(toc, line, text)
                    if target is not None:
                        self.load(target)
        except (OSError, UnicodeError) as error:
            self.error(toc, 1, str(error))
        # WoW loads root Bindings.xml independently of the TOC.
        bindings = self.reference(toc, 1, 'Bindings.xml')
        if bindings is not None:
            self.load(bindings)
        # Also check new first-party runtime Lua files before they are added
        # to the TOC. Debug annotations and unloaded vendor examples are not runtime.
        owned = list(self.root.glob('*.lua'))
        for directory in ('Data', 'Modules'):
            owned.extend((self.root / directory).rglob('*.lua'))
        for path in sorted(owned):
            target = self.reference(toc, 1, str(path.relative_to(self.root)))
            if target is not None:
                self.load(target)
        for name in ('.wowluarc.json', '.pkgmeta-lock.json'):
            path = self.root / name
            if path.exists():
                path = self.reference(toc, 1, name)
                if path is None:
                    continue
                try:
                    json.loads(path.read_text(encoding='utf-8'))
                except (OSError, UnicodeError, ValueError) as error:
                    self.error(path, getattr(error, 'lineno', 1), f"Invalid JSON: {error}")
        for error in self.errors:
            print(error, file=sys.stderr)
        print(f"Validated {self.lua_count} Lua files and {self.inline_count} XML Lua chunks; {len(self.errors)} error(s).")
        return int(bool(self.errors))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--luac', required=True, help='Explicit Lua 5.1 compiler executable or command')
    args = parser.parse_args(argv)
    return Validator(args.root, args.luac).run()


if __name__ == '__main__':
    sys.exit(main())
