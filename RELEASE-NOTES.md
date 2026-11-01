# 0.2.0-rc.2 - Windows x64 source-build release candidate

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
