# fast_68k_pixel

Fastest possible 4-plane pixel plotting routines for the **Atari ST** (MC68000 @ 8 MHz).

All routines use precomputed lookup tables and **zero branches** in the hot path.

## Screen Format

- **Resolution:** 320×200, 4 bitplanes interleaved (16 colors)
- **Pixel group:** 16 pixels = 8 bytes: `[plane0.w][plane1.w][plane2.w][plane3.w]`
- **Scanline:** 160 bytes

## Calling Convention

All routines share the same input convention:

| Register | Purpose |
|----------|---------|
| `d0.w` | X coordinate (0–319) |
| `d1.w` | Y coordinate (0–199) |
| `d2.w` | Color (0–15) |

Persistent registers differ by table variant — see individual sections below.

## Optimized Versions

### MOVEP Variants (~26 KB tables) — Fastest & Smallest

Uses the MC68000 `MOVEP.L` instruction to read/write one byte from each of the 4 bitplanes in a single operation. Since a pixel occupies one bit in either the high or low byte of each plane word, MOVEP provides exact byte-level access to all 4 planes simultaneously. Masks are byte-sized (4 bytes per long) instead of word-sized (8 bytes per two longs), resulting in the smallest tables of any variant while also being the fastest general-purpose implementation.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel_movep.s`](setpixel_movep.s) | `SetPixel_Movep` ★★ | **194** | 24.25 | ~824 | None (general-purpose) |
| [`setpixel_movep.s`](setpixel_movep.s) | `SetPixel_Movep_WriteOnly` | **182** | 22.75 | ~879 | Screen must be cleared first |

**★★ = Fastest** general-purpose version AND smallest tables. Persistent registers: `a4` = x_table_m, `a5` = y_table_m.

### Ultra Variants (~82 KB tables)

Uses a unified mega-table that merges AND masks, OR masks, and byte offsets into single 16-byte entries indexed by (X, color). Eliminates one pointer indirection from the hot path.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel_ultra.s`](setpixel_ultra.s) | `SetPixel_Ultra` | **218** | 27.25 | ~733 | None (general-purpose) |
| [`setpixel_ultra.s`](setpixel_ultra.s) | `SetPixel_Ultra_WriteOnly` ★★ | **174** | 21.75 | ~920 | Screen must be cleared first |

**★★ = Fastest** write-only version. Persistent registers: `a4` = xc_ptr, `a5` = y_table_u.

### Standard Variants (~46 KB tables)

Uses separate x_table and or_table with pointer indirection.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel.s`](setpixel.s) | `SetPixel` | **236** | 29.5 | ~677 | None (general-purpose) |
| [`setpixel_movem.s`](setpixel_movem.s) | `SetPixel_Movem` ★ | **228** | 28.5 | ~701 | None (general-purpose) |
| [`setpixel_writeonly.s`](setpixel_writeonly.s) | `SetPixel_WriteOnly` | **188** | 23.5 | ~851 | Screen must be cleared first |

**★ = Recommended** if table budget is limited to ~46 KB. Persistent registers: `a4` = x_table, `a5` = y_table.

### How They Compare

- **`SetPixel_Movep`** ★★ — The absolute fastest general-purpose pixel plot. Uses `MOVEP.L` to access one byte from each of the 4 bitplanes in a single 24-cycle operation. The pixel modification (read + AND + OR + write) takes only 64 cycles vs 84 for MOVEM — a 20-cycle savings. Byte-sized masks also shrink OR table entries from 8 bytes to 4 bytes, resulting in the smallest tables (~26 KB) of any variant. Fastest AND most memory-efficient.

- **`SetPixel_Ultra_WriteOnly`** ★★ — The absolute fastest write-only variant. Uses the mega-table approach with `or.l` directly to screen memory for minimal cycle count. 14 cycles faster than `SetPixel_WriteOnly` at the cost of larger tables.

- **`SetPixel_Ultra`** — The fastest MOVEM-based general-purpose variant. Merges all lookup data into a single unified xc_data table: one pointer dereference + color offset gives AND mask, OR masks, and byte offset in one contiguous 16-byte read. Uses MOVEM bulk read/write for the pixel modification.

- **`SetPixel_Movep_WriteOnly`** — Write-only variant using MOVEP. 6 cycles faster than `SetPixel_WriteOnly` with standard tables, using even less RAM (~26 KB vs ~46 KB).

- **`SetPixel_Movem`** ★ — The fastest standard-table (~46 KB) version. Uses `MOVEM.L` to bulk-read all 4 planes into registers, performs AND/OR as fast register-to-register operations, then bulk-writes back.

- **`SetPixel`** — The straightforward fast version. Uses longword AND/OR directly to screen memory. Clean and simple.

- **`SetPixel_WriteOnly`** — Write-only variant with standard tables. Skips the AND (clear) step. Only safe when pixels are known to be color 0.

### Inlined / Batch Variants

When plotting many pixels in a tight loop, additional savings are possible:

| Variant | Cycles | Savings | Notes |
|---------|-------:|--------:|-------|
| `SetPixel_Movep` (inlined, no RTS) | 178 | −16 | MOVEP, eliminate JSR/RTS overhead |
| Movep same-Y inlined | 168 | −26 | MOVEP, skip Y lookup when cached |
| Movep WriteOnly inlined | 166 | −16 | MOVEP write-only without RTS |
| Movep WriteOnly same-Y | **156** | −26 | MOVEP write-only, skip Y |
| `SetPixel_Ultra` (inlined, no RTS) | 202 | −16 | Eliminate JSR/RTS overhead |
| Ultra same-Y inlined | 176 | −42 | Skip Y lookup when scanline is cached |
| Ultra WriteOnly inlined | 158 | −16 | Write-only without RTS |
| Ultra WriteOnly same-Y | **132** | −42 | **Best case**: batch + clean screen |
| `SetPixel_Movem` (inlined, no RTS) | 212 | −16 | Standard tables, no RTS |
| Movem same-Y inlined | 202 | −26 | Standard tables, skip Y |
| WriteOnly same-Y | ~158 | −30 | Standard tables, batch + clean |

## Files

| File | Description |
|------|-------------|
| `setpixel_movep.s` | SetPixel_Movep + Movep_WriteOnly — fastest general-purpose, 194/182 cycles ★★ |
| `tables_movep.inc` | MOVEP table definitions and generation code (`InitTables_Movep`, ~26 KB) |
| `setpixel_ultra.s` | SetPixel_Ultra + Ultra_WriteOnly — fastest write-only, 218/174 cycles ★★ |
| `tables_ultra.inc` | Ultra table definitions and generation code (`InitTables_Ultra`, ~82 KB) |
| `setpixel.s` | SetPixel — general-purpose, 236 cycles |
| `setpixel_movem.s` | SetPixel_Movem — fastest standard-table version, 228 cycles ★ |
| `setpixel_writeonly.s` | SetPixel_WriteOnly — write-only for clean screens, 188 cycles |
| `tables.inc` | Standard table definitions and generation code (`InitTables`, ~46 KB) |
| `setpixel_fast.s` | Original exploration document with all approaches and analysis |

## Quick Start

### MOVEP (fastest general-purpose, ~26 KB tables)

```asm
    ; At startup — initialize tables once:
    jsr     InitTables_Movep
    lea     x_table_m,a4
    lea     y_table_m,a5

    ; Plot a pixel at (160, 100) in color 7:
    move.w  #160,d0
    move.w  #100,d1
    move.w  #7,d2
    jsr     SetPixel_Movep
```

### Ultra (fastest write-only, ~82 KB tables)

```asm
    ; At startup — initialize tables once:
    jsr     InitTables_Ultra
    lea     xc_ptr,a4
    lea     y_table_u,a5

    ; Plot a pixel at (160, 100) in color 7:
    move.w  #160,d0
    move.w  #100,d1
    move.w  #7,d2
    jsr     SetPixel_Ultra
```

### Standard (compact, ~46 KB tables)

```asm
    ; At startup — initialize tables once:
    jsr     InitTables
    lea     x_table,a4
    lea     y_table,a5

    ; Plot a pixel at (160, 100) in color 7:
    move.w  #160,d0
    move.w  #100,d1
    move.w  #7,d2
    jsr     SetPixel_Movem
```

## Table Layouts

### MOVEP Tables (~26 KB) — Smallest

| Table | Size | Description |
|-------|-----:|-------------|
| `y_table_m` | 800 B | 200 longs: `screen_base + Y*160` |
| `x_table_m` | 5,120 B | 320 × 16 bytes: AND mask (movep), OR pointer, byte offset |
| `or_table_m` | 20,480 B | 320 × 16 × 4 bytes: OR masks in movep format (1 byte per plane) |
| **Total** | **26,400 B** | ~25.8 KB |

### Ultra Tables (~82 KB)

| Table | Size | Description |
|-------|-----:|-------------|
| `y_table_u` | 800 B | 200 longs: `screen_base + Y*160` |
| `xc_ptr` | 1,280 B | 320 longs: pointer to `xc_data[X][0]` |
| `xc_data` | 81,920 B | 320 × 16 × 16 bytes: AND mask + OR masks + byte offset per (X, color) |
| **Total** | **84,000 B** | ~82 KB |

### Standard Tables (~46 KB)

| Table | Size | Description |
|-------|-----:|-------------|
| `y_table` | 800 B | 200 longs: `screen_base + Y*160` |
| `x_table` | 5,120 B | 320 × 16 bytes: AND mask, OR pointer, byte offset |
| `or_table` | 40,960 B | 320 × 16 × 8 bytes: OR masks for each (X, color) pair |
| **Total** | **46,880 B** | ~45.8 KB |
