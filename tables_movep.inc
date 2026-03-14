; ============================================================================
; MOVEP LOOKUP TABLES — ATARI ST 4-PLANE PIXEL PLOTTING
; ============================================================================
;
; MOVEP-optimized table variant: uses byte-sized masks instead of word-sized,
; exploiting the MC68000 MOVEP.L instruction which reads/writes one byte from
; each of the 4 bitplanes in a single operation.
;
; Call InitTables_Movep once at startup before plotting any pixels.
;
; Screen format: 320×200, 4 bitplanes interleaved
;   16 pixels = 8 bytes: [plane0.w][plane1.w][plane2.w][plane3.w]
;   Scanline = 160 bytes
;
; KEY INSIGHT — MOVEP AND BYTE-SIZED MASKS:
;
;   A single pixel occupies one bit in each of 4 planes. That bit resides
;   in either the high byte or the low byte of each plane word:
;
;     Byte 0 (plane 0 hi)  Byte 1 (plane 0 lo)
;     Byte 2 (plane 1 hi)  Byte 3 (plane 1 lo)
;     Byte 4 (plane 2 hi)  Byte 5 (plane 2 lo)
;     Byte 6 (plane 3 hi)  Byte 7 (plane 3 lo)
;
;   MOVEP.L 0(An),Dn reads bytes at offsets 0, 2, 4, 6 (high bytes).
;   MOVEP.L 1(An),Dn reads bytes at offsets 1, 3, 5, 7 (low bytes).
;   By adjusting the byte_offset to include 0 or 1, we always use
;   displacement 0 in MOVEP and access exactly the right byte per plane.
;
;   Since masks are now byte-wide (one byte per plane packed into a long),
;   AND/OR masks are HALF the size of word-based variants: 4 bytes vs 8.
;
; TABLE LAYOUT (total: ~25.8 KB — smallest of any variant):
;
; y_table_m:    200 longs                                      =   800 bytes
;               y_table_m[Y] = screen_base + Y * 160
;
; x_table_m:    320 entries × 16 bytes each                    =  5120 bytes
;               +0:  long   AND mask (NOT-bitmask, same byte × 4)
;               +4:  long   absolute pointer to or_table_m[X][0]
;               +8:  word   byte offset (includes high/low adjustment)
;               +10: word   (padding)
;               +12: long   (padding)
;
; or_table_m:   320 × 16 entries × 4 bytes each                = 20480 bytes
;               or_table_m[X][color]:
;               +0: long    OR mask for MOVEP (plane0:plane1:plane2:plane3)
;
;   movep.l byte order within long: bits 31..24 → offset+0 (plane 0)
;                                   bits 23..16 → offset+2 (plane 1)
;                                   bits 15..8  → offset+4 (plane 2)
;                                   bits  7..0  → offset+6 (plane 3)
;
; GRAND TOTAL: 800 + 5120 + 20480 = 26,400 bytes (~25.8 KB)
;
; COMPARISON:
;   Standard tables (tables.inc):       ~46 KB
;   Ultra tables (tables_ultra.inc):    ~82 KB
;   MOVEP tables (this file):           ~26 KB  ← smallest!
;
; ============================================================================


; ============================================================================
; TABLE GENERATION (run once at startup)
; ============================================================================

InitTables_Movep:
    movem.l d0-d7/a0-a6,-(sp)

    ; ---- Y table: y_table_m[Y] = screen_base + Y*160 ----
    lea     y_table_m,a0
    movea.l screen_base_ptr_m,a1
    move.w  #199,d7
.yt_loop:
    move.l  a1,(a0)+
    lea     160(a1),a1
    dbf     d7,.yt_loop

    ; ---- X table + OR table (movep format) ----
    lea     x_table_m,a0            ; a0 = x_table_m write pointer
    lea     or_table_m,a2           ; a2 = or_table_m write pointer

    moveq   #0,d7                   ; d7 = X (0-319)
.xt_loop:
    ; -- Byte offset within scanline (with high/low adjustment) --
    ;    base_offset = (X / 16) * 8
    ;    For high byte (bit_pos >= 8, i.e. X&15 <= 7): +0
    ;    For low byte  (bit_pos <  8, i.e. X&15 >= 8): +1
    move.w  d7,d0
    lsr.w   #4,d0                   ; X / 16
    lsl.w   #3,d0                   ; * 8 = base byte offset
    move.w  d7,d1
    andi.w  #$000F,d1               ; X & 15
    cmp.w   #8,d1
    blt.s   .high_byte              ; if (X&15) < 8 → high byte
    addq.w  #1,d0                   ; low byte: add 1
.high_byte:
    move.w  d0,d5                   ; d5 = byte_offset (saved)

    ; -- Bit-in-byte mask --
    ;    bit_in_byte = 7 - (X & 7), always correct for both high/low
    move.w  d7,d0
    andi.w  #$0007,d0               ; X & 7
    moveq   #7,d1
    sub.w   d0,d1                   ; d1 = bit_in_byte (0-7)
    moveq   #1,d0
    lsl.b   d1,d0                   ; d0.b = bitmask_byte

    ; -- AND mask: NOT(bitmask_byte) replicated across all 4 bytes --
    move.b  d0,d4                   ; save bitmask_byte in d4
    not.b   d4                      ; d4.b = NOT(bitmask_byte)
    ; Replicate d4.b into all 4 bytes of d3:
    moveq   #0,d3
    move.b  d4,d3                   ; d3 = $000000xx
    lsl.w   #8,d3                   ; d3 = $0000xx00
    move.b  d4,d3                   ; d3 = $0000xxxx
    move.w  d3,d1                   ; save low word
    swap    d3                      ; d3 = $xxxx0000
    move.w  d1,d3                   ; d3 = $xxxxxxxx (AND mask)

    ; -- Write x_table_m entry --
    move.l  d3,(a0)+                ; +0: AND mask (long, movep format)
    move.l  a2,(a0)+                ; +4: pointer to or_table_m[X][0]
    move.w  d5,(a0)+                ; +8: byte offset
    clr.w   (a0)+                   ; +10: pad
    clr.l   (a0)+                   ; +12: pad

    ; -- Generate 16 OR entries for this X (movep format) --
    ;    Each entry: long OR mask packed as plane0:plane1:plane2:plane3
    ;    movep.l writes: bits 31-24 → plane 0, bits 23-16 → plane 1,
    ;                    bits 15-8  → plane 2, bits 7-0   → plane 3
    moveq   #0,d6                   ; d6 = color (0-15)
.or_loop:
    ; Build OR long byte by byte, MSB (plane 0) first:
    moveq   #0,d1                   ; d1 will be the OR mask long

    ; Plane 0 (bit 0 of color) → bits 31-24
    btst    #0,d6
    beq.s   .skip_p0
    move.b  d0,d1                   ; bits 7-0 = bitmask_byte
.skip_p0:
    lsl.l   #8,d1                   ; shift up 8 bits

    ; Plane 1 (bit 1 of color) → bits 23-16
    btst    #1,d6
    beq.s   .skip_p1
    or.b    d0,d1
.skip_p1:
    lsl.l   #8,d1

    ; Plane 2 (bit 2 of color) → bits 15-8
    btst    #2,d6
    beq.s   .skip_p2
    or.b    d0,d1
.skip_p2:
    lsl.l   #8,d1

    ; Plane 3 (bit 3 of color) → bits 7-0
    btst    #3,d6
    beq.s   .skip_p3
    or.b    d0,d1
.skip_p3:

    ; Write OR entry (4 bytes, movep format)
    move.l  d1,(a2)+

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

screen_base_ptr_m:
    dc.l    $78000                  ; example: screen at $78000

    ; Align tables to even addresses (68000 requirement)
    even

y_table_m:
    ds.l    200                     ; 800 bytes

x_table_m:
    ds.l    1280                    ; 320 entries * 16 bytes = 5120 bytes

or_table_m:
    ds.l    5120                    ; 320 * 16 * 4 bytes = 20480 bytes

; Total data: 800 + 5120 + 20480 = 26,400 bytes (~25.8 KB)
