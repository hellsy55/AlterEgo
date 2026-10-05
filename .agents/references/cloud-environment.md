# Cloud environment configuration

Open this repository on `new-features`. After review, commit and push, manually set the GitHub fork default to `new-features`; these instructions do not change GitHub settings. `main` remains the clean upstream mirror.

Python 3 and Git are required; library checking/vendoring also requires SVN for current `.pkgmeta` sources. No pip packages, Lua or PowerShell are needed. The supported upstream PR workflow also requires authenticated `gh`; provision it with the other tools, but never embed credentials in this script. Network failures remain errors/unknown results.

Minimal reusable setup/install script for the Ubuntu-based Cloud environment (provisioning only, never invoked by maintenance):

```sh
set -eu
missing=""
command -v python3 >/dev/null 2>&1 || missing="$missing python3"
command -v git >/dev/null 2>&1 || missing="$missing git"
command -v svn >/dev/null 2>&1 || missing="$missing subversion"
command -v gh >/dev/null 2>&1 || missing="$missing gh"
if [ -n "$missing" ]; then
    elevation=""
    [ "$(id -u)" -eq 0 ] || elevation="sudo"
    $elevation apt-get update -qq
    $elevation apt-get install -y --no-install-recommends $missing
fi
python3 -c 'import sys; assert sys.version_info.major == 3'
git --version
svn --version --quiet
gh --version
```

Recommended Start skill content (agent instruction, not shell; no application services need starting):

```text
Locate the AlterEgo checkout and work from its repository root.
Read AGENTS.md in full and follow its command routing and safety checkpoints.
Identify the host environment. On Cloud/Linux, never offer or execute physical WoW installation.
Before maintenance changes branches, complete .agents/references/maintenance-runtime.md once and retain its absolute Python 3 executable throughout the workflow and child skills. Never install dependencies during maintenance.
For an update from a positively identified Cloud work checkout, follow the documented preparation in initial-setup and branch-sync; preserve work and stop on dirty or unpublished work. Do not treat work as a project branch.
Use new-features for development, library checks and PR implementation. Keep main as the clean upstream mirror. Sync each independently to the full HEAD of upstream/main; never merge the two branches into each other or limit synchronization by release.
Preserve overlap gates, human conflict/library choices, complete staged review and explicit approval immediately before every commit, and publication rules. Do not commit, push or change GitHub settings without required authorization.
At startup, complete the Python preflight without modifying branches and retain its absolute executable. Verify Git, SVN and gh availability and run the retained Python runtime with -m unittest discover -s scripts/tests -q. Do not fetch remotes, run prepare_update.py, sync branches, run remote library checks, authenticate interactively, or install WoW just to initialize the environment. Report missing tools or failing tests as pending.
Keep interaction in Portuguese and saved content in English. Report verified results compactly; failures or unresolved choices remain pending.
```

Run committed regressions with `<PYTHON> -m unittest discover -s scripts/tests -v`. Fixtures use temporary repositories, local bare remotes and mocked downloads, without WoW or external network requests.

## Required network hosts

Normal maintenance uses `github.com` for the fork/upstream and Git externals, `api.github.com` for the existing `gh pr view`/`gh pr diff` workflow, `repos.wowace.com` for SVN externals, and `www.townlong-yak.com` for TaintLess. These are derived from the actual remotes, PR tooling and `.pkgmeta`. No WoW ZIP download host is required in Cloud because it never installs the addon.

The install script has no project remote requests. Only when a tool is missing, `apt-get` needs the hosts already configured in that Cloud image's `/etc/apt/sources.list` and `/etc/apt/sources.list.d/`. With standard Debian sources these are `deb.debian.org` and `security.debian.org`; do not assume those are the image's actual configuration. The Windows checkout does not contain the Cloud apt sources, so inspect them during environment setup and allow only their real hosts. An image using Ubuntu or custom repositories may require different preparation hosts. No additional host is added to maintenance based on that possibility.

`gh --version` validates installation without an API call. Runtime GitHub authentication/permissions must be supplied by the environment separately; never install tools or request credentials during a routine update.
