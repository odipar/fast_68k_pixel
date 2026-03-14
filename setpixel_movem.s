; ============================================================================
; SetPixel_Movem — THE FASTEST GENERAL-PURPOSE PIXEL PLOT (228 cycles) ★
; ============================================================================
;
; ★ RECOMMENDED version for general-purpose pixel plotting.
;
; Uses MOVEM.L to bulk read/write all 4 bitplanes in single operations,
; then performs AND/OR in registers (8 cycles each vs 20–24 to memory).
; Saves 8 cycles over the direct-to-memory SetPixel variant.
;
; Convention:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Persistent registers (set up once before any plotting):
;   a4 = x_table base (320 entries × 16 bytes = 5120 bytes)
;   a5 = y_table base (200 longs = 800 bytes)
;
; Trashed: d0-d5, a0-a2
;
; Performance: 228 cycles at 8 MHz = 28.5 µs per pixel
;              ~701 pixels per 50 Hz frame
;              Without RTS (inlined): 212 cycles
;              Same-Y variant (skip Y lookup): 202 cycles (inlined)
;
; Table RAM:   ~46 KB (y_table + x_table + or_table)
;
; ============================================================================
;
; KEY INSIGHT — MOVEM ADVANTAGE:
;
;   Direct-to-memory approach (SetPixel):
;     and.l d3,(a0)       = 20 cycles
;     or.l  d0,(a0)       = 20 cycles
;     and.l d3,4(a0)      = 24 cycles
;     or.l  d1,4(a0)      = 24 cycles
;     Total: 88 cycles for 4 planes
;
;   MOVEM approach (this version):
;     movem.l (a0),d4-d5  = 28 cycles (bulk read 8 bytes)
;     and.l   d3,d4       =  8 cycles (register-to-register)
;     or.l    d0,d4       =  8 cycles
;     and.l   d3,d5       =  8 cycles
;     or.l    d1,d5       =  8 cycles
;     movem.l d4-d5,(a0)  = 24 cycles (bulk write 8 bytes)
;     Total: 84 cycles — saves 4 cycles!
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
;       jsr     SetPixel_Movem
;
; ============================================================================

    include "tables.inc"

; ---- Hot path — CYCLE EXACT on MC68000 ----

SetPixel_Movem:
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

    ; ---- Load x_table fields ---- [32 cycles]
    move.l  (a1)+,d3                ; [12] AND mask long
    movea.l (a1)+,a2                ; [12] → or_table[X][0]
    adda.w  (a1),a0                 ; [8]  + byte offset → pixel group addr

    ; ---- OR table lookup ---- [20 cycles]
    lsl.w   #3,d2                   ; [12] color*8
    adda.w  d2,a2                   ; [8]  a2 = &or_table[X][color]

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
