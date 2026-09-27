# Merge-conflict decision

Stop before resolving any actual conflict. Explain in plain Portuguese what each side changes in practice for every conflicted section. Then show the conflicting code for each file with Git conflict markers as a technical reference.

Identify the actual incoming source. It is normally `upstream/main`; an unusual conflict during the fork-remote pull comes from `origin/new-features`, and a PR conflict comes from the named PR. Offer these four options in Portuguese, marking exactly one with `(recommended)` based on the specific practical impact, and briefly explain the recommendation in plain language:

a) Keep the version from the actual incoming source.
b) Keep the local version of the branch being synced (`new-features` or, unexpectedly, `main`).
c) Combine both, with a concrete proposal when technically feasible.
d) Abort with `git merge --abort`, undoing the merge and applying nothing.

Wait for the user's choice. For (d), abort and report that nothing changed on that branch. For (a), (b), or (c), apply only the chosen resolution, stage it, and follow the root `AGENTS.md` checkpoint: show the staged file list, staged stat, and complete staged diff, then wait for explicit approval before `git commit`. Use an English merge message and no AI signature. Push the branch being synced after the commit. If the conflict arose while syncing `main`, do not push `new-features` in its place. Continue the remaining update workflow only after the conflict is resolved or aborted as the user chose.
