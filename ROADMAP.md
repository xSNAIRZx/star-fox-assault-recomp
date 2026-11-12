# Planned updates

Planning baseline: **3 November 2026** · Current experimental release: **0.2.0-rc.5**

The aim is a dependable Windows launcher that builds locally from the user's own USA GF7E01 ISO/CISO, with clear setup, a sharp picture and consistent controls. The stages below describe planned work. They are not promises of delivery dates or claims that the game is fully compatible.

## Current foundation

- The packaged Import & Build flow passed an empty-cache online build and reached the readable safety screen on the tested Windows PC.
- Cancellation, retry, invalid input, corrupt downloads, cached rebuilding and local update protections have been exercised.
- The launcher already exposes internal resolution, aspect ratio, FXAA, output filtering, fullscreen, VSync, volume, a stick
deadzone and controller mapping.
- Native build records now bind a launchable executable to the selected image path and recorded image identity; mismatches require a rebuild.
- Normal launcher-started native sessions write guest-clock and frame pacing diagnostics to their session error log to help separate simulation speed from rendering speed.
- First-mission flight, menus and profile persistence have been tested. Full mission completion and later missions remain unverified. The disappearing first boss and current-thread-pointer crash are open issues.

See [VALIDATION.md](VALIDATION.md) for the evidence and its limits.

## 1. Stabilize the first mission

Use [the Windows capture guide](runtime/docs/gameplay-capture.md) and `tools/Capture-Gameplay.ps1`.
Draw/matrix logs select a presented frame; RAM dumps select submitted frames. Correlate
them using the `[ram] frame ... (presented ...)` line rather than assuming equal counts.

- [ ] Record repeatable steps for the boss disappearing, including when it happens near the screen center,
      with `GCN_VERTCHECK=1`: a `[vertcheck]` line names the frame and draw whose transformed positions
      stopped being finite, and prints the position matrix when it was non-finite. A report
      is not proof that the draw is the boss; no report does not rule out render-state bugs.
- [ ] If no `[vertcheck]` line appears, capture the same window with `GCN_DRAWLOG=<presented-frame>`, `GCN_MTXLOG=<frame>`
      and `GCN_RAM_DUMP_AT=<frame>` for a frame with the boss and one without, so both can be compared.
- [ ] Trace visibility, module state and rendering around the failing encounter; identify the cause before changing behavior.
- [ ] Build a diagnostic build (`tools/Build-StarFoxAssault.ps1 -DiagnosticBuild`) and replay the crashing run
      with `GCN_WATCH_ADDR=800000E4` and `GCN_GUARD=800000E4`: the `[thread-watch]` line names the store that
      writes the invalid word and the `live guest stack` line under it names the code that was running.
- [ ] Trace the corrupted current-thread pointer and fix the responsible memory write or runtime behavior.
- [ ] Capture the guard line and RAM dump from a normal-speed run that reaches the current-thread
      failure, and identify the store that writes the invalid word. A 60,000-frame unpaced diagnostic run
      (2026-11-05, with `GCN_THREAD_WATCH_BAD=1`) did not reproduce it.
- [x] Explain the module-reload fault from the same run: module 12 callbacks still ran after another module
      was linked over its `.bss` (VALIDATION.md, 2026-11-05). Fixed 2026-11-11: a module linked again at an
      earlier copy's header kept the earlier section bases; the runtime now re-reads them. Checked over five
      mission loads (VALIDATION.md, 2026-11-11).
- [ ] Complete the first mission at normal speed, including the boss, transition and save/reload, without the reported failures.

**Evidence so far:** the saved trace resolves to `0x80136C60` inside `fn_80136C44`, with the
reported address `0x3F0002C8` — `0x2C8` past `0x3F000000`, the float `0.5f` — in the word the
SDK loads as the current-thread pointer. The pointer contained float-like bits; the writer and store type are not
yet identified, and the boss has no recording that matches its evidence. Neither defect has
been reproduced or fixed. The capture paths for both are now in the runtime: `GCN_VERTCHECK`
names a draw whose transformed positions stopped being finite, and every guard or store line
carries the live guest stack under it.

**Completion evidence:** repeatable before/after checks, the settings and build used, a completed mission run and targeted regression checks for the fixes.

## 2. Improve graphics confidence

- [ ] Compare original 4:3 and experimental 16:9 in flight, on foot, during the boss encounter and in menus.
- [ ] Resolve game-specific widescreen visibility and composition problems; check HUD proportions and stretched elements.
- [ ] Check supported internal resolutions, FXAA, Sharp/Smooth filtering, fullscreen and VSync on more than one GPU.
- [ ] Document practical presets with honest image-quality and performance tradeoffs.

**Completion evidence:** matching scene comparisons, recorded display settings and a list of remaining limitations. Original textures are still original textures; higher resolution alone does not replace them.

## 3. Validate controls and audio

- Keyboard and mouse gameplay defaults are implemented, including optional F9 mouse steering; live input verification remains open.
- The Windows runtime test build now copies its C++ DLL dependencies beside test executables.

- [ ] Test physical Xbox-style and PlayStation-style controllers, keyboard mapping, dead zones and reconnect behavior.
- [ ] Check control prompts and navigation through setup, menus, gameplay and relaunch.
- [ ] Check music, effects, cutscene audio, volume and mute behavior over longer play sessions.

**Completion evidence:** a tested-device list and mission-by-mission audio/control notes, including any remaining failures.

## 4. Refine the launcher

- [ ] Review font hierarchy, spacing, artwork placement and text clipping at the minimum and default window sizes and common Windows display scales.
- [ ] Make first import, build progress, cancellation, errors and recovery easier to understand.
- [ ] Check keyboard navigation, focus visibility, controller setup, save management and credits for consistency.

**Completion evidence:** updated launcher captures and successful walkthroughs using an isolated new profile and an existing profile.

## 5. Widen testing and prepare the next release

- [ ] Expand coverage to later missions, transitions, save/reload and longer normal-speed sessions.
- [ ] Repeat setup on additional Windows PCs with no preinstalled compiler or populated tool cache.
- [ ] Recheck offline rebuilds, cancellation, failed builds, update rollback and save preservation.
- [ ] Audit the release contents and checksums, publish validation notes and clearly list unresolved issues.

**Completion evidence:** reproducible setup results and a compatibility matrix. Keep releases experimental until broader gameplay evidence supports a different status.

## Longer-term ideas

These need separate design and feasibility work after the core experience improves: additional image revisions, broader platform support, a richer asset-pack workflow and an online update service. They are not supported features or scheduled releases.

## Help with testing

Use [GitHub Issues](https://github.com/xSNAIRZx/star-fox-assault-recomp/issues) to report a problem. Include the release version, Windows version, GPU, controller if relevant, mission/checkpoint, graphics settings, and steps to reproduce. A cropped screenshot can help explain a visual issue. Do not attach your game image, extracted game files, saves or unreviewed diagnostic bundles; remove personal paths from any excerpts you choose to share.
