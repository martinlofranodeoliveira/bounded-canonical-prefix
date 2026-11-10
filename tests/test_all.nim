## Comprehensive unit, adversarial, and C-consumer tests for Bounded Canonical Prefix.

import std/[os, osproc, strutils]
import ../src/bounded_canonical_prefix

proc runAllBcpTests*(cConsumerBin: string = ""): bool =
  # 1. Empty alphabet
  block:
    var freqs: array[256, int64]
    let cb = buildCanonicalCodebook(freqs, 8)
    doAssert cb.status == COMPLETE
    doAssert cb.symbolCount == 0
    doAssert cb.weightedCost == 0
    for L in cb.lengths:
      doAssert L == 0'u8

    let enc = encodeBcp1(@[], 8)
    doAssert enc.status == COMPLETE
    doAssert enc.bytes.len == Bcp1HeaderBytes
    let dec = decodeBcp1(enc.bytes)
    doAssert dec.status == COMPLETE
    doAssert dec.decoded.len == 0

  # 2. Singleton alphabet
  block:
    let payload = @[uint8('A'), uint8('A'), uint8('A'), uint8('A'), uint8('A')]
    let enc = encodeBcp1(payload, 4)
    doAssert enc.status == COMPLETE
    doAssert enc.codebook.symbolCount == 1
    doAssert enc.codebook.lengths[int('A')] == 1'u8
    doAssert enc.codebook.codes[int('A')] == 0'u16
    doAssert enc.meaningfulBits == 5'u32
    let dec = decodeBcp1(enc.bytes)
    doAssert dec.status == COMPLETE
    doAssert dec.decoded == payload

  # 3. All 256 symbols with length limit L = 8 and L = 12
  block:
    var freqs: array[256, int64]
    for s in 0 .. 255:
      freqs[s] = int64(s + 1)
    let cb8 = buildCanonicalCodebook(freqs, 8)
    doAssert cb8.status == COMPLETE
    doAssert cb8.symbolCount == 256
    for s in 0 .. 255:
      doAssert cb8.lengths[s] == 8'u8

    let cb12 = buildCanonicalCodebook(freqs, 12)
    doAssert cb12.status == COMPLETE
    doAssert cb12.weightedCost < cb8.weightedCost
    for s in 0 .. 255:
      doAssert cb12.lengths[s] >= 1'u8 and cb12.lengths[s] <= 12'u8

  # 4. Highly skewed Fibonacci weights forcing length cap L = 5 on 8 symbols
  block:
    var freqs: array[256, int64]
    let fib = [1'i64, 1, 2, 3, 5, 8, 13, 21]
    for i, v in fib:
      freqs[i] = v
    let cb = buildCanonicalCodebook(freqs, 5)
    doAssert cb.status == COMPLETE
    for i in 0 .. 7:
      doAssert cb.lengths[i] >= 1'u8 and cb.lengths[i] <= 5'u8

  # 5. Deterministic tie handling
  block:
    var freqs: array[256, int64]
    freqs[10] = 50
    freqs[20] = 50
    freqs[30] = 50
    let cb1 = buildCanonicalCodebook(freqs, 2)
    let cb2 = buildCanonicalCodebook(freqs, 2)
    doAssert cb1.status == COMPLETE
    doAssert cb1.lengths == cb2.lengths
    doAssert cb1.codes == cb2.codes
    # Deterministic tie-breaking: first pair (10, 20) forms the depth-2 package, leaving 30 at depth 1
    doAssert cb1.lengths[10] == 2'u8
    doAssert cb1.lengths[20] == 2'u8
    doAssert cb1.lengths[30] == 1'u8

  # 6. Infeasible alphabet (5 symbols > 2^2 = 4)
  block:
    var freqs: array[256, int64]
    for i in 0 .. 4:
      freqs[i] = 10
    let cb = buildCanonicalCodebook(freqs, 2)
    doAssert cb.status == INFEASIBLE_ALPHABET

  # 7. Checked integer bounds (frequency > 2^40, sum > 2^48)
  block:
    var freqs: array[256, int64]
    freqs[0] = MaxSymbolFrequency + 1
    let cbOver = buildCanonicalCodebook(freqs, 8)
    doAssert cbOver.status == INVALID_INPUT

  # 8. UNKNOWN_BUDGET enforcement (maxNodes and maxOperations)
  block:
    var freqs: array[256, int64]
    for i in 0 .. 31:
      freqs[i] = int64(i + 1)
    let tinyNodeBudget = BcpBudget(maxNodes: 10, maxOperations: 1_000_000)
    let cbNodes = buildCanonicalCodebook(freqs, 8, tinyNodeBudget)
    doAssert cbNodes.status == UNKNOWN_BUDGET

    let tinyOpBudget = BcpBudget(maxNodes: 65536, maxOperations: 50)
    let cbOps = buildCanonicalCodebook(freqs, 8, tinyOpBudget)
    doAssert cbOps.status == UNKNOWN_BUDGET

  # 9. Exhaustive small-alphabet oracle (n <= 6, L <= 5)
  block:
    let oracleRes = runSmallAlphabetOracleSuite()
    doAssert oracleRes.passed
    doAssert oracleRes.checkedCases == 10

  # 10. Adversarial BCP1 corruption mutations
  block:
    let msg = "Bounded Canonical Prefix BCP1 deterministic round-trip test payload!"
    var raw = newSeq[uint8](msg.len)
    for i, ch in msg:
      raw[i] = uint8(ch)
    let enc = encodeBcp1(raw, 8)
    doAssert enc.status == COMPLETE

    let goodDec = decodeBcp1(enc.bytes)
    doAssert goodDec.status == COMPLETE
    doAssert goodDec.decoded == raw

    # Mutate magic
    var badMagic = enc.bytes
    badMagic[3] = uint8('2')
    let rMagic = decodeBcp1(badMagic)
    doAssert rMagic.status == INVALID_INPUT and rMagic.errorKind == ERR_INVALID_MAGIC

    # Mutate code length > 16
    var badLen = enc.bytes
    badLen[12 + int('B')] = 17'u8
    let rLen = decodeBcp1(badLen)
    doAssert rLen.status == INVALID_INPUT and rLen.errorKind == ERR_INVALID_CODE_LENGTH

    # Mutate Kraft sum
    var badKraft = enc.bytes
    badKraft[12 + int('B')] = badKraft[12 + int('B')] + 1'u8
    let rKraft = decodeBcp1(badKraft)
    doAssert rKraft.status == INVALID_INPUT and rKraft.errorKind == ERR_INVALID_KRAFT_SUM

    # Truncate payload
    var truncated = enc.bytes[0 ..< enc.bytes.len - 1]
    let rTrunc = decodeBcp1(truncated)
    doAssert rTrunc.status == INVALID_INPUT and rTrunc.errorKind == ERR_BYTE_LENGTH_MISMATCH

    # Extra trailing byte
    var extra = enc.bytes & @[0'u8]
    let rExtra = decodeBcp1(extra)
    doAssert rExtra.status == INVALID_INPUT and rExtra.errorKind == ERR_BYTE_LENGTH_MISMATCH

    # Nonzero padding bit in final byte (if unused bits > 0)
    if (enc.meaningfulBits and 7'u32) != 0'u32:
      var badPad = enc.bytes
      badPad[badPad.len - 1] = badPad[badPad.len - 1] or 1'u8
      let rPad = decodeBcp1(badPad)
      doAssert rPad.status == INVALID_INPUT and rPad.errorKind == ERR_NONZERO_PADDING

    # Decoded length mismatch
    var badDecLen = enc.bytes
    badDecLen[4] = badDecLen[4] xor 1'u8
    let rDecLen = decodeBcp1(badDecLen)
    doAssert rDecLen.status == INVALID_INPUT and rDecLen.errorKind == ERR_DECODED_LENGTH_MISMATCH

    # Verify with independent C consumer if path provided
    if cConsumerBin.len > 0 and fileExists(cConsumerBin):
      let tmpDir = getTempDir()
      let bcpPath = tmpDir / "test_sample.bcp1"
      let rawPath = tmpDir / "test_sample.bin"
      var fBcp = open(bcpPath, fmWrite)
      discard fBcp.writeBuffer(unsafeAddr enc.bytes[0], enc.bytes.len)
      fBcp.close()
      var fRaw = open(rawPath, fmWrite)
      discard fRaw.writeBuffer(unsafeAddr raw[0], raw.len)
      fRaw.close()

      let (outp, code) = execCmdEx(quoteShell(cConsumerBin) & " " & quoteShell(bcpPath) & " " & quoteShell(rawPath))
      removeFile(bcpPath)
      removeFile(rawPath)
      doAssert code == 0, "C consumer failed: " & outp
      doAssert "C_CONSUMER_OK" in outp

  return true

when isMainModule:
  let cBin = getEnv("BCP1_C_CONSUMER", "")
  doAssert runAllBcpTests(cBin)
  echo "PASS bounded-canonical-prefix unit, oracle, mutation, and C-consumer tests"
