# Merge-conflict decision

Stop before resolving any actual conflict. Read only the conflicting sections and necessary context internally. Explain in plain Portuguese for each functional area: the module or feature; what the incoming version changes; what the fork customization does; what each one-sided choice would lose; whether both features share a function, flow, or behavior; and one evidence-based recommendation. Do not display source code, hunks, diffs, conflict markers, or large file blocks by default. If the user explicitly requests code or a diff, show only the necessary excerpt.

Identify the actual incoming source. It is normally `upstream/main`; an unusual conflict while integrating the fork remote comes from `origin/new-features`, and a PR conflict comes from the named PR. Offer these four options in Portuguese, marking exactly one as recommended when evidence suffices, and briefly explain the recommendation:

a) Keep the version from the actual incoming source.
b) Keep the local version of the branch being synced (`new-features` or, unexpectedly, `main`).
c) Combine both, with a concrete proposal when technically feasible.
d) Abort with `git merge --abort`, undoing the merge and applying nothing.

Wait for the user's choice. For (d), abort the active merge and report that this merge applied nothing; distinguish any earlier fast-forward or approved commit that remains on the branch. For (a), (b), or (c), apply only the chosen resolution, stage it, and follow the root `AGENTS.md` checkpoint: show the staged file list, staged stat, and complete staged diff, then wait for explicit approval before `git commit`. Use an English merge message and no AI signature. Push the branch being synced after the commit. If the conflict arose while syncing `main`, do not push `new-features` in its place. Continue the remaining update workflow only after the conflict is resolved or aborted as the user chose.

If the interaction is complex or uncertain, use exactly one read-only `deep_reviewer` with only relevant context before recommending. Do not use a reviewer for a no-op, clean merge without overlap, mechanical classification, or routine installation.
