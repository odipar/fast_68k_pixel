; ============================================================================
; SHARED LOOKUP TABLES — ATARI ST 4-PLANE PIXEL PLOTTING
; ============================================================================
;
; Include this file in any of the SetPixel variants.
; Call InitTables once at startup before plotting any pixels.
;
; Screen format: 320×200, 4 bitplanes interleaved
;   16 pixels = 8 bytes: [plane0.w][plane1.w][plane2.w][plane3.w]
;   Scanline = 160 bytes
;
; TABLE LAYOUT (total: ~46 KB):
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


; ============================================================================
; TABLE GENERATION (run once at startup)
; ============================================================================

InitTables:
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
