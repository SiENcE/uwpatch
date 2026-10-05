; SPDX-License-Identifier: MIT
; By SiENcE, https://github.com/SiENcE/
;
; Perspective-correct texturing for UW.EXE: replacements for its two texture
; mappers, gfx_texture_poly_affine (floors, ceilings, most of what is not a
; wall) and gfx_texture_poly_wall, assembled to sit where they do in the
; graphics segment (image paragraph 0x90). The patcher writes two ranges:
;
;   0x060..0x362   the affine mapper and its two edge steppers; its entry
;                  stays at 0x1da, and 0x363 on (the stack switch back, the
;                  null check, the retf) is the original's
;   0x422..0x897   the wall mapper and its four steppers; its entry stays at
;                  0x545, and 0x898 on is the original's
;
; The two entry prologues are the original's bytes, and the patcher keeps the
; relocated segment word inside each (0x1dd, 0x553), for which this file only
; holds places. 0x363..0x421 between the ranges is the original's too, and
; partly live: the wall mapper's diagnostic record and its copy of the vertex
; ring sit at 0x3b0..0x421; this file pads over it and the patcher skips it.
;
; WHAT IS KEPT: the walk, which decides the pixels a face covers. From the
; vertex with the greatest y, the left edge goes backward round the ring and
; the right forward, a row at a time downward; an edge is reseeded when the
; row reaches the vertex it heads for; the walk ends when the two have used
; n+1 vertices. x starts at the vertex plus one half and steps by the
; original's two-divide step (OpenAbyss's src/uw_texmap.c documents it). The
; wall mapper's own rules
; are kept with it: a reseeded edge keeps the x it reached and only its step
; is recomputed (the affine one reloads x from the vertex), and a backward
; span is passed over where the affine one ends the face. So every face
; covers exactly the pixels it covered before, and faces meet where they met.
;
; WHAT IS NOT: the texel each pixel takes. The affine mapper stepped u and v
; linearly across the screen, which is why floors swim; the wall mapper took
; u from a per-column table, right for a vertical face seen level and wrong
; once the view pitches, and stepped v linearly along each row, which is why
; walls bend. Both now carry 1/z, u/z and v/z (Q = 2^30/z, S = u*Q >> 14,
; T = v*Q >> 14, all linear in screen space) along the edges and across the
; span, and recover u and v by division every 16 pixels, stepping them
; linearly in between. u and v are clamped to the texture, so a rounding at a
; face's edge never samples the next row, and a divide that would overflow
; saturates instead of trapping.
;
; 386 instructions throughout (UW1 needs a 386). All eight 32-bit registers
; are saved and restored around the walk.

        cpu 386
        bits 16
        org 0x60

RING    equ 0x659               ; the projected vertices, 14 bytes each:
                                ; +0 sx, +2 sy, +4 u, +6 v, +8 x, +0xa y, +0xc z
RING_END equ 0x7ab              ; one past the last vertex
RING_LAST equ 0x7a9             ; the last vertex
LEFT_N  equ 0x7d1               ; the vertices the walk may still use
ROW     equ 0x7cf               ; the current row
FB_SEG  equ 0x95a               ; the frame buffer's segment
ROW_TAB equ 0x95e               ; its row offsets
SHAPE   equ 0xb07c              ; es:[SHAPE] -> the shape record
STACK_TOP equ 0x5586

A_ENTRY equ 0x1da               ; gfx_texture_poly_affine
A_SAVED_SS equ 0x3a7            ; where its exit finds the caller's stack
A_SAVED_SP equ 0x3a9
A_EXIT  equ 0x363
W_LO    equ 0x422               ; the wall mapper's range
W_ENTRY equ 0x545               ; gfx_texture_poly_wall
W_SAVED_SS equ 0x8e3
W_SAVED_SP equ 0x8e5
W_EXIT  equ 0x898

SPAN    equ 16                  ; pixels between two exact samples

; ---- the frame, on the module's own stack; bp = its base + 72 so every
; field is a byte displacement --------------------------------------------
E_PTR   equ 0                   ; an edge: the vertex it heads for
E_END   equ 4                   ;   the row it ends at
E_X     equ 8                   ;   x, 16.16
E_DX    equ 12
E_Q     equ 16                  ;   Q, S, T and their steps
E_DQ    equ 28
EDGE_L  equ 0
EDGE_R  equ 40
QC      equ 80                  ; the span's Q, S, T, at the current pixel
D_Q     equ 92                  ; and their per-pixel steps
MODE    equ 104                 ; 0 the affine mapper's rules, 1 the wall's
U1      equ 112                 ; u*256 and v*256 at the current pixel
V1      equ 116
ULIM    equ 120                 ; the largest u*256 and v*256 the texture has
VLIM    equ 124
TMP     equ 128                 ; a vertex's Q, S, T
TEXSEG  equ 140
COUNT   equ 142                 ; the span's pixels still to draw
FRAME   equ 148
B       equ -72                 ; field + B = displacement from bp

; ===========================================================================
; 0x060..0x1d9: free

        times A_ENTRY - ($ - $$) - 0x60 db 0x90

; ---- gfx_texture_poly_affine: cx = the vertex count, es:[SHAPE] the shape
; record ---------------------------------------------------------------------
a_entry:
        push    es
        push    ds
        db      0xb8                            ; mov ax, the module's data segment --
        dw      0                               ; relocated; the patcher keeps the original's
        mov     ds, ax
        mov     bx, ss
        mov     [cs:A_SAVED_SS], bx
        mov     [cs:A_SAVED_SP], sp
        cli
        mov     ss, ax
        mov     sp, [STACK_TOP]
        sti
        xor     al, al
        call    walk
        jmp     A_EXIT

        ; to the end of the affine range, then over the original's bytes
        ; the patcher does not write
        times W_LO - ($ - $$) - 0x60 db 0x90

; ===========================================================================
; 0x422..0x897

; ---- vattr: Q, S, T of the vertex at bx into [bp+di..+11] ----------------
vattr:
        movzx   ecx, word [bx+0xc]
        test    cx, cx
        jnz     .z
        inc     cx                      ; z = 0 never survives the clip
.z:     mov     eax, 0x40000000
        cdq
        div     ecx
        mov     [bp+di], eax
        movzx   eax, word [bx+4]
        mul     dword [bp+di]
        shrd    eax, edx, 14
        mov     [bp+di+4], eax
        movzx   eax, word [bx+6]
        mul     dword [bp+di]
        shrd    eax, edx, 14
        mov     [bp+di+8], eax
        ret

; ---- seed: the edge at si (EDGE_L or EDGE_R) takes its next vertex -------
; The steppers: the accumulators reloaded from the vertex the edge reached,
; then on to the next; a horizontal edge passed over, re-entering at the
; top. `reseed` is the row loop's way in: the wall mapper's steppers are
; entered there past the x reload, so its x carries over. ZF set when the
; ring is used up.
reseed:
        cmp     byte [bp+MODE+B], 0
        je      seed
        mov     bx, [bp+si+E_PTR+B]
        jmp     short seed.qst
seed:
        mov     bx, [bp+si+E_PTR+B]
        mov     ax, [bx]
        shl     eax, 16
        mov     ax, 0x8000                      ; one half
        mov     [bp+si+E_X+B], eax
.qst:   lea     di, [si+E_Q+B]
        call    vattr
        add     bx, 14                          ; right: forward
        test    si, si
        jnz     .fw
        sub     bx, 28                          ; left: backward
.fw:    cmp     bx, RING
        jae     .lo
        mov     bx, [RING_LAST]
.lo:    cmp     bx, [RING_END]
        jne     .hi
        mov     bx, RING
.hi:    mov     [bp+si+E_PTR+B], bx
        dec     word [LEFT_N]
        jz      .ret
        mov     ax, [bx+2]
        mov     [bp+si+E_END+B], ax
        mov     cx, [ROW]
        sub     cx, ax
        jz      seed                            ; no rows: the next vertex
        ; x's step as the original takes it, from the x the edge holds: the
        ; whole part, then the remainder halved into the high word, divided,
        ; doubled
        mov     ax, [bx]
        sub     ax, [bp+si+E_X+2+B]
        cwd
        idiv    cx
        push    ax
        xor     ax, ax
        sar     dx, 1
        rcr     ax, 1
        idiv    cx
        cwd
        shl     ax, 1
        rcl     dx, 1
        pop     di
        add     dx, di
        mov     [bp+si+E_DX+B], ax
        mov     [bp+si+E_DX+2+B], dx
        ; Q, S and T step linearly from here to the vertex
        push    cx
        mov     di, TMP+B
        call    vattr
        pop     cx
        movsx   ecx, cx
.st:    mov     eax, [bp+di]
        sub     eax, [bp+si+E_Q+B]
        cdq
        idiv    ecx
        mov     [bp+si+E_DQ+B], eax
        add     si, 4
        add     di, 4
        cmp     di, TMP+12+B
        jne     .st
        sub     si, 12
        test    sp, sp                          ; ZF clear: an edge to walk
.ret:   ret

        times W_ENTRY - ($ - $$) - 0x60 db 0x90

; ---- gfx_texture_poly_wall: cx = the vertex count, es:[SHAPE] the shape
; record. The prologue is the original's to the mov ds; its two cs: stores
; are the wall mapper's diagnostic record, kept. -----------------------------
w_entry:
        mov     [cs:0x3ca], cx
        mov     ax, es
        mov     [cs:0x3cc], ax
        push    es
        push    ds
        db      0xb8                            ; mov ax, the module's data segment --
        dw      0                               ; relocated; the patcher keeps the original's
        mov     ds, ax
        mov     bx, ss
        mov     [cs:W_SAVED_SS], bx
        mov     [cs:W_SAVED_SP], sp
        cli
        mov     ss, ax
        mov     sp, [STACK_TOP]
        sti
        mov     al, 1
        call    walk
        jmp     W_EXIT

; ---- walk: the face, under the affine mapper's rules (al 0) or the wall
; mapper's (al 1). ds and ss the module's data segment, cx the vertex count,
; es the caller's. ---------------------------------------------------------------
walk:
        pushad
        sub     sp, FRAME
        mov     bp, sp
        sub     bp, B
        mov     [bp+MODE+B], al

        ; the ring: its end, its last vertex, the n+1 the walk may use
        imul    ax, cx, 14
        add     ax, RING
        mov     [RING_END], ax
        sub     ax, 14
        mov     [RING_LAST], ax
        mov     ax, cx
        inc     ax
        mov     [LEFT_N], ax

        ; the shape record: width, v_max, the texture's segment, the v mask
        mov     si, [es:SHAPE]
        es lodsw
        shl     eax, 16
        dec     eax
        mov     [bp+ULIM+B], eax
        es lodsw
        movzx   eax, ax
        shl     eax, 8
        or      al, 0xff
        mov     [bp+VLIM+B], eax
        es lodsw
        mov     [bp+TEXSEG+B], ax
        es lodsw
        mov     [cs:p_mask], ax

        ; the vertex with the greatest y, the first of equals
        mov     si, RING
        mov     di, si
.top:   mov     ax, [si+2]
        cmp     ax, [di+2]
        jng     .nt
        mov     di, si
.nt:    add     si, 14
        loop    .top

        mov     es, [FB_SEG]
        mov     [bp+EDGE_L+E_PTR+B], di
        mov     [bp+EDGE_R+E_PTR+B], di
        mov     ax, [di+2]
        mov     [ROW], ax
        mov     si, EDGE_L
        call    seed
        jz      .done
        mov     si, EDGE_R
        call    seed
        jz      .done

.row:   mov     ax, [bp+EDGE_L+E_X+2+B]
        mov     cx, [bp+EDGE_R+E_X+2+B]
        sub     cx, ax
        mov     di, [ROW]
        shl     di, 1
        mov     di, [di+ROW_TAB]
        add     di, ax
        ; Q, S, T from the left edge, their steps to the right; a one-pixel
        ; span divides by one
        movsx   ecx, cx
        push    cx
        test    cx, cx
        jnz     .w
        inc     cx
.w:     xor     si, si
.d:     mov     ebx, [bp+si+EDGE_L+E_Q+B]
        mov     [bp+si+QC+B], ebx
        mov     eax, [bp+si+EDGE_R+E_Q+B]
        sub     eax, ebx
        cdq
        idiv    ecx
        mov     [bp+si+D_Q+B], eax
        add     si, 4
        cmp     si, 12
        jne     .d
        pop     cx
        inc     cx                              ; the width as a pixel count
        jg      .span
        cmp     byte [bp+MODE+B], 0             ; backward: the affine mapper
        jne     .next                           ; ends the face, the wall's
        jmp     .done                           ; passes the row over
.span:  mov     [bp+COUNT+B], cx
        call    uvc

.chunk: push    dword [bp+U1+B]                 ; the chunk's start: the last one's end
        push    dword [bp+V1+B]
        mov     cx, [bp+COUNT+B]
        cmp     cx, SPAN
        jbe     .k
        mov     cx, SPAN
.k:     sub     [bp+COUNT+B], cx
        movzx   ecx, cx
        xor     si, si
.adv:   mov     eax, [bp+si+D_Q+B]
        imul    eax, ecx
        add     [bp+si+QC+B], eax
        add     si, 4
        cmp     si, 12
        jne     .adv
        call    uvc
        pop     ebx                             ; v*256 at the start
        pop     esi                             ; u*256 at the start
        mov     eax, [bp+U1+B]
        sub     eax, esi
        cdq
        idiv    ecx
        push    eax                             ; u's step
        mov     eax, [bp+V1+B]
        sub     eax, ebx
        cdq
        idiv    ecx
        pop     edx
        push    ds
        push    bp
        mov     ds, [bp+TEXSEG+B]
        mov     ebp, eax                        ; v's step
        mov     eax, esi
        jmp     short .px                       ; the prefetch queue past p_mask
        ; eax u*256 (the texel column in the high word), ebx v*256,
        ; edx and ebp their steps
.px:    mov     esi, ebx
        shr     esi, 8
        and     si, strict word 0
p_mask  equ     $ - 2
        ror     eax, 16
        add     si, ax
        rol     eax, 16
        movsb
        add     eax, edx
        add     ebx, ebp
        loop    .px
        pop     bp
        pop     ds
        cmp     word [bp+COUNT+B], 0
        jne     .chunk

        ; the row done: both edges on, a reseed where an edge ends
.next:  dec     word [ROW]
        mov     si, EDGE_L
        call    advance
        mov     si, EDGE_R
        call    advance
        mov     cx, [ROW]
        cmp     cx, [bp+EDGE_L+E_END+B]
        jg      .r
        mov     si, EDGE_L
        call    reseed
        jz      .done
.r:     mov     cx, [ROW]
        cmp     cx, [bp+EDGE_R+E_END+B]
        jg      .row
        mov     si, EDGE_R
        call    reseed
        jnz     .row

.done:  lea     sp, [bp+B+FRAME]
        popad
        ret

; ---- advance: the edge at si one row on ------------------------------------
advance:
        mov     eax, [bp+si+E_DX+B]
        add     [bp+si+E_X+B], eax
        mov     di, 3
.a:     mov     eax, [bp+si+E_DQ+B]
        add     [bp+si+E_Q+B], eax
        add     si, 4
        dec     di
        jnz     .a
        sub     si, 12
        ret

; ---- sample: eax = S or T at the current pixel -> u*256 or v*256, clamped
; to 0..esi. Clobbers ebx, edx. --------------------------------------------
sample:
        mov     edx, eax
        sar     edx, 10
        shl     eax, 22                         ; edx:eax = value << 22
        mov     ebx, [bp+QC+B]
        sar     ebx, 1
        cmp     edx, ebx                        ; the quotient would not fit
        jge     .hi
        neg     ebx
        cmp     edx, ebx
        jle     .lo
        idiv    dword [bp+QC+B]
        test    eax, eax
        js      .lo
        cmp     eax, esi
        jbe     .ret
.hi:    mov     eax, esi
        ret
.lo:    xor     eax, eax
.ret:   ret

; ---- uvc: U1, V1 at the current pixel ---------------------------------------
uvc:
        mov     eax, [bp+QC+4+B]
        mov     esi, [bp+ULIM+B]
        call    sample
        mov     [bp+U1+B], eax
        mov     eax, [bp+QC+8+B]
        mov     esi, [bp+VLIM+B]
        call    sample
        mov     [bp+V1+B], eax
        ret

        ; up to the original's exit, which stays (a negative count is the
        ; patch running into it)
        times W_EXIT - ($ - $$) - 0x60 db 0x90
