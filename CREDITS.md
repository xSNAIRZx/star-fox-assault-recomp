# Credits

Peregrine Forge is the launcher brand for Star Fox Assault Recomp, an independent fan project. It is not an official Nintendo or Namco release and is not affiliated with or endorsed by those companies. Game names, characters and third-party marks remain the property of their respective owners. No trademark registration or official endorsement is claimed.

The original Star Fox: Assault game was published by Nintendo and developed by Namco. Each player supplies their own supported USA game image (GF7E01). The shareable project excludes game images, extracted DOL/REL files and generated game code/executables.

- Native runtime and static recompiler: Ethan Nicholas's **gcn-recomp**, MIT; full license in `runtime/LICENSE`.
- Analysis metadata workflow: **decomp-toolkit / dtk-template**. See `THIRD_PARTY_NOTICES.md`.
- Launcher design, integration and original vector PF monogram icon: Star Fox Assault Recomp project contributors, with AI-assisted development. The icon is used as the Peregrine Forge launcher mark.
- Hangar illustration: game-inspired artwork generated with built-in imagegen. Prompts are preserved alongside the artwork; it is not extracted game art.
- Flight-deck illustration: original AI-assisted fan artwork generated for Peregrine Forge, showing the Star Fox team and spacecraft. The composition prompt is preserved beside the image; it is not extracted from the game.
- Game system-font replacement: Droid Sans-derived resources, copyright Google, Apache-2.0; full notice in `assets/fonts/font-licenses.txt`.
- Launcher title typography: Orbitron, designed by The Orbitron Project Authors, bundled under the SIL Open Font License 1.1; license in `assets/fonts/orbitron-OFL.txt`. Other interface typography uses Windows-provided Bahnschrift SemiBold and Segoe UI.
- SDL 2.30.9: zlib license, retained in `third_party_licenses/`.

The optional first-build tool download uses pinned LLVM-MinGW, CMake, Ninja and Python releases from their official publishers. Their licenses remain with the downloaded distributions in the local tool cache. See `tools/portable-toolchain.json` for exact versions, source URLs and SHA-256 values.

Compatibility remains experimental. The first-boss visibility report and invalid-current-thread-pointer crash are still being investigated. See `RELEASE-NOTES.md` and `VALIDATION.md`.
