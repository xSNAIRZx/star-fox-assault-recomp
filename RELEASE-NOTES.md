# 0.2.0-rc.5 - Windows x64 source-build release candidate

Experimental prerelease, not a stable full-game release. The headline is a crash fix: the
native build crashed on the third load of a mission (after retrying it twice). Also new:
RecompLauncher support (with its `--play` mode fixed), faster launcher pages, an always-on
session summary in each session's log for bug reports, and the housekeeping below.

Checks on this package: archive extraction, per-file SHA-256, forbidden-content and asset
allowlists, packaged PowerShell parsing, and the update install, rollback, traversal, hash,
unknown-document and moved-`VALIDATION.md` tests. A fresh extract with an empty build cache
built the game through RecompLauncher's `--prepare` mode (tools unpacked after SHA-256
checks, SDL built from source, 7,690 functions recompiled, 104 compile steps, no errors), and
that freshly built game then ran the scripted first mission for 25 minutes unpaced: eight
mission loads, no crash. The tool archives were copied in from an earlier download rather
than fetched again; SDL's source was fetched. The launcher window's own Import & Build was
not used for this, and nothing was played by hand.

Known issues: the first-boss visibility fix still needs live confirmation through the boss
fight; the reported current-thread-pointer crash has not reproduced in any test run, before
or after the mission-reload fix; later missions, mission completion, complete audio fidelity
and physical controllers remain unverified. Updating from rc.4 or earlier with the launcher's
Install Local ZIP is refused (those installers do not know `recomplauncher.json`): extract
rc.5 into a fresh folder and copy your old `user-data` folder into it.

## 2026-11-11 mission-retry crash fixed

- **Fixed a crash on the third load of a mission** (for example after losing all lives twice
  and retrying). The game loads each mission's code module again on every attempt; on the
  third load the native build kept using the previous attempt's freed memory and crashed
  shortly after the mission started. Checked with a scripted 40-minute run that loads the
  first mission five times: no crash, and the later attempts play normally.
- **RecompLauncher fixes:** `--play` refused every start as "built from a different copy":
  it compared the image's write time through a floating-point number, which cannot hold the
  60-bit value exactly. It now reads it as an exact integer and starts the game. `--play` also
  refuses to start a second copy while the game is running (exit code 6, explained in
  `recomplauncher.json`), since two copies would write the same memory card, and prunes old
  session logs the way the Peregrine Forge launcher does.
- The replacement system fonts are pinned to their upstream source: byte-identical to Dolphin's
  `Data/Sys/GC` files at commit `0f1ce0e1f42a`, recorded with their SHA-256 in
  `THIRD_PARTY_NOTICES.md`.
- Every desktop session writes `[session]` lines to its stdout log: machine, power source,
  OpenGL renderer, shader cache, display settings, and every 30 s plus at exit the frame rate
  and frame-time percentiles. A player's attached log now says enough to diagnose speed
  reports (see `runtime/docs/diagnostics.md`).
- `GCN_REL_TRACE=1` prints every code-module load the runtime sees and reports a module that
  is still running after its memory was reused (for diagnosing similar reports).

## RecompLauncher support

- Packages carry `recomplauncher.json` at the top, so [RecompLauncher](https://recomplauncher.com)
  can set the game up from the player's own USA disc image, show its graphics, audio and
  controller options on the game's page, and start it. Its setup step runs the same build
  worker as Import & Build, and saves, logs and the build record stay under `user-data/`,
  so Peregrine Forge and RecompLauncher share them.
- The launcher exe has two windowless modes for this, used only when RecompLauncher passes
  them: `--prepare --game <image>` (builds and prints progress lines) and
  `--play --game <image>` (starts the native build the way Play Native does). Opening the exe
  without arguments opens Peregrine Forge as before.
- The update installer accepts `recomplauncher.json`. Installers from rc.4 and earlier don't,
  so they refuse a package that contains it: extract that package fresh instead (keep `user-data`).

## 2026-11-07 repository housekeeping

- The launcher exe (`Star Fox Assault Recomp.exe`) is no longer stored in Git. Packages and
  CI artifacts still include it: the packager builds it from `tools/LauncherBootstrap.cs`.
  In a source checkout, run `tools/Build-Launcher.ps1` or open `Start-StarFoxAssault.cmd`.
- The update installer accepts a package whose `VALIDATION.md` is under `docs/`, so a later
  release can move it without stopping updates from this one.
- The launcher stays in PowerShell. Its native-build status and save-backup logic moved into
  `tools/LauncherNative.ps1` and `tools/LauncherSaves.ps1`, with tests for every rebuild
  reason, launch-image matching, game-process matching and backup naming and metadata (182
  launcher core tests). The window looks and behaves as before.
- Each launcher page is now its own file under `tools/LauncherPages/`; the main script went
  from about 2,180 to about 1,290 lines. The same 71 functions exist with unchanged text,
  and all seven pages were opened in the window after the move.
- Switching launcher pages is 3-5x faster: 170-260 ms (Systems & Controls 350-470 ms) instead
  of 440-1,380 ms. The page is rebuilt while hidden, with window redraw paused, so the old page
  stays on screen until the new one is ready.
- Resizing or maximizing the window lays the current page out again for the new size once the
  resize settles (not Systems & Controls while it has unsaved changes).
- The game's session command line and environment are built by tested functions in
  `tools/LauncherNative.ps1` (210 launcher core tests).

# 0.2.0-rc.4 - Windows x64 source-build release candidate

Experimental prerelease, not a stable full-game release. rc.4 packages everything listed
under the dated headings below and the "Source changes after the rc.3 package" section:
launcher polish and keyboard/controller navigation, the build pre-flight and readable build
failures, the faster native builder, optional HD enhancements (anisotropic filtering, PNG/DDS
and Dolphin-named texture packs, soft particles), presets, Crash Reports bundles and an
update installer that skips unknown documentation instead of failing.

The package was checked as an archive (extraction, per-file SHA-256, content and asset
allowlists, PowerShell parsing) and with the update install, rollback, traversal, hash and
unknown-document tests. It was not launched through the launcher UI with a game image. On the
tested machine the native game built from this source, and a diagnostic build ran 60,000 frames
of scripted first-mission input and attract loop before ending in a module-reload fault (see
VALIDATION.md). The first-boss visibility issue and the current-thread-pointer crash remain
unresolved, and that module-reload fault is open. Mission
completion, later missions, complete audio fidelity and physical controllers remain unverified.

## 2026-11-05 DDS packs, updater, crash hunting

- **DDS texture packs**: BC1, BC2, BC3 and BC7 DDS replacements (Dolphin's usual
  format) are uploaded to the GPU compressed, with the file's own mip levels; Mod
  Library installs them. A GPU without S3TC/BPTC keeps the original textures.
  Checked in game with a BC1 pack on the opening screen.
- **Updater**: a package's documentation files this installer has no rule for are
  checked against the manifest and skipped instead of stopping the whole update, and
  `docs/` is accepted. Installers already shipped (rc.2, rc.3) still reject new paths,
  so the repository layout stays as it is until rc.4 is out.
- Choosing another texture pack clears the replacements loaded from the last one.
- **Crash hunting**: `GCN_THREAD_WATCH_BAD=1` makes a diagnostic build report only
  bad current-thread-pointer stores, so long scripted runs keep full speed.

## 2026-11-05 polish, Dolphin packs, navigation

- **Dolphin HD texture packs** load in the native build: Dolphin's `tex1_` names are
  matched (XXH64 texel and palette hashes, `$` wildcards, `_m`), any whole-number
  scale is accepted, and Mod Library installs a Dolphin pack ZIP as it is. Checked
  against Dolphin's own dump: all 4 paletted textures it dumped had the same names.
  DDS packs are not supported yet (PNG only).
- **Presets**: Original, HD and Widescreen buttons in Systems & Controls.
- **Crash Reports** marks sessions with guard, vertex-check, thread-watch or fatal
  lines, shows the line, and saves a report bundle with private paths replaced.
- **Keyboard and controller**: visible focus on every button, page shortcuts
  (Ctrl+PageUp/PageDown, Ctrl+Tab, Ctrl+1-7), Esc on dialogs, and XInput pad
  navigation (D-pad/stick, A, B, LB/RB) while the launcher is in front.
- Build dialog: themed progress bar; the worker's failure line is no longer repeated
  in the error list. Controller mapping dialog: no overlapping text, Cancel beside
  Save, an empty-list message, and the launcher icon.
- Builder log: a long step's output is written once (it looked like CMake configured
  twice; it did not).
- Not reachable by scripted input from a fresh save: a ground level (VS mode needs a
  second pad), so anisotropic filtering and soft particles remain unchecked there.

## 2026-11-05 HD enhancements

All off by default; Systems & Controls has an HD Enhancements section and an
"Apply HD preset" button (4x resolution, 16x anisotropic filtering, trilinear, sharp).

- **Anisotropic filtering** (`--anisotropy=2|4|8|16`) and **trilinear mips**
  (`--trilinear=1`) for textures the game already filters linearly with mip levels.
  They act where a surface is seen at a slant and minified; in the first mission's
  space battle (ships near the camera, no ground) captures changed by under 0.1% of
  pixels. Not yet checked on a ground or interior scene.
- **HD texture packs** (`--texture-pack=DIR`, `--texture-dump=DIR`). Mod Library can
  dump the game's textures while playing (`user-data\texture-dump`, named by content
  hash) and install a pack ZIP of `<hash>.png` replacements at 2, 4 or 8 times the
  original size (`user-data\hd-textures`, previous pack kept). Replacements of any
  other shape are refused with a logged reason. Textures the game rewrites every frame
  (movies) are not dumped. No pack is included: game textures are not redistributable,
  so packs are made from your own dump.
- **Soft particles (experimental)** (`--soft-particles=1`): additive effects fade where
  they meet geometry behind them. In the space battle this mostly dims glow cards laid
  across the ships' hulls, so it is not part of the HD preset.
- Higher polygon counts are not possible from the renderer: the models are the game's
  own data. Verified in the first mission with the same scripted input: a marked test
  pack replaced 115 of 117 textures with correct mapping; no frame took over 50 ms in
  any variant.

## 2026-11-05 native builder

Measured on a 16-core/32-thread desktop with the cached SDL2 and build tools:

| Build | Before | After |
| --- | --- | --- |
| Fresh build folder | 54.7 s (8 compile jobs) | 35.4 s (30 jobs, chosen automatically) |
| After editing one runtime source | 9.7 s (full re-configure) | 3.9 s (Ninja recompiles that file) |
| Nothing changed | 3.1 s | 3.1 s |

- Compile jobs now default to the hardware threads less two, limited by free memory at
  about 512 MB per job (the largest recompiled file peaked near 200 MB) and capped at 32.
  `-Jobs N` still overrides it.
- Only configure inputs (build scripts, CMake files, the recompiler and its tables) decide
  whether CMake re-configures and regenerates the game code. Runtime C/C++ and shader
  edits are left to Ninja. The full source fingerprint is still recorded in
  `native-build-info.json`.
- Fix an intermittent "Cannot index into a null array" failure on short incremental
  builds, caused by matching Ninja's progress line against an array.
- Progress-file updates retry when the launcher has the file open, instead of risking
  a sharing-violation failure mid-build; the final state must still be written.
- "Close the running game" checks only this project's `assault.exe`, not any process
  with that name, matching the launcher.

## 2026-11-05 launcher polish

- Fix Systems & Controls crashing on open ("op_Subtraction") so no settings
  appeared: two divider widths were parsed as `Width - (50,1)`.
- The launcher is now DPI-aware, so text is sharp at 125%/150% display scaling
  instead of a stretched 96-DPI bitmap. Pages, the sidebar and the build and
  controller-mapping dialogs are laid out in 96-DPI units and scaled once.
- Labels with "&" (Systems & Controls, Import & Build, Picture & Display, ...)
  show it instead of a gap.
- Every page fits the 1180×720 minimum window without a horizontal scrollbar;
  Crash Reports and Mod Library fit without scrolling at all.
- Empty lists say so (crash logs, backups, texture packs); the crash-log message
  was hidden behind its list before. Disabled buttons stay readable.
- Page headings sit on a dark band over the artwork; the Save Archive note moved
  into its card; the home title no longer sits on solid black boxes.
- Page titles match the sidebar names. The sidebar status box sits under its
  heading and starts as "Ready".
- Systems & Controls: Save is in the page header, edits show "Unsaved changes",
  and leaving with unsaved edits asks to save, discard or stay. Notes sit under
  the setting they describe; volume is a dark dropdown.
- About shows the version from `release.json` and the current known limitations.
- Scrollbars are still the light Windows default.

## 2026-11-05 launcher build flow and settings

- Import & Build first checks free disk space (3 GB), that the launcher folder is
  writable, that the tool download hosts are reachable when tools are not yet
  cached, and warns about long folder paths when Windows long paths are off.
- A failed build now names the stage that failed and its first error lines, with
  Open log, Copy report (private paths replaced) and Open job folder buttons.
- The build dialog shows elapsed time for the current phase and the whole build,
  and tool downloads report megabytes received. Step 2 (preparing tools) now shows
  its step number; the toolchain script's phase name was not recognised before.
- Profile settings are defined once (type, default, allowed values) in
  `tools/LauncherCore.ps1` and used by the loader, the Settings page and the
  native arguments. `tools/Test-LauncherCore.ps1` covers that logic in host checks.
- Not yet checked in the launcher window on a desktop with a real build: the
  pre-flight dialog, the failure view and the download progress text.

## 2026-11-04 controls and correctness checks

- Honor CPU-local FPSCR NI result flushing, preserving signed zero; correct
  paired-sum result flags and preserve copied lanes. Regression coverage includes
  a tiny-vector normalization failure mechanism. The recorded boss encounter is
  still the required gameplay gate; this is not a confirmed boss fix yet.
- The combined arithmetic candidate now passes the recorded boss-disappearance
  replay: a visible boss and finite object state replace the baseline infinities
  and NaNs. Fresh live confirmation and boss completion are paused/pending; no
  full-game release claim is made.
- Restore the second packed single-precision PSF context lane correctly, while
  keeping PS0's dedicated double-precision value. This is a tested context-reader
  correction, not a verified fix for the reported pointer crash.

- WASD movement with independent mouse Aim (C-stick), F9 capture/release and F10
  Flight steering. Captured Aim-mode left-click sends R for the game's Dual-Stick
  on-foot controls; released-mouse/Flight left-click sends A. Mode/capture status
  appears in the window title. WASD no longer triggers unrelated action buttons.
- Floating compares now update FPSCR FPCC as well as CR; `mulli` uses defined
  modulo arithmetic rather than relying on the host compiler's overflow behavior.
- Invalid/overflowing z-freeze depth planes leave the previous valid plane intact.
- Smoke checks retain numeric exit codes, isolate diagnostics and reject premature
  exits even when the child exits 0. Capture logs permit live reading and explicit
  scripted navigation/host-key logging; scripts remain absent unless requested.
- These source fixes have synthetic regression coverage. They do not establish
  that the disappearing boss or current-thread-pointer failure is repaired.

## Source-only Windows capture tooling

- Added `tools/Capture-Gameplay.ps1` and `runtime/docs/gameplay-capture.md` for isolated
  thread-crash and boss captures, replay copies, selected-frame diagnostics, build
  identity, streamed logs, plan-only inspection and optional bounded startup checks.
- Corrected draw-log frame selection, submitted/presented frame alignment, replay
  instructions and the limits of non-finite vertex checks. Float-like pointer bits
  alone do not identify the store type or writer.
- No gameplay repair or release-asset replacement is included. Both defects remain open.

# 0.2.0-rc.3 - Peregrine Forge Windows x64 source-build release candidate

## Release summary

This is a complete shareable Windows source package, but it is still an experimental prerelease
and not a stable full-game release. It adds the Peregrine Forge name, matching PF icon, updated
credits and local-file ignore rules. The package contains source and host tools; each recipient
supplies their own supported USA GF7E01 game image and builds locally.

The rc.2 build and bounded-startup evidence below was not repeated for rc.3. The first-boss
visibility issue and current-thread-pointer crash remain unresolved; mission completion, later
missions, complete audio fidelity and all physical controllers remain unverified. No trademark
registration or official affiliation is claimed.

The rc.3 ZIP contains 243 payload files, uses portable forward-slash paths, and passed extraction,
per-file SHA-256, content-safety, asset-allowlist and PowerShell parser checks. The adjacent `.zip.sha256`
sidecar records its archive checksum.

### Stick deadzone for the built-in controller path

`--deadzone=<percent>` (0 to 40) is new, and Settings exposes it as **Stick deadzone**. It
shapes the built-in controller sticks with one radial deadzone and spreads the travel past it
across the full range, so a diagonal push needs the same travel as a straight one and leaving
the zone is a small step rather than a jump the size of the threshold. A controls.txt binding
keeps its own `deadzone` for the pads it names, and **Runtime default** leaves the previous
per-axis thresholds exactly as they were.

### Launcher tool audit

Native asset packs now use the portable Python that Import & Build already downloads and
verifies, so importing a pack no longer depends on a separate Python install. The package and
updater required-file lists now name every launcher script and recompiler module they read, and
`tools/Test-LauncherTools.ps1` fails when a referenced tool is missing or no packaging rule
ships it.

## Source changes after the rc.3 package

These launcher changes were not in the rc.3 archive; rc.4 is the first package that includes
them.

- The status line now starts after the navigation row and is sized to the space actually free,
  so it no longer sits on top of the About button at the minimum window size. Long messages are
  ellipsized with the complete text available as a tooltip, so build and game-image errors can
  be read instead of being cut off at a fixed width.
- The Play page reports BUILD honestly: red for NOT BUILT, cyan for UPDATE AVAILABLE and green
  only for CURRENT, instead of green in every case.
- Settings are written to a temporary file beside the profile and swapped in, with a plain copy
  kept as a fallback for folders whose volume does not support `File.Replace`. An interrupted
  save therefore leaves the previous settings readable instead of truncating them, and a profile
  whose volume value is not a number opens with the default volume rather than stopping the
  launcher before its window appears.
- Two widgets that were created but never placed on any page were removed.
- Native build metadata now records the selected image path, size, modification time and SHA-256.
  The launcher refuses to play if the selected image no longer matches that build record or the
  executable hash has changed; builds also reject an image that changes while compiling.
- Save restore verifies recorded backup hashes and installs a checked temporary copy atomically,
  preserving the live card if the source is invalid or the copy is interrupted.
- Texture-pack extraction now limits ZIP entry count and expanded data to reduce resource-exhaustion
  risks, and checks actual extracted bytes against the ZIP declarations.
- The settings chooser now lists only ISO/CISO formats accepted by the image inspector. Launcher
  typography can scale below 10 pt and a narrow viewport scrolls the existing page layout instead
  of forcing the content panel itself to be 880 pixels wide.
- Native sessions now enable the runtime's clock diagnostics. They add guest-time, host-time,
  presented-frame, work-per-frame and audio-frame lines to the session error log; they are intended
  to diagnose reported speed differences, not to claim that the game-speed issue is fixed.
- The source packager now includes the launcher font file it already required, and the update
  installer accepts the packaged PowerShell data manifest. A fresh local package and its safe
  install/rollback checks passed; this local audit package is not a published release.

## rc.2 diagnostics and validation baseline

The launcher branding and code-source changes are described above. The analysis below is retained
as earlier evidence for the build pipeline and runtime; it does not establish full-game compatibility.

The current-thread crash trace now has an explanation to test. `0x80136C60` lies inside
`fn_80136C44`, and the reported address `0x3F0002C8` is `0x2C8` past `0x3F000000` — the float
`0.5f` — in the word the SDK loads as the current-thread pointer, so a float was stored over a
pointer. `GCN_GUARD` now watches a list of words and says so when a watched pointer word stops
being one, and the launcher enables it for `0x800000E4` on every native session, so the next run
that fails carries the frame and both values in its own log. See `VALIDATION.md` for the analysis
and the capture that is still missing.

This candidate includes image-hash and build-worker-input fingerprinting so a changed image or build script invalidates stale build state. The launcher reports the image-check step and verifies the worker's completion status. The packaged rc.2 launcher completed a fresh empty-cache online build and bounded startup, described below. This verifies first-use build and startup only; it does not establish full-game compatibility.

## Empty-cache online build and startup

The actual rc.2 package was extracted into a Unicode-named folder without a tool, SDL or game build cache. Using a plain ISO path with spaces and an apostrophe, the launcher downloaded and verified all four pinned tool archives, fetched and built SDL, compiled the native executable in about 150 seconds, then launched it. The ISO image was recognized read-only. Windows-only PATH was used and preexisting launcher settings remained unchanged. The resulting executable was 42,158,080 bytes (SHA-256 `CA32F4644F6318C976DA3DC80FB49350BD5143598481CB039A2812322DF9188C`).

A hidden, silent, normal-speed startup survived its 10-second bound and rendered the health-and-safety screen with readable text. The harness intentionally terminated at the time limit using an isolated test save. This is not a clean-exit, gameplay, or full-game stability claim.

## Earlier empty-cache baseline from rc.1

The rc.1 source-only ZIP (`66EB3A3BF6987CC465073CD30670289BBB9734404722B58DB1C589C31D8F425E`) was extracted into a Unicode-named folder without a tool cache or native game executable. The actual launcher **Import & Build** flow downloaded and SHA-256-verified all four pinned tool archives, fetched and built SDL, compiled 101 Ninja units, and produced the native executable in about 147 seconds. A subsequent hidden, normal-speed boot survived its 10-second time limit and rendered the safety-screen text. The harness intentionally ended the boot at its time bound; this does not establish full-game stability. The run used an isolated test save.

## Candidate scope and limits

The shareable package contains the launcher, runtime/recompiler source, analysis metadata and a standalone image inspector. It does not contain a game image or a precompiled game executable. Select your own USA GF7E01 ISO/CISO, choose **Import & Build**, then use **Play Native** after the local build completes.

The first build downloads a pinned portable compiler, CMake, Ninja, Python and SDL source. It requires internet access and several GB of writable disk space. Windows 10 version 1903 or newer and an OpenGL 3.3-capable driver are required. No administrator installation, Dolphin installation or manually installed compiler is required. Subsequent builds reuse the local cache.

Settings, saves, build caches and logs are kept under `user-data/` in portable mode. Updates preserve these files and a recipient's locally built executable.

Known limits: first-mission flight and profile persistence have been tested. Mission completion, the reported disappearing first boss, the invalid-current-thread-pointer crash, later missions, full audio fidelity and all physical controllers are not yet verified. Widescreen is experimental. This is not a stable full-game release.

The launcher includes graphics settings, controller mapping, save backups, local asset-pack support, local package updates and optional Dolphin fallback. Online update/mod services are not implemented. Branding/icon/credits do not imply official affiliation or trademark registration.

## 0.2.0-rc.1 baseline

The shareable package contains the launcher, runtime/recompiler source, analysis metadata and a standalone image inspector. It does not contain a game image or a precompiled game executable. Select your own USA GF7E01 ISO/CISO, choose **Import & Build**, then use **Play Native** after the local build completes.

The first build downloads a pinned portable compiler, CMake, Ninja, Python and SDL source. It requires internet access and several GB of writable disk space. Windows 10 version 1903 or newer and an OpenGL 3.3-capable driver are required. No administrator installation, Dolphin installation or manually installed compiler is required. A source-only extracted package passed the real launcher Import & Build flow with Windows-only PATH, fresh tool extraction and a fresh native build cache; its tool archives and SDL SDK were seeded from the separately verified online setup. A bounded hidden boot loaded both fonts from the Unicode installation path. Subsequent builds reuse the local cache.

Settings, saves, build caches and logs are kept under `user-data/` in portable mode. Updates preserve these files and a recipient's locally built executable.

Known limits: first-mission flight and profile persistence have been tested. Mission completion, the reported disappearing first boss, the invalid-current-thread-pointer crash, later missions, full audio fidelity and all physical controllers are not yet verified. Widescreen is experimental. This is not a stable full-game release.

The launcher includes graphics settings, controller mapping, save backups, local asset-pack support, local package updates and optional Dolphin fallback. Online update/mod services are not implemented. Branding/icon/credits do not imply official affiliation or trademark registration.
