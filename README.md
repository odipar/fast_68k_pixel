# fast_68k_pixel

Fastest possible 4-plane pixel plotting routines for the **Atari ST** (MC68000 @ 8 MHz).

All routines use precomputed lookup tables and **zero branches** in the hot path.

## Screen Format

- **Resolution:** 320×200, 4 bitplanes interleaved (16 colors)
- **Pixel group:** 16 pixels = 8 bytes: `[plane0.w][plane1.w][plane2.w][plane3.w]`
- **Scanline:** 160 bytes

## Calling Convention

| Register | Purpose |
|----------|---------|
| `d0.w` | X coordinate (0–319) |
| `d1.w` | Y coordinate (0–199) |
| `d2.w` | Color (0–15) |
| `a4` | x_table base (persistent) |
| `a5` | y_table base (persistent) |

## Optimized Versions

Each version is in its own file and includes the shared `tables.inc` for table generation and data.

| File | Routine | Cycles | µs @ 8 MHz | Pixels/frame | Constraint |
|------|---------|-------:|-----------:|-------------:|------------|
| [`setpixel.s`](setpixel.s) | `SetPixel` | **236** | 29.5 | ~677 | None (general-purpose) |
| [`setpixel_movem.s`](setpixel_movem.s) | `SetPixel_Movem` ★ | **228** | 28.5 | ~701 | None (general-purpose) |
| [`setpixel_writeonly.s`](setpixel_writeonly.s) | `SetPixel_WriteOnly` | **188** | 23.5 | ~851 | Screen must be cleared first |

**★ = Recommended** general-purpose version.

All versions use ~46 KB of lookup tables (y_table + x_table + or_table).

### How They Compare

- **`SetPixel`** — The straightforward fast version. Uses longword AND/OR directly to screen memory to clear+set 4 bitplanes in pairs. Clean and simple.

- **`SetPixel_Movem`** ★ — The fastest general-purpose version. Uses `MOVEM.L` to bulk-read all 4 planes into registers, performs AND/OR as fast register-to-register operations, then bulk-writes back. Saves 8 cycles over `SetPixel`.

- **`SetPixel_WriteOnly`** — The fastest variant for rendering onto a freshly cleared screen. Skips the AND (clear) step entirely since there are no old bits to clear. 20% faster than `SetPixel`, but **only safe when pixels are known to be color 0**.

### Inlined / Batch Variants

When plotting many pixels in a tight loop, additional savings are possible:

| Variant | Cycles | Savings | Notes |
|---------|-------:|--------:|-------|
| `SetPixel_Movem` (inlined, no RTS) | 212 | −16 | Eliminate JSR/RTS overhead |
| Same-Y inlined | 202 | −26 | Skip Y lookup when scanline is cached |
| Same-Y WriteOnly | ~158 | −70 | Best case: batch + clean screen |

## Files

| File | Description |
|------|-------------|
| `setpixel.s` | SetPixel — general-purpose, 236 cycles |
| `setpixel_movem.s` | SetPixel_Movem — fastest general-purpose, 228 cycles ★ |
| `setpixel_writeonly.s` | SetPixel_WriteOnly — write-only for clean screens, 188 cycles |
| `tables.inc` | Shared lookup table definitions and generation code (`InitTables`) |
| `setpixel_fast.s` | Original exploration document with all 10 approaches and analysis |

## Quick Start

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

## Table Layout (~46 KB)

| Table | Size | Description |
|-------|-----:|-------------|
| `y_table` | 800 B | 200 longs: `screen_base + Y*160` |
| `x_table` | 5,120 B | 320 × 16 bytes: AND mask, OR pointer, byte offset |
| `or_table` | 40,960 B | 320 × 16 × 8 bytes: OR masks for each (X, color) pair |
| **Total** | **46,880 B** | ~45.8 KB |
