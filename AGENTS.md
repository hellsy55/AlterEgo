# AlterEgo project instructions

This repository is the fork at https://github.com/hellsy55/AlterEgo of https://github.com/DennisRas/AlterEgo. Treat these instructions as the routing and safety rules for its maintenance workflows.

## Language and commits

- Speak to the user in Portuguese, including explanations, options, and completion reports. Write everything saved to files or GitHub in English, including code comments, documentation, Git-generated messages, commits, pull requests, and tags.
- Commit subjects are one English imperative line covering every distinct change concisely. Use `Module (type): change` with a space before `(`. Choose a meaningful module or area and type such as `fix`, `feature`, `docs`, or `chore`.
- Group changes of the same module and type under one prefix with `; ` between changes. Keep different types for one module adjacent. Separate different module/type groups with `. ` and omit the final period. Examples: `CDM (fix): guard secret spellID values. Raid Tools (feature): disable Convert to Party above 5 members` and `CDM (feature): add cooldown filters; add spell grouping. Raid Tools (fix): correct group count`.
- Use only the user's identity in commits. Add no automatic AI signatures or generated-by lines.
- Before **every** commit, inspect the staged file list and remove unrelated files from the index. Show the user the staged file list, a concise staged stat, and the **complete staged diff**. Wait for explicit approval immediately before `git commit`; earlier approval to make a change does not replace it. The same checkpoint applies to merge and library commits.
- Never commit local test, scratch, diagnostic, temporary, or other development-only artifacts unless explicitly requested.

## Branch and workflow invariants

- `new-features` is the development, library-check, PR-implementation, and installation branch. Its committed `Libs/` makes the GitHub ZIP installable. Never ignore or remove its committed `Libs/`.
- `main` is the fork default and carries no fork-specific commits. Sync `main` and `new-features` independently from `upstream/main`; never merge them into each other. Return to `new-features` after syncing `main`.
- Stop at a real merge conflict. Explain each side's practical effect and interaction, offer incoming/local/combine/abort, recommend exactly one based on the actual conflict, and wait for the user's choice. Show marked conflict code only when requested. Read the conflict reference only when needed.
- Never install without the install-menu choice. Selecting the install option is the confirmation; do not ask again. Installation uses a fresh GitHub ZIP of `new-features`, never the working tree, and runs in the current session without a separate window.
- The remote ZIP requirement never authorizes publishing an unapproved local commit or merge. A locally created commit must pass the staged-list, staged-stat, complete-staged-diff, and explicit-approval checkpoint before commit; pre-existing unpublished history requires review and explicit publication approval before push.
- Never apply an upstream PR before explaining what is gained, lost, and unchanged and receiving the user's explicit choice.

## Command routing

Match commands case-insensitively and accept close variants, including "update alterego" and "atualizar o addon". Users do not need to name skills.

- `update`, `atualizar`, `update AlterEgo`, `atualizar AlterEgo`: read [.agents/skills/alterego-update/SKILL.md](.agents/skills/alterego-update/SKILL.md). Classify the pending upstream library range during independent branch sync, then offer the install menu. Do not load the library skill, run its checker, ask about libraries, or mention libraries unless the user explicitly requests a check or the exact incoming upstream range touches `Libs/` or recognized library metadata.
- `update com libs`, `update and check libs`, and unambiguous equivalents: run the normal update and the explicit library check.
- `check libs`, `verificar libs`: read [.agents/skills/alterego-libs/SKILL.md](.agents/skills/alterego-libs/SKILL.md). Run only the library version check; do not sync or install.
- `implement PR <upstream URL>`, `implementar PR <upstream URL>`, or a request to apply, port, or evaluate an upstream PR: read [.agents/skills/alterego-implement-pr/SKILL.md](.agents/skills/alterego-implement-pr/SKILL.md). Inspect compact PR metadata and changed paths first. Run the library check only on explicit request or after a PR library-change choice, then analyze the PR and stop for the implementation choice.
- When the install stage is reached or installation is requested directly, read [.agents/skills/alterego-install/SKILL.md](.agents/skills/alterego-install/SKILL.md).

Keep routine work in the primary agent without subagents: Git status, clean sync, already-current results, script execution, library checks with no pending updates, authorized installation, simple diffs or stats, and small clear PRs. Do not parallelize sequential work by default. Subagents consume additional tokens, so do not delegate when the primary agent is sufficient. Automatically request exactly one project-scoped `deep_reviewer` only when an independent read-only review can materially improve an important decision: a nontrivial merge conflict, large or ambiguous PR, possible loss of local customizations, change across several modules, difficult regression, or genuinely uncertain library impact. The reviewer only advises; it never replaces the user's conflict, library, PR, installation, or commit decisions. Preserve the staged file list, staged stat, complete staged diff, and explicit approval immediately before every commit.

After every task, proactively report its verified result in Portuguese. If a choice or failure remains, say the overall task is pending. For update-related work, summarize the upstream result on each branch, any conflict and its resolution, and whether installation ran and succeeded. Include library status and action only when a library trigger occurred.
