# Builds ./uwpatch with any C11 compiler. `make header` reassembles the patch
# (needs nasm and python3) and regenerates src/uwpatch_perspective.h.

CC     ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wno-sign-conversion

uwpatch: src/uwpatch.c src/uwpatch_perspective.h
	$(CC) $(CFLAGS) -Isrc src/uwpatch.c -o $@

header:
	sh patch/build.sh

clean:
	rm -f uwpatch

.PHONY: header clean
