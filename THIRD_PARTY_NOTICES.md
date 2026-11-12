# Star Fox Assault Recomp third-party notices

## Launcher artwork
- `assets/assault-arwing-hangar.png` is game-inspired concept artwork generated with the built-in imagegen tool for this launcher. Generation and framing prompts are retained in `assets/assault-arwing-hangar.prompt.txt`.
- The earlier generated `assets/assault-launcher-background.png` is retained as a fallback. Neither background is extracted from the supplied disc image.
- `assets/assault-launcher.ico` is an original project icon drawn by `tools/Build-LauncherIcon.ps1` from geometric shapes and project colors. It is not extracted from the game or another application.
- The launcher artwork depicts Star Fox series subject matter for an unaffiliated fan project. Nintendo and Namco retain rights in the game and its characters; the art does not imply endorsement.

## Replacement GameCube system fonts
- Files: `assets/fonts/font_western.bin`, `assets/fonts/font_japanese.bin`.
- Source: the user's installed Dolphin distribution (`Sys/GC`); generated replacement fonts, not Nintendo IPL ROM dumps.
- Pinned upstream: byte-identical to `Data/Sys/GC/font_western.bin` and `font_japanese.bin` in <https://github.com/dolphin-emu/dolphin> at commit `0f1ce0e1f42ae6f149405778457116abba87af72` (the last commit to change them, 2016-12-26). SHA-256: `4ad991be2b0aa305f09b90a79fc50f57833b30b008890b5ef1336cc3d9d0bae0` (western, 6,478 bytes) and `38f9f59d505bc4e2d86b0196706195f33ad72b7fe9d029cf263072cde19d044f` (Japanese, 259,626 bytes). `font-licenses.txt` matches that commit's copy apart from CRLF line endings. Checked 2026-11-11.
- Based on Droid Sans. Copyright 2006–2014 Google Corporation. Licensed under the Apache License, Version 2.0.
- The distribution's attribution and complete license are retained in `assets/fonts/font-licenses.txt`.
- The runtime independently serves these font bytes through its EXI ROM interface; no Dolphin emulator source code is included by this integration.

## gcn-recomp
- Source: https://github.com/ethannicholas/gcn-recomp
- License: MIT
- Used as a subdirectory runtime and static recompiler framework. Copyright 2026 Ethan Nicholas. See `runtime/LICENSE` for the full license.

## decomp-toolkit template and analyzer
- Source: https://github.com/encounter/dtk-template and https://github.com/encounter/decomp-toolkit
- The template is CC0-1.0; the toolkit's license is included in its upstream repository.
- Used for GameCube DOL/REL analysis. No game assets are included in source control.

## SDL2
- Version: 2.30.9
- Source: https://github.com/libsdl-org/SDL
- License: zlib; license text is in `third_party_licenses/SDL2-2.30.9-LICENSE.txt`.
- Fetched from the official SDL release archive by the first desktop CMake configure and built locally.

## GLAD OpenGL loader
- Version: 2.0.8; generated C loader sources and headers are in `runtime/runtime/gx/glad` and `runtime/runtime/gx/glad_es`.
- Project: <https://github.com/Dav1dde/glad>.
- The generated files identify their license as `(WTFPL OR CC0-1.0) AND Apache-2.0` in their SPDX headers. The Apache-2.0 license text is included in `assets/fonts/font-licenses.txt`.

## Optional first-build downloads
- The source package includes pinned download metadata in `tools/portable-toolchain.json`; the tool archives themselves download on the recipient's first **Import & Build** action and stay in the install's local `user-data` cache. They are not included in the source ZIP.
- LLVM-MinGW `20261020`: <https://github.com/mstorsjo/llvm-mingw/releases/tag/20261020>. The llvm-mingw project scripts are ISC licensed; the assembled toolchain contains components with their own licenses, including LLVM's Apache-2.0 license with LLVM exceptions. Component notices are included with the downloaded distribution. See <https://github.com/mstorsjo/llvm-mingw/blob/master/LICENSE.txt>.
- CMake `4.4.5`: <https://github.com/Kitware/CMake/releases/tag/v4.4.5>. BSD 3-Clause; the distribution includes its license and third-party notices. See <https://cmake.org/licensing/>.
- Ninja `1.13.2`: <https://github.com/ninja-build/ninja/releases/tag/v1.13.2>. Apache License 2.0. See <https://github.com/ninja-build/ninja/blob/master/COPYING>.
- Python `3.13.17`: <https://www.python.org/downloads/release/python-31317/>. Python Software Foundation License Version 2; the distribution includes its license and acknowledgements. See <https://docs.python.org/3.13/license.html>.
- Exact archive URLs and SHA-256 digests are pinned in `tools/portable-toolchain.json`. These notices identify upstream licensing; each downloaded archive retains its own license and notices.

## Package scope
- The default release is a source-and-host-tools package. It includes the Windows launcher and standalone image-inspector utility, but not the generated native game executable. That executable is built locally from the recipient's own supported game image.
- The package contains no ISO/CISO/GCM image, extracted DOL/REL, generated game code, memory-card data, profile/settings files, or build/cache output. The private native-prototype packaging switch is opt-in and is not used for the shareable source package.
- `decomp/config/GF7E01` contains analysis configuration, splits, and symbol-name metadata for the recipient's locally supplied disc. It contains no disc bytes or extracted executable code.
