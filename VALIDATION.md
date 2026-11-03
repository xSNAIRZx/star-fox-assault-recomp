# Validation summary

Scope: bounded setup, build and startup checks completed on one tested Windows PC.
Passing checks here do not establish full-game compatibility.

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
- The launcher sets `GCN_GUARD=800000E4` for every native session. It previously set only
  `GCN_WATCH_ADDR`, which reports in a diagnostic build and the packaged build is not one,
  so a session that hit this crash recorded nothing about it.

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
