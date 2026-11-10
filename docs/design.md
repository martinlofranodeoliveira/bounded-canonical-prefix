# Design — Bounded Canonical Prefix

## Architecture

1. **`bounded_canonical_prefix/types.nim`**: Domain constants, budget limits, and result structures.
2. **`bounded_canonical_prefix/package_merge.nim`**: Level-by-level Larmore–Hirschberg package-merge implementation with deterministic `(weight, isPackage, minSymbol)` ordering and canonical MSB-first code assignment.
3. **`bounded_canonical_prefix/bcp1_codec.nim`**: Strict encoder and decoder for the `BCP1` binary demonstration format, enforcing Kraft's equality, exact byte-length matching, and zero padding-bit validation.
4. **`bounded_canonical_prefix/oracle.nim`**: Brute-force length-tuple enumerator for small alphabets ($n \le 6, L \le 5$) that verifies exact optimality of the package-merge weighted cost without calling package-merge.
5. **`tools/bcp1_c_consumer.c`**: Standalone C11 decoder compiled during test preparation to verify cross-language binary interoperability.
