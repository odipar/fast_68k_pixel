; ============================================================================
; SetPixel_WriteOnly — FASTEST VARIANT FOR CLEARED SCREENS (188 cycles)
; ============================================================================
;
; Optimized variant that skips the AND (clear) step entirely.
; Only ORs in the new pixel color — saves 44 cycles over SetPixel.
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
;   a4 = x_table base
;   a5 = y_table base
;
; Trashed: d0, d2, a0-a2
;
; Performance: 188 cycles at 8 MHz = 23.5 µs per pixel
;              ~851 pixels per 50 Hz frame
;              Same-Y inlined: ~158 cycles
;
; Table RAM:   ~46 KB (y_table + x_table + or_table)
;              (same tables as SetPixel/SetPixel_Movem)
;
; ============================================================================
;
; KEY INSIGHT:
;
;   If the screen is cleared (all pixels = color 0, all bits = 0), then the
;   AND step that clears old pixel bits is unnecessary — there are no old
;   bits to clear. We skip it entirely, saving 44 cycles (two and.l ops).
;
;   SetPixel:          236 cycles (AND + OR)
;   SetPixel_WriteOnly: 188 cycles (OR only) — 20% faster!
;
;   Ideal for: first-pass rendering, clean-screen drawing, particle effects,
;   wireframe rendering on cleared backgrounds.
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
;   ; Clear screen first! (required)
;       ; ... your screen clear routine ...
;
;   ; Plot a pixel (on clean screen):
;       move.w  #160,d0             ; X = 160
;       move.w  #100,d1             ; Y = 100
;       move.w  #7,d2               ; color = 7
;       jsr     SetPixel_WriteOnly
;
; ============================================================================

    include "tables.inc"

; ---- Hot path — CYCLE EXACT on MC68000 ----

SetPixel_WriteOnly:
;----------------------------------------------------------------------
; Input:
;   d0.w = X (0–319)
;   d1.w = Y (0–199)
;   d2.w = color (0–15)
;
; Precondition: pixel was ALREADY color 0 (screen cleared or known state)
;
; Persistent:
;   a4 = x_table base
;   a5 = y_table base
;
; Trashed: d0, d2, a0-a2
;----------------------------------------------------------------------

    ; ---- Y → scanline ---- [26 cycles]
    add.w   d1,d1                   ; [4]
    add.w   d1,d1                   ; [4]
    movea.l 0(a5,d1.w),a0           ; [18] scanline addr

    ; ---- X → x_table entry ---- [26 cycles]
    lsl.w   #4,d0                   ; [14] X*16
    lea     0(a4,d0.w),a1           ; [12] &x_table[X]

    ; ---- Skip AND mask, load OR pointer ---- [20 cycles]
    addq.l  #4,a1                   ; [8]  skip AND mask (unused)
    movea.l (a1)+,a2                ; [12] or sub-table pointer

    ; ---- Add byte offset ---- [8 cycles]
    adda.w  (a1),a0                 ; [8]  add byte offset

    ; ---- Color → OR entry ---- [24 cycles]
    lsl.w   #3,d2                   ; [12] color*8
    lea     0(a2,d2.w),a1           ; [12] &or_table[X][color]

    ; ---- OR in the new pixel (no AND needed!) ---- [68 cycles]
    move.l  (a1)+,d0                ; [12]
    or.l    d0,(a0)                 ; [20] set planes 0+1
    move.l  (a1),d0                 ; [12]
    or.l    d0,4(a0)               ; [24] set planes 2+3

    rts                             ; [16]

;----------------------------------------------------------------------
; TOTAL CYCLE COUNT:
;   Y lookup:        4 + 4 + 18           = 26
;   X table addr:    14 + 12              = 26
;   Skip + OR ptr:   8 + 12               = 20
;   Byte offset:     8                    = 8
;   Color lookup:    12 + 12              = 24
;   OR + write:      12 + 20 + 12 + 24    = 68
;   RTS:             16                   = 16
;   -----------------------------------------
;   TOTAL:                                = 188 cycles
;
; SAVINGS vs SetPixel:       236 - 188 = 48 cycles (20% faster)
; SAVINGS vs SetPixel_Movem: 228 - 188 = 40 cycles (18% faster)
;----------------------------------------------------------------------
