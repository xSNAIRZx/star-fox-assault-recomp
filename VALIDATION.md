## 2026-11-03 — replay save isolation and stability investigation

The native executable rebuilt successfully from the existing local tool cache after a change to input replay: replay now refuses to start without the recording's memory-card snapshot, and the snapshot copy reports read/write/flush/close failures. This closes a path where a failed snapshot copy could make replay write to the live memory card. The first-boss disappearance and the recorded current-thread-pointer crash remain unresolved. The retained boss evidence has no matching gameplay recording; the crash log shows the pointer was already invalid before the SDK dereference. Capture an isolated, normal-speed controller/input recording and frames at the failure to continue diagnosis. This focused rebuild does not validate either gameplay fix.

# Validation summary

Validation date: 2026-11-01. This report summarizes the completed rc.2 empty-cache
package build and bounded boot. It contains no local image paths, image hashes, or
user data.

## Checks passed

- The rc.2 source package was extracted into a Unicode-named folder with no existing
  tool, SDL or game build cache. Its actual **Import & Build** action downloaded all
  four pinned tool archives, verified their SHA-256 values, fetched and built SDL, and
  compiled 101 fresh Ninja units. A plain ISO path with spaces and an apostrophe was
  accepted. The 42,158,080-byte native executable was produced in about 150 seconds.
  This is an end-to-end empty-cache online first-use run.
- The launcher build used only the Windows system path plus portable tools from
  `user-data`; it did not use a preinstalled compiler, CMake, Ninja, Python, or Dolphin.
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
  build, cancellation, worker failure, exit-code mismatch, missing status, and retry.
  Build-cache signature regressions passed two cases. Worker invalid-image and
  cancellation runs returned the expected failure/cancel states and retained the
  prior executable.
- Portable tool setup rejected empty offline caches, quarantined a corrupt archive,
  and rejected a traversal archive without leaving staging files.
- An unchanged offline rebuild completed in 2.86 seconds with the same native
  executable hash.
- The standalone image inspector validates supported USA GF7E01 images read-only.
- Package integrity, excluded-file checks, and update rollback/preservation checks
  passed for the source-and-host-tools package.

## Not yet established

- Full-game compatibility, later missions, mission completion, complete audio
  fidelity, and all physical controllers remain unverified.
- The reported first-boss visibility issue and invalid-current-thread-pointer crash
  remain unresolved. Widescreen remains experimental.

The package excludes game images, extracted DOL/REL files, generated game code,
prebuilt game executables, local settings, saves, and build caches. Each recipient
provides their own supported game image and builds locally.
