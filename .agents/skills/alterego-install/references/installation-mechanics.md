# Installation mechanics and invariants

This mechanism applies only to the local Windows host with the existing installer and WoW AddOns directory. Cloud/Linux cannot perform physical installation and must not invoke this script. Do not assume Administrator privileges. The existing PowerShell script lives outside the repository at `C:\Users\jonat\Desktop\AlterEgo\atualizar-alterego.ps1`. Retail's AddOns directory is `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`. Run the script directly in the current session and wait; a separate window has previously hung.

The script must:

1. Download a fresh ZIP from `https://github.com/hellsy55/AlterEgo/archive/refs/heads/new-features.zip`, then extract it into a temporary directory. This source comes from the pushed branch, regardless of local uncommitted state.
2. Strip `@debug@` through `@end-debug@` packager blocks from every `.lua`, `.toc`, and `.xml` file. The raw `AlterEgo.toc` names development-only `Debug\Types\*.lua` files; without block stripping, the later removal of `Debug` leaves broken file references and the addon fails to load. Replace `@project-version@` in the `.toc` with a readable local version string; this is cosmetic.
3. Remove root dotfiles and dot-directories such as `.agents`, `.codex`, `.github`, `.gitignore`, `.editorconfig`, `.luarc.json`, `.wowluarc.json`, and `.pkgmeta`, along with `Debug`, `scripts`, and `AGENTS.md` (agent metadata/infrastructure). Keep `Libs`, `Data`, `Media`, `Modules`, root `.lua` files, `AlterEgo.toc`, `Bindings.xml`, and ordinary `.md` documentation, matching a normal addon folder. `Libs/` is already committed in `new-features`; do not fetch or merge it separately.
4. Rename the extracted `AlterEgo-new-features` folder to `AlterEgo`, remove any existing `AlterEgo` folder in AddOns, and move the cleaned folder there.

Use this reference to understand or diagnose the script, not to re-explain every step in routine completion reports. If an unexpected UAC prompt appears, ask the user to approve that prompt and wait for confirmation. Report a verified success or a pending failure; do not infer success merely because the process started.
