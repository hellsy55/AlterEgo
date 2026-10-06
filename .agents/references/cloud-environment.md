# Cloud environment configuration

Open this repository on `new-features`. After review, commit and push, manually set the GitHub fork default to `new-features`; these instructions do not change GitHub settings. `main` remains the clean upstream mirror.

Python 3 and Git are required; library checking/vendoring also requires SVN for current `.pkgmeta` sources. No pip packages, Lua or PowerShell are needed. The supported upstream PR workflow also requires authenticated `gh`; provision it with the other tools, but never embed credentials in this script. Network failures remain errors/unknown results.

## Checkout preparation

Reuse the root and environment context from [maintenance preflight](maintenance-runtime.md); complete its deferred runtime gate before invoking preparation, then retain the runtime. Strictly read-only PR URL validation, compact metadata and changed paths may precede this adapter. `--cloud-work` is permitted only for positively identified Codex Cloud on isolated `work`, never from Linux or the branch name alone; the helper also rejects it on Windows.

For update, run `<PYTHON> scripts/prepare_update.py --cloud-work` once as branch sync's normal preparation. It fetches upstream and both origin branches with explicit destinations and preserves existing tips. Validate `work` ancestry to `origin/new-features` before fetching when that ref exists, and always after fetching. Dirty, unpublished or divergent `work` stops for review. Preserve `work`; never reset, merge or publish it as a project branch. Only eligible `work` switches to real `new-features`.

For a direct library or PR entrypoint on `work`, run `<PYTHON> scripts/prepare_update.py --mode development --cloud-work` once and require success and real `new-features` before checker/apply or PR comparison against the development checkout/application/commit. It fetches only `origin/new-features`, creates only its missing tracking branch, and leaves `main` and `upstream` untouched. It preserves `work`, rejects dirty or unpublished/divergent work before switching, and never resets, merges, commits or pushes. Compare existing `new-features` with `origin/new-features`: stop on divergence; review pre-existing unpublished commits and obtain explicit publication approval before any eventual push. A report-only check does not authorize publication.

If already prepared on `new-features`, reuse the parent result without preparing or fetching again. Existing real branches retain core ancestry, overlap, conflict, commit and publication gates.

## Rootless SVN bootstrap

This checkout contains the startup instructions; an external Start skill configured in the environment editor is not required. On Cloud/Linux, when SVN is missing and a workflow requires it, complete this bootstrap before starting the maintenance workflow. Provisioning is a separate setup step, never an installation performed by maintenance scripts.

Python 3, Git and gh must already be available in the Cloud image. The rootless SVN method below was validated on the Debian trixie x86_64 Cloud environment and provided SVN 1.14.5 at `/home/agent/.local/bin/svn`. It requires `apt-get`, `dpkg-deb`, access to `deb.debian.org`, and write access to `/tmp` and `/home/agent/.local`. It downloads packages and extracts them into the user's directory without root, sudo, global installation or changes to system apt sources. If these prerequisites or platform assumptions are not met, report setup as pending rather than falling back to global installation.

```sh
set -eu

export PATH="/home/agent/.local/bin:$PATH"

if ! command -v svn >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1
    command -v dpkg-deb >/dev/null 2>&1

    setup_dir=$(mktemp -d /tmp/alterego-svn.XXXXXX)
    trap 'rm -rf "$setup_dir"' 0
    trap 'exit 1' HUP INT TERM

    mkdir -p "$setup_dir/lists/partial" "$setup_dir/archives/partial"
    printf '%s\n' 'deb https://deb.debian.org/debian trixie main' > "$setup_dir/sources.list"

    apt-get \
        -o Dir::Etc::sourcelist="$setup_dir/sources.list" \
        -o Dir::Etc::sourceparts=- \
        -o Dir::State::lists="$setup_dir/lists" \
        -o Dir::Cache::archives="$setup_dir/archives" \
        -o APT::Update::Error-Mode=any \
        update

    apt-get \
        -o Debug::NoLocking=1 \
        -o Dir::Etc::sourcelist="$setup_dir/sources.list" \
        -o Dir::Etc::sourceparts=- \
        -o Dir::State::lists="$setup_dir/lists" \
        -o Dir::Cache::archives="$setup_dir/archives" \
        --download-only -y install subversion

    install_dir=/home/agent/.local/opt/subversion
    mkdir -p "$install_dir" /home/agent/.local/bin

    for package in "$setup_dir/archives/"*.deb; do
        dpkg-deb -x "$package" "$install_dir"
    done

    cat > /home/agent/.local/bin/svn <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH="/home/agent/.local/opt/subversion/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec python3 -c '
import os
import sys
from urllib.parse import urlsplit

svn = "/home/agent/.local/opt/subversion/usr/bin/svn"
options = []
proxy = next((os.environ[name] for name in
              ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")
              if os.environ.get(name)), None)
if proxy:
    try:
        if any(char.isspace() or ord(char) < 32 or ord(char) == 127
               for char in proxy):
            raise ValueError
        parsed = urlsplit(proxy)
        if parsed.username is not None or parsed.password is not None:
            raise ValueError
        host = parsed.hostname
        port = parsed.port
        if (parsed.scheme not in ("http", "https") or not host
                or parsed.path not in ("", "/") or parsed.query or parsed.fragment
                or any(char in proxy for char in ("\\", "%", "?", "#"))
                or parsed.netloc.endswith(":")):
            raise ValueError
        if port is None:
            port = 443 if parsed.scheme == "https" else 80
        if not 1 <= port <= 65535:
            raise ValueError
    except ValueError:
        sys.exit("SVN proxy error: expected a valid HTTP(S) proxy URL without credentials.")
    options = ["--config-option", f"servers:global:http-proxy-host={host}",
               "--config-option", f"servers:global:http-proxy-port={port}"]
os.execv(svn, [svn, *options, *sys.argv[1:]])
' "$@"
EOF

    chmod 755 /home/agent/.local/bin/svn
fi

command -v svn
svn --version --quiet
```

Retain `/home/agent/.local/bin` on `PATH` for subsequent workflow commands, including new shell invocations; exporting it in one shell does not persist it in another. Reuse an available SVN without reprovisioning. Stop on download, extraction or validation failures.

Checkout startup instructions (also suitable for an optional external Start skill; agent instruction, not shell; no application services need starting):

```text
Locate the AlterEgo checkout and work from its repository root.
Read AGENTS.md in full and follow its command routing and safety checkpoints.
Identify the host environment. On Cloud/Linux, never offer or execute physical WoW installation.
Before maintenance changes branches, complete .agents/references/maintenance-runtime.md once and retain its absolute Python 3 executable throughout the workflow and child skills. Never install dependencies during maintenance.
For an update from a positively identified Cloud work checkout, follow the documented preparation in initial-setup and branch-sync; preserve work and stop on dirty or unpublished work. Do not treat work as a project branch.
Use new-features for development, library checks and PR implementation. Keep main as the clean upstream mirror. Sync each independently to the full HEAD of upstream/main; never merge the two branches into each other or limit synchronization by release.
Preserve overlap gates, human conflict/library choices, complete staged review and explicit approval immediately before every commit, and publication rules. Do not commit, push or change GitHub settings without required authorization.
At startup, provision missing SVN using the rootless bootstrap in this reference before any workflow that requires it. Complete the Python preflight without modifying branches and retain its absolute executable. Verify Git, SVN and gh availability and run the retained Python runtime with -m unittest discover -s scripts/tests -q. Do not fetch remotes, run prepare_update.py, sync branches, run remote library checks, authenticate interactively, or install WoW just to initialize the environment. Report missing tools or failing tests as pending.
Keep interaction in Portuguese and saved content in English. Report verified results compactly; failures or unresolved choices remain pending.
```

Run committed regressions with `<PYTHON> -m unittest discover -s scripts/tests -v`. Fixtures use temporary repositories, local bare remotes and mocked downloads, without WoW or external network requests.

## Required network hosts

Normal maintenance uses `github.com` for the fork/upstream and Git externals, `api.github.com` for the existing `gh pr view`/`gh pr diff` workflow, `repos.wowace.com` for SVN externals, and `www.townlong-yak.com` for TaintLess. These are derived from the actual remotes, PR tooling and `.pkgmeta`. No WoW ZIP download host is required in Cloud because it never installs the addon.

The rootless SVN bootstrap makes no project remote requests. Its temporary apt source explicitly uses `https://deb.debian.org/debian` with the `trixie main` suite, so setup requires `deb.debian.org`. It does not use or modify the Cloud image's system apt sources. This setup host does not add any remote request to maintenance workflows.

`gh --version` validates installation without an API call. Runtime GitHub authentication/permissions must be supplied by the environment separately; never install tools or request credentials during a routine update.
