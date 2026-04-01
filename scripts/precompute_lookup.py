#!/usr/bin/env python3
"""
Precompute the Kubelka-Munk pigment mixing lookup table for all 78 pigments.

Outputs: ios/RefPlane/PigmentLookup.bin

Binary layout
─────────────
Header (24 bytes):
  [0-3]   "KMLT"            magic
  [4]     version = 1       uint8
  [5]     pigment_count     uint8  (e.g. 78)
  [6-7]   resolution = 8    uint16 LE  (concentration steps: 0/8 … 8/8)
  [8-11]  pair_count        uint32 LE  (= C(N,2))
  [12-15] triplet_count     uint32 LE  (= C(N,3))
  [16-19] pair_steps = 9    uint32 LE  (0/8 … 8/8 inclusive)
  [20-23] triplet_steps=45  uint32 LE  (full simplex grid including edges/corners)

Data (entry_count = pair_count*pair_steps + triplet_count*triplet_steps):
  Section A – pair entries, ordered by (i, j) lex then a0 = 0,1,…,8
  Section B – triplet entries, ordered by (i, j, k) lex then (a0, a1) in simplex order

Per entry (10 bytes, little-endian):
  [0]   i0  uint8       global pigment index for slot 0
  [1]   i1  uint8       global pigment index for slot 1
  [2]   i2  uint8       global pigment index for slot 2 (0 for pair entries)
  [3]   packed uint8    high nibble = a0 (0-8), low nibble = a1 (0-8)
                        a2 = 8 - a0 - a1  (derived: only valid for triplet entries)
                        For pair entries: a0+a1 = 8, a2 always 0.
  [4-5] L   float16 LE  Oklab L (≈ 0..1)
  [6-7] a   float16 LE  Oklab a (≈ -0.5..0.5)
  [8-9] b   float16 LE  Oklab b (≈ -0.5..0.5)

paintCount per entry (derived at runtime):
  pair:    1 if a0==0 or a1==0, else 2
  triplet: number of non-zero amounts among (a0, a1, 8-a0-a1)

Usage
─────
  cd /path/to/RefPlane
  python3 scripts/precompute_lookup.py

After running, add ios/RefPlane/PigmentLookup.bin to the Xcode target's resources.
The project.pbxproj in this repo already includes the necessary entries.
"""

import json
import struct
import sys
import time
from pathlib import Path

import numpy as np

# ── Spectral pipeline constants ────────────────────────────────────────────

M_XYZ_TO_RGB = np.array([
    [ 3.2404542, -1.5371385, -0.4985314],
    [-0.9692660,  1.8760108,  0.0415560],
    [ 0.0556434, -0.2040259,  1.0572252],
], dtype=np.float64)

M_RGB_TO_LMS = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005],
], dtype=np.float64)

M_LMS_TO_OKLAB = np.array([
    [0.2104542553,  0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050,  0.4505937099],
    [0.0259040371,  0.7827717662, -0.8086757660],
], dtype=np.float64)

RESOLUTION = 8

# ── Batch KM pipeline: (B, 31) ks_batch → (B, 3) oklab ────────────────────

def ks_batch_to_oklab(ks_batch: np.ndarray, cmf_xyz: np.ndarray, ill: np.ndarray, norm: float) -> np.ndarray:
    """
    ks_batch: (B, 31) float64 mixed K/S spectra
    Returns:  (B, 3)  float64 Oklab [L, a, b]
    """
    ks = np.maximum(ks_batch, 0.0)
    ref = 1.0 + ks - np.sqrt(ks * ks + 2.0 * ks)   # (B, 31)
    rI  = ref * ill                                   # (B, 31) broadcast
    xyz = (rI @ cmf_xyz) / norm                       # (B, 3)  XYZ
    rgb = (M_XYZ_TO_RGB @ xyz.T).T                    # (B, 3)  linear sRGB
    rgb_c = np.maximum(rgb, 0.0)
    lms  = (M_RGB_TO_LMS @ rgb_c.T).T                # (B, 3)
    lms_ = np.cbrt(lms)                               # (B, 3)  cube root
    return (M_LMS_TO_OKLAB @ lms_.T).T               # (B, 3)  Oklab


# ── Grid generators ────────────────────────────────────────────────────────

# pair_concs[step, slot]: concentrations for 2-slot grid (9 steps × 2 slots)
PAIR_CONCS = np.array(
    [[a0, RESOLUTION - a0] for a0 in range(RESOLUTION + 1)],
    dtype=np.float64,
) / RESOLUTION   # (9, 2)

# triplet_amounts[step, slot]: integer amounts for 3-slot simplex (45 steps × 3 slots)
TRIPLET_AMOUNTS = np.array(
    [
        (a0, a1, RESOLUTION - a0 - a1)
        for a0 in range(RESOLUTION + 1)
        for a1 in range(RESOLUTION + 1 - a0)
    ],
    dtype=np.uint8,
)  # (45, 3)

# triplet concentrations as float
TRIPLET_CONCS = TRIPLET_AMOUNTS.astype(np.float64) / RESOLUTION   # (45, 3)

assert PAIR_CONCS.shape    == (9, 2),  f"pair grid shape: {PAIR_CONCS.shape}"
assert TRIPLET_AMOUNTS.shape == (45, 3), f"triplet grid shape: {TRIPLET_AMOUNTS.shape}"

# ── Packed amount bytes for each grid step ─────────────────────────────────

# For pair steps: packed = (a0 << 4) | a1
PAIR_PACKED = np.array(
    [((a0 & 0xF) << 4) | (RESOLUTION - a0) for a0 in range(RESOLUTION + 1)],
    dtype=np.uint8,
)  # (9,)

# For triplet steps: packed = (a0 << 4) | a1  (a2 inferred as 8-a0-a1)
TRIPLET_PACKED = ((TRIPLET_AMOUNTS[:, 0].astype(np.uint16) & 0xF) << 4 |
                  (TRIPLET_AMOUNTS[:, 1].astype(np.uint16) & 0xF)).astype(np.uint8)  # (45,)

# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    project_root = Path(__file__).resolve().parent.parent
    db_path  = project_root / "ios" / "RefPlane" / "GoldenAcrylicsKS.json"
    out_path = project_root / "ios" / "RefPlane" / "PigmentLookup.bin"

    print(f"Loading {db_path} …")
    with db_path.open() as f:
        db = json.load(f)

    pigments = db["pigments"]
    N = len(pigments)
    print(f"  {N} pigments found.")

    # Spectral data as (N, 31) float64
    all_ks  = np.array([p["kOverS"] for p in pigments], dtype=np.float64)
    cmf_xyz = np.stack([db["cmfX"], db["cmfY"], db["cmfZ"]], axis=1).astype(np.float64)  # (31, 3)
    ill     = np.array(db["illuminantSpd"], dtype=np.float64)  # (31,)
    norm    = float(ill @ cmf_xyz[:, 1])   # Y normalisation scalar

    PAIR_COUNT       = N * (N - 1) // 2
    TRIPLET_COUNT    = N * (N - 1) * (N - 2) // 6
    PAIR_STEPS_N     = 9
    TRIPLET_STEPS_N  = 45
    TOTAL_ENTRIES    = PAIR_COUNT * PAIR_STEPS_N + TRIPLET_COUNT * TRIPLET_STEPS_N

    print(f"  Pairs:    {PAIR_COUNT:,}  × {PAIR_STEPS_N} = {PAIR_COUNT * PAIR_STEPS_N:,} entries")
    print(f"  Triplets: {TRIPLET_COUNT:,} × {TRIPLET_STEPS_N} = {TRIPLET_COUNT * TRIPLET_STEPS_N:,} entries")
    print(f"  Total:    {TOTAL_ENTRIES:,} entries × 10 bytes = {TOTAL_ENTRIES * 10 / 1_048_576:.1f} MB")

    # ── Header (24 bytes) ────────────────────────────────────────────────
    header = struct.pack("<4sBBHIIII",
        b"KMLT", 1, N, RESOLUTION,
        PAIR_COUNT, TRIPLET_COUNT, PAIR_STEPS_N, TRIPLET_STEPS_N,
    )
    assert len(header) == 24

    # ── Output buffer ────────────────────────────────────────────────────
    # Each entry is 10 bytes: 4 × uint8 + 3 × uint16 (float16 bits)
    # We'll fill a structured numpy array then dump to bytes.

    # dtype: 4 uint8 fields + 3 uint16 (float16 stored as bits)
    entry_dtype = np.dtype([
        ("i0", np.uint8), ("i1", np.uint8), ("i2", np.uint8), ("packed", np.uint8),
        ("L_bits", np.uint16), ("a_bits", np.uint16), ("b_bits", np.uint16),
    ])
    assert entry_dtype.itemsize == 10

    entries = np.empty(TOTAL_ENTRIES, dtype=entry_dtype)
    write_pos = 0

    t0 = time.time()

    # ── Section A: pair entries ──────────────────────────────────────────
    print("Computing pair entries …")
    # For each pair (i,j): compute 9 oklab values at once via matrix multiply
    # ks_pair = c0 * ks[i] + c1 * ks[j]  for each (c0, c1) in PAIR_CONCS
    # ks_pair shape: (9, 31)

    pair_idx = 0
    for i in range(N):
        for j in range(i + 1, N):
            # Mixed K/S: (9, 2) @ (2, 31) → (9, 31)
            ks_pair = PAIR_CONCS @ np.stack([all_ks[i], all_ks[j]])  # (9, 31)
            oklab   = ks_batch_to_oklab(ks_pair, cmf_xyz, ill, norm)  # (9, 3) float64

            oklab_f16 = oklab.astype(np.float16)
            lab_bits  = oklab_f16.view(np.uint16)  # (9, 3) uint16

            sl = slice(write_pos, write_pos + 9)
            entries["i0"][sl]     = i
            entries["i1"][sl]     = j
            entries["i2"][sl]     = 0
            entries["packed"][sl] = PAIR_PACKED
            entries["L_bits"][sl] = lab_bits[:, 0]
            entries["a_bits"][sl] = lab_bits[:, 1]
            entries["b_bits"][sl] = lab_bits[:, 2]
            write_pos += 9
            pair_idx  += 1

        if (i + 1) % 10 == 0 or i == N - 1:
            elapsed = time.time() - t0
            done = sum(range(N - i, N))
            pct  = pair_idx / PAIR_COUNT * 100
            print(f"  pairs: pigment {i+1}/{N}  ({pct:.1f}%)  {elapsed:.1f}s")

    # ── Section B: triplet entries ────────────────────────────────────────
    print("Computing triplet entries …")
    triplet_idx = 0
    t1 = time.time()

    for i in range(N):
        for j in range(i + 1, N):
            for k in range(j + 1, N):
                # Mixed K/S: (45, 3) @ (3, 31) → (45, 31)
                ks_trip = TRIPLET_CONCS @ np.stack([all_ks[i], all_ks[j], all_ks[k]])
                oklab   = ks_batch_to_oklab(ks_trip, cmf_xyz, ill, norm)  # (45, 3)

                oklab_f16 = oklab.astype(np.float16)
                lab_bits  = oklab_f16.view(np.uint16)  # (45, 3)

                sl = slice(write_pos, write_pos + 45)
                entries["i0"][sl]     = i
                entries["i1"][sl]     = j
                entries["i2"][sl]     = k
                entries["packed"][sl] = TRIPLET_PACKED
                entries["L_bits"][sl] = lab_bits[:, 0]
                entries["a_bits"][sl] = lab_bits[:, 1]
                entries["b_bits"][sl] = lab_bits[:, 2]
                write_pos  += 45
                triplet_idx += 1

        if (i + 1) % 5 == 0 or i == N - 1:
            elapsed = time.time() - t1
            done    = sum((N - ii - 1) * (N - ii - 2) // 2 for ii in range(i + 1))
            pct     = done / TRIPLET_COUNT * 100
            print(f"  triplets: pigment {i+1}/{N}  ({pct:.1f}%)  {elapsed:.1f}s")

    assert write_pos == TOTAL_ENTRIES, \
        f"write_pos mismatch: {write_pos} != {TOTAL_ENTRIES}"

    # ── Write output ─────────────────────────────────────────────────────
    print(f"Writing {out_path} …")
    with out_path.open("wb") as f:
        f.write(header)
        f.write(entries.tobytes())

    elapsed_total = time.time() - t0
    size_mb = out_path.stat().st_size / 1_048_576
    print(f"Done. {size_mb:.1f} MB  in {elapsed_total:.1f}s")
    print()
    print("Next step: add ios/RefPlane/PigmentLookup.bin to the Xcode target's")
    print("Copy Bundle Resources build phase (project.pbxproj already patched).")


if __name__ == "__main__":
    main()
