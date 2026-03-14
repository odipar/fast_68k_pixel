; ============================================================================
; ULTRA LOOKUP TABLES — ATARI ST 4-PLANE PIXEL PLOTTING
; ============================================================================
;
; Mega-table variant: merges x_table and or_table into a single unified
; xc_data table indexed by (X, color). Eliminates one pointer indirection
; from the hot path, saving 10 cycles on general-purpose and 14 on
; write-only versus the standard tables.inc layout.
;
; Call InitTables_Ultra once at startup before plotting any pixels.
;
; Screen format: 320×200, 4 bitplanes interleaved
;   16 pixels = 8 bytes: [plane0.w][plane1.w][plane2.w][plane3.w]
;   Scanline = 160 bytes
;
; TABLE LAYOUT (total: ~82 KB):
;
; y_table_u:  200 longs                                       =    800 bytes
;             y_table_u[Y] = screen_base + Y * 160
;
; xc_ptr:     320 longs                                       =  1,280 bytes
;             xc_ptr[X] = absolute pointer to xc_data[X][0]
;
; xc_data:    320 × 16 entries × 16 bytes each                = 81,920 bytes
;             xc_data[X][color]:
;             +0:  long   AND mask (NOT-bitmask replicated: hi.w = lo.w)
;             +4:  long   OR mask for planes 0+1
;             +8:  long   OR mask for planes 2+3
;             +12: word   byte offset of pixel group in scanline
;             +14: word   (padding)
;
; GRAND TOTAL: 800 + 1,280 + 81,920 = 84,000 bytes (~82 KB)
;
; ============================================================================


; ============================================================================
; TABLE GENERATION (run once at startup)
; ============================================================================

InitTables_Ultra:
    movem.l d0-d7/a0-a6,-(sp)

    ; ---- Y table: y_table_u[Y] = screen_base + Y*160 ----
    lea     y_table_u,a0
    movea.l screen_base_ptr_u,a1
    move.w  #199,d7
.yt_loop:
    move.l  a1,(a0)+
    lea     160(a1),a1
    dbf     d7,.yt_loop

    ; ---- xc_ptr + xc_data ----
    lea     xc_ptr,a0               ; a0 = xc_ptr write pointer
    lea     xc_data,a2              ; a2 = xc_data write pointer

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
    swap    d3
    move.w  d4,d3                   ; d3.l = NOT(bitmask):NOT(bitmask)

    ; -- Write xc_ptr entry: pointer to this X's block --
    move.l  a2,(a0)+                ; xc_ptr[X] = &xc_data[X][0]

    ; -- Generate 16 xc_data entries for this X (one per color) --
    moveq   #0,d6                   ; d6 = color (0-15)
.color_loop:
    ; +0: AND mask (long)
    move.l  d3,(a2)+

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

    ; +4: OR mask planes 0+1
    move.l  d1,(a2)+

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

    ; +8: OR mask planes 2+3
    move.l  d2,(a2)+

    ; +12: byte offset + padding
    move.w  d5,(a2)+                ; byte offset within scanline
    clr.w   (a2)+                   ; padding

    addq.w  #1,d6
    cmp.w   #16,d6
    bne.s   .color_loop

    addq.w  #1,d7
    cmp.w   #320,d7
    bne     .xt_loop

    movem.l (sp)+,d0-d7/a0-a6
    rts


; ============================================================================
; DATA SECTION — Table Storage
; ============================================================================

    section data

screen_base_ptr_u:
    dc.l    $78000                  ; example: screen at $78000

    ; Align tables to even addresses (68000 requirement)
    even

y_table_u:
    ds.l    200                     ; 800 bytes

xc_ptr:
    ds.l    320                     ; 1,280 bytes

xc_data:
    ds.b    81920                   ; 320 * 16 * 16 = 81,920 bytes

; Total data: 800 + 1,280 + 81,920 = 84,000 bytes (~82 KB)
