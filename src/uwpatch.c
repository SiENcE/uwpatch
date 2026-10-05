/* SPDX-License-Identifier: MIT */
/* uwpatch -- the original game's UW.EXE patched to draw its textures
 * perspective-correct, for playing in DOS or DOSBox.
 * By SiENcE, https://github.com/SiENcE/
 *
 *     uwpatch UW.EXE              patch it, the original kept as UW.BAK
 *     uwpatch UW.EXE -o NEW.EXE   write the patched copy elsewhere
 *     uwpatch --check UW.EXE      say what the file is, change nothing
 *
 * WHAT IT CHANGES. The game's two texture mappers -- gfx_texture_poly_affine,
 * which draws the floors and ceilings, and gfx_texture_poly_wall, the walls
 * -- are replaced in place by patch/perspective.asm (its
 * header says how it works): the graphics segment's (image paragraph 0x90)
 * offsets 0x60..0x362 and 0x422..0x897. The relocated segment word in each
 * entry prologue (0x1dd, 0x553) is left as it is, and so is everything else
 * in the file -- no relocation, no overlay, nothing moves.
 *
 * WHICH FILES. Both ranges are byte-for-byte the same, but for those two
 * relocated words, in GOG's UW.EXE (F1.94S) and in the German floppy release
 * (F1.50S), at the same place. The patcher does not trust a file's name or
 * size: it reads the ranges and takes them only when their CRC-32 is the
 * original's, and reports ranges already patched. Anything else is refused
 * untouched. The file's own CRC-32 names the release when it is one of the
 * two it was tried on.
 *
 * The patched game needs a 386 (as UW1 does); a textured face costs a few
 * divisions per 16 pixels more than it did. Saves are not affected. */
#include "uwpatch_perspective.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GFX_PARA     0x90                  /* the graphics segment's image paragraph */
#define CRC_ORIGINAL 0xb92c6223u           /* the two ranges, the relocated words zeroed */
#define CRC_PATCHED  0xd85c791du
#define CREDIT       "uwpatch by SiENcE, https://github.com/SiENcE/"

static const struct { long lo, hi; } ranges[] = { { 0x60, 0x363 }, { 0x422, 0x898 } };
static const long relocs[] = { 0x1dd, 0x553 };    /* each a word */

static const struct { uint32_t crc; long size; const char *name; } releases[] = {
    { 0xf2bf2527u, 547248, "GOG (F1.94S)" },
    { 0xbf1282c0u, 561744, "German floppy (F1.50S)" },
};

static uint32_t crc32_add(uint32_t c, uint8_t byte) {
    int k;
    c ^= byte;
    for (k = 0; k < 8; k++) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
    return c;
}

static uint32_t crc32_of(const uint8_t *p, size_t n) {
    uint32_t c = 0xffffffffu;
    size_t i;
    for (i = 0; i < n; i++) c = crc32_add(c, p[i]);
    return ~c;
}

static int relocated(long off) {
    size_t i;
    for (i = 0; i < sizeof relocs / sizeof relocs[0]; i++)
        if (off == relocs[i] || off == relocs[i] + 1) return 1;
    return 0;
}

static uint8_t *slurp(const char *path, long *size) {
    FILE *f = fopen(path, "rb");
    uint8_t *d;
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) || (*size = ftell(f)) <= 0 || fseek(f, 0, SEEK_SET)) { fclose(f); return NULL; }
    d = malloc((size_t)*size);
    if (d && fread(d, 1, (size_t)*size, f) != (size_t)*size) { free(d); d = NULL; }
    fclose(f);
    return d;
}

static int spill(const char *path, const uint8_t *d, long size) {
    FILE *f = fopen(path, "wb");
    int ok;
    if (!f) return 0;
    ok = fwrite(d, 1, (size_t)size, f) == (size_t)size;
    return fclose(f) == 0 && ok;
}

/* The ranges' CRC-32, the relocated words read as zero; 0 when the file is
 * not an MZ executable long enough to hold them. *at is the segment's
 * place in the file. */
static uint32_t ranges_crc(const uint8_t *d, long size, long *at) {
    uint32_t c = 0xffffffffu;
    size_t r;
    long k;
    if (size < 0x20 || d[0] != 'M' || d[1] != 'Z') return 0;
    *at = (long)(d[8] | d[9] << 8) * 16 + GFX_PARA * 16L;
    if (*at + ranges[1].hi > size) return 0;
    for (r = 0; r < sizeof ranges / sizeof ranges[0]; r++)
        for (k = ranges[r].lo; k < ranges[r].hi; k++)
            c = crc32_add(c, relocated(k) ? 0 : d[*at + k]);
    return ~c;
}

/* NAME.EXE -> NAME.BAK, beside it */
static void backup_name(const char *path, char *out, size_t cap) {
    const char *dot = strrchr(path, '.'), *sep = strrchr(path, '/'), *bs = strrchr(path, '\\');
    size_t n = strlen(path);
    if (bs && (!sep || bs > sep)) sep = bs;
    if (dot && (!sep || dot > sep)) n = (size_t)(dot - path);
    snprintf(out, cap, "%.*s.BAK", (int)n, path);
}

static int usage(void) {
    fprintf(stderr, CREDIT "\n"
                    "usage: uwpatch UW.EXE [-o OUT.EXE]   perspective-correct floors, ceilings and walls\n"
                    "       uwpatch --check UW.EXE         what the file is; nothing changed\n"
                    "Without -o the file is patched in place and the original kept as .BAK beside it.\n");
    return 2;
}

int main(int argc, char **argv) {
    const char *in = NULL, *out = NULL;
    int check = 0, i;
    long size, at = 0, k;
    size_t r;
    uint8_t *d;
    uint32_t crc, region;
    const char *name = NULL;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--check")) check = 1;
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (argv[i][0] == '-' || in) return usage();
        else in = argv[i];
    }
    if (!in) return usage();
    printf(CREDIT "\n");
    if (!(d = slurp(in, &size))) { fprintf(stderr, "uwpatch: %s will not read\n", in); return 1; }

    crc = crc32_of(d, (size_t)size);
    for (i = 0; i < (int)(sizeof releases / sizeof releases[0]); i++)
        if (releases[i].crc == crc && releases[i].size == size) name = releases[i].name;
    region = ranges_crc(d, size, &at);
    printf("%s: %ld bytes, CRC-32 %08x%s%s\n", in, size, (unsigned)crc, name ? ", " : "", name ? name : "");

    if (region == CRC_PATCHED) {
        printf("%s: already patched\n", in);
        free(d);
        return 0;
    }
    if (region != CRC_ORIGINAL) {
        fprintf(stderr, "uwpatch: %s does not hold the texture mappers this patch replaces; nothing changed\n", in);
        free(d);
        return 1;
    }
    if (check) {
        printf("%s: unpatched, and the patch fits it\n", in);
        free(d);
        return 0;
    }

    if (!out) {
        char bak[1024];
        backup_name(in, bak, sizeof bak);
        if (!spill(bak, d, size)) { fprintf(stderr, "uwpatch: the backup %s will not write; nothing changed\n", bak); free(d); return 1; }
        printf("%s: the original kept as %s\n", in, bak);
        out = in;
    }
    for (r = 0; r < sizeof ranges / sizeof ranges[0]; r++)
        for (k = ranges[r].lo; k < ranges[r].hi; k++)
            if (!relocated(k)) d[at + k] = uwpatch_perspective[k - UWPATCH_PERSPECTIVE_ORG];
    if (ranges_crc(d, size, &at) != CRC_PATCHED || !spill(out, d, size)) {
        fprintf(stderr, "uwpatch: %s will not write\n", out);
        free(d);
        return 1;
    }
    printf("%s: patched -- floors, ceilings and walls perspective-correct\n", out);
    free(d);
    return 0;
}
