# Project collaboration instructions

- The user wants GitHub kept up to date whenever work on this project makes an update necessary. Publish relevant completed changes after appropriate verification without asking again for routine commits and pushes.
- The only authorized repository is https://github.com/xSNAIRZx/star-fox-assault-recomp, owned by XSNAIRZX. Verify the selected account and destination before writes. Never publish to another account or organization.
- Use the GitHub noreply identity 348800968+xSNAIRZx@users.noreply.github.com for both commit author and committer. Avoid personal email addresses in commits.
- Upload only audited, shareable source and explicitly verified release payloads. Never recursively stage the development directory or user-data. Exclude game images, extracted game executables/code, generated PPC code, native game binaries, settings, saves, logs, private images, and tool/build caches. Preserve original game images and user data.
- Use a clean publishing checkout and an explicit allowlist based on the package script or verified release archive. The development directory contains private and non-shareable files.
- Keep releases experimental prereleases until the evidence supports a change. Disclose unresolved issues and validation limits accurately. Create or replace release assets only when an updated, tested package is needed; ordinary source changes do not require a new release.
- Before pushing, inspect remote changes and preserve unrelated work. Do not routinely rewrite published history or retag releases.
- Launcher improvement work is tracked in docs/launcher-goals.md. Read it before launcher changes and tick items there in the same PR as the change.
