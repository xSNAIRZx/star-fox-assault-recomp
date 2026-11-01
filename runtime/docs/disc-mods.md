# Disc asset overlays

The desktop runtime can replace files that are read from the game disc by putting a file
at the same relative path under a mods directory. Set `GCN_MODS_DIR` to that directory
before starting the native game. For example, if the disc FST contains `data/ui/menu.arc`,
place the replacement at `<mods directory>/data/ui/menu.arc`.

The first implementation requires every replacement to have exactly the byte size listed
in the disc FST. It overlays reads at the original disc offsets, so the FST, image length,
and original disc image remain unchanged. Missing replacement files are ignored. A bad
replacement rejects the mods directory during startup.

The runtime rejects paths that traverse outside the mods directory, symlink/reparse paths,
files under `sys/`, and `.dol` or `.rel` replacements. Main DOL and REL code is statically
recompiled into the native executable, so changing those files on disc would not change
the running code. Asset replacements therefore apply to files loaded through DVD reads;
they do not modify already-loaded data or add/remove FST entries.

This is a local asset override path, not a downloadable mod catalog or full parity with
Foxhollow's mod framework. The current size restriction also excludes most replacements
that change an asset's encoded size.
