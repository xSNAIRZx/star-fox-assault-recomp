# Credits

Star Fox Assault Recomp is an independent fan project. It is not an official Nintendo or Namco release and is not affiliated with or endorsed by those companies. Game names, characters and third-party marks remain the property of their respective owners. No trademark registration or official endorsement is claimed.

The original Star Fox: Assault game was published by Nintendo and developed by Namco. Each player supplies their own supported USA game image (GF7E01). The shareable project excludes game images, extracted DOL/REL files and generated game code/executables.

- Native runtime and static recompiler: Ethan Nicholas's **gcn-recomp**, MIT; full license in `runtime/LICENSE`.
- Analysis metadata workflow: **decomp-toolkit / dtk-template**. See `THIRD_PARTY_NOTICES.md`.
- Launcher design, integration and original vector wing icon: Star Fox Assault Recomp project contributors, with AI-assisted development.
- Hangar illustration: game-inspired artwork generated with built-in imagegen. Prompts are preserved alongside the artwork; it is not extracted game art.
- Game system-font replacement: Droid Sans-derived resources, copyright Google, Apache-2.0; full notice in `assets/fonts/font-licenses.txt`.
- Interface typography: Windows-provided Bahnschrift SemiBold and Segoe UI. Font files are not redistributed.
- SDL 2.30.9: zlib license, retained in `third_party_licenses/`.

The optional first-build tool download uses pinned LLVM-MinGW, CMake, Ninja and Python releases from their official publishers. Their licenses remain with the downloaded distributions in the local tool cache. See `tools/portable-toolchain.json` for exact versions, source URLs and SHA-256 values.

Compatibility remains experimental. The first-boss visibility report and invalid-current-thread-pointer crash are still being investigated. See `RELEASE-NOTES.md` and `VALIDATION.md`.
