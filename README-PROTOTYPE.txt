PEREGRINE FORGE / STAR FOX ASSAULT RECOMP 0.2.0-RC.3 - WINDOWS X64 SOURCE PACKAGE

This package contains the launcher, the recompiler source, the build tools and a
standalone game-image inspector. It does not contain a game image or a prebuilt
game executable. You supply your own USA Star Fox: Assault ISO or CISO
(disc ID GF7E01).

GETTING STARTED

1. Extract this folder somewhere you can write files.
2. Start "Star Fox Assault Recomp.exe" (or "Start-StarFoxAssault.cmd").
3. Choose Import Game Image and select your own supported USA ISO/CISO.
4. Choose Import & Build. The launcher checks the image, downloads the pinned
   portable build tools and the required SDL source, then builds a local game
   executable.
5. When the build finishes, choose Play Native.

The first build needs internet access, downloads about 280 MB of pinned build
tools plus SDL source, and should have at least 3 GB of free disk space for
downloads, build files and caches. It requires 64-bit Windows 10 version 1903 or
newer and a graphics adapter with desktop OpenGL 3.3 support. No administrator
installation, Dolphin or separately installed compiler is required. Later builds
reuse the local cache.

If Windows blocks a download or the build stops early, read the launcher message
and retry once internet access is restored. Close the game before rebuilding.

PORTABLE FILES AND UPDATES

This folder includes portable.txt. Settings, downloaded tools, build output,
saves and logs stay under user-data. Package updates preserve those local files
and your locally built game executable. Keep the whole folder together when
moving the installation to another location.

The launcher provides graphics options, controller mapping, save backups, local
mod pack management, package updates and optional Dolphin launch support. Native
asset replacement accepts same-size files at matching disc paths; it does not
replace DOL/REL game code. Online update and mod services are not included.

PROJECT STATUS

This is an experimental source-build release candidate, not a complete or stable
game release. The rc.3 archive passed structural, checksum, content-filter and
PowerShell parser checks. The rc.2 package completed an empty-cache online build
and a bounded hidden boot on the tested machine; those runtime checks were not
repeated for rc.3. See VALIDATION.md for the scope of that evidence. First-mission
flight and profile persistence have been tested.
The first-boss visibility report, an invalid-current-thread-pointer crash, later
missions, mission completion, full audio fidelity and all physical controllers
remain unverified. Widescreen is experimental. See RELEASE-NOTES.md and
VALIDATION.md for the release scope and known limits.

The included LICENSE covers original project software source; CREDITS.md,
THIRD_PARTY_NOTICES.md and the font license file list attributions and licenses.
The original game image and any extracted or generated game code are not
included. The adjacent SHA256SUMS.txt covers package files, and the adjacent
.zip.sha256 file fingerprints the complete ZIP archive.
