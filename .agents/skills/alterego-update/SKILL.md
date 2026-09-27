---
name: alterego-update
description: Run the AlterEgo update or atualizar workflow, including independent upstream sync of new-features and main, library check, and install choice.
---

# Update AlterEgo

1. Read [initial setup](references/initial-setup.md) only if the remotes, `new-features`, or required branch tooling are missing.
2. Follow [branch sync](references/branch-sync.md) in order. Stop at a conflict and read [merge conflicts](references/merge-conflicts.md) before presenting a decision. Never decide the conflict for the user. Push each clean branch after its sync and return to `new-features` after `main`.
3. Read and run [the library skill](../alterego-libs/SKILL.md) on `new-features`. Finish its approval or skip checkpoint before continuing.
4. Present the install menu in Portuguese: (a) run the addon update now, or (b) do nothing more and stop. The user's choice of (a) authorizes immediate execution. Read [the install skill](../alterego-install/SKILL.md) only if the installation stage is reached. Do not run the installer before that choice.
5. Report the result in Portuguese using the summary fields in the root `AGENTS.md`. If a conflict or another decision remains, report the overall update as pending.
