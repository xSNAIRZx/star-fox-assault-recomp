## 2026-11-01 — empty-cache online rc.2 build and boot

The source-only **0.2.0-rc.2** package was tested from a Unicode-named installation folder with no existing tool, SDL, or game build cache. The actual packaged launcher **Import & Build** action used a plain ISO path with spaces and an apostrophe, downloaded all four pinned build-tool archives, checked their SHA-256 hashes, fetched and built SDL, compiled 101 Ninja units, and produced the native executable in about 150 seconds. The executable was 42,158,080 bytes, SHA-256 `CA32F4644F6318C976DA3DC80FB49350BD5143598481CB039A2812322DF9188C`. Windows-only PATH was used, and preexisting launcher settings stayed unchanged.

A hidden, silent, normal-speed startup then survived its 10-second bound, loaded the Western and Japanese fonts from the Unicode path, and rendered the health-and-safety screen text. The harness intentionally terminated the process at the time bound using an isolated test save; this is not a clean-exit or full-game stability result. Evidence is under `user-data/verification/fresh rc2 Ω 20261101-020933/`, with boot result `user-data/verification/fresh rc2 Ω 20261101-020933/user-data/validation-runs/20261101-021307-a845e529/result.json`.

The rc.2 launcher UI passed six cases covering Unicode paths, success, cancellation, worker failure/exit handling, missing status, and retry; two build-cache signature regressions passed. Worker invalid-image/cancellation checks preserved the previous executable. Portable tool setup rejected empty offline caches, quarantined a corrupt archive, and rejected archive traversal without leaving staging files. An unchanged offline rebuild completed in 2.86 seconds with the same native executable hash. The source package and local update/rollback checks also passed. This confirms first-use setup and bounded startup on the tested machine, not complete gameplay or full-game stability.

## 2026-10-31 — titled release and reversible cleanup

At that time, the distributable was `user-data/releases/Star-Fox-Assault-Recomp-v0.2.0-rc.1-Windows-x64.zip`. Its payload and source-only exclusion checks passed, and the local update/rollback suite passed against this named archive. Packaging defaults use the project title, version and Windows platform in the filename.

Seventeen superseded release ZIPs (plus their checksum sidecars), four duplicate extracted test installations, and an unused zero-byte scratch lock were sent to the Windows Recycle Bin. The redundant copies totaled 5.34 GiB; this is recycled data, not a claim of immediately reclaimed disk space. Fifteen report/log/screenshot files were copied and SHA-256 verified before recycling, under `user-data/verification/archived-release-evidence/`. Earlier relocated-test report paths below can be found under that archive, preserving each test folder name and its internal relative path.

Source, the active native executable, downloaded tools, the active build cache, real saves and launcher settings were retained. Protected executable/save/settings hashes remained unchanged. The original supplied CISO still matches `F36D82912AAA67EB726E5892E05ABC6259A9C718B34DAE123AC8F3FF5640EEB6`. Cleanup receipt: `user-data/cleanup/20261031-164433.json`.

## 2026-10-31 — extracted source-package build and Unicode paths

The audited source-only ZIP `20261031-162542.zip` (SHA-256 `839a135c2f1453a378993cf027ca8a9f02ec5002eea163ce947ca5d3a6b02a86`) was extracted into a new folder containing spaces and Ω. It started without a native game executable, generated game code or game build cache. The actual packaged launcher **Import & Build** button invoked the real worker, freshly extracted the pinned LLVM-MinGW/CMake/Ninja/Python archives, compiled **101 Ninja units**, and published a 42,158,080-byte native game executable (SHA-256 `DA9FE00150D528E5E37FC2FC667A135F4A9CB0755A405ABCDCC460BE0E25E89F`). PATH contained only Windows system directories. The original LocalAppData settings hash stayed unchanged. Evidence: `user-data/verification/relocated final Ω build 839a135c 20261031-162610/user-data/verification-relocated-build-result.json`.

This relocation test seeded only previously verified tool archives and the portable SDL SDK; it did not copy game code, a native executable or an existing game build cache. The earlier portable worker separately performed and verified all four official archive downloads and the SDL source fetch/build. The combined online first-launch GUI action was not retested from an empty network cache. This distinction avoids claiming a fresh-PC installation test.

A silent, hidden normal-speed startup from the relocated package survived its 10-second bound and rendered readable health-and-safety text. Both replacement font files were logged as loaded from the Ω folder. It used an isolated test save path. The harness intentionally forced termination at the time limit; no natural-exit or full-game stability claim is made. Evidence: the relocated package's `user-data/validation-runs/20261031-162843-0b3e6001/result.json` and `frames/output_00200.png`.

The runtime now embeds `runtime/runtime/assault.manifest`, selecting UTF-8 for Windows narrow argv/environment/file APIs. A before/after probe lost Ω and failed file access without the manifest; with the manifest, argv, GCN_FONT_DIR, std::ifstream and CreateFileA tests passed. The regression passes under both MSVC and portable LLVM-MinGW, including a relocated source/build folder. Evidence: `user-data/verification/utf8-path-matrix.txt`. This setting requires Windows 10 version 1903 or newer. The full isolated suite now passes **9/9** in `user-data/verification/runtime-regression-tests.txt`.

The main project also built with the embedded resource successfully (`portable-utf8-build-status.json`): SHA-256 `99A2F6B03D228E3ED9F1D732D8B11D2E72D9B86974C8118A51A48A7D2D866905`. Different build/source paths produce different executable hashes. An offline cached rebuild succeeded, and an identical executable no longer replaces the previous-build backup: its hash and modification timestamp stayed unchanged (`portable-backup-preservation.json`).

The shareable package includes scoped MIT terms for project-authored software, component notices, original artwork/icon provenance, credits and sanitized release validation. Default ZIP checks reject game images, extracted/generated game code, saves/settings/caches, private paths and unexpected executable/art files. Local-update tests preserve recipient-built executables and user data. The first-boss visibility defect and current-thread-pointer crash remain unresolved; this is an experimental release candidate.

## 2026-10-31 — launcher-integrated portable native build

The source distribution now builds the game from a recipient-selected USA GF7E01 ISO/CISO through the launcher. The build worker uses pinned portable LLVM-MinGW 20261020, CMake 4.4.5, Ninja 1.13.2 and Python 3.13.17. All four official archives were actually downloaded and passed the SHA-256 values in `tools/portable-toolchain.json`; setup output is in `user-data/verification/portable-tool-setup.log`. SDL 2.30.9 is fetched separately with its CMake-pinned SHA-256.

The actual portable Release build completed successfully, recompiling the supplied CISO and linking the native executable. Earlier attempts failed on a Windows CMake resource-compiler path and missing C/C++ standard headers; those failures were fixed before retrying. Worker failure exit codes are now propagated. Final build status: `state=succeeded`, `percent=100`; log/status: `user-data/verification/portable-native-build.{log,json}` (the JSON status is `portable-build-status.json`). The resulting executable is 42,157,056 bytes, SHA-256 `CFB059052A2B0B44BBC72E690CF9F2B9B7B8AF9FFC529C48103EAF7640B0BDEF`.

A subsequent unchanged build took **1.37 seconds**, exited 0 and reported `ninja: no work to do.` This is a cached-build duration, not first-build timing or a game-performance comparison. Evidence: `user-data/verification/portable-cached-build-{result.json,log}`. DLL import inspection found Windows/UCRT imports only, with no VCRUNTIME, MSVCP, SDL or compiler-support DLL requirement. The standalone image inspector imports only KERNEL32. Evidence: `user-data/verification/portable-dll-imports.{json,txt}`.

The real worker rejected a synthetic invalid image with exit 1 / `failed` and honored an existing cancel request with exit 2 / `cancelled`; the prior executable SHA-256 stayed unchanged. Evidence: `user-data/verification/build-worker-0ad75cda7ce140b58d8fe5ee1dd2c9ac/results.json`. An AST harness using the actual process helper cancelled a synthetic parent/child process tree, confirmed both stopped, and preserved a prior executable sentinel: `user-data/verification/build-cancel-process-tree-run/result.json`. Build-cache relocation now triggers fresh CMake configuration; the launcher receives atomic build-status replacements. Cancelled/failed tool extraction cleans only its checked staging directory.

The launcher passed real read-only image inspection and synthetic invalid-image rejection, fresh-use CTA states, a mocked asynchronous successful build, and a mocked cancellation that retained the sentinel previous build. The build mocks exercise UI orchestration; the separate real worker build above exercises compilation. Evidence: `launcher-onboarding-51b8cd3a719945c5ae38a4439ed6faf4`, `launcher-build-ui-0da759dd1fdb428fa2ef4e5f76fe8fdc` and `launcher-build-ui-187208a3b69e482b850040d7e28059ee` under `user-data/verification/`. All seven launcher pages rendered at default and minimum sizes; captures are in `ui-review-c5ff0e8d80d44a6d98b983316cd6db93`. These are application-render captures, not physical desktop/controller tests.

The isolated runtime suite passed **8/8**: display options, render math, audio gain, disc overlays, texture coordinates, REL rebinding, thread-watch filter and ISO/CISO image-reader cases. Output: `user-data/verification/runtime-regression-tests.txt`. The portable executable survived a 10-second silent hidden normal-speed startup check, rendering readable health-and-safety text; the harness then forced termination at the bound. This does not establish gameplay compatibility. Evidence: `user-data/validation-runs/20261031-161351-f5accf39/result.json` and `frames/frame_00200.png`.

The original supplied CISO still hashes to `F36D82912AAA67EB726E5892E05ABC6259A9C718B34DAE123AC8F3FF5640EEB6`. The project artifact/syntax/original-preservation verifier passed all 28 checks. Existing disappearing-boss and current-thread-pointer crash reports remain open. A clean extracted source-package build is being checked separately; no stable full-game claim is made.

# Validation record

## 2026-10-31 — live boss report, depth correction and final launcher design

The user reported the first boss disappearing even in the center of the screen. Two read-only computer-use observations of the live session showed the Arwing, terrain and attack effects drawing without a visible boss model. The session subsequently terminated with `MMU: access to 3F0002C8 with no page table`, LR `80136C60`. The launcher log is `user-data/native-run/logs/native-20261031-135627-944-7349e7.err`; it had loaded mb01a and mb01b. The game was not closed by the assistant. No synchronized boss snapshot or input recording was available from that session, so its exact state could not be replayed.

Static analysis shows the failing SDK routine reads OSCurrentThread at `0x800000E4`, receives `0x3F000000`, and then writes a field at offset `0x2C8`. The source of the bad pointer remains unconfirmed. The MMU failure now optionally writes RAM, prints guest thread/call-stack context and includes the access direction/current-thread value. Launcher children receive a unique session-local RAM dump path and watched address, with the parent's prior environment restored after successful and failed starts. The crash viewer names a RAM dump only if it exists. Real input-recording preferences were preserved.

A separate, concrete renderer bug was corrected: widescreen changes projection X but the depth-freeze plane was fitted using the old X coordinates. The actual fitting code is now in `gx/render_math.h` and receives the per-draw aspect transform. Its regression verifies the original 4:3 plane, the corrected 0.75 plane against an independent interior depth sample, stale-plane depth error and exact degenerate geometry. This proves the math correction; it does **not** prove that the user's boss disappearance is fixed.

The initial broad watched build was replaced with optional `GCN_THREAD_WATCH`, which filters store addresses inline and only calls the trace callback near the low-memory word. It preserves the separate `GCN_WATCH` option. A C11 regression checks cached/uncached RAM aliases and excludes locked cache/heap addresses. An initial C-interface `bool` compile error was corrected to an `int` return type and the test was changed to compile the real interface as C11.

The final Release build returned exit 0, log `user-data/verification/boss-thread-watch-build.log`. It was promoted byte-for-byte to the isolated package candidate, rather than described as a second independent build. Both SHA-256 values: `51B0316FE58552335F30819314B79A22726C09652FE73FC34CD40E8A8DF0DA9E`. This development artifact has narrow watching and call tracing enabled; clean-build defaults leave watching off. Existing compiler warnings remain.

```text
100% tests passed, 0 tests failed out of 7
graphics-test: sharp-step=1 smooth=64/191 sharp=52/203
graphics-test: flat=1 letterbox=1 stretch=1 fxaa-edge=1 changed=334 gl-error=0x0 result=PASS
graphics: F8 aspect=original
graphics: F8 aspect=widescreen
graphics-test: F8-event-roundtrip=PASS
```

The final GPU/event log is `user-data/verification/boss-final-663ccdcf37754f4b9d0a87271a422671/gpu.err`. The F8 test uses actual SDL event queue processing and checks repeat suppression. A previous normal-speed, muted visible startup check exited cleanly after 60 seconds (`20261031-143139-5ebe0916`), but injected computer-use F8 presses produced no matching log; that attempt is not claimed as physical-hotkey verification. Final-output capture now requires a nonzero `GCN_DUMP_OUTPUT`, avoiding accidental capture when a host retains an empty environment value.

The final isolated, hidden/silent 300-second replay (`user-data/validation-runs/20261031-144428-0a6e5d41/`) reached frame 30000 in the first Arwing battle, then was stopped at its bound. Its copied seed remained isolated; watched E4 changes were only the expected scheduler select/clear stores (`80136328` / `8013626C`). It did not load mb01a/b, reproduce the invalid pointer, or reach the reported boss state. Two earlier bounded broad-watch attempts also failed to reach the boss; an input-string interpolation mistake in the first was corrected before the subsequent runs. No boss-success or crash-root-cause claim is made. Retesting the reported boss with the new executable remains required.

The launcher received a separate designer review and a final Assault-inspired steel/teal treatment: aspect-preserving Arwing hangar artwork, chamfered bevels, cyan/violet focus, Bahnschrift SemiBold headings/buttons and Segoe UI body text. Repeated Home branding/status wording was removed; region/ID appears once, and disc status says Found rather than claiming verification based solely on a path. Section hierarchy, spacing and dark dropdowns were reviewed at default and minimum sizes. The prior art remains a fallback. The new art was made with built-in imagegen; its complete generation/framing prompts are in `assets/assault-arwing-hangar.prompt.txt`, and attribution is in `THIRD_PARTY_NOTICES.md`.

All six pages rendered at 1496x939 and 1180x720. Final editorial/layout captures are in `user-data/verification/ui-review-24f8bd72e39f4e2daa26eef914f6ac8a/`; the icon-bearing Home capture is `ui-review-23740f89289e416fb3c372131091f7e0/default-home.png`. Offscreen nonactivating forms and a message loop were used so actual dropdown selections rendered; background-only captures were rejected as insufficient. Early owner-draw constructor errors were fixed before the passing review. The PowerShell 5.1 scratch harness passed save/reload, actual handler launch arguments, environment restoration on success/failure, unique RAM dump paths, crash viewer gating and image/icon file unlock checks. No real saves/preferences were modified by those harnesses.

The original vector wing icon is generated at seven sizes (16 to 256) by `tools/Build-LauncherIcon.ps1`; the Windows bootstrap was rebuilt with the icon resource, and both standalone and associated executable icons load. An actual source-entrypoint child opened with the expected window title/handle and Responding=True; the computer-use inventory did not expose that WinForms window, so direct visual desktop QA relied on the rendered source-form captures rather than a claimed automation screenshot.

Final project verification passed 25 checks, including the original image baseline. Final package `user-data/releases/20261031-150921.zip` contains 221 verified payload files, SHA-256 `F39634C1D3B8C4AFB14A3327A7C9C25B8422650BC6A1F30906EB50846C8FE5BF`. Extraction/hash, forbidden-content and PowerShell parsing checks passed. User cards, RAM dumps, disc images and extracted game code are excluded.

## 2026-10-31 — stretched UI and soft output correction

The user's saved configuration was Auto/widescreen/fullscreen/VSync with FXAA enabled. The previous wide path changed every flat perspective projection but left orthographic menu/HUD geometry unchanged. Final-output inspection confirmed stretched 2D artwork and labels. The new path tracks onscreen perspective draws across the submitted frame: 2D-only menus/movies retain the Original 4:3 viewport; world frames use 16:9, with bounded ortho HUD X and scissor bounds corrected by 0.75 around the viewport center. Full-frame overlays and offscreen render passes retain their projection. The global scissor and per-program projection caches include the new transform inputs. Submitted batches flush at a completed display copy (`xf.cpp`), so batch pre-scanning does not mix successive frames.

Sharp output uses separable Catmull-Rom bicubic reconstruction, clamped to the local contrast and guest display rectangle. Smooth retains bilinear filtering. This implementation uses the mathematical filter family described in [Mitchell and Netravali's paper](https://courses.cs.washington.edu/courses/cse557/02wi/lectures/mitchell/Mitchell.pdf); no library or shader source was imported. The GPU regression reads back a quarter-texel step: Smooth gives 64/191, Sharp gives 52/203, preserving more contrast at that synthetic edge without changing flat regions. FXAA remains independently selectable and can soften text/HUD.

Windows now requests per-monitor V2 DPI awareness and DPI-scaled window coordinates before video initialization, following [SDL's DPI awareness](https://wiki.libsdl.org/SDL2/SDL_HINT_WINDOWS_DPI_AWARENESS) and [DPI scaling](https://wiki.libsdl.org/SDL2/SDL_HINT_WINDOWS_DPI_SCALING) APIs. Widescreen windows start with 16:9 dimensions. Actual log output on this PC:

```text
display pixels: window=1280x720 drawable=1600x900
graphics: OpenGL, aspect=widescreen, aa=off, filter=sharp, scale=2.50 (match window)
graphics-test: sharp-step=1 smooth=64/191 sharp=52/203
graphics-test: flat=1 letterbox=1 stretch=1 fxaa-edge=1 changed=334 gl-error=0x0 result=PASS
100% tests passed, 0 tests failed out of 5
```

Match window now incorporates actual guest display dimensions, including the game's 448-line surface, rather than assuming 480 lines. Regression cases cover that resolution selection, 2D-only frame presentation, world/HUD correction, excluded offscreen draws and transformed HUD scissor edges. Both Release builds completed; main SHA-256 `88F2401007C003BCFEDBBB95289264469B1C08751CCCE441358746C814657995`; candidate SHA-256 `8E803DE7BE3C9A938F9CC5B3DFD211FAD64517C49BFFF89BB18227BE3A43D2E1`. Existing MSVC warnings remain.

The candidate's isolated hidden/silent 90-second replay (`user-data/validation-runs/20261031-121121-38594af2/`) survived to the bound without a fatal error or crash RAM dump, then was forcibly stopped (93.25 seconds with grace, exit -1). Four raw and four final-output images were collected. `output_04000.png` is 1600x900 with a 1200x900 menu and 200-pixel side bars, preserving 4:3; `output_12000.png` fills the 1600x900 frame with the first-mission world and HUD. These were visually inspected. This does not establish mission completion or a clean exit. Final-output capture is optional (`-CaptureOutput`) and honors the existing dump interval/range.

The in-process Windows PowerShell 5.1 launcher harness passed both filter save/reload and exact launch-argument checks independently of AA, plus minimum-width/no-overlap checks. Evidence: `user-data/verification/launcher-graphics-dcb2e66e3ac04ce79fa53d365ea8f92d/result.json`; inspected settings image: `launcher-graphics-235e51380e9543b38da943060b3d0e95/settings-page.png`. The final candidate rejects `--filter=invalid` with exit 1 (`crisp-cli-01c2d21ccb4a4b16878a805ab9cbd6da`).

Real user preferences were backed up to `user-data/settings-backups/before-crisp-20261031-121218.json`, then AA Off and Sharp were saved and read back. Auto resolution, widescreen, volume, fullscreen and VSync were retained. The original game image still matches its baseline. The regenerated Windows PowerShell 5.1 package is `user-data/releases/20261031-121452.zip`, 214 verified payload files, archive SHA-256 `1A21A876AD4DDB667EA0BB1637E7E1EF7980D194CD5AAD4D99899098F887EEE9`.

Remaining visual limits: the original textures/bitmap text are not HD replacements; guest culling still needs camera-specific work; unusual overlay layouts remain unverified; a 2D-only fade between 3D scenes may briefly present at 4:3. Widescreen remains experimental. Public game-specific widescreen patch addresses were investigated against local analysis metadata, but no unverified guest patch was shipped in this change.

## 2026-10-31 — graphics controls and resident REL callback

The installed Foxhollow Settings page was inspected directly. Its video controls include original/widescreen aspect, Match window and 1/1.5/2/3/4x resolution, fullscreen, VSync, and Automatic/D3D12/D3D11/Vulkan renderer choices. No anti-aliasing selector was visible. This project's graphics controls now expose actual original 4:3, experimental 16:9 and fill-window presentation; true fractional render resolution; window-matched resolution; Off/FXAA; fullscreen and VSync. The backend remains OpenGL. Unsupported renderer options are not shown.

Widescreen scales the perspective projection's horizontal coefficients by 0.75 and presents at 16:9. This is not complete game-specific widescreen support: guest culling and 2D layout are unchanged. FXAA is applied during final presentation, with sample bounds restricted to the guest display rectangle. It is independently implemented from the published local-contrast directional-filtering method ([NVIDIA paper](https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf)); no vendor shader source was imported. HUD and text are included in the filtering; raw EFB frame dumps precede that pass.

Both sequential Release builds completed successfully. Main executable SHA-256: `080CA2D5C2B57531100A7B873629F30C4D52A504462EE530B603DC66F9DF3B99`; separately built package candidate: `A0EC2256D0F6502FB1595A960DB8BFBBB3A2F98B537D737BE75511F5C2671FAA`. Existing MSVC C4996 and C4805 warnings remain.

The hidden GPU check `--hidden --test-graphics --scale=1.5 --aspect=widescreen --aa=fxaa` exited 0. It executes the real final shader against synthetic FBO textures: flat colors are unchanged, widescreen letterboxes, stretch fills, and FXAA changes 334 pixels around a diagonal edge; `gl-error=0x0 result=PASS`. The independent Auto check (`--scale=0`) selected 2.00 for the 1280x960 drawable and passed the same checks. Invalid scale values 0.5/1.5x/nan/9, invalid aspect and unsupported AA were rejected with exit 1. Evidence: `user-data/verification/graphics-cli-33d019b9aed8479899902092230607f6/`.

Command output from `ctest --test-dir user-data/verification/runtime-tests -C Release --output-on-failure`:

```text
display_options_test ... Passed
audio_gain_test ... Passed
disc_mods_test ... Passed
texcoord_test ... Passed
rel_rebinding_test ... Passed
100% tests passed, 0 tests failed out of 5
Total Test time (real) = 0.14 sec
```

The candidate ran hidden and silent with 1.5x/widescreen/FXAA for an 80-second bounded check (`user-data/validation-runs/20261031-113524-d9c19f54`). It reached the first mission's rendered scene and HUD; frame 12000 is 960x672, proving the fractional surface dimensions. It survived the time limit without a fatal error or crash RAM dump, then required forced termination (83.28 seconds including grace, exit -1). This is not a clean-exit or completed-mission claim. The original seeded card was copied into the run folder.

The previous extended combat failure at `0x815F2D1C` was a resident m9 callback rejected after OSUnlink restored file-relative section descriptors. Identity/variant-validated resident mappings now accept that header state; successful generic unlink cleanup runs after the SDK call. The added regression passes. The prior candidate's hidden 180-second replay (`20261031-072445-a212f1ba`) passed that crash point, recorded a hit, reached GAME OVER and returned to the main menu. That run also required forced termination at its time limit; mission completion remains open.

The Windows PowerShell 5.1 packaging path initially exposed a missing explicit compression-assembly load; it is now loaded before packaging. A rerun created `user-data/releases/20261031-113845.zip`: 214 payload files passed extracted SHA-256, excluded-content and PowerShell parser checks. Archive SHA-256: `7258BC65100A416F95FD2FB74F887EF1BDEFB2146437C11DD59E668C4B7CCC99`. No disc images, extracted game executables or user cards are included. The project verifier passed, including the unchanged original CISO baseline.

The actual WinForms Settings handlers passed an in-process Windows PowerShell 5.1 save/reload/launch-wiring check. It saved and reloaded 1.5/widescreen/FXAA and Auto/stretch/off, then verified the exact native arguments using a mocked process launch. Volume 37, VSync, fullscreen, normal timing override/restoration and unlocked background-image handling were retained. All paths were isolated under verification; no native game was launched by this harness. Its 1496x939 render fits the settings controls and card, with scrolling enabled. Evidence: `user-data/verification/launcher-graphics-cd6814296c794460b42afcbd06ae47b0/{result.json,settings-page.png}`. Physical fullscreen behavior, multiple display scales, and resize-during-game Auto transitions still need direct UI checks.

## 2026-10-30 — fresh native run and artifact audit

`powershell -NoProfile -File tools/Verify-Project.ps1` returned exit 0. All nine checks passed: original image baseline, syntax of three PowerShell scripts, native executable presence, 23 distinct standalone REL entries, and presence of artwork/license/notices. Detailed machine-readable evidence is kept in ignored `user-data/verification/project-verification.json`.

The original `D:\Emulators\Roms\GameCube\Star Fox - Assault (USA).ciso` was read directly for hashing. Size: 1,329,627,712 bytes. SHA-256: `F36D82912AAA67EB726E5892E05ABC6259A9C718B34DAE123AC8F3FF5640EEB6`, matching the recorded baseline. Its modification timestamp remains 2022-10-18.

The native executable checked at this point was 26,564,608 bytes, SHA-256 `F28198E54315768911E350FAB2338A4876813D6255F08C1DC1D98F4F265C8444`. A subsequent build changes that fingerprint; rerun the verifier to record the new artifact.

A fresh desktop run used `--scale=1 --input-log=saves/inputs/prototype-scripted` with `GCN_INPUT=120:START:30,1200:START:30,1800:START:30`, from `user-data/native-run`. It passed the safety screen and rendered the opening character movie, then registered m4 and m2. The window reached approximately 60 fps with dialog borders and selection frames visible. Dialog text was absent. This run establishes progress beyond the intro movie, **not playable gameplay**. Logs: `user-data/native-run/prototype-scripted.err`; input recording: `user-data/native-run/saves/inputs/prototype-scripted/`.

## Remaining acceptance work

- Extend first-mission flight checks to mission completion, later stage transitions, checkpoint saving/loading, full audio fidelity and physical controllers.
- Verify every launcher page through its actual user actions, resizing and common display scales.
- Complete Foxhollow feature parity: native function patches, resized assets and mod settings, release updates/catalog, renderer options and supported online services. Local asset packs, card labels/tags and a controller mapping editor now exist; their coverage does not establish full parity.
- Package a reproducible launcher/native release using user-supplied game data; verify on a clean local installation.

The project remains a prototype until these checks are complete.

## 2026-10-31 — first-mission flight, normal pace, profile persistence and package

Hidden run `user-data/validation-runs/20261031-063237-36030b52` survived its 120-second time limit and captured real flight gameplay, including Arwing/HUD/reticle, dialogue, scripted steering/firing, damage and respawn. Frames 18000, 19000 and 20000 show flight with changing ship position and a life-count transition from 04 to 03. The harness then forcibly stopped its hidden process after the grace period (reported exit -1); this was an intentional time limit, not a clean game exit or proof of mission completion.

Profile reload was tested with an isolated copy of that run's 524,288-byte card, SHA-256 `99D17BC3CCCEC4108F79930888A37154F9BA0018B4D8BD373BF1CAC7308E90EA`. Run `20261031-063635-c8b9af11` shows saved player `A` at frame 3500 and Story / Mission 1 at frame 4500. The seed card was only read; the test wrote to its own new copy.

The corrected Release candidate (`user-data/verification/desktop-release/Release/assault.exe`, SHA-256 `844C604CDD7C9D5211BB31DDC664CA9CA96BDBF8BF6AC7888DD7D5E121E58D06`) passed a hidden normal-speed 240-second run: `20261031-063956-6d6de183`. It survived the limit and was then intentionally forced closed. The flight capture at frame 10000 and steering capture at 11000 were written 16.6845416 seconds apart, giving 1000 / 16.6845416 = **59.9357 rendered game frames/s** for that segment. This measures one segment, not the entire game or every machine.

SDL's inner Visual Studio build had installed Debug into a Release-named shared cache because it omitted `--config`. The build now selects the requested configuration, validates matching package/library files and uses a versioned cache. A cached `SDL2_DIR` also needed explicit migration; otherwise find_package retained the old Debug package despite the new prefix. The separate Release candidate links `SDL2-static.lib` with MSVCRT, and both the candidate and repaired main build relinked without LNK4098. Existing MSVC CRT deprecation diagnostics are still present in source builds.

The rebuilt main executable is 25,525,248 bytes, SHA-256 `692D7B576791B792C499AB1A81263B00FDFCF11C4BA96E90B78173D3AF8FF830`; its silent hidden startup check survived five seconds (`20261031-065202-152a94c3`). Hidden checks now use the dummy audio output so they do not play accelerated sounds on the desktop.

`tools/Package-Prototype.ps1` creates a local prototype ZIP with the validated Release candidate, launcher, necessary source/build metadata, licensed fonts and notices. It excludes disc images, extracted DOL/REL files, cards, analysis directories and generated game C. It extracts its own ZIP to an isolated scratch directory, checks every payload against SHA256SUMS.txt and parses all included PowerShell scripts. This package is a working first-flight prototype; full Foxhollow feature parity and game-wide compatibility remain open.

## 2026-10-31 — readable menus and REL address reuse

The font draw's SU scale registers were both zero (encoded scale 1), while the font image was 512×512 and the submitted UVs were in pixels (for example 288,24). The renderer incorrectly multiplied by image size and divided by the same size, leaving UVs outside the normalized image. It now sends coordinate-slot SU scale separately from texture-map dimensions for ordinary and indirect sampling. Automatic image-size scaling is preserved; framebuffer coordinates supplied by the VR override retain their image-size conversion.

Release build returned exit 0. The fresh bounded run at `user-data/validation-runs/20261031-061639-85761181` survived 20.31 seconds and closed normally (exit 0). `frames/frame_01400.png` shows the previously blank memory-card dialog with readable text; `frame_04000.png` shows the complete main-menu choices; `frame_05800.png` shows the letter grid and entered character. The tested binary SHA-256 was `F8ECE41A17D5C54BB1395C857B51B97BF79908182DF23223E5887DF69BB54BE5`.

A longer run (`20261031-061900-3048d954`) reached the first mission but failed at `call_indirect(0x81558590)` after 41.58 seconds. The old m2 mapping assumed text at header+0xDC. The game's anonymous loader reused that header for m5, whose text starts 16 bytes earlier at header+0xCC; logs record the reuse at `0x815583C0`. Runtime mappings now validate current module identity/section descriptors, retire overlaps and retry binding on misses. The same 55-second sequence then survived and exited normally: `user-data/validation-runs/20261031-rel-fix-2543d5b1/result.json`. Its `frame_12000.png` shows the mission opening cinematic. This is **not yet proof of player-controlled gameplay**.

The REL lifecycle regression links the real implementation and checks reused headers and overlapping ranges. Coordinate tests cover manual pixel UVs, automatic scaling and the full 16-bit scale field. The independent disc-overlay tests remain in the runtime test suite. Release builds still report MSVC CRT deprecation warnings and an LNK4098 runtime-library warning; these are recorded, not claimed resolved.

After the user reported accelerated motion, visible fast testing was stopped. The game was reopened without `--fast` or scripted inputs, with `GCN_TIMESCALE=1`; its safety screen reported 30 fps. Normal launcher play now explicitly selects normal timing, and the check harness defaults to hidden windows and refuses visible accelerated checks.

The check harness is `tools/Run-NativeCheck.ps1`: it uses a unique project-local folder, sets font resources explicitly, records logs/inputs/frames and fingerprints the binary, then bounds and reports the run. Each report states its limited scope; surviving the time limit does not establish gameplay correctness. Earlier default-working-directory test artifacts were recovered from the unrelated Obsidian folder into ignored `user-data/recovered-test-runs/`, with hashes preserved.

## 2026-10-30 — system-font ROM dependency

The same scripted run that showed the blank dialog logged EXI ROM reads starting at `0x001FCF00`, previously unsupported and returning zero. The locally installed Dolphin distribution includes generated Droid Sans replacement fonts under Apache-2.0; those two binaries and their full attribution/license are now in `assets/fonts/`. The native launcher passes their absolute directory through `GCN_FONT_DIR`.

The device mapping preserves the compressed font stream: the game loader at `0x80131DB0` checks for `Yay` and calls its own Yay0 decompressor at `0x80131BD8`. Independent decoding of the Western source produced 65,808 bytes, SHA-256 `1755F3A9152A915365DF4F0F33438482AAB1B259FA8ADB902DFFAE106BDF1271`; the oracle and metadata are in `user-data/verification/font-oracle/`. EXI diagnostics confirmed the returned `59 61 79 30` header. This establishes the ROM-byte contract, not a successful full guest-font decode.

The later `text-font-raw/frames/frame_04000.png` screenshot shows name-entry labels and controls, while its letter grid remains blank. The earlier dialog remains under investigation. Full menu text and gameplay are not yet verified. Project verification currently passes sixteen file/syntax/metadata/font checks.

## 2026-10-30 — reproducible metadata, native assets and session tracking

The main symbol file and all 46 per-REL metadata files in `decomp/config/GF7E01/` matched the previous local analysis files byte for byte. CMake now reads these source files, preparing per-REL copies in its own output folder. A fresh configure under `user-data/verification/clean-configure` succeeded against the supplied original CISO; the resulting Release `assault_bench` build completed with exit 0. MSVC reported existing CRT deprecation warnings. An accidental overlapping build was stopped; the subsequent clean build is the verified result.

The fresh headless artifact completed 2,122 frames in 3 seconds with exit 0. This is a startup check only, and does not exercise rendered menus or gameplay. Output: `user-data/verification/clean-bench-run/startup-check.txt`.

Native asset overlay synthetic tests passed (1/1 CTest), covering intersecting reads and rejected sizes/unsafe/system/executable paths; symlink creation was unavailable on this Windows installation. Integration with the newly built headless runtime was also checked using a synthetic, zero-filled `opening.bnr` replacement of the disc's exact 6,496-byte size. Startup succeeded; the same replacement with 6,495 bytes was rejected before guest boot. This verifies overlay loading and size enforcement, not visual mod behavior. Evidence: `user-data/verification/native-overlay/{valid,invalid}-startup.txt`.

The save-page harness used synthetic memory cards only, verifying label/tag persistence, checksum/size/date display, wrong-size restore blocking, valid restoration, and an automatic pre-restore backup. The native ZIP harness verified exact-size import, size rejection without changing the active pack, backup retention, rollback of files and metadata, and traversal rejection. Physical card data and original disc bytes were not changed by these harnesses.

Playtime tracking was exercised using a short-lived process under Windows PowerShell 5.1: the tracker finalized a 2.19-second session when that process exited. A separate synthetic 5,400-second record displayed as `1H 30M PLAYED`. The tracker checks both process ID and start time to distinguish reused IDs, runs independently of the launcher, and checkpoints every ten seconds. These synthetic records remain under verification folders and do not count as real play history.

## 2026-10-30 — Windows launcher executable

`tools/Build-Launcher.ps1` compiled `tools/LauncherBootstrap.cs` with the installed .NET Framework C# compiler, producing a 6,144-byte Windows GUI executable. The launch test produced a visible, responding `Star Fox Assault Recomp` window and then closed only that test instance. The existing launcher remained open. The executable locates the PowerShell UI beside itself, launches without a console, and displays an error dialog if its dependencies are absent. The main build action now rebuilds this entry point, and the command file prefers it when present.

After integration, `tools/Verify-Project.ps1` returned exit 0 with **eleven checks passed**, including the additional bootstrap build-script syntax and launcher executable fingerprint checks. The current report supersedes the earlier nine-check artifact audit above.

## 2026-10-30 — controller mapping and launch diagnostics

The new mapping editor was exercised with a local modal harness: it added `A = "Test Pad" button 0`, retained `B = key X` and `stick_x_min = 7`, and wrote UTF-8 without a BOM. The native runtime accepted that file using `--test-ffb --controls=...` and reported two bindings and the retained stick range, with no ignored-line warnings. This checks file generation and runtime parsing; a physical controller still requires user input to validate its bindings during gameplay.

Native launches now create distinct stderr/stdout files under `user-data/native-run/logs/`, which the Crashes page already enumerates. Calling the actual launch function while a game was running produced the expected duplicate-session refusal. This protects a shared native memory card from concurrent launcher sessions. A separate launch-function smoke test used an isolated scratch run folder and card, reached the safety screen, and captured 1,338 characters of boot diagnostics including the GF7E01 disc header. Its process was then stopped. Evidence: `user-data/verification/launch-smoke/logs/native-20261030-220453-802-c3cea1.err`. The runtime's open redirected file did not publish its final length until the process closed, so file length is not a live-run health check.
## 2026-11-03 — replay save isolation and stability investigation

The native executable rebuilt successfully from the existing local tool cache after a change to input replay: replay now refuses to start without the recording's memory-card snapshot, and the snapshot copy reports read/write/flush/close failures. This closes a path where a failed snapshot copy could make replay write to the live memory card. The first-boss disappearance and the recorded current-thread-pointer crash are **still unresolved**. The retained boss evidence has no matching gameplay recording; the crash log shows the pointer was already invalid before the SDK dereference. Capture an isolated, normal-speed controller/input recording and frames at the failure to continue diagnosis. This focused rebuild does not validate either gameplay fix.
