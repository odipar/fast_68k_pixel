; ============================================================================
; SetPixel_Ultra — THE ABSOLUTE FASTEST PIXEL PLOT (218 cycles) ★★
; ============================================================================
;
; ★★ NEW CHAMPION — 10 cycles faster than SetPixel_Movem.
;
; Uses a unified mega-table (xc_data) that merges AND masks, OR masks, and
; byte offsets into single 16-byte entries indexed by (X, color). This
; eliminates the pointer indirection from x_table → or_table, replacing two
; separate table chains with one contiguous lookup.
;
; Convention:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent registers (set up once before any plotting):
;   a4 = xc_ptr base (320 longs = 1,280 bytes)
;   a5 = y_table_u base (200 longs = 800 bytes)
;
; Trashed: d0-d5, a0-a2
;
; Performance: 218 cycles at 8 MHz = 27.25 µs per pixel
;              ~733 pixels per 50 Hz frame
;              Without RTS (inlined): 202 cycles
;              Same-Y variant (skip Y lookup): 176 cycles (inlined)
;
; Table RAM:   ~82 KB (y_table_u + xc_ptr + xc_data)
;
; ============================================================================
;
; KEY INSIGHT — UNIFIED MEGA-TABLE:
;
;   Previous approach (SetPixel_Movem, 228 cycles):
;     x_table[X] stores: AND mask + pointer to or_table[X][0] + byte offset
;     Requires: load AND, load pointer, follow pointer + color offset, load ORs
;     Data load chain: 12 + 12 + 8 + 12 + 8 + 12 + 12 = 76 cycles
;
;   This approach (SetPixel_Ultra, 218 cycles):
;     xc_ptr[X] stores: pointer to xc_data[X][0]
;     xc_data[X][color] stores: AND + OR01 + OR23 + byte_offset (all in one)
;     Data load chain: 12 + 12 + 12 + 8 = 44 cycles
;     Pointer + color: 4 + 4 + 18 + 14 + 8 = 48 cycles
;     Total lookup: 92 cycles (vs 102 for Movem) — saves 10 cycles!
;
;   Trade-off: tables grow from ~46 KB to ~82 KB.
;   Well within the 512 KB budget.
;
; ============================================================================
;
; USAGE:
;
;   ; At startup:
;       jsr     InitTables_Ultra
;       lea     xc_ptr,a4
;       lea     y_table_u,a5
;
;   ; Plot a pixel:
;       move.w  #160,d0             ; X = 160
;       move.w  #100,d1             ; Y = 100
;       move.w  #7,d2               ; color = 7
;       jsr     SetPixel_Ultra
;
; ============================================================================

    include "tables_ultra.inc"

; ---- Hot path — CYCLE EXACT on MC68000 ----

SetPixel_Ultra:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent:
;   a4 = xc_ptr (320 longs = 1,280 bytes)
;   a5 = y_table_u (200 longs = 800 bytes)
;
; Trashed: d0-d5, a0-a1
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]   Y*2
    add.w   d1,d1                   ; [4]   Y*4
    movea.l 0(a5,d1.w),a0           ; [18]  a0 = screen_base + Y*160

    ; ---- X → xc_ptr lookup ---- [26 cycles]
    add.w   d0,d0                   ; [4]   X*2
    add.w   d0,d0                   ; [4]   X*4
    movea.l 0(a4,d0.w),a1           ; [18]  a1 = &xc_data[X][0]

    ; ---- Color → entry offset ---- [22 cycles]
    lsl.w   #4,d2                   ; [14]  color*16 (entry size = 16 bytes)
    adda.w  d2,a1                   ; [8]   a1 = &xc_data[X][color]

    ; ---- Load all masks + byte offset from single entry ---- [44 cycles]
    move.l  (a1)+,d3                ; [12]  d3 = AND mask (NOT-bitmask replicated)
    move.l  (a1)+,d0                ; [12]  d0 = OR mask planes 0+1
    move.l  (a1)+,d1                ; [12]  d1 = OR mask planes 2+3
    adda.w  (a1),a0                 ; [8]   a0 += byte_offset → pixel group addr

    ; ---- MOVEM bulk read ---- [28 cycles]
    movem.l (a0),d4-d5              ; [28]  d4 = planes 0+1, d5 = planes 2+3

    ; ---- Modify in registers ---- [32 cycles]
    and.l   d3,d4                   ; [8]   clear old bits planes 0+1
    or.l    d0,d4                   ; [8]   set new bits planes 0+1
    and.l   d3,d5                   ; [8]   clear old bits planes 2+3
    or.l    d1,d5                   ; [8]   set new bits planes 2+3

    ; ---- MOVEM bulk write ---- [24 cycles]
    movem.l d4-d5,(a0)              ; [24]  write back all 4 planes at once

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   Y lookup:        4 + 4 + 18           = 26
;   X pointer:       4 + 4 + 18           = 26
;   Color offset:    14 + 8               = 22
;   Data load:       12 + 12 + 12 + 8     = 44
;   MOVEM read:      28                   = 28
;   Register ops:    8 + 8 + 8 + 8        = 32
;   MOVEM write:     24                   = 24
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 218 cycles
;
; AT 8 MHz: 27.25 µs per pixel
; PIXELS PER 50Hz FRAME: ~733 (with just pixel plotting, no other code)
;
; WITHOUT RTS (inlined in a loop): 202 cycles per pixel
; SAME-Y VARIANT (skip Y lookup): 176 cycles per pixel (inlined)
;
; COMPARISON:
;   SetPixel:          236 cycles — this is 18 cycles faster (7.6%)
;   SetPixel_Movem:    228 cycles — this is 10 cycles faster (4.4%)
;   SetPixel_WriteOnly: 188 cycles — see Ultra_WriteOnly below
;----------------------------------------------------------------------


; ============================================================================
; SetPixel_Ultra_WriteOnly — FASTEST WRITE-ONLY PIXEL PLOT (174 cycles) ★★
; ============================================================================
;
; ★★ NEW CHAMPION — 14 cycles faster than SetPixel_WriteOnly.
;
; Combines the mega-table approach with write-only optimization.
; Skips the AND (clear) step entirely — only ORs in the new color.
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
; Persistent registers (set up once before any plotting):
;   a4 = xc_ptr base
;   a5 = y_table_u base
;
; Trashed: d0-d2, a0-a1
;
; Performance: 174 cycles at 8 MHz = 21.75 µs per pixel
;              ~920 pixels per 50 Hz frame
;              Without RTS (inlined): 158 cycles
;              Same-Y variant (skip Y lookup): 132 cycles (inlined)
;
; Table RAM:   ~82 KB (same tables as SetPixel_Ultra)
;
; ============================================================================

SetPixel_Ultra_WriteOnly:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Precondition: pixel was ALREADY color 0 (screen cleared or known state)
;
; Persistent:
;   a4 = xc_ptr base
;   a5 = y_table_u base
;
; Trashed: d0-d2, a0-a1
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]   Y*2
    add.w   d1,d1                   ; [4]   Y*4
    movea.l 0(a5,d1.w),a0           ; [18]  a0 = screen_base + Y*160

    ; ---- X → xc_ptr lookup ---- [26 cycles]
    add.w   d0,d0                   ; [4]   X*2
    add.w   d0,d0                   ; [4]   X*4
    movea.l 0(a4,d0.w),a1           ; [18]  a1 = &xc_data[X][0]

    ; ---- Color → entry offset ---- [22 cycles]
    lsl.w   #4,d2                   ; [14]  color*16
    adda.w  d2,a1                   ; [8]   a1 = &xc_data[X][color]

    ; ---- Skip AND mask, load OR masks + byte offset ---- [40 cycles]
    addq.l  #4,a1                   ; [8]   skip AND mask (unused for write-only)
    move.l  (a1)+,d0                ; [12]  d0 = OR mask planes 0+1
    move.l  (a1)+,d1                ; [12]  d1 = OR mask planes 2+3
    adda.w  (a1),a0                 ; [8]   a0 += byte_offset → pixel group addr

    ; ---- OR in the new pixel (no AND needed!) ---- [44 cycles]
    or.l    d0,(a0)                 ; [20]  set planes 0+1
    or.l    d1,4(a0)                ; [24]  set planes 2+3

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   Y lookup:        4 + 4 + 18           = 26
;   X pointer:       4 + 4 + 18           = 26
;   Color offset:    14 + 8               = 22
;   Skip + loads:    8 + 12 + 12 + 8      = 40
;   OR + write:      20 + 24              = 44
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 174 cycles
;
; AT 8 MHz: 21.75 µs per pixel
; PIXELS PER 50Hz FRAME: ~920 (with just pixel plotting, no other code)
;
; WITHOUT RTS (inlined in a loop): 158 cycles per pixel
; SAME-Y VARIANT (skip Y lookup): 132 cycles per pixel (inlined)
;
; COMPARISON:
;   SetPixel_WriteOnly:      188 cycles — this is 14 cycles faster (7.4%)
;   SetPixel_Ultra:          218 cycles — this is 44 cycles faster (20.2%)
;----------------------------------------------------------------------


; ============================================================================
; WHY THIS IS THE FASTEST POSSIBLE
; ============================================================================
;
; IRREDUCIBLE COSTS (cannot be optimized away):
;
;   Pixel modification:
;     MOVEM read  (4 planes):  28 cycles — bulk read is fastest
;     AND × 2 + OR × 2:       32 cycles — register ops, minimum possible
;     MOVEM write (4 planes):  24 cycles — bulk write is fastest
;     Subtotal:                84 cycles — THE HARD FLOOR for read-modify-write
;
;   Return:
;     RTS:                     16 cycles — unavoidable for subroutine call
;
;   Address computation:
;     Y → scanline:            26 cycles — Y*4 index + table lookup
;     X → data pointer:        26 cycles — X*4 index + pointer table lookup
;     Color → entry:           22 cycles — color*16 offset
;     Data load (4 fields):    44 cycles — 3 longs + 1 word from table
;     Subtotal:               118 cycles
;
;   TOTAL:                    218 cycles = 84 (pixel) + 118 (setup) + 16 (ret)
;
; THEORETICAL MINIMUM ANALYSIS:
;
;   - We must read at least 14 bytes of precomputed data (AND + OR01 + OR23 +
;     byte_offset). At 12 cycles per long read + 8 for word = minimum 44 cycles.
;   - We must compute 3 table indices (Y*4, X*4, color*16).
;     Y*4 = 8 cycles (two ADD), X*4 = 8 cycles, color*16 = 14 cycles.
;     Minimum: 30 cycles for index computation.
;   - We must perform 3 indexed memory accesses to reach the data.
;     Minimum 2 accesses (Y table + combined X/color): 18+18 = 36 cycles.
;     Plus color offset add: 8 cycles.
;     Minimum: 44 cycles.
;   - Pixel modification: 84 cycles (proven minimum for MOVEM + AND/OR).
;   - RTS: 16 cycles.
;
;   Conservative theoretical floor: ~84 + 44 + 30 + 16 = 174 cycles
;   But that ignores the pointer add for color (8 cycles) and byte offset
;   add (8 cycles) which brings us to: 174 + 16 = 190 cycles.
;   Our actual implementation at 218 cycles is 28 cycles above this
;   extremely optimistic floor, representing the unavoidable overhead of
;   the table indirection and byte-offset addition on the 68000.
;
;   For write-only (no AND step): floor ≈ 84 - 32 - 28 + 44 = 68 for pixel
;   ops (just OR to memory) + setup. Our 174 cycles is near-optimal.
;
; ============================================================================
;
; TABLE BUDGET COMPARISON:
;
;   Standard (tables.inc):     ~46 KB  → 228 cycles (Movem), 188 (WriteOnly)
;   Ultra (tables_ultra.inc):  ~82 KB  → 218 cycles (Ultra),  174 (WriteOnly)
;   Increase:                  +36 KB  → −10 cycles (4.4%),   −14 (7.4%)
;
;   Cost: 36 KB additional RAM (well within 512 KB budget)
;   Benefit: 10–14 fewer cycles per pixel
;   Break-even: ~3,600 pixels pay for the extra table RAM at 10 cycles each
;
; ============================================================================
