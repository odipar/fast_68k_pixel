; ============================================================================
; SetPixel — THE DEFINITIVE VERSION (236 cycles)
; ============================================================================
;
; General-purpose pixel plotter for Atari ST (320×200, 4 bitplanes).
; Uses longword operations on plane pairs with lookup tables.
;
; Convention:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent registers (set up once before any plotting):
;   a4 = x_table base
;   a5 = y_table base
;
; Trashed: d0, d1, d2, d3, a0, a1, a2
;
; Performance: 236 cycles at 8 MHz = 29.5 µs per pixel
;              ~677 pixels per 50 Hz frame
;
; Table RAM:   ~46 KB (y_table + x_table + or_table)
;
; ============================================================================
;
; USAGE:
;
;   ; At startup:
;       jsr     InitTables
;       lea     x_table,a4
;       lea     y_table,a5
;
;   ; Plot a pixel:
;       move.w  #160,d0             ; X = 160
;       move.w  #100,d1             ; Y = 100
;       move.w  #7,d2               ; color = 7
;       jsr     SetPixel
;
; ============================================================================

    include "tables.inc"

; ---- Hot path — CYCLE EXACT on MC68000 ----

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
                                    ; NOTE: X=319, 319*16=5104, OK (< 32767 ✓)

    ; ---- Step 3: Load AND mask ----
    move.l  (a1)+,d3                ; [12]  d3 = AND mask; a1 now at +4
                                    ;       12 cycles

    ; ---- Step 4: Load OR sub-table pointer ----
    movea.l (a1)+,a2                ; [12]  a2 = &or_table[X][0]; a1 now at +8
                                    ;       12 cycles

    ; ---- Step 5: Add byte offset to screen pointer ----
    adda.w  (a1),a0                 ; [8]   a0 += byte_offset
                                    ;       a0 now points to the exact pixel group
                                    ;       8 cycles

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
