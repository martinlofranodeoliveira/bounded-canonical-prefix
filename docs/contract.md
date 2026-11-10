# Contract — Bounded Canonical Prefix (v0.1.0)

## Codebook Construction (`buildCanonicalCodebook`)

- **Inputs**:
  - `frequencies: array[256, int64]` with $0 \le f_s \le 2^{40}$ and $\sum f_s \le 2^{48}$.
  - `maxLen: int` in $1 \dots 16$.
  - `budget: BcpBudget` (`maxNodes = 65536`, `maxOperations = 1000000`).
- **Outputs (`BcpStatus`)**:
  - `COMPLETE`:
    - $n = 0$: all 256 lengths are `0`, `weightedCost = 0`.
    - $n = 1$: single active symbol gets `length = 1`, `code = 0`, `weightedCost = f`.
    - $2 \le n \le 2^L$: lengths $1 \le \ell_s \le L$ satisfying $\sum 2^{L - \ell_s} = 2^L$ with minimum weighted length sum $\sum f_s \ell_s$.
  - `INFEASIBLE_ALPHABET`: active symbol count $n > 2^L$.
  - `INVALID_INPUT`: out-of-range `maxLen` or negative/overflowing frequencies.
  - `UNKNOWN_BUDGET`: package node or operation budget exceeded.

## BCP1 Binary Format (`encodeBcp1` / `decodeBcp1`)

- **Header (268 bytes)**:
  - `0..3`: ASCII `"BCP1"`
  - `4..7`: little-endian `uint32` `decoded_length` ($\le 1,048,576$)
  - `8..11`: little-endian `uint32` `meaningful_bits` ($\le 16,777,216$)
  - `12..267`: 256 `uint8` code lengths ($0 \dots 16$)
- **Payload**: $\lceil \text{meaningful\_bits} / 8 \rceil$ bytes, packed MSB-first; unused low bits in the final byte must be `0`.
