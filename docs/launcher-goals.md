# Launcher improvement goals

Status as of 2026-11-05. Working list for the Peregrine Forge launcher (`Launch-StarFoxAssault.ps1` and its tools). Gameplay blockers (first-boss visibility, current-thread pointer) are tracked in [ROADMAP.md](../ROADMAP.md) and [VALIDATION.md](../VALIDATION.md), not here. Follow [AGENTS.md](../AGENTS.md) for publishing rules.

Tick items here as they land, in the same PR as the change.

## Where things stand

- **Done:** Tier 1 reliability fixes, heading-font fallback and a GitHub bug-report form ([PR #1](https://github.com/xSNAIRZx/star-fox-assault-recomp/pull/1)). CI now keeps the launcher exe, image inspector and host-check ZIP with SHA-256 as a 30-day workflow artifact ([PR #2](https://github.com/xSNAIRZx/star-fox-assault-recomp/pull/2)).
- **Not yet verified on a desktop:** PR #1 passed hosted Windows CI (PowerShell 5.1 parse, 110-path launcher audit, update tests) but the launcher window itself has not been opened with these changes. Check before calling them verified: switch pages; install a local ZIP (window stays responsive); corrupt `settings.json` once (expect a status notice and a `settings.corrupt-*.json` copy); launch with a controls file in a path containing spaces.
- **Also done, 2026-11-05:** build pre-flight, readable build failures, phase timing and download sizes (Tier 2), and the single settings schema in `tools/LauncherCore.ps1` with its tests (Tier 3). The launcher window starts with these changes; the pre-flight dialog, failure view and download text still need a desktop check with a real build.
- **Also done, 2026-11-05 (polish):** fixed the Systems & Controls crash on open, DPI awareness with scaled layout, "&" in labels, minimum-size fit, empty states, readable disabled buttons, header bands, matching page names, Settings save/unsaved handling and refreshed About text. See RELEASE-NOTES.md.
- **Done, 2026-11-05:** rc.4 published as an experimental prerelease with its package digest. The desktop and clean-machine UI walkthroughs below are still open.
- **Also done, 2026-11-07:** the launcher exe is no longer tracked in Git (the packager builds it from source), and the update installer accepts `VALIDATION.md` at the root or under `docs/`, the first step of the root tidy.
- **Next:** decide C# vs PowerShell (step 3 of the order below).
- **Open decision:** keep the launcher UI in PowerShell or port it to C#. Decide before the Tier 3 module split.

## What the launcher is today

One ~1,860-line PowerShell 5.1 + WinForms script behind a small C# bootstrap exe (`tools/LauncherBootstrap.cs`). Seven pages: Flight Deck, Game Library, Save Archive, Mod Library, Crash Reports, Systems & Controls, About.

Already solid: atomic settings writes, build-to-image identity binding, SHA-256-pinned portable toolchain, cancellable build worker with a progress file, previous-exe retention, checksum-verified save restore, capped texture-pack import, the launcher path audit and package allowlists.

Main weak spots: every control is placed with absolute coordinates (now in 96-DPI units scaled to the display, checked at 125% and the 1180×720 minimum); switching pages disposes and rebuilds every control; scrollbars use the light Windows default.

## Tier 1 — Correctness and reliability

- [x] Run the local ZIP update installer as a background process (`-ResultPath` result file), not on the UI thread. Builds and updates refuse to overlap.
- [x] Track the current page in `$script:currentPage` instead of comparing nav-button colours.
- [x] Keep an unreadable `settings.json` as `settings.corrupt-<time>.json` and say so, instead of silently resetting.
- [x] Set session `GCN_*` variables through one save/restore helper (`Invoke-WithProcessEnvironment`). Start-Process is kept so game output still goes straight to files.
- [x] Quote `--controls=` and the disc path with `ConvertTo-NativeArgument`.
- [x] Treat only this project's `assault.exe` as the running game (`Get-RunningNativeGame`, matched by path; an unreadable path still counts as running).
- [x] Keep the newest 20 session logs plus up to 20 older sessions flagged with `[guard]`, `[vertcheck]`, `[thread-watch]` or `fatal`.
- [x] Report `REBUILD REQUIRED` with a reason instead of `UPDATE AVAILABLE`.
- [x] Cache the recursive source-freshness scan per session; reset after a build or package install.

## Tier 2 — UX and first run

- [x] Pre-flight check before Import & Build: free disk (blocks under 3 GB, as the build worker would fail), writable folder, download-host reachability when tools are not cached, path-length warning when Windows long paths are off.
- [x] Readable build failures: show the failing stage and first errors from the worker's `stdout.log`/`stderr.log`, with Open log, Copy report (paths redacted) and Open job folder buttons.
- [x] Show elapsed time per phase and MB downloaded in the build dialog.
- [ ] One-click controller binding ("press the button for A now") with a live test view, replacing detect → close → reload.
- [ ] Visually verify every page at 100%, 125% and 150% scaling and at 1180×720. Done at 125% for the default window and 1180×720 (2026-11-05); 100% and 150% are still unchecked.
- [x] Fall back to Segoe UI Semibold when Bahnschrift is not installed.
- [x] Keyboard and controller navigation: focus cues on every button, Ctrl+PageUp/PageDown (or Ctrl+Tab) and Ctrl+1-7 for pages, Enter/Esc on dialogs, XInput pad (D-pad/stick moves focus, A presses, B back, LB/RB pages). Pad not yet tried with a physical controller.
- [x] Crash Reports: flag sessions with `[guard]`/`[vertcheck]`/`[thread-watch]`/fatal lines, show the line, and save a redacted report bundle (no paths, saves or RAM) for an issue.
- [x] Settings presets: Original (4:3, 2x, sharp, no AA or enhancements), HD (4x, 16x anisotropic, trilinear, sharp), Widescreen (HD at 16:9). Matches ROADMAP item 2.

## Tier 3 — Architecture and maintainability

- [ ] Decide PowerShell vs C# for the launcher UI. C# (WinForms or WPF on .NET Framework 4.8) gives async/await, data binding, faster startup and a debugger; keep the build worker in PowerShell.
- [ ] Split the script into modules: settings, native build/status, game launch, one file per page. Logic modules must not touch WinForms.
- [ ] Unit-test the logic modules with Pester (settings round-trip and corruption, status branches, argument escaping, phase-to-percent mapping) and add them to `tools/Test-ReleaseHost.ps1`. Started: `tools/Test-LauncherCore.ps1` (plain PowerShell, since Windows PowerShell 5.1 ships Pester 3.4 and CI has 5.x) covers settings, escaping, phase mapping, pre-flight rules and failure reports and runs in host checks. Native status branches are not covered yet.
- [ ] Replace absolute layout with `TableLayoutPanel`/`FlowLayoutPanel`, anchors and padding. Interim step landed: the process is DPI-aware and each page is laid out in 96-DPI units, then scaled once (`Set-UiScale`); pages still use absolute positions and are rebuilt on each switch.
- [ ] Build each page once and refresh data, instead of disposing and rebuilding on every switch.
- [ ] Replace the hidden `Track-Session.ps1` process with a `Process.Exited` handler or a session record written by the game.
- [x] Define settings defaults and allowed values once, used by both the loader and `Get-NativeGraphicsArguments` (`$LauncherSettingSchema` in `tools/LauncherCore.ps1`; the Settings page reads its value lists from it too).

## Tier 4 — Distribution, trust and release

- [x] Publish rc.4: package current source, run the full checks against that exact ZIP, publish with its digest. Per [RELEASE-READINESS.md](../RELEASE-READINESS.md), rc.2/rc.3 evidence cannot certify it. Published 2026-11-05 as an experimental prerelease; package and update checks ran against the exact ZIP, the launcher UI walkthrough did not.
- [ ] Run the launcher UI end to end on a clean Windows machine or Windows Sandbox: Import & Build, Play Native, cancel, update, rollback, save restore (readiness gate 3).
- [x] Keep CI-built launcher, inspector and package with SHA-256 as a workflow artifact.
- [x] Stop committing `Star Fox Assault Recomp.exe`: attach the CI-built exe to releases instead. The package and updater required-file lists name it at the repo root, so change them together. Done 2026-11-07: it is ignored by Git, `tools/Package-Prototype.ps1` builds it from `tools/LauncherBootstrap.cs` before staging, so packages still ship it at the root (both required-file lists unchanged), and CI keeps the built exe as a workflow artifact. The tool audit checks the bootstrap source instead of the exe.
- [ ] Authenticate updates: sign `release.json` (minisign or a code-signing certificate) and verify before installing a local ZIP.
- [x] Fix the old-updater dead end (older updaters reject new doc paths): skip unknown docs instead of failing, or show a one-time migration note. This installer now skips unknown documentation (still hash-checked) and accepts `docs/`; installers already shipped keep the old rule, so layout changes wait until rc.4 ships it.
- [x] Add a GitHub bug-report form with the roadmap's fields.
- [ ] Tidy the repo root: move `README-PROTOTYPE.txt`, `RELEASE-READINESS.md` and `VALIDATION.md` under `docs/`, updating the package and updater allowlists. Staged because the installers already shipped decide what an update may contain: rc.2-rc.4 require `VALIDATION.md` and `README-PROTOTYPE.txt` at the root, and rc.2/rc.3 reject any `docs/` path. Step 1 (2026-11-07): this installer accepts `VALIDATION.md` at either place. Step 2, after a release ships that installer: move `VALIDATION.md` and `RELEASE-READINESS.md`, and update the package document list and links. Keep `README-PROTOTYPE.txt` at the root (it is the first file a player opens after extracting). An update does not delete the old root copies.
- [ ] Record a pinned upstream source for the replacement font bytes in `THIRD_PARTY_NOTICES.md`.

## Suggested order

1. ~~Quick wins: Tier 1, font fallback, issue form.~~ Done.
2. Ship rc.4: desktop check of the Tier 1 changes, clean-machine UI walkthrough, refreshed package and digest from a CI build.
3. Decide C# vs PowerShell, then the module split and Pester tests.
4. Layout rewrite: layout panels, build-once pages, DPI captures at three scales.
5. First-run polish: pre-flight check, readable build errors, elapsed time and sizes.
6. Player features: controller binding, presets, Crash Reports bundles, couch navigation.
7. Trust: signed updates and the old-updater migration path.
