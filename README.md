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

### Ultra Variants (~82 KB tables) — Fastest

Uses a unified mega-table that merges AND masks, OR masks, and byte offsets into single 16-byte entries indexed by (X, color). Eliminates one pointer indirection from the hot path.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel_ultra.s`](setpixel_ultra.s) | `SetPixel_Ultra` ★★ | **218** | 27.25 | ~733 | None (general-purpose) |
| [`setpixel_ultra.s`](setpixel_ultra.s) | `SetPixel_Ultra_WriteOnly` ★★ | **174** | 21.75 | ~920 | Screen must be cleared first |

**★★ = Fastest** versions. Persistent registers: `a4` = xc_ptr, `a5` = y_table_u.

### Standard Variants (~46 KB tables)

Uses separate x_table and or_table with pointer indirection.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel.s`](setpixel.s) | `SetPixel` | **236** | 29.5 | ~677 | None (general-purpose) |
| [`setpixel_movem.s`](setpixel_movem.s) | `SetPixel_Movem` ★ | **228** | 28.5 | ~701 | None (general-purpose) |
| [`setpixel_writeonly.s`](setpixel_writeonly.s) | `SetPixel_WriteOnly` | **188** | 23.5 | ~851 | Screen must be cleared first |

**★ = Recommended** if table budget is limited to ~46 KB. Persistent registers: `a4` = x_table, `a5` = y_table.

### How They Compare

- **`SetPixel_Ultra`** ★★ — The absolute fastest general-purpose pixel plot. Merges all lookup data into a single unified xc_data table: one pointer dereference + color offset gives AND mask, OR masks, and byte offset in one contiguous 16-byte read. Uses MOVEM bulk read/write for the pixel modification. 10 cycles faster than `SetPixel_Movem` at the cost of 36 KB more table RAM.

- **`SetPixel_Ultra_WriteOnly`** ★★ — The absolute fastest write-only variant. Same mega-table approach but skips the AND step. 14 cycles faster than `SetPixel_WriteOnly`.

- **`SetPixel_Movem`** ★ — The fastest version with the standard ~46 KB table layout. Uses `MOVEM.L` to bulk-read all 4 planes into registers, performs AND/OR as fast register-to-register operations, then bulk-writes back.

- **`SetPixel`** — The straightforward fast version. Uses longword AND/OR directly to screen memory. Clean and simple.

- **`SetPixel_WriteOnly`** — Write-only variant with standard tables. Skips the AND (clear) step. Only safe when pixels are known to be color 0.

### Inlined / Batch Variants

When plotting many pixels in a tight loop, additional savings are possible:

| Variant | Cycles | Savings | Notes |
|---------|-------:|--------:|-------|
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
| `setpixel_ultra.s` | SetPixel_Ultra + Ultra_WriteOnly — fastest versions, 218/174 cycles ★★ |
| `tables_ultra.inc` | Ultra table definitions and generation code (`InitTables_Ultra`, ~82 KB) |
| `setpixel.s` | SetPixel — general-purpose, 236 cycles |
| `setpixel_movem.s` | SetPixel_Movem — fastest standard-table version, 228 cycles ★ |
| `setpixel_writeonly.s` | SetPixel_WriteOnly — write-only for clean screens, 188 cycles |
| `tables.inc` | Standard table definitions and generation code (`InitTables`, ~46 KB) |
| `setpixel_fast.s` | Original exploration document with all approaches and analysis |

## Quick Start

### Ultra (fastest, ~82 KB tables)

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
