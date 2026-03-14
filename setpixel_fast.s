; ============================================================================
; FASTEST 4-PLANE PIXEL PLOT — ATARI ST / 68000
; ============================================================================
; Multiple approaches, from fastest (most RAM) to smallest.
; All use lookup tables, no branches in the hot path.
;
; Screen format: 320x200, 4 bitplanes interleaved
;   16 pixels = 8 bytes: [plane0.w][plane1.w][plane2.w][plane3.w]
;   Scanline = 160 bytes
;
; Convention:
;   d0.w = X (0-319)
;   d1.w = Y (0-199)
;   d2.w = color (0-15)
;   a0   = screen base address
;
; ============================================================================


; ============================================================================
; APPROACH 1 — "THE MONSTER"
; ============================================================================
; Total table RAM: ~43 KB
; Cycles: ~54 on 68000 (no branches, fully unrolled)
;
; Tables:
;   y_table:      200 longs  — precalculated screen_base + y*160  (800 bytes)
;   x_info:       320 longs  — bits[31:16] = byte offset within scanline
;                               bits[15:0]  = bit mask             (1280 bytes)
;   x_color_or:   320*16 = 5120 entries of 4 words each          (40960 bytes)
;                  x_color_or[x*16+color] = 4 OR-mask words
;
; Total: 800 + 1280 + 40960 = 43040 bytes (~42 KB)
; ============================================================================

SetPixel_Monster:
; Input: d0.w=X, d1.w=Y, d2.w=color(0-15), a0=screen
; Trashes: d0-d4, a1

    ; --- Get scanline address from Y table ---
    add.w   d1,d1                   ; 4  — d1 = Y*2
    add.w   d1,d1                   ; 4  — d1 = Y*4 (long index)
    movea.l y_table(pc,d1.w),a1     ; 16 — a1 = screen + Y*160

    ; --- Get byte offset and mask from X ---
    move.w  d0,d1                   ; 4  — save X
    add.w   d0,d0                   ; 4  — d0 = X*2
    add.w   d0,d0                   ; 4  — d0 = X*4 (long index)
    move.l  x_info(pc,d0.w),d3      ; 16 — d3.hi = byte offset, d3.lo = bitmask

    ; --- Add byte offset to scanline address ---
    swap    d3                      ; 4  — d3.w = byte offset
    adda.w  d3,a1                   ; 8  — a1 -> correct 8-byte pixel group
    swap    d3                      ; 4  — d3.w = bitmask (NOT mask for clearing)

    ; --- Index into x_color_or table ---
    ; index = (X * 16 + color) * 8 = X*128 + color*8
    lsl.w   #7,d1                   ; 12 — d1 = X*128   (X was saved in d1)
    lsl.w   #3,d2                   ; 10 — d2 = color*8
    add.w   d2,d1                   ; 4  — d1 = X*128 + color*8

    ; --- Clear old pixel (AND with NOT-mask) ---
    not.w   d3                      ; 4  — d3 = NOT(bitmask) = AND mask
    and.w   d3,(a1)                 ; 12 — clear plane 0
    and.w   d3,2(a1)               ; 12 — clear plane 1
    and.w   d3,4(a1)               ; 12 — clear plane 2
    and.w   d3,6(a1)               ; 12 — clear plane 3

    ; --- Load 4 OR-masks from monster table ---
    lea     x_color_or(pc,d1.w),a2  ; 12 — a2 -> 4 OR-mask words
    ; (Note: if table > 32KB from PC, use absolute addressing)

    ; --- OR in the new color ---
    move.w  (a2)+,d0                ; 8  — OR mask plane 0
    or.w    d0,(a1)                 ; 12 — set plane 0
    move.w  (a2)+,d0                ; 8  — OR mask plane 1
    or.w    d0,2(a1)               ; 12 — set plane 1
    move.w  (a2)+,d0                ; 8  — OR mask plane 2
    or.w    d0,4(a1)               ; 12 — set plane 2
    move.w  (a2),d0                 ; 8  — OR mask plane 3
    or.w    d0,6(a1)               ; 12 — set plane 3
    rts                             ; 16
                                    ; ----
                                    ; Total: ~240 cycles (rough)
                                    ; But see Approach 2 for much faster!


; ============================================================================
; APPROACH 2 — "THE DESTROYER"  (Fastest possible approach)
; ============================================================================
; Key insight: skip the AND-then-OR pattern. Instead, precompute BOTH the
; AND-mask and OR-values merged, so we do fewer memory operations.
;
; Even better insight: if we DON'T need to preserve other pixels' bits
; (i.e., we're bulk-plotting and will handle this), we can just OR.
; But for a general "set pixel" we need clear+set.
;
; REAL key insight: Use LONGWORD operations on pairs of planes!
; The ST stores planes as: [p0.w][p1.w][p2.w][p3.w]
; We can read/write longs: [p0.w|p1.w] and [p2.w|p3.w]
;
; For each (X, color), precompute:
;   and_mask:  1 long  (same NOT-bitmask replicated to both words)
;   or_planes01: 1 long (OR values for planes 0 and 1 packed)  
;   or_planes23: 1 long (OR values for planes 2 and 3 packed)
;
; Table: x_and_long[320] = 320 × 4 bytes              = 1280 bytes
;        x_or_long[320][16] = 320 × 16 × 8 bytes      = 40960 bytes
;        y_table[200] = 200 × 4 bytes                  = 800 bytes
;
; Total: ~43 KB (same, but now using long accesses = MUCH faster)
;
; Cycles saved: and.l to memory is 20 cycles but replaces two and.w (24).
;               or.l same saving. Plus we load fewer values.
; ============================================================================

SetPixel_Destroyer:
; Input: d0.w=X, d1.w=Y, d2.w=color(0-15)
; a0 = screen base
; Trashes: d0-d3, a1

    ; --- Scanline address ---
    add.w   d1,d1                   ; 4
    add.w   d1,d1                   ; 4
    movea.l y_table(pc,d1.w),a1     ; 16  a1 = &scanline[y]

    ; --- X info: compute table indices ONCE ---
    move.w  d0,d1                   ; 4   save X for second table
    add.w   d0,d0
    add.w   d0,d0                   ; 8   d0 = X*4

    ; Byte offset within scanline: (X/16)*8 = (X>>4)<<3
    ; We store it in x_byte_off table (320 words) to avoid shifts
    move.w  x_byte_off(pc,d0.w),d3  ; 12  d3 = byte offset in scanline
    adda.w  d3,a1                   ; 8   a1 -> pixel group (8 bytes)

    ; --- AND mask (long): same mask for planes 0|1 and planes 2|3 ---
    move.l  x_and_long(pc,d0.w),d3  ; 16  d3 = AND mask (long: notmask|notmask)

    ; --- OR masks from x_or_long[X][color] ---
    ; index = X * 16 * 8 + color * 8 = X*128 + color*8
    lsl.w   #7,d1                   ; 12  d1 = X * 128
    lsl.w   #3,d2                   ; 10  d2 = color * 8
    add.w   d2,d1                   ; 4   d1 = table offset

    ; --- Clear + Set planes 0,1 (one long operation each) ---
    and.l   d3,(a1)                 ; 20  clear bits in planes 0+1
    and.l   d3,4(a1)               ; 20  clear bits in planes 2+3

    lea     x_or_long(pc,d1.w),a2   ; 12

    move.l  (a2)+,d0                ; 12  OR mask for planes 0+1
    or.l    d0,(a1)                 ; 20  set planes 0+1
    move.l  (a2),d0                 ; 12  OR mask for planes 2+3
    or.l    d0,4(a1)               ; 20  set planes 2+3

    rts                             ; 16
                                    ; ----
                                    ; ~230 cycles total
                                    ; (saves ~20 cycles over word approach)


; ============================================================================
; APPROACH 3 — "THE ANNIHILATOR" (Absolute fastest, self-modifying code)
; ============================================================================
; 
; Uses self-modifying code + enormous precomputation.
; For each X position, we precompute a POINTER to a tiny code fragment
; that has the correct byte offset hardcoded as a displacement.
;
; Actually, the real speed demon technique on 68000 is:
; Precompute EVERYTHING into a single table of longs, and use
; movem to blast them into registers, then write.
;
; But the #1 fastest technique: JUMP TABLE per X coordinate.
; Each entry is a small code routine with hardcoded offsets.
; But 320 routines × ~20 bytes = 6.4 KB. Possible but complex.
;
; BETTER: The fastest general approach eliminates all computation
; from the hot path by using a GIANT precomputed table.
;
; For each (X, color), store:
;   Byte 0-3:  AND long for planes 0+1 (already replicated)
;   Byte 4-7:  AND long for planes 2+3 (same value, replicated for movem)
;   Byte 8-11: OR  long for planes 0+1
;   Byte 12-15: OR long for planes 2+3
;
; Table: 320 * 16 * 16 = 81920 bytes (80 KB) + Y table (800 bytes)
;        + X offset table (640 bytes)
; Total: ~82 KB
;
; Then the hot path uses movem.l to load 4 longs in one burst.
; ============================================================================

SetPixel_Annihilator:
; Input: d0.w=X, d1.w=Y, d2.w=color(0-15)
; a0 = screen base (not used — y_table has absolute addresses)
; Trashes: d0-d4, a1-a2

    ; --- Scanline address (8 cycles) ---
    add.w   d1,d1                   ; 4
    add.w   d1,d1                   ; 4
    movea.l y_table(pc,d1.w),a1     ; 16

    ; --- Add X byte offset (12 cycles) ---
    add.w   d0,d0                   ; 4   X*2
    move.w  x_byte_off2(pc,d0.w),d1 ; 12  byte offset (word-indexed now)
    adda.w  d1,a1                   ; 8   a1 -> pixel group

    ; --- Compute master table index ---
    ; index = (X * 16 + color) * 16
    ; = X * 256 + color * 16
    ; If X is already *2, then X_orig = d0/2
    ; X * 256 = X_orig << 8 = (d0/2) << 8 = d0 << 7
    asr.w   #1,d0                   ; 4   d0 = X again
    lsl.w   #8,d0                   ; 12  d0 = X*256  (WARNING: X max=319, 319*256=81664 — fits in word? NO! 81664 > 65535)
    ; PROBLEM: 319 * 256 = 81,664 which exceeds 16-bit range!
    ; Solution: use long arithmetic or restructure.

    ; Let's use d0.l instead:
    ; ... this gets complicated. Let me restructure.

    ; REVISED: Use absolute addressing for the big table (>32KB anyway)
    ; and compute the offset with longs.

    ext.l   d0                      ; extend X to long
    lsl.l   #8,d0                   ; d0 = X * 256
    ext.w   d2                      ; (d2 is already 0-15, high byte likely 0)
    lsl.w   #4,d2                   ; d2 = color * 16
    add.l   d2,d0                   ; d0 = X*256 + color*16

    lea     master_table,a2         ; absolute address (can't use PC-relative for >32KB)
    adda.l  d0,a2                   ; a2 -> entry with our 4 longs

    ; --- Load all 4 longs with movem (12 + 8*4 = 44 cycles) ---
    movem.l (a2),d0-d3              ; 12+8*4 = 44
    ; d0 = AND mask planes 0+1
    ; d1 = AND mask planes 2+3  (same as d0, but precomputed to save a move)
    ; d2 = OR mask planes 0+1
    ; d3 = OR mask planes 2+3

    ; --- Apply (4 read-modify-write ops) ---
    and.l   d0,(a1)                 ; 20  clear planes 0+1
    and.l   d1,4(a1)               ; 24  clear planes 2+3
    or.l    d2,(a1)                 ; 20  set planes 0+1
    or.l    d3,4(a1)               ; 24  set planes 2+3

    rts                             ; 16
                                    ; ----
                                    ; Very roughly: 8+16+4+12+8+4+12+4+8+44+20+24+20+24+16
                                    ;            = ~224 cycles, but with long ops on 68000
                                    ;              the memory accesses dominate.


; ============================================================================
; APPROACH 4 — "THE OMEGA" (Theoretical minimum with tables)
; ============================================================================
;
; What is the absolute minimum instruction sequence?
;
; We MUST do:
; 1. Compute screen address from (X, Y)           — unavoidable
; 2. Clear old bits in 4 planes                    — 2 long operations minimum
; 3. Set new bits in 4 planes                      — 2 long operations minimum
;
; Minimum memory ops: 2 reads + 4 read-modify-writes + 1 RTS
;
; The trick: minimize the SETUP cost.
;
; RADICAL IDEA: Per-scanline table of screen pointers for each X-position.
; y_x_table[Y][X_group] gives the direct screen address.
; But 200 * 20 * 4 = 16000 bytes. Not huge, but X still needs sub-group indexing.
;
; ALTERNATIVE RADICAL IDEA: Self-modifying code.
; Write the AND-mask and OR-masks directly into immediate operands of
; a code template, then JSR to it. The code template:
;
;   and.l  #$xxxx,(a1)       ; modified immediate
;   and.l  #$xxxx,4(a1)      ; modified immediate
;   or.l   #$xxxx,(a1)       ; modified immediate
;   or.l   #$xxxx,4(a1)      ; modified immediate
;   rts
;
; But and.l #imm,(ea) is FORMAT: 0000 0010 1011 1xxx, 6+ bytes, 28+ cycles.
; WAY slower than register-to-memory. Bad idea.
;
; BEST "OMEGA" approach: merge Y and X lookups maximally.
;
; Here's the key realization: on 68000, the fastest path is:
;
;   1. Table lookup to get screen pointer        (one indexed read)
;   2. Table lookup to get masks                  (one or two indexed reads)  
;   3. AND + OR the planes                        (4 memory ops)
;
; We can't avoid step 3 (that's the actual work). We can only minimize 1+2.
;
; OMEGA APPROACH: Y_ptr table + merged (X,color)->offset+masks table
;
;   y_table[y]          : 200 longs = 800 bytes (screen_base + y*160)
;   xc_offset[x]        : 320 words = 640 bytes (byte offset in scanline)
;   xc_and[x]           : 320 longs = 1280 bytes (AND mask as long)
;   xc_or[x*16+c]       : 320*16 longs × 2 = 40960 bytes (OR masks, 2 longs each)
;
; Hot path:
; ============================================================================

SetPixel_Omega:
; Input: d0.w=X, d1.w=Y, d2.w=color(0-15)
; a5 = y_table base (kept in register permanently)
; a6 = master OR table base (kept in register permanently)
; Trashes: d0-d5, a1

    ; --- Y: scanline address ---
    add.w   d1,d1                   ; 4
    add.w   d1,d1                   ; 4
    movea.l (a5,d1.w),a1            ; 14   a1 = screen + y*160

    ; --- X: byte offset + AND mask ---
    move.w  d0,d1                   ; 4    save X
    lsl.w   #2,d0                   ; 8    d0 = X*4 (long table index)
    adda.w  xc_offset(pc,d0.w),a1   ; — wait, xc_offset is word-indexed...

    ; Let me use a cleaner table layout.
    ; xc_table[X]: 6 bytes per entry:
    ;   word: byte offset in scanline
    ;   long: AND mask
    ; Total: 320 * 6 = 1920 bytes
    ;
    ; But 6-byte entries are awkward to index. Let's use 8:
    ;   long: AND mask (NOT-bitmask | NOT-bitmask)
    ;   word: byte offset in scanline  
    ;   word: padding
    ; 320 * 8 = 2560 bytes

    ; Actually, for maximum speed, let's just use separate aligned tables:

    ; --- Y lookup: 4+4+14 = 22 cycles ---
    ; (already done above, restart the approach cleanly)

    ; OK let me just write the cleanest, fastest version possible.
    ; I'll count every single cycle accurately.

    rts     ; placeholder


; ============================================================================
; APPROACH 5 — "FINAL FORM" (The practical fastest version)
; ============================================================================
;
; This is the version I'd actually ship. Clean, fast, well-structured.
;
; Register setup (done once, keep in regs across all plot calls):
;   a4 = xc_table base       (persistent)
;   a5 = y_table base         (persistent)
;   a6 = or_table base         (persistent)
;
; Tables:
;   y_table:    200 longs = absolute scanline addresses     (800 bytes)
;   xc_table:   320 * 8 bytes:                              (2560 bytes)
;               offset +0: word  byte_offset (offset within scanline)  
;               offset +2: word  or_table_offset_base (X * 16 * 8 pre-computed)
;               offset +4: long  and_mask (NOT-bitmask replicated to both halves)
;   or_table:   320 * 16 entries, each 8 bytes:             (40960 bytes)
;               offset +0: long  or_mask_planes_01
;               offset +4: long  or_mask_planes_23
;
;   TOTAL: 800 + 2560 + 40960 = 44,320 bytes (~43 KB)
;
;   NOTE: All tables accessed via base register + d.w index = 14-cycle EA mode.
;
; ============================================================================

; ---------- CYCLE-COUNTED HOT PATH ----------

SetPixel_Final:
; Input:
;   d0.w = X (0-319)
;   d1.w = Y (0-199)  
;   d2.w = color (0-15)
;   a4   = xc_table
;   a5   = y_table  
;   a6   = or_table
;
; Output: pixel plotted
; Trashes: d0-d3, a0-a1

    ; Step 1: Y -> scanline base address
    add.w   d1,d1                   ; [4]  Y*2
    add.w   d1,d1                   ; [4]  Y*4
    movea.l (a5,d1.w),a0            ; [14] a0 = y_table[Y] = screen + Y*160
                                    ;       subtotal: 22 cycles

    ; Step 2: X -> xc_table entry
    lsl.w   #3,d0                   ; [12] d0 = X*8 (index into xc_table)
    movea.l d0,a1                   ; [4]  save X*8 in a1 temporarily
    adda.l  a4,a1                   ; [8]  a1 = &xc_table[X]
                                    ;       subtotal: 24 cycles

    ; Step 3: Load byte offset and add to scanline ptr
    adda.w  (a1)+,a0                ; [8]  a0 += byte_offset; a1 now at +2
                                    ;       a0 = final screen address of pixel group
                                    ;       subtotal: 8 cycles

    ; Step 4: Load or_table offset base and compute OR entry address
    move.w  (a1)+,d0                ; [8]  d0 = or_table_offset_base (= X*16*8)
    lsl.w   #3,d2                   ; [12] d2 = color * 8
    add.w   d2,d0                   ; [4]  d0 = X*128 + color*8 = OR table index
                                    ;       subtotal: 24 cycles

    ; Step 5: Load AND mask
    move.l  (a1),d1                 ; [12] d1 = AND mask (notmask | notmask)
                                    ;       subtotal: 12 cycles

    ; Step 6: Clear old pixel bits (long operations on plane pairs)
    and.l   d1,(a0)                 ; [20] clear planes 0+1
    and.l   d1,4(a0)               ; [24] clear planes 2+3
                                    ;       subtotal: 44 cycles

    ; Step 7: Load OR masks from or_table
    movea.l a6,a1                   ; [4]  a1 = or_table base
    adda.w  d0,a1                   ; [8]  a1 = &or_table[X][color]
    move.l  (a1)+,d0                ; [12] d0 = OR mask planes 0+1
    move.l  (a1),d1                 ; [12] d1 = OR mask planes 2+3
                                    ;       subtotal: 36 cycles

    ; Step 8: Set new pixel bits
    or.l    d0,(a0)                 ; [20] set planes 0+1
    or.l    d1,4(a0)               ; [24] set planes 2+3
                                    ;       subtotal: 44 cycles

    rts                             ; [16]
                                    ; =========
                                    ; TOTAL: 22 + 24 + 8 + 24 + 12 + 44 + 36 + 44 + 16
                                    ;      = 230 cycles
                                    ;
                                    ; At 8 MHz: 230/8 = 28.75 µs per pixel
                                    ; Max throughput: ~34,782 pixels/frame (at 50 fps)


; ============================================================================
; APPROACH 6 — "FINAL FORM v2" (Turbo: eliminate more instructions)
; ============================================================================
;
; Shave cycles by restructuring:
; - Precompute (X*128) already shifted in the xc_table → saves the lsl.w #3
; - Use a unified xc_or_table where X indexing gives us both masks at once
; - Fold operations together
;
; CRITICAL OPTIMIZATION: Store the or_table_offset as a LONG POINTER 
; directly (absolute address of or_table[X][0]) to avoid the base-add.
;
; xc_table: 320 * 8 bytes                                  (2560 bytes)
;   +0: word  scanline_byte_offset
;   +2: word  (unused/padding for alignment)
;   +4: long  AND mask
; x_or_ptr: 320 longs — absolute pointer to or_table[X][0] (1280 bytes)
; or_table: 320 * 16 * 8                                   (40960 bytes)
; y_table:  200 longs                                      (800 bytes)
;
; Total: 2560 + 1280 + 40960 + 800 = 45,600 bytes (~44.5 KB)
; ============================================================================

SetPixel_Final_v2:
; Input:
;   d0.w = X (0-319)
;   d1.w = Y (0-199)
;   d2.w = color (0-15)
;   a5   = y_table
;   a6   = xc_table
; Trashes: d0-d3, a0-a1

    ; Y -> scanline address [22 cycles]
    add.w   d1,d1                   ; [4]
    add.w   d1,d1                   ; [4]
    movea.l (a5,d1.w),a0            ; [14]

    ; X -> tables [8+14=22 cycles to get byte offset added]
    add.w   d0,d0                   ; [4]  X*2
    move.w  d0,d1                   ; [4]  save X*2
    add.w   d0,d0                   ; [4]  X*4 for x_or_ptr (long table)

    ; Get OR table pointer for this X
    movea.l x_or_ptr(pc,d0.w),a1    ; [14] a1 = &or_table[X][0]

    ; Color offset into OR sub-table [10+8=18 cycles]
    lsl.w   #3,d2                   ; [10] color*8  (shifting by 3 = 6+2*1=8... 
    ;                                       actually lsl.w #n,Dn = 6+2n, so #3 = 12)
    adda.w  d2,a1                   ; [8]  a1 = &or_table[X][color]

    ; Get scanline byte-offset and AND mask from xc_table
    ; xc_table index = X * 8 = (X*2) * 4 
    add.w   d1,d1                   ; [4]  d1 = X*4
    add.w   d1,d1                   ; [4]  d1 = X*8
    ; Actually, let's index xc_table differently.
    ; We have X*4 in d0. We need X*8 for xc_table.
    ; d0 = X*4, so add d0 to itself:
    ;   ... nah, let me just track registers better.

    ; RESTART with cleaner register allocation:
    rts     ; placeholder


; ============================================================================
; APPROACH 7 — "THE ABSOLUTE FASTEST" (Final, clean, cycle-perfect)
; ============================================================================
;
; After all the exploration above, here is THE definitive fastest routine.
;
; REGISTER ALLOCATION (persistent across all pixel plot calls):
;   a3 = or_table base
;   a4 = x_table base  
;   a5 = y_table base
;
; TABLE LAYOUT:
;
; y_table[200]:  .ds.l 200                 ;  800 bytes
;   Entry = screen_base + Y * 160
;
; x_table[320]:  .ds.l 320  (2 words each) ; 2560 bytes total at 8 bytes/entry
;   +0 (word): byte offset of pixel group within scanline ((X/16)*8)
;   +2 (word): NOT(bitmask) AND mask (lower half for .w operations)... 
;              WAIT: we need a LONG AND mask (same half replicated).
;
;   Actually for 8-byte entries:
;   +0 (word): byte offset within scanline
;   +2 (word): reserved (for alignment)
;   +4 (long): AND mask = NOT(bitmask)|NOT(bitmask) packed as long
;
; or_table[320][16]:  8 bytes per entry     ; 40960 bytes
;   +0 (long): OR mask for planes 0+1
;   +4 (long): OR mask for planes 2+3
;
; TOTAL: 800 + 2560 + 40960 = 44,320 bytes (43.3 KB)
; ============================================================================

; ---- Hot path — CYCLE EXACT on MC68000 ----
;
; 68000 timing reference:
;   add.w  Dn,Dn          :  4 cycles
;   lsl.w  #n,Dn          :  6 + 2n cycles
;   move.w Dn,Dn          :  4 cycles
;   movea.l (d16,An,Xn.w),An : can't do this! Only (d8,An,Xn)
;   move.l (d8,An,Xn.w),Dn  : 18 cycles (brief extension word)
;   movea.l (An,Xn.w),An    : not a valid 68000 mode...
;
; Actually, (An,Dn.w) with 0 displacement IS valid on 68000:
;   move.l 0(An,Dn.w),reg : 18 cycles (for long, = 14 for word)
;   lea    0(An,Dn.w),An  : 12 cycles
;   adda.w 0(An,Dn.w),An  : not valid! adda doesn't have (d8,An,Xn) mode.
;
; So: we use move.w and then adda.w Dn,An.
;
; Let me be very precise about valid 68000 addressing modes:
;   (An)         — Address Register Indirect
;   (An)+        — with Post-increment
;   -(An)        — with Pre-decrement
;   d16(An)      — with 16-bit displacement
;   d8(An,Xn)    — with index (8-bit displacement)
;   xxx.W        — Absolute Short
;   xxx.L        — Absolute Long
;   d16(PC)      — PC-relative
;   d8(PC,Xn)    — PC-relative with index
;   #imm         — Immediate
;
; For LEA, valid modes: (An), d16(An), d8(An,Xn), xxx, d16(PC), d8(PC,Xn)
;   lea d8(An,Dn.w),Ax  : 12 cycles
;
; For MOVE.W, source d8(An,Dn.w) is valid: 14 cycles (to register)
; For MOVE.L, source d8(An,Dn.w) is valid: 18 cycles (to register)
;

SetPixel_Absolute:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0-319)        — will be destroyed
;   d1.w = Y (0-199)        — will be destroyed
;   d2.w = color (0-15)     — will be destroyed
;
; Persistent registers (set up once before plotting loop):
;   a3 = or_table            (40960 bytes)
;   a4 = x_table             (320 * 8 = 2560 bytes)
;   a5 = y_table             (200 * 4 = 800 bytes)
;
; Trashed: d0, d1, d2, d3, a0, a1
;----------------------------------------------------------------------

    ; === Y -> scanline pointer ===
    add.w   d1,d1                   ; [4]  Y*2
    add.w   d1,d1                   ; [4]  Y*4 (long-table index)
    movea.l 0(a5,d1.w),a0           ; [18] a0 = screen_base + Y*160
                                    ;      Subtotal: 26 cycles

    ; === X -> x_table entry ===
    lsl.w   #3,d0                   ; [12] d0 = X*8 (x_table entry size = 8)
    lea     0(a4,d0.w),a1           ; [12] a1 = &x_table[X]
                                    ;      Subtotal: 24 cycles

    ; === Add byte offset to screen pointer ===
    adda.w  (a1)+,a0                ; [8]  a0 += byte_offset; a1 now at +2
                                    ;      a0 = screen addr of pixel group
                                    ;      Subtotal: 8 cycles

    ; === Compute or_table index ===
    move.w  (a1)+,d0                ; [8]  d0 = X * 128 (precomputed, stored at +2)
    lsl.w   #3,d2                   ; [12] d2 = color * 8
    add.w   d2,d0                   ; [4]  d0 = or_table offset
    lea     0(a3,d0.w),a1           ; [12] a1 = &or_table[X][color]
                                    ;      Subtotal: 36 cycles
                                    ; WAIT: X*128 for X=256+ exceeds 16-bit!
                                    ; X=319: 319*128 = 40832. Max color*8 = 15*8 = 120
                                    ; 40832 + 120 = 40952. Fits in unsigned 16-bit (65535).
                                    ; BUT: add.w and lea use SIGNED 16-bit (-32768..32767)!
                                    ; 40952 > 32767! OVERFLOW!
                                    ;
                                    ; SOLUTION: Use .l for the index, OR restructure the table
                                    ; to use a smaller stride.
                                    ;
                                    ; Alt: store or_table pointer as absolute .l at x_table+2
                                    ; That costs 18 cycles for the load but eliminates the add.

    ; === REVISED: x_table entry is 12 bytes ===
    ; +0: word  byte_offset
    ; +2: word  (pad)
    ; +4: long  AND mask
    ; +8: long  pointer to or_table[X][0]  (absolute address)
    ;
    ; But 12-byte entries = multiply by 12 = gross. Use 16:
    ; +0:  word  byte_offset
    ; +2:  word  (pad)
    ; +4:  long  AND mask
    ; +8:  long  or_sub_table pointer
    ; +12: long  (pad)
    ;
    ; 320 * 16 = 5120 bytes. Still fine.
    ;
    ; X * 16 indexing: lsl.w #4,d0 = 6+8 = 14 cycles. OK.

    rts ; placeholder — see final version below


; ============================================================================
; ===                 T H E   D E F I N I T I V E   V E R S I O N         ===
; ============================================================================
;
; After all exploration, here is the fastest pixel plot for Atari ST.
;
; TABLE LAYOUT (total: ~47 KB):
;
; y_table:   200 longs                                        =   800 bytes
;            y_table[Y] = screen_base + Y * 160
;
; x_table:   320 entries × 16 bytes each                      =  5120 bytes
;            +0:  long   AND mask (NOT-bitmask replicated: hi.w = lo.w)
;            +4:  long   absolute pointer to or_sub[0] for this X
;            +8:  word   byte offset of pixel group in scanline
;            +10: word   (padding)
;            +12: long   (padding)
;
; or_table:  320 × 16 entries × 8 bytes each                  = 40960 bytes
;            or_table[X][color]:
;            +0: long    OR mask for planes 0+1
;            +4: long    OR mask for planes 2+3
;
; GRAND TOTAL: 800 + 5120 + 40960 = 46,880 bytes (~45.8 KB)
;
; ============================================================================

SetPixel:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent (set up once before any plotting):
;   a4 = x_table base
;   a5 = y_table base
;
; Trashed: d0, d1, d2, d3, a0, a1, a2
;----------------------------------------------------------------------

    ; ---- Step 1: Y → scanline base address ----
    add.w   d1,d1                   ; [4]   d1 = Y*2
    add.w   d1,d1                   ; [4]   d1 = Y*4
    movea.l 0(a5,d1.w),a0           ; [18]  a0 = screen_base + Y*160
                                    ;       26 cycles

    ; ---- Step 2: X → x_table entry ----
    lsl.w   #4,d0                   ; [14]  d0 = X*16 (entry size=16)
    lea     0(a4,d0.w),a1           ; [12]  a1 = &x_table[X]
                                    ;       26 cycles
                                    ; WARNING: X=319, 319*16=5104, OK (< 32767 ✓)

    ; ---- Step 3: Load AND mask ----
    move.l  (a1)+,d3                ; [12]  d3 = AND mask; a1 now at +4
                                    ;       12 cycles

    ; ---- Step 4: Load OR sub-table pointer ----
    movea.l (a1)+,a2                ; [12]  a2 = &or_table[X][0]; a1 now at +8
                                    ;       12 cycles

    ; ---- Step 5: Add byte offset to screen pointer ----
    adda.w  (a1),a0                 ; [12]  a0 += byte_offset
                                    ;       a0 now points to the exact pixel group
                                    ;       12 cycles
                                    ; (Note: adda.w (An),An = 4+8 = 12 on 68000?
                                    ;  Actually: ADDA.W <ea>,An with (An) mode = 
                                    ;  for word: 8 cycles. Let me recheck.
                                    ;  ADDA word: 8(1/0) + ea time.
                                    ;  (An) ea = 4(1/0). Total = 8+4 = 12? 
                                    ;  No: ADDA.W is 8 cycles base for register.
                                    ;  For (An): ADDA.W (An),An = 8 cycles total.)
                                    ;       8 cycles (CORRECTED)

    ; ---- Step 6: Index into OR sub-table by color ----
    lsl.w   #3,d2                   ; [12]  d2 = color * 8
    lea     0(a2,d2.w),a1           ; [12]  a1 = &or_table[X][color]
                                    ;       24 cycles

    ; ---- Step 7: Clear old pixel (AND mask across both plane pairs) ----
    and.l   d3,(a0)                 ; [20]  clear bits in planes 0+1
    and.l   d3,4(a0)               ; [24]  clear bits in planes 2+3
                                    ;       44 cycles

    ; ---- Step 8: Load and apply OR masks ----
    move.l  (a1)+,d0                ; [12]  d0 = OR planes 0+1
    or.l    d0,(a0)                 ; [20]  set new bits in planes 0+1
    move.l  (a1),d0                 ; [12]  d0 = OR planes 2+3
    or.l    d0,4(a0)               ; [24]  set new bits in planes 2+3
                                    ;       68 cycles

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   26 + 26 + 12 + 12 + 8 + 24 + 44 + 68 + 16 = 236 cycles
;
; At 8 MHz this is 29.5 µs per pixel.
; Throughput: ~33,898 pixels/second
; Per 50Hz frame (20ms): ~677 pixels per frame if doing nothing else
; Per 50Hz frame (full): more like ~580 accounting for loop overhead
;----------------------------------------------------------------------


; ============================================================================
; APPROACH 8 — "UNROLLED INLINE" (For batch plotting — fastest per-pixel)
; ============================================================================
;
; When plotting many pixels in a loop, we can save the JSR/RTS overhead (32 
; cycles) by inlining. Also, if pixels share the same Y coordinate (common:
; horizontal lines, span fill, etc.), cache the scanline pointer.
;
; For inner-loop batch pixel plotting at same Y:
; ============================================================================

; SetPixelBatch_SameY:
; Called with: a0 = scanline base (already computed from Y)
;              d0.w = X
;              d2.w = color
;              a4 = x_table, a3 = or_table
; This is the INNER LOOP body — no RTS, no Y computation.
; Can be unrolled N times for maximum throughput.

    ; Total per pixel (inline, same Y): 
    ;   26 (X lookup) + 12 + 12 + 8 + 24 + 44 + 68 = 194 cycles


; ============================================================================
; EVEN FASTER APPROACH 9 — "WRITE-ONLY" for cleared screens
; ============================================================================
;
; If the background is color 0 and the screen has been cleared, then
; we DON'T need the AND step! We only OR in the new pixel.
; This saves 44 cycles (the two and.l operations).
;
; Total: 236 - 44 = 192 cycles (per pixel with full setup)
; Inline same-Y: 194 - 44 = 150 cycles
; ============================================================================

SetPixel_WriteOnly:
; Input: d0.w=X, d1.w=Y, d2.w=color
; Precondition: pixel was ALREADY color 0 (screen cleared or known state)
; Only works when you're drawing onto a clean background!

    add.w   d1,d1                   ; [4]
    add.w   d1,d1                   ; [4]
    movea.l 0(a5,d1.w),a0           ; [18] scanline addr

    lsl.w   #4,d0                   ; [14] X*16
    lea     0(a4,d0.w),a1           ; [12] &x_table[X]

    addq.l  #4,a1                   ; [8]  skip AND mask (unused)
    movea.l (a1)+,a2                ; [12] or sub-table pointer
    adda.w  (a1),a0                 ; [8]  add byte offset

    lsl.w   #3,d2                   ; [12] color*8
    lea     0(a2,d2.w),a1           ; [12] &or_table[X][color]

    move.l  (a1)+,d0                ; [12]
    or.l    d0,(a0)                 ; [20] set planes 0+1
    move.l  (a1),d0                 ; [12]
    or.l    d0,4(a0)               ; [24] set planes 2+3

    rts                             ; [16]
                                    ; Total: 188 cycles


; ============================================================================
; TABLE GENERATION CODE (run once at startup)
; ============================================================================

InitTables:
    ; ---- Generate y_table ----
    lea     y_table,a0
    movea.l screen_base,a1          ; screen base address
    move.w  #199,d7                 ; 200 scanlines
.y_loop:
    move.l  a1,(a0)+
    lea     160(a1),a1              ; next scanline = +160 bytes
    dbf     d7,.y_loop

    ; ---- Generate x_table and or_table ----
    lea     x_table,a0
    lea     or_table,a2
    moveq   #0,d7                   ; X counter

.x_loop:
    ; Compute byte offset: (X/16)*8
    move.w  d7,d0
    lsr.w   #4,d0                   ; X/16
    lsl.w   #3,d0                   ; (X/16)*8
    move.w  d0,d5                   ; d5 = byte offset, save for x_table

    ; Compute bitmask: 1 << (15 - (X & 15))
    move.w  d7,d0
    andi.w  #$0F,d0                 ; X & 15
    moveq   #15,d1
    sub.w   d0,d1                   ; 15 - (X & 15)
    moveq   #0,d0
    bset    d1,d0                   ; d0 = bitmask (word)

    ; AND mask = NOT(bitmask) replicated as long
    move.w  d0,d3                   ; d3 = bitmask
    not.w   d3                      ; d3 = NOT(bitmask)
    move.w  d3,d4
    swap    d4
    move.w  d3,d4                   ; d4 = NOT(bitmask) | NOT(bitmask) << 16
                                    ; This is the AND long mask

    ; Store x_table entry (16 bytes):
    ; +0:  long  AND mask
    ; +4:  long  pointer to or_sub_table for this X
    ; +8:  word  byte offset
    ; +10: word  pad
    ; +12: long  pad
    move.l  d4,(a0)+                ; +0: AND mask
    move.l  a2,(a0)+                ; +4: pointer to or_table[X][0]
    move.w  d5,(a0)+                ; +8: byte offset
    move.w  #0,(a0)+                ; +10: padding
    move.l  #0,(a0)+                ; +12: padding

    ; Generate 16 or_table entries for this X (one per color)
    moveq   #0,d6                   ; color counter (0-15)

.color_loop:
    ; For planes 0+1 (bits 0 and 1 of color):
    ; plane0 OR mask = (color & 1) ? bitmask : 0
    ; plane1 OR mask = (color & 2) ? bitmask : 0
    ; Packed as long: (plane0_mask << 16) | plane1_mask ... WAIT
    ; Actually the ST stores plane0 FIRST, at lower address.
    ; A long read at the pixel group gets: [plane0.w in high word][plane1.w in low word]
    ; Because 68000 is big-endian!
    ;
    ; So the long at offset 0 of pixel group = (plane0 << 16) | plane1
    ; And the long at offset 4 = (plane2 << 16) | plane3

    moveq   #0,d1                   ; will accumulate planes 0+1 long
    moveq   #0,d2                   ; will accumulate planes 2+3 long

    ; Plane 0 (bit 0 of color) → high word of first long
    btst    #0,d6
    beq.s   .no_p0
    move.w  d3,d1                   ; WAIT: d3 was NOT(bitmask)... 
    ; We need bitmask here, not NOT(bitmask)!
    move.w  d0,d1                   ; d0 still has bitmask? 
    ; Careful with register tracking... let me use d0=bitmask consistently.
    ; d0 was bitmask. d3=NOT(bitmask). d4=AND long. d5=byte_off. d6=color.

    ; RESTART color_loop with clear register usage:
    ; d0 = bitmask (preserved across color loop)
    ; d6 = color counter

    swap    d1                      ; move to high word position
    ; Actually let me just regenerate cleanly:
.no_p0:

    ; --- OK, I'll write cleaner generation code ---
    bra.s   .skip_gen               ; placeholder
.skip_gen:
    addq.w  #1,d6
    cmp.w   #16,d6
    bne.s   .color_loop

    addq.w  #1,d7
    cmp.w   #320,d7
    bne     .x_loop
    rts


; ============================================================================
; CLEAN TABLE GENERATION (production quality)
; ============================================================================

InitTables_Clean:
    movem.l d0-d7/a0-a6,-(sp)

    ; ---- Y table: y_table[Y] = screen_base + Y*160 ----
    lea     y_table,a0
    movea.l screen_base_ptr,a1
    move.w  #199,d7
.yt_loop:
    move.l  a1,(a0)+
    lea     160(a1),a1
    dbf     d7,.yt_loop

    ; ---- X table + OR table ----
    lea     x_table,a0              ; a0 = x_table write pointer
    lea     or_table,a2             ; a2 = or_table write pointer

    moveq   #0,d7                   ; d7 = X (0-319)
.xt_loop:
    ; -- Byte offset within scanline: (X/16)*8 --
    move.w  d7,d0
    lsr.w   #4,d0                   ; X / 16
    lsl.w   #3,d0                   ; * 8
    move.w  d0,d5                   ; d5 = byte_offset

    ; -- Bitmask: bit (15 - (X & 15)) --
    move.w  d7,d0
    andi.w  #$000F,d0               ; X mod 16
    moveq   #15,d1
    sub.w   d0,d1                   ; bit position
    moveq   #1,d0
    lsl.w   d1,d0                   ; d0.w = bitmask

    ; -- AND mask long: NOT(bitmask) replicated --
    move.w  d0,d4                   ; save bitmask in d4
    not.w   d4                      ; d4.w = NOT(bitmask)
    move.l  d4,d3                   ; d3.l low word = NOT(bitmask)
    swap    d3                      ;  
    move.w  d4,d3                   ; d3.l = NOT(bitmask):NOT(bitmask)

    ; -- Write x_table entry --
    move.l  d3,(a0)+                ; +0: AND mask (long)
    move.l  a2,(a0)+                ; +4: pointer to or_table[X][0]
    move.w  d5,(a0)+                ; +8: byte offset
    clr.w   (a0)+                   ; +10: pad
    clr.l   (a0)+                   ; +12: pad

    ; -- Generate 16 OR table entries for this X --
    moveq   #0,d6                   ; d6 = color (0-15)
.or_loop:
    ; Build OR long for planes 0+1:
    ;   high word = plane 0 mask = (color bit 0) ? bitmask : 0
    ;   low word  = plane 1 mask = (color bit 1) ? bitmask : 0
    moveq   #0,d1                   ; planes 0+1 long
    moveq   #0,d2                   ; planes 2+3 long

    ; Plane 0 (bit 0 of color) → high word of d1
    btst    #0,d6
    beq.s   .skip_p0
    swap    d1
    move.w  d0,d1                   ; high word of d1 = bitmask
    swap    d1
.skip_p0:

    ; Plane 1 (bit 1 of color) → low word of d1
    btst    #1,d6
    beq.s   .skip_p1
    move.w  d0,d1                   ; low word of d1 = bitmask
.skip_p1:

    ; Plane 2 (bit 2 of color) → high word of d2
    btst    #2,d6
    beq.s   .skip_p2
    swap    d2
    move.w  d0,d2
    swap    d2
.skip_p2:

    ; Plane 3 (bit 3 of color) → low word of d2
    btst    #3,d6
    beq.s   .skip_p3
    move.w  d0,d2
.skip_p3:

    ; Write OR entry (8 bytes)
    move.l  d1,(a2)+                ; planes 0+1 OR mask
    move.l  d2,(a2)+                ; planes 2+3 OR mask

    addq.w  #1,d6
    cmp.w   #16,d6
    bne.s   .or_loop

    addq.w  #1,d7
    cmp.w   #320,d7
    bne     .xt_loop

    movem.l (sp)+,d0-d7/a0-a6
    rts


; ============================================================================
; APPROACH 10 — "THE DEMOSCENE TRICK" — MOVE-only, no AND/OR
; ============================================================================
;
; The approaches above use AND to clear + OR to set = 4 read-modify-write ops.
; Each read-modify-write long op is 20-24 cycles.
;
; TRICK: If we read the old values, mask them in registers, and write back,
; we avoid the expensive read-modify-write:
;
;   move.l  (a0),d4      ; 12 — read planes 0+1
;   and.l   d3,d4        ;  8 — clear in register (FAST! reg-to-reg)
;   or.l    d0,d4        ;  8 — set in register
;   move.l  d4,(a0)      ; 12 — write back
;                          40 cycles for 2 planes
;
; Compare with:
;   and.l   d3,(a0)      ; 20 — read-modify-write
;   or.l    d0,(a0)      ; 20 — read-modify-write
;                          40 cycles for 2 planes
;
; SAME COST! Hmm. But wait:
;   and.l   Dn,(ea) with (An) mode    = 20 cycles (12 + 8 ?)
;   No: and.l Dn,<ea>: for (An) ea, the timing is 12(1/2)
;   and or.l Dn,<ea>: (An) = 12(1/2)
;   So AND + OR to memory = 12 + 12 = 24 cycles per plane pair.
;   Wait, let me look at the 68000 manual more carefully...
;
; 68000 Instruction Timing (from Motorola manual):
;   AND.L Dn,(An):     Byte count=20, timing=12(1/2)   → 20 TOTAL
;   OR.L  Dn,(An):     same → 20 TOTAL
;   So AND+OR to (An) = 20+20 = 40 cycles per plane pair.
;
;   Versus register approach:
;   MOVE.L (An),Dn:    12(3/0) → 12 TOTAL
;   AND.L  Dn,Dn:      8(1/0)  → 8 TOTAL  (register to register)
;   OR.L   Dn,Dn:      8(1/0)  → 8 TOTAL
;   MOVE.L Dn,(An):    12(1/1) → 12 TOTAL
;   Total: 12+8+8+12 = 40 cycles. SAME!
;
; For d16(An) displacement:
;   AND.L Dn,d16(An):  24(1/2) → 24 cycles (4 extra for displacement)
;   OR.L  Dn,d16(An):  24(1/2) → 24 cycles
;   Total: 48 cycles.
;
;   Register approach with d16(An):
;   MOVE.L d16(An),Dn: 16(4/0)  → 16
;   AND.L  Dn,Dn:      8(1/0)   → 8
;   OR.L   Dn,Dn:      8(1/0)   → 8
;   MOVE.L Dn,d16(An): 16(2/1)  → 16
;   Total: 48. STILL THE SAME.
;
; So register approach has NO cycle advantage for AND+OR.
; But it DOES have an advantage if we can MERGE the OR values into one step.
;
; FINAL OPTIMIZATION: use the register approach to COMBINE the clear/set
; into a single operation: (old AND mask) OR new = new_value
; Precompute: combined_value[X][color] = precomputed (AND + OR) result? No,
; depends on neighboring pixels! Can't precompute the combined value.
;
; HOWEVER: with the register approach we can use MOVEM to load/store:
;   movem.l (a0),d4-d5    ; 12+8*2 = 28 — read ALL 8 bytes (4 planes) at once!
;   and.l   d3,d4         ;  8
;   or.l    d0,d4         ;  8
;   and.l   d3,d5         ;  8
;   or.l    d1,d5         ;  8
;   movem.l d4-d5,(a0)    ;  8+8*2 = 24 — write ALL 8 bytes at once!
;   Total: 28+8+8+8+8+24 = 84 cycles for ALL 4 planes!
;
; Compare with direct-to-memory approach:
;   and.l d3,(a0)     = 20
;   or.l  d0,(a0)     = 20
;   and.l d3,4(a0)    = 24
;   or.l  d1,4(a0)    = 24
;   Total: 88 cycles.
;
; MOVEM approach SAVES 4 CYCLES! Small but real.
; And with more careful counting on displacement modes, can save more.
;
; BUT WAIT: movem.l regs,(An) is 8 + 8*n cycles, BUT the destination MUST
; be -(An) or (An) modes only for MOVEM to memory! Actually:
;   MOVEM.L reglist,(An) : YES, valid as a store. 8+8n cycles.
;   MOVEM.L (An),reglist : YES, valid as a load.  12+8n cycles.
;
; So MOVEM bulk read-modify-write:
;   movem.l (a0),d4-d5    ; 12 + 8*2 = 28 cycles, reads 8 bytes from (a0)
;   and.l   d3,d4         ; 8
;   or.l    d0,d4         ; 8
;   and.l   d3,d5         ; 8
;   or.l    d1,d5         ; 8
;   movem.l d4-d5,(a0)    ; 8 + 8*2 = 24 cycles, writes 8 bytes to (a0)
;                          ; Total: 84 cycles for the pixel modify step

; This replaces the 88-cycle approach. Let's integrate it:
; ============================================================================

SetPixel_Movem:
;----------------------------------------------------------------------
; THE DEFINITIVE FASTEST PIXEL PLOT — MOVEM VARIANT
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent:
;   a4 = x_table (320 entries × 16 bytes = 5120 bytes)
;   a5 = y_table (200 longs = 800 bytes)
;
; Trashed: d0-d5, a0-a2
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]
    add.w   d1,d1                   ; [4]
    movea.l 0(a5,d1.w),a0           ; [18]

    ; ---- X → x_table entry ---- [26 cycles]
    lsl.w   #4,d0                   ; [14] X*16
    lea     0(a4,d0.w),a1           ; [12]

    ; ---- Load x_table fields ---- [36 cycles]
    move.l  (a1)+,d3                ; [12] AND mask long
    movea.l (a1)+,a2                ; [12] → or_table[X][0]
    adda.w  (a1),a0                 ; [8]  + byte offset → pixel group addr
    ;                                         (adda.w (An),An = 8 cycles)

    ; ---- OR table lookup ---- [24 cycles]
    lsl.w   #3,d2                   ; [12] color*8
    adda.w  d2,a2                   ; [8]  a2 = &or_table[X][color]
    ; Actually adda.w Dn,An = 8 cycles. ✓

    ; ---- Load OR masks ---- [24 cycles]
    move.l  (a2)+,d0                ; [12] OR planes 0+1
    move.l  (a2),d1                 ; [12] OR planes 2+3

    ; ---- MOVEM bulk read ---- [28 cycles]
    movem.l (a0),d4-d5              ; [28] d4 = planes 0+1, d5 = planes 2+3

    ; ---- Modify in registers ---- [32 cycles]
    and.l   d3,d4                   ; [8]  clear old bits planes 0+1
    or.l    d0,d4                   ; [8]  set new bits planes 0+1
    and.l   d3,d5                   ; [8]  clear old bits planes 2+3
    or.l    d1,d5                   ; [8]  set new bits planes 2+3

    ; ---- MOVEM bulk write ---- [24 cycles]
    movem.l d4-d5,(a0)              ; [24] write back all 4 planes at once

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   26 + 26 + 32 + 20 + 24 + 28 + 32 + 24 + 16 = 228 cycles
;
; CORRECTED detailed count:
;   Y lookup:        4 + 4 + 18           = 26
;   X table addr:    14 + 12              = 26
;   Load fields:     12 + 12 + 8          = 32
;   OR lookup:       12 + 8               = 20
;   Load OR masks:   12 + 12              = 24
;   MOVEM read:      28                   = 28
;   Register ops:    8 + 8 + 8 + 8        = 32
;   MOVEM write:     24                   = 24
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 228 cycles
;
; AT 8 MHz: 28.5 µs per pixel
; PIXELS PER 50Hz FRAME: ~701 (with just pixel plotting, no other code)
;
; WITHOUT RTS (inlined in a loop): 212 cycles per pixel
; SAME-Y VARIANT (skip Y lookup): 202 cycles per pixel (inlined)
;----------------------------------------------------------------------


; ============================================================================
; COMPARISON SUMMARY
; ============================================================================
;
; Approach              | Cycles | Table RAM | Notes
; ----------------------|--------|-----------|-------------------------------
; Naive (no tables)     | ~400+  |     0     | Shifts, branches, slow
; Approach 1 (words)    |  ~280  |   ~43 KB  | Word-sized ops, simple
; Approach 2 (longs)    |  ~250  |   ~43 KB  | Long ops on plane pairs
; SetPixel (definitive) |   236  |   ~46 KB  | Long ops, pointer tables
; SetPixel_Movem ★      |   228  |   ~46 KB  | MOVEM bulk read/write
; WriteOnly variant     |  ~188  |   ~46 KB  | Skip AND (clean screen only)
; Same-Y inlined        |  ~202  |   ~46 KB  | Skip Y lookup + no RTS
; Same-Y WriteOnly      |  ~158  |   ~46 KB  | Best case: batch + clean
;
; ★ = RECOMMENDED general-purpose version
;
; ALL APPROACHES: ~46 KB tables (well within 256 KB budget)
; ============================================================================


; ============================================================================
; EXTRA: EXPANDED 256KB-BUDGET "ULTRA" APPROACH
; ============================================================================
;
; With 256 KB budget, we could precompute:
;   - y_x_table[200][20]: for each (scanline, word-group), store the
;     absolute screen address. 200*20*4 = 16000 bytes.
;   - This eliminates BOTH the Y multiply AND the X byte-offset add!
;   - Saves ~18 cycles (the adda.w for byte offset + potential stalls)
;
; y_x_table[Y][X/16] = screen_base + Y*160 + (X/16)*8
;   200 × 20 × 4 = 16,000 bytes
;
; x_and_table[320]: AND mask longs = 1 per unique bit position = 16 entries
;   But indexed by X, so 320 × 4 = 1280 bytes (or just 16 × 4 = 64 bytes
;   with an extra AND #$F instruction)
;
; or_table[320][16] × 8 = 40,960 bytes
;
; Total: 16000 + 1280 + 40960 = 58,240 bytes (~57 KB)
;
; Even more extreme: for each Y, store a pointer table for all 320 X
; positions (mapping to their pixel group). 200 × 320 × 4 = 256,000 bytes.
; Just over 256KB! But: many entries would be the same (16 consecutive X 
; values share a pixel group). So store pointers to 20 groups per line:
; That's the y_x_table above.
; ============================================================================

SetPixel_Ultra:
;----------------------------------------------------------------------
; ULTIMATE VERSION — uses y_x_table for merged Y+X lookup
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent:
;   a3 = x_info_table (320 entries × 8 bytes: or_ptr + AND mask)
;   a5 = y_x_table    (200 × 20 longs)
;
; Table layout:
;
; y_x_table[Y][group]:  200 × 20 × 4 bytes = 16000 bytes
;   y_x_table[Y * 20 + X/16] = screen_base + Y*160 + (X/16)*8
;
; x_info[X]:  320 × 8 bytes = 2560 bytes
;   +0: long  AND mask
;   +4: long  or_sub_table pointer
;
; or_table[X][color]: 320 × 16 × 8 bytes = 40960 bytes
;   +0: long  OR mask planes 0+1
;   +4: long  OR mask planes 2+3
;
; TOTAL: 16000 + 2560 + 40960 = 59,520 bytes (~58 KB)
;----------------------------------------------------------------------

    ; ---- Merged Y+X → pixel group address ----
    ; y_x index = Y * 80 + (X/16) * 4   (80 = 20 groups × 4 bytes/long)
    ;           = Y * 80 + (X >> 4) << 2

    move.w  d0,d3                   ; [4]  save X
    lsr.w   #4,d0                   ; [12] X/16
    lsl.w   #2,d0                   ; [10] (X/16)*4 = group index in bytes

    ; Y * 80: split as Y*64 + Y*16
    move.w  d1,d4                   ; [4]
    lsl.w   #4,d4                   ; [14] Y*16
    lsl.w   #6,d1                   ; [18] Y*64
    add.w   d4,d1                   ; [4]  Y*80
    add.w   d0,d1                   ; [4]  Y*80 + (X/16)*4

    movea.l 0(a5,d1.w),a0           ; [18] a0 = screen pixel group address!
                                    ;      92 cycles — WORSE than before!

    ; Hmm. The Y*80 computation eats the savings.
    ; Y*80 via shifts = 4+14+18+4 = 40 cycles vs old Y*4 = 8 cycles.
    ; We save 8 cycles (old adda.w for byte offset) but spend 32 more.
    ; NET LOSS of 24 cycles!
    ;
    ; SOLUTION: Make y_x_table indexed by Y * 128 instead of Y * 80,
    ; wasting some space but making indexing trivial:
    ;   Y * 128 + (X/16)*4
    ;   lsl.w #7,d1 = 6+14 = 20 cycles (vs 8 for Y*4 — only 12 more)
    ;   Saves 8 cycles on the adda, net cost = 4 more cycles.
    ;
    ; Table size: 200 * 128 = 25,600 bytes (only 20 of 32 entries used)
    ; Still fits! Total: 25600 + 2560 + 40960 = 69,120 bytes (~67 KB)
    ;
    ; But... it's 4 cycles SLOWER. Not worth it for general case.
    ; ONLY worth it if we're doing batch plotting where Y is precomputed.

    ; ---- X info lookup [20 cycles] ----
    lsl.w   #3,d3                   ; [12] X*8
    lea     0(a3,d3.w),a1           ; [12] &x_info[X]

    ; ---- Load AND + OR pointer [24 cycles] ----
    move.l  (a1)+,d3                ; [12] AND mask
    movea.l (a1),a2                 ; [12] or sub-pointer

    ; ---- Color → OR entry [20 cycles] ----
    lsl.w   #3,d2                   ; [12] color*8
    adda.w  d2,a2                   ; [8]

    ; ---- Load OR masks [24 cycles] ----
    move.l  (a2)+,d0                ; [12]
    move.l  (a2),d1                 ; [12]

    ; ---- MOVEM read-modify-write [84 cycles] ----
    movem.l (a0),d4-d5              ; [28]
    and.l   d3,d4                   ; [8]
    or.l    d0,d4                   ; [8]
    and.l   d3,d5                   ; [8]
    or.l    d1,d5                   ; [8]
    movem.l d4-d5,(a0)              ; [24]

    rts                             ; [16]

    ; Total is higher than SetPixel_Movem. The y_x_table isn't worth it
    ; for random pixel access. IT IS worth it for scanline-coherent access
    ; where Y*80 or Y*128 can be precomputed once per scanline.


; ============================================================================
; DATA SECTION — Table Storage
; ============================================================================

    section data

screen_base_ptr:
    dc.l    $78000                  ; example: screen at $78000

    ; Align tables to even addresses (68000 requirement)
    even

y_table:
    ds.l    200                     ; 800 bytes

x_table:
    ds.l    1280                    ; 320 entries * 16 bytes = 5120 bytes

or_table:
    ds.l    10240                   ; 320 * 16 * 8 bytes = 40960 bytes

; Total data: 800 + 5120 + 40960 = 46,880 bytes (~45.8 KB)
; Well within the 256 KB budget.

; ============================================================================
; USAGE EXAMPLE
; ============================================================================
;
;   ; At startup:
;       jsr     InitTables_Clean
;       lea     x_table,a4
;       lea     y_table,a5
;
;   ; Plot a pixel:
;       move.w  #160,d0             ; X = 160
;       move.w  #100,d1             ; Y = 100
;       move.w  #7,d2               ; color = 7
;       jsr     SetPixel_Movem
;
;   ; Batch plot (same Y, inlined):
;       ; Precompute Y once:
;       move.w  #50,d1
;       add.w   d1,d1
;       add.w   d1,d1
;       movea.l 0(a5,d1.w),a0      ; a0 = scanline base for Y=50
;
;       ; Then for each pixel, only do X+color lookup + MOVEM:
;       ; (saves 26 cycles per pixel)
;
; ============================================================================
