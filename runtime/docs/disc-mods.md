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
Foxhollow's mod framework.

## Why a replacement must be exactly the disc's size

The overlay is delivered at the original disc offset, and the guest asks the disc for the
length recorded in the FST. A file of another size cannot be served that way: a larger one
would move every file stored after it, and the image is read-only and never repacked. The
check is exact equality in `runtime/runtime/disc_mods.cpp`, and a rejected pack names both
sizes and this file.

That is what stops higher-resolution particle and VFX textures today. Such an asset needs
one of two things, and neither is a size check:

- a container that carries its own sizes, repacked offline and then installed as a
  same-size replacement of that container -- the growth has to be absorbed by the
  container's own layout, because the disc's FST is not rewritten;
- a redirection table consulted at read time, handing the guest an address and length that
  differ from its FST entry. That changes what the guest sees and is a feature in its own
  right, not a relaxation of the overlay.

Same-size edits remain possible where the format allows them: a re-authored texture of the
same dimensions and encoding occupies the same bytes and is delivered unchanged.
