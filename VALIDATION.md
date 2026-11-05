# Validation summary

## Continued correctness and controls work — 2026-11-04

### Recorded boss replay: candidate passes; live run pending

The NI + paired-sum candidate replay reached the selected after frame with the
Winged Aparoid visibly present. Its entire 0x180-byte boss object at the before
frame was byte-identical to the baseline. At the after frame, the same object,
actor, generation and phase remained valid in both runs. The baseline had eight
non-finite values among 26 identified float fields; the candidate had zero. Its
position was approximately (-5.0098, -16.1077, 130), rather than infinities.
No replay-divergence warning was reported. Candidate RAM at submitted 29995
mapped to presented 29994; the independently inspected PNG was presented 29995.

This is evidence that the combined arithmetic candidate prevents this recorded
failure. It excludes the later packed-context fix. The private log-only trace
build was SHA-256 `24632ede513f1f4359512bebb164feec58c5124a4fbce8b7f6c48209d0fc47c5`.
Its normalizer log filter missed an intervening wrapper, so absence of those log
lines does not prove active NI mode or which guarded path ran. The RAM/PNG result
does not rely on that trace. NI-only causal attribution remains narrower than the
combined-candidate result.

Both baseline and candidate replay were stopped at their 620-second test bounds;
neither was a mission-completion run. The work is paused immediately before the
fresh live run at the user's request. Next: live-test the clean build through the
meteor attack and boss completion, then save/reload; keep the pointer crash and
later-mission checks open. The clean source with the separate context correction
also rebuilt and passed the full Windows host checks. Hosted Windows and Linux
CI passed commit `97651e7ddd29f21b9ca861d4c7695057d2c213e1`.

The reproduced boss object's position offsets become infinities while its actor
and generation remain valid. The recorded route reproduced this transition in a
same-build replay with no reported divergence through the selected snapshots:
submitted 28364 (presented 28363) has finite offsets, submitted 29995 (presented
29995) has infinite offsets and NaN transform fields. A selected presented-frame
28364 PNG shows the boss still visible amid meteors. These game-derived snapshots
are private and are never source or package payloads.

A subsequent candidate implements CPU-local FPSCR NI result handling for scalar,
paired and double arithmetic and single rounding. NI flushes tiny results to signed
zero; loads, binary moves and reciprocal-estimate operands remain unchanged. The
independently synthetic tiny-vector regression fails on the baseline and passes
after correction. All 40 NI, 48 paired-sum, 288 comparison and 12,600 integer
generated-code checks pass; 14/14 runtime tests and the full Windows host runner
pass. Paired-sum flags now describe the sum lane, with copied lanes preserved.
Full exception flags, arithmetic rounding modes and estimate fidelity remain limits.

A separate fresh-context restore regression found that PSF slots contain two
packed binary32 lanes, while the runtime interpreted their combined bits as one
binary64 PS1 value. A synthetic slot carrying PS1 -2.5 restored as about 0.03125
on the baseline. The corrected reader expands the slot's second binary32 lane,
preserving the full PS0 from its separate FPR slot. The actual context-reader test
passes 32 PS0/PS1 value pairs plus control-register and FPSCR checks; the full host
suite and native rebuild pass. Existing-binding snapshots bypass this reader.
No claim is made that this separate correction fixes the recorded thread-pointer
failure or the boss. Lazy-FPU valid-state semantics remain a separate concern.

The NI candidate's clean native build SHA-256 is
`44094fe32c5f82371fc7623c1edfdd852bec1d3a740c17ec5d692ba142f8272f`.
A separate private build adds a narrow log-only normalizer trace. Replaying the
recorded encounter is still required to establish whether NI handling repairs the
boss; architecture tests alone do not establish that outcome.

References: [MPC750 manual, table 2-21](https://www.nxp.com/docs/en/reference-manual/MPC750UM.pdf)
and [Dolphin's documented single-result behavior](https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/PowerPC/Interpreter/Interpreter_FPUtils.h).
The implementation is independently written; no Dolphin source or estimate tables
were copied into this MIT project.

**Gameplay reproduction obtained:** the updated diagnostic executable
`374c659ae2e99d83f9c42f87b0322e74c098051132aa51fd63b99ad98aa875bc`
reached the Winged Aparoid with a person playing. The boss was visibly present,
then absent during the first meteor attack while its health bar and encounter
continued. A silent game-window video, input recording, starting-card snapshot,
build identity and diagnostic logs were retained privately. The game closed
normally with exit 0. No vertex non-finite report, invalid-pointer guard report
or fatal MMU message was found around this reproduction. This rules out none of
game-side visibility, finite off-frustum geometry or render-state failures; the
vertex check only inspects submitted positions. The boss defect is confirmed
on this changed build, not fixed. Before/after replay captures are the next check.

The changed native build succeeded, 14/14 CTest targets passed, and the complete
host runner (including the process, generated-instruction and package/update
checks below) passed on Windows PowerShell 5.1. These local results do not certify
hosted CI or full-game playability.

Three focused agents reviewed PPC translation, renderer math and process tooling.
The original `mulli` emission traps under signed-overflow checking; its modulo
replacement passes 12,600 generated-C cases. The existing LLVM target already
uses `-fwrapv`, so this is portability hardening, not a demonstrated gameplay repair.
Floating comparisons previously left FPSCR FPCC stale; generated compare/mffs/mcrfs
sequences fail on the baseline and pass 288 cases after preserving the pending
arithmetic classification and updating FPCC. NaN exception flags remain incomplete.

Renderer math now rejects non-finite/overflowing z-freeze inputs without replacing
the valid plane; the new cases produce 146 failures on the original helper and none
after correction. A pure desktop input helper passes 23 checks for WASD/mouse channel
independence, fire mappings, mode/focus changes and extreme mouse deltas. Its live
feel and all game control configurations still need validation.

The diagnostic baseline build reached mission-one flight and its ground/canyon
section with a copied card and input recording, then closed cleanly with exit 0.
No invalid-pointer transition or vertex diagnostic was observed in that capture.
The scripted route held A continuously, preventing the user from releasing it to
fire; it was stopped, and a subsequent human-controlled run must omit held fire.
This session did not establish a boss reproduction or mission completion.

Process regressions cover early exits 0/7, nonzero shutdown-grace exit, numeric
forced-stop codes, large stdout/stderr, Unicode paths and environment/save isolation.
Capture tests verify live log readers, rejection of second writers, explicit input
options and replay exclusion. Hosted CI for these new changes is a separate gate.

Historical primary research located Dolphin's 2011 fadds workaround and 2013
FPRF correction for Assault's invisible boss. This project already records arithmetic
FPRF, so those fixes cannot simply be assumed to explain its current failure:
<https://github.com/dolphin-emu/dolphin/commit/5a212a8fe0cc05b375a0d26aa62e9cd4d3f0977c>.

## Final-readiness audit — 2026-11-03

See [RELEASE-READINESS.md](RELEASE-READINESS.md) for the latest fresh Windows build,
13/13 runtime checks, host-tool and package/update verification, bounded native
startup evidence, distribution boundary and unresolved release blockers. These
checks do not resolve the boss-visibility or current-thread-pointer gameplay bugs.
The new image-free CI includes Windows and Linux checks; hosted results must be
reported separately from local results.

## Windows gameplay capture tooling - 2026-11-03

Added `tools/Capture-Gameplay.ps1`, its ISO-free synthetic-process tests, and
[the Windows capture guide](runtime/docs/gameplay-capture.md). No gameplay behavior
was changed and neither reported defect was reproduced or fixed.

- Windows PowerShell 5.1 synthetic-process checks passed: Unicode/space/apostrophe
  argument preservation, separate stdout/stderr, child exit-code recording, inherited
  GCN environment removal without modifying the parent, mode selection, replay/card
  copying, plan-only with no files/processes, invalid arguments/missing inputs and
  bounded termination. These exercise orchestration, not guest correctness.
- Launcher tool audit passed: 110 paths, zero problems. Both new scripts parsed and
  `git diff --check` passed.
- After a user-supplied local CISO became available, image validation and the current
  diagnostic native build completed. A 15-second bounded startup produced OpenGL,
  guest-clock, thread-store and live-stack output. It was forcibly stopped; this is
  startup/capture evidence, not mission or crash-reproduction evidence.
- The first fresh-card recording could not replay: input logging precedes creation
  of the initial card, so the recording lacked a starting snapshot. The guide now
  explains a fresh-card initialization followed by a new recording with that card;
  the script warns on fresh runs and rejects replay folders missing the snapshot.
  It does not invent a starting snapshot from a later card state.
- A subsequent 8-second run with a copied starting card, and an 8-second replay of
  that recording, both produced a selected frame-10 PNG, a 24 MiB RAM dump and matrix
  logging. The RAM line mapped submitted frame 10 to presented frame 10 in this run;
  that equality is not assumed generally. The PNG was inspected: this early frame
  was black, so it does not demonstrate readable menus or gameplay. Replay loaded
  the copied card/input data and then returned to live input when the short log
  ended. It does not establish a deterministic boss/crash reproduction.

Untested: capturing the disappearing boss, capturing the reported invalid-pointer
transition, a crash-generated RAM dump, mission completion and save/reload gameplay.
No public release assets were created or replaced. Private images, logs, cards, RAM,
generated game code and native game binaries are excluded from the source commit.

Scope: bounded setup, build and startup checks completed on one tested Windows PC.
Passing checks here do not establish full-game compatibility.

## Reliability and launcher audit — 2026-11-03

Source review found that a locally built executable was not tied to the currently selected
game-image identity, save restore did not verify available backup checksums, and texture-pack
import had no archive-entry or expanded-size ceiling. The current source now records image path,
size, modification time and SHA-256 with each native build; launch checks the recorded path,
size and time plus the executable hash, and the build rejects an image that changes during
compilation. (The launcher does not re-hash a multi-gigabyte image at every play attempt.) Save
restore verifies any recorded checksum and uses a checked temporary card plus an atomic replace.
Texture imports are limited to 50,000 entries and 2 GiB expanded, with streamed byte-count checks.

The settings picker now advertises only ISO/CISO, and the launcher permits smaller label fonts and
a narrower content viewport while keeping the page layout scrollable. Normal launcher-started game
sessions enable `GCN_CLOCKLOG=1` and write clock/frame/audio timing to that session's `.err` log.
These diagnostics can distinguish guest-time progression from presentation rate during a later
speed investigation; they do not fix or verify the reported speed issue. The source package initially
failed its own checks because the extension allowlist skipped the required font, and the update
installer rejected a packaged `.psd1` tool manifest. Both allowlists are now aligned. The refreshed local candidate contained 254 payload
files and passed extraction, hash, content-safety, asset-list, local-path and script-parser checks;
installer success, rollback and preservation checks also passed against that candidate. The native
runtime test suite passed 13 of 13 checks, the PowerShell parser passed 18 scripts, the launcher tool
audit passed 110 path checks, and build-cache signature checks passed. These checks do not exercise
image-mismatch, save-restore, texture-import or narrow-window behavior in a live launcher session.
The rc.3 download remains older than this source audit; the refreshed local candidate is not a
published release.

## Source-only branding update — 2026-11-03

The launcher title, top-bar brand, About page, bootstrap error titles, README and credits now use
Peregrine Forge as the launcher brand. The project and executable remain Star Fox Assault Recomp.
The icon uses a matching PF monogram, regenerated at seven sizes and reviewed in a 256-pixel
preview. The launcher itself was not opened for a visual check. No trademark registration is
claimed.
The PowerShell launcher and C# bootstrap each use centralized product-title values. `.gitignore`
excludes local builds, user data and Python caches. Both PowerShell files parsed, bootstrap C#
compilation succeeded, and `git diff --check` passed; no gameplay or launcher GUI checks were run.

| Area | Result |
| --- | --- |
| Empty-cache online first build from the rc.2 source package | Passed |
| Bounded startup to the health-and-safety screen | Passed |
| Runtime regression suite | Passed, 9 of 9 checks |
| Launcher build UI, worker, cache-signature, tool-setup and update paths | Passed |
| Full-game compatibility, mission completion and later missions | Not established |
| First-boss visibility and invalid-current-thread-pointer crash | Unresolved |

## rc.3 package checks — 2026-11-03

The branded rc.3 launcher and source package passed archive creation, extraction, portable forward-slash
path, per-file SHA-256, forbidden-content and asset-allowlist checks. The package's PowerShell scripts
parsed, its C# bootstrap compiled, and the regenerated icon contains seven sizes. The launcher was not
opened, and the native game build and gameplay were not run. The empty-cache native build and
bounded-startup evidence below is for rc.2 only.

## Checks passed — 2026-11-01, rc.2

The rc.2 source package was extracted into a Unicode-named folder with no existing
tool, SDL or game build cache. This report summarizes the completed empty-cache
package build and bounded boot. It contains no local image paths, image hashes or
user data.

- Its actual **Import & Build** action downloaded all four pinned tool archives,
  verified their SHA-256 values, fetched and built SDL, and compiled 101 fresh Ninja
  units. A plain ISO path with spaces and an apostrophe was accepted. The
  42,158,080-byte native executable was produced in about 150 seconds. This is an
  end-to-end empty-cache online first-use run.
- The launcher build used only the Windows system path plus portable tools from
  `user-data`; it did not use a preinstalled compiler, CMake, Ninja, Python or Dolphin.
- Existing `%LOCALAPPDATA%` launcher settings remained unchanged during the portable
  build.
- A hidden normal-speed boot ran for its full 10-second bound after that build. The
  health-and-safety screen rendered readable text. Both Japanese and Western
  replacement fonts loaded from the Unicode-named asset path. The test used an
  isolated synthetic save and ended at the planned time limit.
- Portable Windows x64 build-tool manifest verification and an incremental native
  build completed successfully.
- The runtime regression suite passed 9 of 9 checks.
- The rc.2 launcher build UI passed six cases covering Unicode paths, successful
  build, cancellation, worker failure, exit-code mismatch, missing status and retry.
  Build-cache signature regressions passed two cases. Worker invalid-image and
  cancellation runs returned the expected failure and cancel states and retained the
  prior executable.
- Portable tool setup rejected empty offline caches, quarantined a corrupt archive,
  and rejected a traversal archive without leaving staging files.
- An unchanged offline rebuild completed in 2.86 seconds with the same native
  executable hash.
- The standalone image inspector validates supported USA GF7E01 images read-only.
- Package integrity, excluded-file checks and update rollback/preservation checks
  passed for the source-and-host-tools package.

## Not yet established

- Full-game compatibility, later missions, mission completion, complete audio
  fidelity and all physical controllers remain unverified.
- The reported first-boss visibility issue and invalid-current-thread-pointer crash
  remain unresolved. Widescreen remains experimental.

The package excludes game images, extracted DOL/REL files, generated game code,
prebuilt game executables, local settings, saves and build caches. Each recipient
provides their own supported game image and builds locally.

## Validation log

### 2026-11-03 — launcher tool audit

Every project path the launcher opens was checked against what the package ships. Two real gaps
came out of it. Native asset-pack import shelled out to a system `python.exe`, so it failed on a
machine without one even though Import & Build already downloads and hash-verifies a portable
Python into `user-data/build-tools`; the launcher now uses that copy first (re-checking the
recorded archive and executable hashes) and only then falls back to PATH, and its message points
at Import & Build before suggesting an install. Separately, the package and updater required-file
lists did not name `tools/Install-PrototypeUpdate.ps1`, `tools/Track-Session.ps1` or the
`runtime/recomp` modules the launcher and the build read, so a trimmed payload could have been
published and failed at the user. Both lists cover them now.

`tools/Test-LauncherTools.ps1` checks this without Windows or a game: every path the launcher
opens must exist and be shipped (named explicitly or covered by a copied source tree) or be
created at run time under `user-data`/`build-desktop`, and every file either required list names
must exist in the repository, with the launcher's own dependencies required by both lists.

### 2026-11-03 — stick deadzone for the built-in controller path

Added `--deadzone=<percent>` (0 to 40) and a launcher setting for it. A controls.txt binding
has carried its own `deadzone` for a while, but a pad the file does not name went through a
threshold fixed in the source (4000/32767 on the stick, 1000 on the C stick), compared per
axis with the raw axis passed through afterwards, and the launcher had no way to reach it.
With the option set both sticks use a radial deadzone: anything inside a circle of that
radius is at rest, and the travel left over is spread across the full range, so a diagonal
push needs the same travel as a straight one and the first movement past the circle is a
small step instead of a jump the size of the threshold. Without the option the previous
per-axis thresholds are used unchanged, so an existing profile keeps its behavior.

Covered by `pad_curve_test`: percent and clamping, rest inside the circle, unity with no
deadzone, rescale past the edge, a straight and a diagonal push of equal length agreeing, no
jump at the edge, direction preserved at every distance, a square-cornered axis pair held at
1 rather than overflowing the byte, and the byte conversion including NaN and out-of-range
input. Not verified: any feel on a real pad.

### 2026-11-03 — particle and VFX rendering review; asset-override size limit

How particle and visual-effect draws reach the renderer was reviewed from source only. No
build of the game, no GPU and no gameplay were available here, so nothing in this entry is a
visual result, and no rendering code was changed.

- Effects are guest GX draws, and the analysis metadata carries no particle, effect, trail or
  explosion symbols, so they cannot be identified by name from this repository. They arrive
  as point, line and triangle primitives under the game's TEV blending and alpha test.
- Points are already a complete sprite path: `gl_PointSize` is sent from the game's point
  size, the fragment shader spreads the coordinate range back out with `gl_PointCoord`
  (`u_points`, `u_point_off`, set per draw in `apply_state`), point size is kept in EFB
  pixels, and `GL_PROGRAM_POINT_SIZE` is enabled for desktop core. A smoke or spark point
  therefore samples its whole texture instead of one texel.
- Lines are the one known gap, already documented in `graphics.md`: GX widens an antialiased
  line into a quad and runs a texture coordinate across that width, while the front end moves
  the coordinate to the middle of its range and draws a one-pixel GL line. Matching wide
  lines needs geometry expansion rather than a GL line width, and desktop core profiles
  commonly report an aliased width range of 1, so the limitation was documented rather than
  changed blind.
- Blend modes, blend factors, the alpha test and depth state were checked against their GX
  encodings. No defect was found and none was modified: `kBlendSrc`/`kBlendDst` mirror the
  hardware's asymmetric source and destination factor encoding deliberately.
- Asset override: a replacement must equal the disc FST size exactly. A larger file would
  move every following file in a read-only image, so a higher-resolution particle texture
  cannot be delivered by this path. A rejected pack now names both sizes and points at
  `runtime/docs/disc-mods.md`, which explains the two designs that could allow larger assets;
  `disc_mods_test` covers the message.

Requires a person in game, and is not established here: explosions and impact effects (shape,
framing, whether every element appears), engine and exhaust trails, additive and subtractive
blending against bright backgrounds, particle alpha edges and sorting against the world,
effect timing and cadence, and visibility in both original 4:3 and experimental 16:9 at 1x
and higher internal resolution.

### 2026-11-03 — current-thread pointer trace analysis and capture tooling

The saved crash trace was read against the project's own analysis metadata. Instruction
`0x80136C60` lies inside `fn_80136C44` (size `0xEC`) in the DOL, and the reported address
`0x3F0002C8` is exactly `0x2C8` past `0x3F000000`. The word at `0x800000E4`, which the
launcher already watched as the SDK's current-thread pointer, therefore held `0x3F000000` at
the failure, and `0x3F000000` is the IEEE-754 encoding of `0.5f`.

What that establishes: the corruption is a 32-bit float store landing in the pointer word,
already in place before the failing SDK access — what the crash log reported without
explaining it. What it does not establish: which store did it, in which frame, and whether
the failing access is the first use of the bad value. A guest store can only be narrowed to
the stretch between two polls, and the previous capture carried no guard output.

Changes made to capture it, all diagnostics-only with no effect on guest behavior:

- `GCN_GUARD` accepts up to eight comma-separated words instead of one, so the pointer and
  the thread structure it should point at can be watched together.
- A watched word that cannot be a guest pointer is named as such the moment it changes,
  including the float it decodes to (`runtime/pointer_sanity.h`, covered by
  `runtime/tests/pointer_sanity_test.cpp`).
- The launcher sets `GCN_GUARD=800000E4` for every native session. The guard now reports only
  non-null values that cannot be guest-memory pointers; valid thread switches and the brief
  null value between threads are ignored so normal play does not flood the session log.

Nine runtime tests now build and pass outside Windows: the eight recorded above plus the
pointer-word test. The Windows verify, build and packaging paths were not run, and no game
build or gameplay was exercised.

Next capture needed: a normal-speed session that reaches the failure with the launcher's own
log. The `[guard] 800000E4: ... at <where>, frame <n>` line names the frame and the value
either side of the change, and the session's `GCN_RAM_DUMP` at the crash holds the thread
structure around it. That pair is what identifies the writer.

### 2026-11-03 — host-script and runtime source checks

The host scripts and runtime sources were also checked outside Windows for defects
the packaged build steps would not surface. This is not a Windows build or a gameplay
run: the launcher GUI was not exercised, no game image was imported and the shipped
bootstrap executable was not rebuilt.

- All 16 PowerShell host scripts (`Launch-StarFoxAssault.ps1` plus `tools/*.ps1`) parse
  without syntax errors under the PowerShell 7.6.9 parser. `tools/Verify-Project.ps1`
  performs the same parse check during a Windows verification run.
- PSScriptAnalyzer 1.25.0 reported no error-severity findings. Two automatic-variable
  collisions were fixed: the launcher assembled the native game's argument list by
  assigning to `$args`, and the update installer reused `$input` for a ZIP entry
  stream. The remaining warnings are convention-only (console output through
  `Write-Host`, `ShouldProcess` on internal helpers, plural helper nouns) and are
  documented in `tools/PSScriptAnalyzerSettings.psd1`.
- The eight runtime tests that build without a game image or SDL passed on the
  checked-out sources: display options, render math, audio gain, texcoord, disc mods,
  REL rebinding, disc image and thread-watch filter. `utf8_path_test` is Windows-only
  and was not run.
- `runtime/tools/check_generic.py`, the shared-layer guard against game-specific code,
  passed.

The open gameplay defects are unaffected by these checks; see the entries above.

### 2026-11-03 — replay save isolation and stability investigation

The native executable rebuilt successfully from the existing local tool cache after a
change to input replay: replay now refuses to start without the recording's
memory-card snapshot, and the snapshot copy reports read/write/flush/close failures.
This closes a path where a failed snapshot copy could make replay write to the live
memory card.

The first-boss disappearance and the recorded current-thread-pointer crash remain
unresolved. The retained boss evidence has no matching gameplay recording, and the
crash log shows the pointer was already invalid before the SDK dereference. Capture an
isolated, normal-speed controller/input recording and frames at the failure to
continue diagnosis. This focused rebuild does not validate either gameplay fix.

### 2026-11-03 — launcher polish source checks

`Launch-StarFoxAssault.ps1` was polished in source: the status line now starts after the
navigation row and is sized to the free sidebar width, with an ellipsis and a tooltip carrying
the full message; the Play page's BUILD value is coloured per state; settings are written
through a temporary file and swapped in; and a profile whose volume is not a number no longer
stops the launcher before its window appears.

Checked here, without Windows, a game image or a GUI:

- All 17 host PowerShell scripts (the launcher plus `tools/*.ps1`) parse without errors under
  the PowerShell 7.4.6 parser, and PSScriptAnalyzer 1.25.0 reports no error-severity findings.
  The remaining warnings are the convention-only ones already documented.
- `tools/Test-LauncherTools.ps1` passes: 100 paths checked, 0 problems.
- The launcher's own `Save-Settings` text was executed against a temporary profile: disc,
  volume, deadzone and vsync round-trip, a deliberately truncated profile is replaced, no
  `.tmp` file is left behind and no UTF-8 BOM is written. The first run of this check failed
  on `[IO.File]::Replace($temp,$settings,$null)`, where PowerShell binds `$null` as an empty
  path; the save now passes a real null and falls back to a copy where `File.Replace` is
  unsupported.
- The volume-parsing statement was executed with `'loud'`, `$null`, `999`, `-5`, `42` and
  `'35'`, producing 100, 0, 100, 0, 42 and 35.

Not verified: the WinForms window was never shown, so the navigation and status geometry at
the 1180 px minimum width, the tooltip and the new colours are reasoned from the layout code
rather than observed. Capture the default and minimum window sizes before describing the
launcher as visually verified, and repackage before this reaches a download.

### 2026-11-03 — first-mission stability: what the source can and cannot establish

Both open gameplay defects were re-examined against the repository. Neither has a cause yet,
and no game behavior was changed to guess at one.

**Current-thread pointer crash.** `fn_80136C44`, which contains the reported `0x80136C60`, sits
between `SelectThread` (`0x80136130`) and `OSClearStack` (`0x80136EFC`) in `symbols.txt`: the
failing access is SDK thread code reading the current-thread pointer, which agrees with the
earlier reading that `0x800000E4` held `0x3F000000`, the float `0.5f`. What that does not give
is the writer. The DOL and the RELs are deliberately not in this repository, so the store that
writes the pointer word cannot be disassembled here, and the guard observes a change only at an
interrupt poll, a presented frame or a runtime write — it names the interval, not the
instruction. Naming the store needs a `-DGCN_THREAD_WATCH` build, which the launcher does not
produce; `tools/Build-StarFoxAssault.ps1 -DiagnosticBuild` does.

**First-boss disappearance.** There is still no recording of the encounter, and the analysis
metadata carries no boss or visibility symbols, so the scene graph and the game's own draw
culling cannot be identified by name in this repository. What could be added is a way to tell
the two shapes of "not there" apart from one run.

Changes made, all diagnostics-only with no effect on guest behavior or on what is drawn:

- `GCN_VERTCHECK=1` counts each draw's transformed positions that are not finite and prints
  `[vertcheck] frame <n> draw <n> (command <n>): ...`, naming whether the position matrix was
  already bad (a bad matrix is printed in full) or was finite while the arithmetic produced the
  bad values. The check only reports the draw; it does not discard or change rendered geometry.
  A report shows a numerical problem worth investigating. No report does not rule out
  geometry or render-state problems: the check only sees submitted positions and is capped. Tested by
  `runtime/tests/vertex_sanity_test.cpp` over infinity, NaN, denormals, a finite maximum, the
  stride, and both causes in the message.
- Every `[guard]` and `[thread-watch]` line is now followed by `live guest stack: <addr> ...`,
  walked from the running guest thread's `r1` chain, so a capture names the game code that was
  live when the word changed rather than only where in the runtime it was noticed. Tested by
  `runtime/tests/guest_stack_test.cpp`: two frames innermost first, a chain that ends at a zero
  word, a frame pointer that does not move up the stack, a pointer outside main memory, a
  pointer in the locked-cache window, a stack pointer outside main memory, and the depth and
  capacity limits.

Checks run here: all 12 runtime tests build with `g++ -std=c++20` and pass (the nine recorded
earlier plus the two above and `thread_watch_filter_test`), `threads.cpp` and `gx/xf.cpp` pass
`-fsyntax-only -Wall -Wextra`, and `tools/Test-LauncherTools.ps1` passes. Not run: a native
build, the launcher GUI, any GPU path, any controller, and any gameplay. `GCN_VERTCHECK` has
therefore been exercised only through its helper, never against a real frame, and the guest
stack has been exercised only against a synthetic memory image.

What a person must capture next, and nothing here replaces it:

1. Boss: replay or play to the encounter with `GCN_VERTCHECK=1`, and keep the log from the
   moment the boss is last drawn to the moment it is missing. A `[vertcheck]` line names the
   frame, the draw and the matrix. No such line does not establish a cause: the check only sees submitted positions and
   is capped; inspect visibility, transforms and render state.
2. Boss, if there is no `[vertcheck]` line: capture the same window with `GCN_DRAWLOG=<presented-frame>`,
   `GCN_MTXLOG=<frame>` for a frame with the boss and one without, and `GCN_RAM_DUMP_AT=` those
   two frames, so the draw list, the matrices and memory can be compared frame to frame.
3. Crash: build with `-DiagnosticBuild`, then replay the run that crashes with
   `GCN_WATCH_ADDR=800000E4` and `GCN_GUARD=800000E4`. The `[thread-watch]` line names the store
   that changed the word and the guest stack under it names the code; `GCN_RAM_DUMP` beside it
   holds the thread structure as it was at the failure.
4. Record controller input and replay the entire recording directory with `--replay=<dir>`.
   Keep build identities separate. The launcher clears `GCN_INPUT`; it is not a replay option.

### 2026-11-03 — controls, build progress and Windows test startup

The desktop input layer now accepts Space/A and left-click as A, Enter as Start, B/Z and
right-click as B, and middle-click as X. Arrow keys steer, I/J/K/L send the D-pad, and the
legacy X/C/S/D/Q/W bindings remain available. F9 captures the mouse for relative flight
steering; focus loss and exit release it. These mappings are compiled into the native build,
but keyboard and mouse play have not been observed through a physical game session. The
launcher Home page now shows the quick controls, and its build dialog has a larger progress
bar, named build stages, percentage when the build tool reports it, and clear finish/fail/cancel
states. The WinForms window has not been visually checked on this PC.

The screenshot error `libc++.dll was not found` came from a Windows test executable. CMake now
copies llvm-mingw's `libc++.dll` and `libunwind.dll` alongside each test executable, so the test
can run by itself without adding the compiler folder to `PATH`. A clean test build was made,
`disc_mods_test.exe` was launched with only the Windows system directory on `PATH`, and all 13
CTest checks passed.

The native game executable was rebuilt from a new offline build directory using the user's
existing USA GF7E01 CISO, which was only read. It survived a bounded 128-second normal-speed
run with scripted controller inputs and no crash. That run produced no frame captures at the
requested interval, so it does not confirm the title/menu transition. The earlier retained
frame at guest render frame 5,000 shows the `SELECT GAME` screen, but it came from a previous
build. The current main-menu report and the first-boss disappearance remain open; no gameplay
fix is claimed here.
