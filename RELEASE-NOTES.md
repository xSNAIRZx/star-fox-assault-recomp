# Unreleased — 2026-11-04 controls and correctness checks

- Honor CPU-local FPSCR NI result flushing, preserving signed zero; correct
  paired-sum result flags and preserve copied lanes. Regression coverage includes
  a tiny-vector normalization failure mechanism. The recorded boss encounter is
  still the required gameplay gate; this is not a confirmed boss fix yet.
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

# Source-only Windows capture tooling

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

These launcher changes are in the repository but not in the rc.3 archive; they need a Windows
repackaging run before they reach a download.

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
