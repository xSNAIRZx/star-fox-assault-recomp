STAR FOX ASSAULT RECOMP 0.2.0-RC.2 - WINDOWS X64 SOURCE PACKAGE

This package contains the launcher, recompiler source, build tools, and a standalone
game-image inspector. It does not contain a game image or a prebuilt game executable.
You must provide your own USA Star Fox: Assault ISO or CISO (disc ID GF7E01).

GETTING STARTED

1. Extract this folder somewhere you can write files.
2. Start "Star Fox Assault Recomp.exe" (or "Start-StarFoxAssault.cmd").
3. Choose Import Game Image and select your own supported USA ISO/CISO.
4. Choose Import & Build. The launcher checks the image, downloads the pinned
   portable build tools and required SDL source, then builds a local game executable.
5. When the build finishes, choose Play Native.

The first build needs internet access and downloads about 280 MB of pinned build tools,
plus SDL source. Allow several GB of free disk space for downloads, build files, and
caches. It requires 64-bit Windows 10 version 1903 or newer and a graphics adapter
with desktop OpenGL 3.3 support. It does not require administrator installation,
Dolphin, or a separately installed compiler. Later builds reuse the local tool cache.
If Windows blocks a download, read the launcher message and retry after restoring
internet access.

PORTABLE FILES AND UPDATES

This folder includes portable.txt. Settings, downloaded tools, build output, saves,
and logs are kept under user-data. Package updates preserve those local files and
your locally built game executable. Keep the whole folder together when moving the
installation to another location.

The launcher provides graphics options, controller mapping, save backups, local mod
pack management, package updates, and optional Dolphin launch support. Native asset
replacement currently accepts same-size files at matching disc paths. It does not
replace DOL/REL game code. Online update and mod services are not included.

PROJECT STATUS

This is an experimental source-build release candidate, not a complete or stable
game release. The rc.2 package completed an empty-cache online build and bounded
hidden boot on the tested machine; see VALIDATION.md for scope. First-mission flight
and profile persistence have been tested. The
first-boss visibility report, an invalid-current-thread-pointer crash, later missions,
mission completion, full audio fidelity, and all physical controllers remain
unverified. Widescreen is experimental. See RELEASE-NOTES.md and VALIDATION.md.

The included LICENSE covers original project software source; CREDITS.md,
THIRD_PARTY_NOTICES.md, and the font license file list
attributions and licenses. The original game image and extracted or generated game
code are not included. The adjacent SHA256SUMS.txt covers package files, and the
adjacent .zip.sha256 file fingerprints the complete ZIP archive.
