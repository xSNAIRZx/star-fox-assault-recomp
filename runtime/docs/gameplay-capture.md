# Windows capture guide: first boss and current-thread crash

These tools gather evidence. Neither defect is fixed. Use your own supported USA
GF7E01 ISO/CISO. Keep captures private: RAM can contain game code, and cards contain saves.

## Build and record

Run Windows PowerShell 5.1 from the project folder. Replace the example image path.
Close the game before building. The first build needs internet and at least 3 GB free.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-StarFoxAssault.ps1 -GameImage "D:\GameDumps\Star Fox Assault.ciso" -UsePortableToolchain -DiagnosticBuild
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-Gameplay.ps1 -GameImage "D:\GameDumps\Star Fox Assault.ciso" -Mode Both
```

The script uses the built `build-desktop/Release/assault.exe`. It does not build,
validate the disc, or establish that the executable matches the image. Build from that
same image first. `-Executable` can select another build; its SHA-256 is recorded.
The copied build record is provenance, not proof that a custom executable matches it.

Captures default to unique directories under `user-data/captures`. Each run has its
own working directory and saves. An existing launcher card is copied, never moved;
`-MemoryCard` selects a different starting card. Without either, the run starts fresh,
but the runtime starts logging before it creates the new card, so that first recording
cannot be replayed. Let the first run initialize its card, then record a new session with
`-MemoryCard "...\FIRST-SESSION\run\saves\memcard_a.raw"`. Do not add that later card to
the first recording: it was not its starting state. The script warns about this and
rejects replays missing their starting snapshot before launching.
The launcher's default `controls.txt`, if present, is copied. Custom mappings stored
elsewhere must be placed in the capture's run directory for subsequent manual use.

Baseline: 1x, 4:3, AA off, sharp filtering, VSync on, normal speed, no mods. Inherited
`GCN_*` variables are removed from the child environment; the parent is unchanged.
To compare widescreen, repeat with `-Aspect widescreen` and the same replay.
Focus the game window; Space continues past safety, Enter sends Start, Escape exits.
WASD moves; F9 captures/releases the mouse, F10 selects C-stick Aim or main-stick
Flight. Use the game's Dual-Stick setting for on-foot aiming; captured Aim-mode
left-click sends R, while Flight-mode or released-mouse left-click sends A.
Record the route, boss phase, camera position, and last visible/first missing moment.

`-Mode Thread` enables guard/store watch; `-Mode Boss` enables vertex diagnostics;
`Both` enables both. A normal build can report guard changes but needs
`-DiagnosticBuild` for per-store `[thread-watch]` output. Missing output alone does
not establish that the watched word stayed intact.

## Replay and select frames

The capture prints its folder. Replay the `inputs` subdirectory, not stdout.log:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-Gameplay.ps1 -GameImage "D:\GameDumps\Star Fox Assault.ciso" -ReplayDirectory "C:\Games\SFA\user-data\captures\RECORDING\inputs" -Mode Both
```

The script copies inputs.txt and its starting memcard_a.raw into the new session
before replay; the runtime writes its scratch card there. Preserve the entire input
folder. Replay uses recorded input until it ends, then live input resumes. Compare
matching builds first; timing/rendering nondeterminism can prevent exact reproduction.

For a known visible or missing **presented** frame, add `-DrawFrame 12000` (example
only). This requests its draw list, matrix log and PNG. Repeat for the other frame.
`GCN_DRAWLOG=1` means frame 1, not continuous logging; zero disables it.
For RAM, use PowerShell array syntax when invoking the script directly:

```powershell
& .\tools\Capture-Gameplay.ps1 -GameImage "D:\GameDumps\Star Fox Assault.ciso" -ReplayDirectory "C:\Games\SFA\user-data\captures\RECORDING\inputs" -Mode Both -DrawFrame 12000 -RamFrames @(11995,12005)
```

RAM frames are **submitted** frames, while draw/matrix/PNG numbering is presented.
Use `[ram] frame N (presented M)` to align them; do not assume equal numbering.
Frame numbers above are placeholders, not a known boss reproduction. Capture the
same route first and narrow the relevant interval. A screenshot is requested, not
guaranteed if the runtime never reaches/presents that frame.

`-PlanOnly` prints the arguments and environment without requiring an ISO or executable,
creating files, or starting a process. `-StopAfterSeconds 15` bounds a startup check;
it forcibly stops only the child process at the limit, may leave input logs incomplete,
and must not be interpreted as a successful playthrough. Normal captures have no limit.

`-InputScript '120:A:20,400:START:20'` explicitly supplies scripted pad presses for
navigation. It cannot be combined with replay. Omit it for a person-controlled run:
scripted buttons are merged with live input, so a long held A prevents a player from
releasing A to fire a charged shot. `-LogHostKeys` logs SDL key-down events for input
diagnosis. Both options are recorded in `capture.json`; inherited scripts still do
not leak into the child. Logs can be read during capture while concurrent writers
remain blocked. Normal interruption/error cleanup stops only the child it started.
`-Hidden` adds hidden/script-only presentation and a dummy audio device for an
isolated unattended replay; the recorded input still drives the guest. Use a visible
capture for a person playing. Hidden replay is silent and cannot validate audio feel.

## Read the evidence

- `capture.json`: executable hash, paths, arguments, environment and image size/time.
- `native-build-info.json`: copied if available; may be absent or refer to another executable.
- `stdout.log`, `stderr.log`: raw process output, streamed to disk during execution.
- `result.json`: exit code and whether the time limit forced termination.
- `inputs/`: recording plus starting card, if one existed.
- `run/saves/`: isolated session saves; `replay/`: copied replay and scratch card.
- `crash.ram.bin`: only if a supported crash handler writes it.
- `frames/`, `ram/`: requested selected-frame artifacts, if reached.

Thread crash: find the first invalid `800000E4` transition in `[thread-watch]` or
`[guard]`. The diagnostic store hook runs after the store; inspect its PC, operands,
effective address, live guest stack and any REL mapping. Guard polling identifies
an interval, not necessarily the exact writer, and can miss transient corruption.
A runtime DMA/copy overlap instead calls for inspecting its destination and length.
`3F000000` is the encoding of 0.5f, but those bits alone do not prove a float store.
Do not replace the thread pointer with a guessed value as a fix.

Boss: `[vertcheck]` reports non-finite transformed XYZ positions for submitted draws
and is capped at 32 reports. A report is a lead, not proof that the draw is the boss.
No report does not rule out bad geometry, projection, clipping, depth, alpha/TEV state
or game-side visibility/culling; geometry never submitted cannot be checked here.
Compare visible/missing draw lists, matrices, screenshots and RAM. Missing boss draws
suggest tracing object lifetime/visibility and callbacks; present draws suggest tracing
transform and render state. Repeat original/widescreen separately.

## Version and validation limits

rc.3 supports the diagnostic build and guard/store capture, but its published archive
does not contain the later `GCN_VERTCHECK` or live guest-stack additions. Use current
source for those, rebuild, and keep recordings/build identities separate. Current-source
tool changes do not imply that published rc.3 assets were replaced or revalidated.
The latest release with documented empty-cache build and bounded-startup evidence is
rc.2; rc.3 has package checks, not a documented game-image run.

Neither bug is claimed reproduced or fixed by this script. See VALIDATION.md for
the specific checks actually performed. To report a run, include version/commit,
build identity, Windows/GPU/driver, settings, steps, result, logs and video; share
cards/RAM privately rather than committing or attaching game-derived data publicly.
