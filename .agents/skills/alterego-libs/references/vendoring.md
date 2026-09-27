# Why `Libs/` is committed on `new-features`

Upstream ignores `Libs/` because its official release packager fetches third-party libraries, including Ace3, LibStub, and LiqUI, at build time. An upstream source clone or GitHub ZIP, including the fork's `main`, lacks those files and will not load as an addon by itself.

The fork installs directly from a GitHub ZIP of `new-features`, so this branch commits `Libs/` as static files. Its `.gitignore` must not ignore `Libs/`, and the committed directory must not be deleted as cleanup. `main` continues to match upstream's ignore rule. Upstream does not normally touch these paths, so merging `upstream/main` into `new-features` does not remove the vendored files.

`.pkgmeta` declares the exact upstream library sources and pins. `.pkgmeta-lock.json` records the versions last vendored, and `scripts/check_lib_updates.py` compares them. `.pkgmeta-cache/` is only a local diff aid and stays ignored. A change to upstream's `.pkgmeta` becomes visible to this branch's checker after the update workflow merges `upstream/main` into `new-features`; the checker does not read remote `.pkgmeta` directly.
