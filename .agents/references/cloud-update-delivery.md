# Cloud update delivery

Load this reference only when a Cloud prompt explicitly requests it after the user selects a workflow that executes an update. Read it before the first modification of the installable target to capture the initial state. This is an additional delivery layer; it never replaces, modifies, or bypasses [AGENTS.md](../../AGENTS.md) or the [update skill](../skills/alterego-update/SKILL.md).

Checkpoints, conflicts, approvals, merge semantics, libraries, publication, and installation remain governed exclusively by the normal project workflow. If that workflow awaits approval or a decision, or fails, the update remains pending: do not generate final artifacts early. Options that do not execute an update receive no automatic installer or update summary from this reference. An incremental delivery ZIP is a downloadable artifact, not physical installation or a replacement for the normal installation source.

## Immutable baseline

Before the first modification of the installable state, identify the installable target from AGENTS.md: for AlterEgo, use `new-features`. Record its full SHA, short SHA, commit subject, and addon version when safely determinable. Preserve that exact state as the immutable delivery baseline. Auxiliary or mirror branches may be recorded for workflow purposes but never replace the installable baseline.

## Incremental installer

Only after the normal workflow is actually complete, compare the recorded initial `new-features` state with its final installable state. Use the complete net difference and final file contents, including necessary new files; omit files that end identical to the baseline.

- Generate exactly one incremental installer, never a full distribution. Include only changed files belonging to the installed addon; do not add entire modules or addons to complete the distribution.
- Exclude unchanged files, temporary files, tests, operational scripts/helpers, Codex/Cloud tooling, operational documentation, and packaging artifacts outside the installed addon.
- Structure the ZIP for extraction over `Interface/AddOns`: repository-root paths map to `AlterEgo/...`, for example `Data.lua` to `AlterEgo/Data.lua` and `Data/Currencies.lua` to `AlterEgo/Data/Currencies.lua`. Do not add an outer wrapper folder.
- Include `AlterEgo/Libs/...` only for library runtime content actually changed in the final result; omit unchanged libraries. This delivery comparison does not trigger a library check or alter library decisions.
- Name the archive `AlterEgo_<final-version>_installer.zip` when the version is reliable; otherwise use `AlterEgo_<final-short-SHA>_installer.zip`.
- Do not represent deletions inside the ZIP. List required manual removal paths separately in Portuguese.
- Do not install, extract, or copy the ZIP into the WoW folder.

## Update summary

For the installer, produce a concise English summary of the complete net functional difference between the initial baseline and final state, not just the last commit. Include relevant final runtime code, behavior, UI, content, data, functional configuration, and compatibility changes. Mention libraries only when their distributed runtime content actually changed.

Exclude reverted intermediate changes, workflow, merges as a process, checkpoints, debugging, intermediate conflicts, and discarded attempts. Exclude AGENTS.md, agent tools, Codex/Cloud tooling, environment maintenance, helper scripts, bootstrap, proxies, checkout preparation, operational documentation, tests, CI/CD, checkers, drift baselines, locks, and infrastructure metadata. Filter by the effective final change, never by commit names or subjects; retain the functional portion of mixed commits.

Show the summary alone in one copy-ready code block using:

```text
Module (type): item; item. Module2 (type): item
```

Group the same module/type with `; `, separate different groups with `. `, and omit the final period. Be concise without omitting relevant functional changes. If no functional changes remain, state that in English in the code block without inventing a change. If there are no eligible added or modified addon files, do not fabricate an empty installer; report that no incremental ZIP is needed and list any removals separately.

## Final report

Report in Portuguese for the `new-features` target:

- Initial version when available, initial subject and short SHA.
- Final version when available, final subject and short SHA, and `initial -> final`.
- ZIP filename and number of files, or why no ZIP is needed.
- Required manual removals, or none.
- Whether `Libs/` actually changed, distinguishing runtime content from metadata when relevant.
- Confirmation that the ZIP contains only the final net difference and that no files were installed into the WoW folder.

Keep this delivery report separate from the functional English summary and retain all reporting required by the normal workflow.
