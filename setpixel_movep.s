; ============================================================================
; SetPixel_Movep — MOVEP-BASED PIXEL PLOT (194 cycles)
; ============================================================================
;
; Uses the MC68000 MOVEP.L instruction to read/write one byte from each of
; the 4 bitplanes in a single 24-cycle operation. This replaces the MOVEM.L
; approach (which moves full words per plane pair) with byte-level access
; that matches the natural granularity of a single pixel bit.
;
; The MOVEP.L instruction reads/writes bytes at offsets d, d+2, d+4, d+6
; from the base address — exactly the spacing of the 4 interleaved plane
; bytes in Atari ST screen memory. This gives two key advantages:
;
;   1. Pixel modification: one AND + one OR (2 ops) vs two each (4 ops)
;      MOVEP: read(24) + AND(8) + OR(8) + write(24) = 64 cycles
;      MOVEM: read(28) + AND×2(16) + OR×2(16) + write(24) = 84 cycles
;      → 20 cycles saved on pixel modification
;
;   2. Smaller masks: 1 long per mask (4 bytes) vs 2 longs (8 bytes)
;      OR table: 320×16×4 = 20 KB  vs  320×16×8 = 40 KB
;      → tables shrink from ~46 KB to ~26 KB
;
; Convention:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent registers (set up once before any plotting):
;   a4 = x_table_m base (320 entries × 16 bytes = 5120 bytes)
;   a5 = y_table_m base (200 longs = 800 bytes)
;
; Trashed: d0-d4, a0-a2
;
; Performance: 194 cycles at 8 MHz = 24.25 µs per pixel
;              ~824 pixels per 50 Hz frame
;              Without RTS (inlined): 178 cycles
;              Same-Y variant (skip Y lookup): 168 cycles (inlined)
;
; Table RAM:   ~26 KB (y_table_m + x_table_m + or_table_m)
;              Smallest of any variant (vs ~46 KB standard, ~82 KB ultra)
;
; ============================================================================
;
; KEY INSIGHT — MOVEP.L AND BITPLANE BYTE ACCESS:
;
;   Atari ST screen: [plane0.w][plane1.w][plane2.w][plane3.w] = 8 bytes
;
;   High bytes (offsets 0,2,4,6):     Low bytes (offsets 1,3,5,7):
;     plane 0 bits 15-8                 plane 0 bits 7-0
;     plane 1 bits 15-8                 plane 1 bits 7-0
;     plane 2 bits 15-8                 plane 2 bits 7-0
;     plane 3 bits 15-8                 plane 3 bits 7-0
;
;   MOVEP.L 0(An),Dn reads all 4 high bytes (or low bytes if An is odd)
;   into a single register: plane0→bits31-24, plane1→23-16, etc.
;
;   A single pixel occupies one bit in either the high or low byte of each
;   plane word. So ONE movep.l read + AND + OR + movep.l write modifies
;   all 4 planes at once — no need for separate plane-pair operations.
;
;   The byte_offset in the table includes a +0 (high byte) or +1 (low byte)
;   adjustment, so the hot path always uses MOVEP.L 0(a0) regardless.
;
; ============================================================================
;
; COMPARISON WITH OTHER APPROACHES:
;
;   Variant                Cycles   Table RAM   Pixel mod
;   SetPixel               236      ~46 KB      88 cy (AND/OR to memory)
;   SetPixel_Movem         228      ~46 KB      84 cy (MOVEM + reg ops)
;   SetPixel_Ultra         218      ~82 KB      84 cy (MOVEM + reg ops)
;   SetPixel_Movep →       194      ~26 KB      64 cy (MOVEP + reg ops) ★
;
;   ★ Fastest AND smallest tables!
;
; ============================================================================
;
; USAGE:
;
;   ; At startup:
;       jsr     InitTables_Movep
;       lea     x_table_m,a4
;       lea     y_table_m,a5
;
;   ; Plot a pixel:
;       move.w  #160,d0             ; X = 160
;       move.w  #100,d1             ; Y = 100
;       move.w  #7,d2               ; color = 7
;       jsr     SetPixel_Movep
;
; ============================================================================

    include "tables_movep.inc"

; ---- Hot path — CYCLE EXACT on MC68000 ----

SetPixel_Movep:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent:
;   a4 = x_table_m (320 entries × 16 bytes = 5120 bytes)
;   a5 = y_table_m (200 longs = 800 bytes)
;
; Trashed: d0-d4, a0-a2
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]   Y*2
    add.w   d1,d1                   ; [4]   Y*4
    movea.l 0(a5,d1.w),a0           ; [18]  a0 = screen_base + Y*160

    ; ---- X → x_table_m entry ---- [26 cycles]
    lsl.w   #4,d0                   ; [14]  X*16 (entry size = 16 bytes)
    lea     0(a4,d0.w),a1           ; [12]  a1 = &x_table_m[X]
                                    ;       NOTE: X=319, 319*16=5104 ✓ (< 32767)

    ; ---- Load x_table_m fields ---- [32 cycles]
    move.l  (a1)+,d3                ; [12]  d3 = AND mask (movep format)
    movea.l (a1)+,a2                ; [12]  a2 = &or_table_m[X][0]
    adda.w  (a1),a0                 ; [8]   a0 += byte_offset → target byte addr
                                    ;       (includes +0/+1 for high/low byte)

    ; ---- Color → OR entry ---- [18 cycles]
    lsl.w   #2,d2                   ; [10]  color*4 (entry size = 4 bytes)
    adda.w  d2,a2                   ; [8]   a2 = &or_table_m[X][color]

    ; ---- Load OR mask ---- [12 cycles]
    move.l  (a2),d0                 ; [12]  d0 = OR mask (movep format)

    ; ---- MOVEP read-modify-write ---- [64 cycles]
    movep.l 0(a0),d4                ; [24]  read 1 byte from each of 4 planes
    and.l   d3,d4                   ; [8]   clear old pixel bit in all 4 planes
    or.l    d0,d4                   ; [8]   set new color bits in all 4 planes
    movep.l d4,0(a0)                ; [24]  write back 1 byte to each of 4 planes

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   Y lookup:        4 + 4 + 18           = 26
;   X table addr:    14 + 12              = 26
;   Load fields:     12 + 12 + 8          = 32
;   Color lookup:    10 + 8               = 18
;   Load OR mask:    12                   = 12
;   MOVEP read:      24                   = 24
;   Register ops:    8 + 8                = 16
;   MOVEP write:     24                   = 24
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 194 cycles
;
; AT 8 MHz: 24.25 µs per pixel
; PIXELS PER 50Hz FRAME: ~824 (with just pixel plotting, no other code)
;
; WITHOUT RTS (inlined in a loop): 178 cycles per pixel
; SAME-Y VARIANT (skip Y lookup): 168 cycles per pixel (inlined)
;
; COMPARISON:
;   SetPixel:          236 cycles — this is 42 cycles faster (17.8%)
;   SetPixel_Movem:    228 cycles — this is 34 cycles faster (14.9%)
;   SetPixel_Ultra:    218 cycles — this is 24 cycles faster (11.0%)
;----------------------------------------------------------------------


; ============================================================================
; SetPixel_Movep_WriteOnly — WRITE-ONLY MOVEP PIXEL PLOT (182 cycles)
; ============================================================================
;
; Write-only variant: skips the AND (clear) step. Uses MOVEP to read-or-write
; in a single pass. Still requires a read because other pixels in the same
; byte must be preserved.
;
; ⚠ PRECONDITION: The target pixel MUST already be color 0.
;   Use this ONLY when drawing onto a freshly cleared screen or
;   when you know the pixel area is already zeroed.
;
; Convention:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent registers:
;   a4 = x_table_m base
;   a5 = y_table_m base
;
; Trashed: d0-d2, a0-a2
;
; Performance: 182 cycles at 8 MHz = 22.75 µs per pixel
;              ~879 pixels per 50 Hz frame
;              Without RTS (inlined): 166 cycles
;              Same-Y variant (skip Y lookup): 156 cycles (inlined)
;
; Table RAM:   ~26 KB (same tables as SetPixel_Movep)
;
; ============================================================================

SetPixel_Movep_WriteOnly:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Precondition: pixel was ALREADY color 0 (screen cleared or known state)
;
; Persistent:
;   a4 = x_table_m base
;   a5 = y_table_m base
;
; Trashed: d0-d2, a0-a2
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]   Y*2
    add.w   d1,d1                   ; [4]   Y*4
    movea.l 0(a5,d1.w),a0           ; [18]  a0 = screen_base + Y*160

    ; ---- X → x_table_m entry ---- [26 cycles]
    lsl.w   #4,d0                   ; [14]  X*16
    lea     0(a4,d0.w),a1           ; [12]  a1 = &x_table_m[X]

    ; ---- Skip AND mask, load OR pointer ---- [20 cycles]
    addq.l  #4,a1                   ; [8]   skip AND mask (unused for write-only)
    movea.l (a1)+,a2                ; [12]  a2 = &or_table_m[X][0]

    ; ---- Add byte offset ---- [8 cycles]
    adda.w  (a1),a0                 ; [8]   a0 += byte_offset

    ; ---- Color → OR entry ---- [18 cycles]
    lsl.w   #2,d2                   ; [10]  color*4
    adda.w  d2,a2                   ; [8]   a2 = &or_table_m[X][color]

    ; ---- Load OR mask ---- [12 cycles]
    move.l  (a2),d0                 ; [12]  d0 = OR mask (movep format)

    ; ---- MOVEP read-or-write (no AND needed!) ---- [56 cycles]
    movep.l 0(a0),d1                ; [24]  read current bytes from all 4 planes
    or.l    d0,d1                   ; [8]   set new color bits
    movep.l d1,0(a0)                ; [24]  write back

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   Y lookup:        4 + 4 + 18           = 26
;   X table addr:    14 + 12              = 26
;   Skip + OR ptr:   8 + 12               = 20
;   Byte offset:     8                    = 8
;   Color lookup:    10 + 8               = 18
;   Load OR mask:    12                   = 12
;   MOVEP read:      24                   = 24
;   OR:              8                    = 8
;   MOVEP write:     24                   = 24
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 182 cycles
;
; AT 8 MHz: 22.75 µs per pixel
; PIXELS PER 50Hz FRAME: ~879 (with just pixel plotting, no other code)
;
; WITHOUT RTS (inlined in a loop): 166 cycles per pixel
; SAME-Y VARIANT (skip Y lookup): 156 cycles per pixel (inlined)
;
; COMPARISON:
;   SetPixel_WriteOnly:       188 cycles — this is  6 cycles faster (3.2%)
;   SetPixel_Ultra_WriteOnly: 174 cycles — this is  8 cycles slower (4.6%)
;                             but uses ~26 KB vs ~82 KB tables (68% less RAM)
;----------------------------------------------------------------------


; ============================================================================
; WHY MOVEP WORKS HERE
; ============================================================================
;
; THE MOVEP INSTRUCTION:
;
;   MOVEP.L d(An),Dn reads 4 bytes at offsets d, d+2, d+4, d+6:
;     bits 31-24 ← byte at An+d
;     bits 23-16 ← byte at An+d+2
;     bits 15-8  ← byte at An+d+4
;     bits  7-0  ← byte at An+d+6
;
;   MOVEP.L Dn,d(An) writes 4 bytes at offsets d, d+2, d+4, d+6:
;     An+d   ← bits 31-24
;     An+d+2 ← bits 23-16
;     An+d+4 ← bits 15-8
;     An+d+6 ← bits  7-0
;
; ATARI ST SCREEN MEMORY:
;
;   [plane0.w][plane1.w][plane2.w][plane3.w] = 8 bytes per 16-pixel group
;
;   Byte 0: plane 0 high byte (bits 15-8)
;   Byte 1: plane 0 low byte  (bits 7-0)
;   Byte 2: plane 1 high byte
;   Byte 3: plane 1 low byte
;   Byte 4: plane 2 high byte
;   Byte 5: plane 2 low byte
;   Byte 6: plane 3 high byte
;   Byte 7: plane 3 low byte
;
;   MOVEP.L 0(a0) → reads bytes 0, 2, 4, 6 (high bytes of all 4 planes)
;   MOVEP.L 1(a0) → reads bytes 1, 3, 5, 7 (low bytes of all 4 planes)
;
; THE MATCH:
;
;   Each pixel occupies ONE BIT in either the high or low byte of each plane.
;   MOVEP reads/writes exactly the right byte from each plane in one shot.
;
;   By encoding the high/low selection into the byte_offset (adding +0 or +1),
;   the hot path always uses displacement 0: MOVEP.L 0(a0),Dn.
;
;   The AND mask clears one bit in all 4 bytes; the OR mask sets the correct
;   color bits. Since all masks are byte-sized and packed into single longs,
;   both the register operations and the table entries are half the size of
;   the word-based approach.
;
; ============================================================================
;
; TABLE BUDGET COMPARISON:
;
;   Tables                  Size       Fastest variant    Cycles
;   tables.inc (standard)   ~46 KB     SetPixel_Movem      228
;   tables_ultra.inc        ~82 KB     SetPixel_Ultra       218
;   tables_movep.inc ★      ~26 KB     SetPixel_Movep       194
;
;   ★ MOVEP: smallest tables AND fastest execution!
;
; ============================================================================
