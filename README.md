# Bounded Canonical Prefix

Development version `0.1.0` — a length-limited canonical Huffman codebook library and CLI in Nim (`>= 2.0`), featuring deterministic Larmore–Hirschberg package-merge optimization, checked integer bounds, an explicit binary demonstration format (`BCP1`), and an independent native C11 consumer verifier.

Built by [Lofrano Tecnologia](https://lofranotecnologia.com.br). [Versão em português](README.pt-BR.md).

## Overview

`bounded-canonical-prefix` computes optimal prefix code lengths $\ell_i \in [1, L]$ for byte alphabets (`<= 256` active symbols, maximum length $L \in [1, 16]$) using the Larmore–Hirschberg package-merge algorithm:
- **Checked 64-bit integer arithmetic**: symbol frequencies up to $2^{40}$ and total weight sum up to $2^{48}$.
- **Explicit edge cases**: empty alphabets (`0` symbols), singletons (`1` symbol assigned a 1-bit `0` code), and infeasible alphabets ($n > 2^L \implies$ `INFEASIBLE_ALPHABET`).
- **Explicit work bounds**: package nodes (`65,536`) and construction operations (`1,000,000`) return `UNKNOWN_BUDGET` when exceeded.
- **BCP1 demonstration format**: 268-byte header (`"BCP1"` magic, little-endian uint32 `decoded_length <= 1,048,576`, little-endian uint32 `meaningful_bits <= 16,777,216`, 256 one-byte code lengths) followed by MSB-first packed bitstream with zero-verified padding bits.

## Quick Start

### Run Offline Tests & Independent C11 Consumer

```sh
/bin/sh scripts/test-offline.sh
```

### Run Offline Demo

```sh
/bin/sh scripts/demo-offline.sh --assert
/bin/sh scripts/demo-offline.sh --assert --json
```

Example output:

```text
PASS status=COMPLETE oracle_cases=10 decoded_bytes=47 meaningful_bits=182 encoded_bytes=291
```

## Limitations and Scope Exclusions

- `BCP1` is a narrow demonstration format, not DEFLATE, gzip, or ZIP.
- Provides no checksum, cryptographic integrity, or streaming archive support.

## License

MIT — Copyright (c) 2026 Lofrano Tecnologia. See [LICENSE](LICENSE).
