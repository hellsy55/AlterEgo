# Local and CI validation

Run validation after applying an incremental ZIP and before deciding what to
commit in GitHub Desktop. The validator reads the current filesystem, including
staged, unstaged and untracked files. It does not require a clean checkout and
does not use Git or write files. It never downloads dependencies, repairs code,
updates branches, vendors libraries, installs the addon or publishes anything.

## Dependencies and Python resolution

Use Python 3.12 and an actual Lua 5.1 compiler (`luac`), not LuaJIT, Luau or a
newer Lua compiler. Do not assume the Windows `py` launcher works. Follow the
shared maintenance runtime resolution procedure: try an available launcher for
`scripts/maintenance_runtime.py`, check its exit status, then retain the printed
absolute Python executable. An already installed absolute Python executable,
including a discovered Codex bundled runtime, can bootstrap this resolver when
aliases fail. Do not copy a machine-specific bundled path into project code.

PowerShell example, with `$bootstrap` set to an existing Python executable:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:PYTHONUTF8 = '1'
$pythonExe = & $bootstrap -B scripts/maintenance_runtime.py
if ($LASTEXITCODE -ne 0) { throw 'Python resolution failed' }
& $pythonExe -B -X utf8 --version
```

These environment variables affect only this process and its children. Bytecode
suppression must be inherited by subprocesses; `-B` alone is insufficient.

Find an existing compiler with `Get-Command luac5.1,luac51,luac -ErrorAction
SilentlyContinue` and inspect its absolute executable path and `-v` output.
The validator also verifies the version and fails explicitly if the compiler
is absent or incompatible. It does not provision one. If unavailable, obtain
Lua 5.1 from a trusted provider separately, or build the official Lua 5.1 source
with an existing C toolchain. Lua.org links LuaBinaries as a binary provider.
Do not install globally or change permanent PATH just to run these checks.

CI uses Ubuntu 24.04 repositories to install `lua5.1` into the disposable runner.
The explicit `/usr/bin/luac5.1` is checked again by the validator. Actions are
pinned to verified commit SHAs; Python is explicitly 3.12. No Python packages,
SVN, WoW installation or Codex Cloud host are needed by the tests.

## Daily ZIP procedure

1. Confirm `new-features`, record HEAD and inspect existing local changes in
   GitHub Desktop before applying the ZIP. Keep its expected base and deletions
   available for manual review.
2. Apply the ZIP with the existing external tool. This project does not change it.
3. Set `$luac51Exe` to the verified absolute Lua 5.1 compiler path and run:

   ```powershell
   & $pythonExe -B -X utf8 scripts/validate_addon.py --luac $luac51Exe
   if ($LASTEXITCODE -ne 0) { throw 'Addon validation failed' }
   $env:ALTEREGO_LUAC51 = $luac51Exe
   & $pythonExe -B -X utf8 -m unittest discover -s scripts/tests -p 'test_*.py' -v
   if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
   ```

4. Inspect all changed, added and deleted files and the complete diff in GitHub
   Desktop. Passing validation does not establish the ZIP's provenance or intent.
5. Decide commit and push manually. No hooks or automatic staging are installed.
6. After a push, open GitHub Actions, select **Validate AlterEgo**, and match its
   full head SHA to the commit you published. Check both jobs and their logs.
   Actions cannot validate an uncommitted local ZIP before your push.

For Linux, use the resolved Python executable with the same arguments, export
`PYTHONUTF8=1`, `PYTHONDONTWRITEBYTECODE=1` and
`ALTEREGO_LUAC51=/usr/bin/luac5.1`. The tests use temporary local Git repositories;
their fixture commits, merges, remotes and configurations never target the real
checkout. They do not need external network access. Git must be installed.

## Checks and diagnostics

The validator checks:

- Every Lua file loaded through `AlterEgo.toc` and recursive XML references,
  including the loaded vendored libraries. It also checks first-party runtime
  Lua under the root, `Data/` and `Modules/`, including new files absent from TOC.
- Root `Bindings.xml`, loaded independently by WoW.
- Exact capitalization of path components, including on Windows, missing files,
  root escapes, absolute paths, recursive inclusion cycles and XML well-formedness.
- Inline XML `Script` chunks (including TaintLess CDATA), `Binding` bodies and
  children of `Scripts`. Handlers are compiled inside a function accepting
  `self, ...`; standalone Script bodies remain standalone chunks. Nothing runs.
- JSON syntax in `.wowluarc.json` and `.pkgmeta-lock.json`, when present.

Lua is compiled individually with `-p`, never producing bytecode. Inline chunks
use stdin. Diagnostics identify the source, line and cause; compiler messages
are preserved. XML parsing does not retrieve schemas or entities; DOCTYPE is
rejected. Textures, template names and schema URLs are not local load paths.

The summary reports Lua-file, XML-chunk and error counts. Exit 0 means these
checks passed; nonzero means failure, including a missing dependency. CLI usage
errors return argparse's nonzero status. A skip in the test suite is not a pass:
the real compiler integration test skips only when `ALTEREGO_LUAC51` is unset.
CI sets it explicitly, so an absent/broken compiler fails there.

These are syntax and structure checks, not complete WoW XML-schema validation
or proof of runtime compatibility. Unloaded vendor examples and `Debug/` type
annotations are excluded. JSON validation does not enforce a semantic schema.
Explicit cross-addon Script/Include paths are unsupported; the current addon
uses local loads. Lua handlers referenced by function/method names are not
resolved, and conditional loader behavior is not simulated. Actual XML used by
AlterEgo is covered without preprocessing its production files.

Symlink load paths are rejected instead of guessing how ZIP extraction and the
game will resolve them. Inline line numbers refer to the original XML; the
compiler's original stdin diagnostic is retained for context.

## Workflow boundaries

`validate.yml` runs on relevant pushes to `new-features`, PRs targeting that
branch and manual dispatch on that branch. Lua/XML/TOC, library metadata/content,
scripts, agent instructions and the validation workflow trigger both jobs.
Documentation outside these paths does not trigger it. It has read-only token
permissions, no secrets, no credential persistence, finite timeouts and cancels
obsolete runs for the same ref or PR. It does not call preparation or update CLIs.

`release.yml`, tag publication, `.pkgmeta`, the lock, libraries, the independent
upstream sync procedure, the Windows installer and `main` are unchanged. Do not
require this path-filtered workflow as a branch check without revisiting skipped
check behavior. Test code from a PR still executes in the disposable runner;
read-only permissions do not make arbitrary contributed code trustworthy.

## Resolved contract failures and remaining runtime tests

At the implementation base `60fabfa864f52b7df5cd2ed5410e1578e7c16524`, three
existing textual-contract tests failed against the instruction wording:
the two development-entrypoint tests in `test_cloud_checkout.py` and
`test_install_environment_contract` in `test_maintenance.py`. These contracts were
corrected in this implementation without suppressing, skipping or weakening the
safety guarantees. The final local run passed all 106 tests with no failures,
errors or skips; these three failures are not current maintenance-job blockers.
Those results were obtained before this documentation-only correction; GitHub
Actions itself has not yet been run for this implementation. Windows sandbox Git
ownership restrictions may also prevent temporary fixture initialization; use
an ordinary authorized local session rather than changing global safe.directory.

SavedVariables and production Lua are unchanged. A second stage should load
the real `Data.lua` in Lua 5.1 with a small addon namespace and controlled
LiqUI/AceDB dependencies, then call `Initialize`/`MigrateDB` on synthetic tables.
First inventory top-level WoW dependencies so stubs cannot hide load failures.
Test new/current/old databases, sequential upgrades to dbVersion 51,
idempotence, old/new field coexistence and preservation of unrelated character,
account and UI settings. Do not copy the migration algorithm into tests or use
real SavedVariables. This is deferred rather than introducing a parallel profile
framework or extensive WoW mocks in this first stage.

In-game testing remains necessary for login/reload with existing data, migrations,
window creation and layout, combat restrictions, taint, secret values, real event
payloads/timing, API changes, asynchronous item data and Sync between accounts.
`wowlua-ls` is not a dependency; evaluate a pinned version and its actual baseline
diagnostics separately before considering required static checks.
