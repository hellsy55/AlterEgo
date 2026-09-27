---
name: alterego-install
description: Install AlterEgo after the update or PR install-menu choice by running the existing PowerShell installer in the current session.
---

# Install from GitHub

Read [installation mechanics](references/installation-mechanics.md) when the workflow reaches the install stage. Offer the menu in Portuguese if the user has not already chosen: (a) run the addon update now, or (b) stop without installing. An earlier choice of (a) is sufficient authorization; run immediately without a second confirmation.

Run the existing script directly in the current Codex session, waiting for completion:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\AlterEgo\atualizar-alterego.ps1"
```

Do not use `start`, `Start-Process`, or another window. If a UAC prompt appears, tell the user to approve it manually and wait for confirmation before proceeding. Verify and report the final installation result in Portuguese. The source is the GitHub `new-features` ZIP, never local working-tree files.
