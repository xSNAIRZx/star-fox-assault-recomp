# Relocatable modules

The SDK's `.rel` files are code the game links at run time with `OSLink`, into memory its
allocator chose. A game may keep most of itself in them, and may place them differently
from one run to the next. `gcn_add_game(RELS ...)` recompiles them.

## Build time

`recomp/rel.py` extracts the listed modules from the disc into `build/rels/`, then links
every module at a canonical address: code from 0x81800000, just above RAM and within a relative
branch of the DOL; data from 0x82000000; bss from 0x83000000. The linked modules are
appended to the DOL the recompiler reads (`build/main_rels.dol`), with three files beside
it:

- `.rels`: each module's id, name and sections with their canonical addresses;
- `.relocs`: every instruction whose immediate the linker patches with an address in a
  module (the HA, HI and LO halves of `lis`/`addi`, `lis`/`lwz` pairs), with the target
  module, section and addend;
- `.syms`: the modules' functions at their canonical addresses, from dtk's per-module
  symbols (`REL_SYMBOLS/<module>.txt`, with dtk's splits file beside it to name the
  sections).

The recompiler compiles the modules like the DOL. A relocated instruction is translated
with a placeholder immediate, which is then replaced by `REL_HA`/`REL_HI`/`REL_LO` of the
section's run-time base plus the addend: the value the linker would have written. A
branch needs nothing, since the canonical link resolved it and it is a C call. A module
function's jump tables are keyed on `rels_canon(c->ctr)`.

Some games ship alternate `.rel` files with the same numeric module ID. Those files can
share the ID because the game loads one variant at a time. The static build keeps each
variant under its own filename; a self import resolves to that file, while an import from
another module resolves only when its section and addend identify one variant uniquely.
At run time the module string-table name distinguishes same-ID variants after `OSLink`.

For dtk, list the modules under `modules:` in the game's `config.yml`, each with a `name`
(dtk otherwise names a module by its file name up to the first dot, and two
`game.a.rel` and `game.b.rel` files collide).

## Modules the game assembles itself

A game may not keep a module on the disc as a plain file: it may build it in memory --
read from somewhere else, unpacked, put together -- and only then hand it to `OSLink`.
`REL_RUNTIME <names>` lists those, by the name the game's module string table gives them.
The recompiler needs them at build time, and the only faithful source is the game itself,
so the first configure bootstraps:

1. it configures and builds `<build>/bootstrap` with `GCN_BOOTSTRAP=ON`, which leaves the
   runtime modules out (and with them any module that imports from one: `rel.py` drops
   it), building only the headless benchmark;
2. it runs that with `GCN_REL_DUMP=<build>/rels-runtime` and `GCN_REL_DUMP_WANT=<names>`.
   Before every link the generated code calls `rels_linking`, which writes any module that
   was not recompiled to that directory as `<name>.rel`, exactly as `OSLink` is about to
   see it, and ends the run once all the wanted ones are written;
3. the main build then compiles them with the rest.

`<build>/rels-runtime` is kept between configures, so this happens once per build
directory. A cross build (Android) cannot run what it builds, so it copies the modules from
a desktop build's `rels-runtime/` instead (`GCN_HOST_BUILD_DIR`, by default `build/`) and
says so if there is none. The game's own code, run on the user's disc, is what produces the modules; the
build contains nothing that knows how.

## Run time

When the DOL names the SDK's `OSLink`, `OSLinkFixed` and `OSUnlink`, the recompiler wraps
them and records successful links and unlinks. Some games keep their loader anonymous;
for those, the first indirect call to an unmapped code address scans the SDK module list
at `0x800030C8`, identifies the compiled module by ID, name or section sizes, and registers
its linked section bases. `rels_linked` (`runtime/rels.cpp`) reads the section bases from
the module header after the linker has made them absolute; `rels_unlinked` forgets a link
when the hook is available. `call_indirect` maps a runtime code address -- a callback or
vtable entry -- to its canonical address with `rels_canon`. Data the linker relocates is
in guest memory as the game linked it. `--log=os` prints each registered module.

Nothing checks that a module's code is only entered while it is linked; the game cannot
do otherwise on the console either.

A module's code finds its own data through `g_rel_base`, which holds one set of section
bases per compiled module: the last link registered. Without the hooks, a game can unlink a
module and link it again -- at the header of an earlier copy whose mapping is still live,
with its `.bss` somewhere new -- and the first call into the new link resolves through that
earlier mapping, so nothing re-reads the header. The code would then use the previous
copy's freed sections, which by then belong to whatever was loaded next. So `rels_canon`
compares the header's section bases with `g_rel_base` whenever a call resolves through a
mapping, and registers the link again when they differ. A header restored to file offsets
(an unlink in progress, running the module's epilog) leaves the bases as they are.
`GCN_REL_TRACE=1` ([diagnostics.md](diagnostics.md)) shows links, reuse and calls into reused
copies.
