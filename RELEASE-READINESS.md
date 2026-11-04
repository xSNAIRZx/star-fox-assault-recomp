# Release decision: blocked

Continuation on 2026-11-04 added WASD/mouse controls, tested CPU FPCC and integer
translation corrections, invalid depth-plane rejection, and process-test fixes.
See the dated entry in `VALIDATION.md` and `RELEASE-NOTES.md`. These are source
improvements; neither original gameplay blocker is claimed fixed. Earlier package
digests and smoke results below belong to the earlier candidate, not this changed
runtime. Build and test the changed candidate separately before distribution.

Assessed 2026-11-03 against source baseline
`d46e231a2494d201923b08898f52cf9753abb030` plus the host CI changes accompanying
this document. This is an experimental source-and-host-tools candidate, not a
verified full-game release. No tag, store submission or release upload is authorized
by this assessment.

## Current verification

- A fresh Windows x64 build from a user-supplied GF7E01 CISO succeeded using newly
  downloaded, SHA-256-verified portable tools and a fresh SDL build. The desktop
  build compiled the generated game and native runtime (101 build steps).
- Windows runtime CTest: 13/13 passed, including Unicode paths, disc handling,
  REL rebinding, rendering math, audio gain and diagnostic helpers.
- Windows PowerShell 5.1: all host scripts parse; launcher path audit (110 checks),
  cache-signature tests and synthetic capture orchestration tests passed.
- Invalid-image and pre-cancelled builds failed and preserved the previous executable.
- Launcher C# and standalone image inspector rebuilt. The latter uses warnings as errors.
- Source-only package: 261 payload files passed extracted SHA-256 checks, content/path
  exclusions, asset allowlist and script parsing. Update installation, preservation,
  rollback, traversal rejection and corrupted-payload rejection passed.
- A normal-speed hidden 45-second native smoke run survived its bound. It captured
  21 guest frames and 21 output frames; an inspected output frame showed the Falco
  intro and readable text. It was forcibly terminated after the bound, not a clean
  game exit. Music was disabled and audio used the dummy device. This verifies
  startup/rendering only, not a mission, audio quality or physical controls.
- Native executable SHA-256 for that private run:
  `bc46071d92da11ce96685f230e02853a996a1795823c57416fc972a597f147cd`.

`tools/Test-ReleaseHost.ps1` runs the image-free Windows checks with pinned tools.
It stops on failed child commands and uses CTest's `--no-tests=error`. Run with
`-Offline` after first setup. GitHub Actions runs Windows checks and portable C++
tests on Linux; a local pass is not evidence of a hosted CI pass.

## Reproduce privately

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-ReleaseHost.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Build-StarFoxAssault.ps1 -GameImage 'X:\Your\Assault.ciso' -UsePortableToolchain
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Run-NativeCheck.ps1 -GameImage 'X:\Your\Assault.ciso' -Seconds 45 -DumpEvery 100 -CaptureOutput
```

Tools and SDL have pinned archive hashes. These are repeatable build instructions;
byte-identical independent builds have not been established. ZIP timestamps, C#
compiler output and PE metadata are not normalized. Long checkout paths produced
CMake object-path warnings on this machine but the build succeeded; use a short
writable extraction path. Recompilation also reported six branch-outside-code
warnings; their gameplay implications remain unverified.

Older installed updater scripts reject the newly shipped README, roadmap and release
assessment paths. Upgrade those installations by extracting the entire new source
package into a fresh folder; preserve the old `user-data` privately. The updated
installer accepts these documents, and its rollback/preservation tests pass.

## Required before a gameplay release

1. Reproduce and fix the disappearing first boss and current-thread-pointer crash,
   using the diagnostic build and isolated input/card captures documented in
   `runtime/docs/gameplay-capture.md`. Neither is fixed by this change.
2. Complete mission one including its boss, then test all missions, save/reload,
   cutscenes, audio and supported physical controllers on the exact candidate.
3. Exercise the packaged launcher's Import & Build on an empty-cache machine,
   Play Native, cancellation, updates, rollback and save restoration through its UI.
   This session used the worker directly, not the launcher UI.
4. Review native build warnings and unsupported fallback instructions/audio commands.
   Headless tests do not prove complete PPC, DSP, GX or game compatibility.
5. Keep exact source revision, package digest and test evidence together. Re-run
   gameplay against the final package; prior rc.2/rc.3 results cannot certify it.

## Distribution boundary

The default package includes source, original launcher artwork, separately licensed
replacement fonts, launcher and image inspector. Never upload the game image,
extracted DOL/REL, generated PPC code, native game executable, RAM, cards, input
recordings, private paths or tool caches. Do not use `-IncludeNativePrototype` for
public artifacts. Keep upstream MIT, SDL zlib, font Apache/OFL and GLAD notices.
The font notice records installed-Dolphin provenance; a pinned upstream provenance
record for those exact replacement font bytes is still desirable. This audit is
an inventory and packaging boundary, not a legal clearance for game trademarks.

## RecompStore submission preparation (not submitted)

Official pages checked: <https://recompstore.com/submit> and
<https://recompstore.com/hub>. The public submission page asks for GitHub, project
details and pictures, and states that game files are not hosted and users need
their own copy. The server-rendered page does not expose a complete acceptance
checklist; do not invent an approval or claim its dynamic form has been validated.

- Repository: <https://github.com/xSNAIRZx/star-fox-assault-recomp>
- Platform: Windows x64; native build requires the user's USA GF7E01 ISO/CISO.
- Description: Experimental Star Fox Assault native recompilation and Peregrine
  Forge launcher. Builds locally from the user's image. Known boss-visibility and
  thread-pointer failures remain; full-game compatibility is unverified.
- Pictures: `docs/images/launcher-home.png`, `launcher-settings.png`, `project-cover.png`.
  Label artwork as launcher concept artwork; it is not gameplay evidence.
- Download: hold pending final candidate validation. Do not present the older rc.3
  download as the tested source revision.

The project's release standard is stricter than the public site's short intake
description. A store listing alone would not establish playability.
