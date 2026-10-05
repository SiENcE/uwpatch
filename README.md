# uwpatch

**Perspective-correct textures for the original *Ultima Underworld: The
Stygian Abyss* (1992).**

`uwpatch` patches the DOS game's `UW.EXE` so that its floors, ceilings and
walls are textured perspective-correct. The original draws floors and
ceilings with an *affine* texture mapper, which is why a floor seen at a
slant swims as you move, and its walls with a mapper that is only right for
a vertical wall seen level, which is why walls bend when you look up or
down. After the patch, floors and ceilings no longer swim and mortar lines
stay straight at any angle.

The patched game runs in DOSBox (or DOS on a 386 or better, as UW1 itself
needs). Saves are not affected: a game saved with the patch loads without
it, and the other way round.

## Which versions can be patched

| Release | `UW.EXE` size | CRC-32 | Version string | Tested |
|---|---|---|---|---|
| GOG | 547,248 bytes | `f2bf2527` | F1.94S | yes, in DOSBox |
| German floppy | 561,744 bytes | `bf1282c0` | F1.50S | yes, in DOSBox |

The patcher does not go by the file's name or size. It reads the two
pieces of code it replaces and patches them only when they are exactly the
ones it was made for (their CRC-32, ignoring the two words DOS fills in at
load time). Both releases above hold that code byte for byte at the same
place, so other releases that do are patched too, and say so; anything
else is refused and left untouched. `uwpatch --check` tells you which case
a file is without changing it.

A patched file is recognised as such and is not patched twice. After
patching, the two releases above have the CRC-32 `78729003` (GOG) and
`9e99e5d4` (German floppy).

## Using it

Ready-made executables are in `build/`: `uwpatch.exe` for 64-bit Windows,
`uwpatch` for 64-bit Linux (statically linked). Run it on the game's
`UW.EXE`, in the folder the game is installed in:

```sh
uwpatch UW.EXE              # patched in place; the original kept as UW.BAK
uwpatch UW.EXE -o NEW.EXE   # or a patched copy, the original left alone
uwpatch --check UW.EXE      # what the file is; nothing changed
```

To undo the patch, copy `UW.BAK` back over `UW.EXE`.

GOG installs the game as a CD image (`game.gog`) that DOSBox mounts; to
patch it, take the `UW` folder out of the image (7-Zip opens it, or rename
it `game.iso`), patch the `UW.EXE` in it, and point the game's DOSBox
configuration at that folder.

## How it works

The game has two texture mappers in its graphics code:
`gfx_texture_poly_affine`, which draws floors, ceilings and most of what is
not a wall, and `gfx_texture_poly_wall`, which draws the walls. Both are
hand-written 8086 assembly that walk a polygon row by row from its top
vertex. `uwpatch` replaces both, in place, with new 386 assembly
(`patch/perspective.asm`):

- **The pixels each face covers are the original's.** The edge walk is
  kept exactly, its rounding included, along with the wall mapper's own
  rules (an edge carries its x past a vertex; a backward span is skipped).
  So every face keeps its outline and faces meet where they always met.
- **Only the texel each pixel shows changes.** The new mappers carry 1/z,
  u/z and v/z along the edges and across each row (these are linear on the
  screen, where u and v are not), divide the depth out every 16 pixels, and
  step u and v linearly in between. u and v are clamped to the texture, so
  no pixel samples the next row of the texture, and a division that would
  overflow saturates instead of stopping the game.
- **Nothing moves.** The new code fits in the space of the routines it
  replaces (graphics segment offsets `0x60..0x362` and `0x422..0x897`); both
  entry points stay where the game calls them, and no relocation, overlay
  or other code is touched.

A textured face costs a few divisions per 16 pixels more than before. That
is nothing to DOSBox at its usual settings; on a real 386 or 486 the game
will be somewhat slower, and that has not been measured.

## Building

The executables in `build/` are built from this source. To build them
yourself you need only a C11 compiler:

```sh
make                                     # ./uwpatch
cmake -S . -B out && cmake --build out   # or with CMake
cmake -S . -B out-win -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-w64-x86_64.cmake
cmake --build out-win                    # uwpatch.exe, cross-compiled with MinGW-w64
```

The patch itself is `patch/perspective.asm` (NASM). Its assembled bytes are
checked in as `src/uwpatch_perspective.h`; after changing the assembly,
`make header` (or `sh patch/build.sh`, needing `nasm` and `python3`)
regenerates them, and the patcher's `CRC_PATCHED` in `src/uwpatch.c` has to
be updated to the new code's CRC-32.

## Credits

**uwpatch and the perspective-correct mappers: SiENcE**
(https://github.com/SiENcE/).

With thanks to:

- **OpenAbyss** (https://github.com/cimmerianpit/openabyss), the C
  reimplementation of Ultima Underworld whose port of the two texture
  mappers -- their walk, their rounding and their quirks, worked out from
  the original instructions -- this patch is built on, and where the same
  perspective-correct texturing is available as `--perspective`.
- **hankmorgan's UWReverseEngineering**
  (https://github.com/hankmorgan/UWReverseEngineering), the disassembly and
  file-format notes for UW1 and UW2.
- **John Glassmyer's UltimaHacks**
  (https://github.com/JohnGlassmyer/UltimaHacks), patches for the original
  executables and the place the question was asked
  ([issue #30](https://github.com/JohnGlassmyer/UltimaHacks/issues/30):
  "Is there a chance to fix the distorted texture rendering code of UW1?").
- **Blue Sky Productions** (later Looking Glass Technologies) and **Origin
  Systems**, who made the game.

## Licence and trademarks

MIT licence (`LICENSE`). This repository contains no part of the game: the
patch is new code, and the patcher checks the original's code by checksum
only. You need your own copy of Ultima Underworld. Ultima and Ultima
Underworld are trademarks of their owners; this project is not affiliated
with or endorsed by them.
