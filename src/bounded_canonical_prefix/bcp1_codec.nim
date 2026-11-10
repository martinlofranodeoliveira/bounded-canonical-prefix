## BCP1 binary format encoder and decoder.
##
## Format layout (268-byte header + packed bitstream):
##   Bytes 0..3:    "BCP1" magic (0x42, 0x43, 0x50, 0x31)
##   Bytes 4..7:    uint32 little-endian decoded_length (<= 1_048_576)
##   Bytes 8..11:   uint32 little-endian meaningful_bits (<= 16_777_216)
##   Bytes 12..267: 256 uint8 code lengths (each 0..16)
##   Bytes 268..:   ceil(meaningful_bits / 8) packed payload bytes (MSB-first, zero low-bit padding)

import types
import package_merge

proc writeLe32(buf: var seq[uint8], val: uint32) =
  buf.add(uint8(val and 0xFF'u32))
  buf.add(uint8((val shr 8) and 0xFF'u32))
  buf.add(uint8((val shr 16) and 0xFF'u32))
  buf.add(uint8((val shr 24) and 0xFF'u32))

proc readLe32(data: openArray[uint8], offset: int): uint32 =
  uint32(data[offset]) or
  (uint32(data[offset + 1]) shl 8) or
  (uint32(data[offset + 2]) shl 16) or
  (uint32(data[offset + 3]) shl 24)

proc validateCodeLengths*(lengths: array[256, uint8], activeCount: out int): bool =
  activeCount = 0
  var kraftSum = 0'u32
  for s in 0 .. 255:
    let L = int(lengths[s])
    if L < 0 or L > MaxCodeLengthLimit:
      return false
    if L > 0:
      inc activeCount
      kraftSum += (1'u32 shl (MaxCodeLengthLimit - L))

  if activeCount == 0:
    return true
  elif activeCount == 1:
    # Singleton must use length 1 (kraftSum == 32768)
    return kraftSum == (1'u32 shl (MaxCodeLengthLimit - 1))
  else:
    return kraftSum == (1'u32 shl MaxCodeLengthLimit)

proc encodeBcp1*(
  payload: openArray[uint8],
  maxLen: int = MaxCodeLengthLimit,
  budget: BcpBudget = defaultBudget()
): EncodeResult =
  if payload.len > MaxDecodedPayloadBytes:
    result.status = INVALID_INPUT
    result.errorCode = "payload_too_large"
    result.message = "Payload exceeds 1048576-byte limit"
    return result

  var freqs: array[256, int64]
  for b in payload:
    inc freqs[b]

  let cb = buildCanonicalCodebook(freqs, maxLen, budget)
  result.codebook = cb
  if cb.status != COMPLETE:
    result.status = cb.status
    result.errorCode = cb.errorCode
    result.message = cb.message
    return result

  if cb.weightedCost > int64(MaxMeaningfulBits):
    result.status = INVALID_INPUT
    result.errorCode = "meaningful_bits_exceeded"
    result.message = "Encoded bitstream exceeds 16777216 bits"
    return result

  let decodedLen = uint32(payload.len)
  let totalBits = uint32(cb.weightedCost)
  let packedBytes = int((totalBits + 7'u32) shr 3)

  var outBytes = newSeqOfCap[uint8](Bcp1HeaderBytes + packedBytes)
  outBytes.add(uint8('B'))
  outBytes.add(uint8('C'))
  outBytes.add(uint8('P'))
  outBytes.add(uint8('1'))
  writeLe32(outBytes, decodedLen)
  writeLe32(outBytes, totalBits)
  for s in 0 .. 255:
    outBytes.add(cb.lengths[s])

  var curByte = 0'u8
  var bitPos = 0
  for b in payload:
    let L = int(cb.lengths[b])
    let code = cb.codes[b]
    for shift in countdown(L - 1, 0):
      let bit = uint8((code shr shift) and 1'u16)
      curByte = (curByte shl 1) or bit
      inc bitPos
      if bitPos == 8:
        outBytes.add(curByte)
        curByte = 0'u8
        bitPos = 0

  if bitPos > 0:
    curByte = curByte shl (8 - bitPos)
    outBytes.add(curByte)

  result.status = COMPLETE
  result.bytes = outBytes
  result.meaningfulBits = totalBits
  result.decodedLength = decodedLen
  return result

proc decodeBcp1*(
  encoded: openArray[uint8],
  budget: BcpBudget = defaultBudget()
): DecodeResult =
  if encoded.len < Bcp1HeaderBytes:
    result.status = INVALID_INPUT
    result.errorKind = ERR_TRUNCATED_HEADER
    result.errorCode = "truncated_header"
    result.message = "Input is shorter than 268-byte BCP1 header"
    return result

  if encoded.len > MaxEncodedFileBytes:
    result.status = INVALID_INPUT
    result.errorKind = ERR_PAYLOAD_LIMIT
    result.errorCode = "encoded_file_too_large"
    result.message = "Encoded input exceeds 2097420 bytes"
    return result

  if encoded[0] != uint8('B') or encoded[1] != uint8('C') or
     encoded[2] != uint8('P') or encoded[3] != uint8('1'):
    result.status = INVALID_INPUT
    result.errorKind = ERR_INVALID_MAGIC
    result.errorCode = "invalid_magic"
    result.message = "Header magic must be BCP1"
    return result

  let decodedLen = readLe32(encoded, 4)
  let meaningfulBits = readLe32(encoded, 8)

  if decodedLen > uint32(MaxDecodedPayloadBytes) or meaningfulBits > uint32(MaxMeaningfulBits):
    result.status = INVALID_INPUT
    result.errorKind = ERR_PAYLOAD_LIMIT
    result.errorCode = "header_limit_exceeded"
    result.message = "Decoded length or meaningful bit count exceeds format bounds"
    return result

  var lengths: array[256, uint8]
  for s in 0 .. 255:
    let L = encoded[12 + s]
    if L > uint8(MaxCodeLengthLimit):
      result.status = INVALID_INPUT
      result.errorKind = ERR_INVALID_CODE_LENGTH
      result.errorCode = "invalid_code_length"
      result.message = "Code length exceeds 16"
      return result
    lengths[s] = L

  var activeCount = 0
  if not validateCodeLengths(lengths, activeCount):
    result.status = INVALID_INPUT
    result.errorKind = ERR_INVALID_KRAFT_SUM
    result.errorCode = "invalid_kraft_sum"
    result.message = "Code lengths violate complete prefix-tree Kraft identity"
    return result

  let expectedPayloadBytes = int((meaningfulBits + 7'u32) shr 3)
  if encoded.len != Bcp1HeaderBytes + expectedPayloadBytes:
    result.status = INVALID_INPUT
    result.errorKind = ERR_BYTE_LENGTH_MISMATCH
    result.errorCode = "byte_length_mismatch"
    result.message = "Encoded byte length does not match meaningful_bits"
    return result

  let unusedBits = (8 - int(meaningfulBits and 7'u32)) and 7
  if unusedBits > 0 and expectedPayloadBytes > 0:
    let lastByte = encoded[encoded.len - 1]
    let mask = uint8((1 shl unusedBits) - 1)
    if (lastByte and mask) != 0'u8:
      result.status = INVALID_INPUT
      result.errorKind = ERR_NONZERO_PADDING
      result.errorCode = "nonzero_padding_bits"
      result.message = "Unused low padding bits in final byte must be zero"
      return result

  if activeCount == 0:
    if decodedLen != 0'u32 or meaningfulBits != 0'u32:
      result.status = INVALID_INPUT
      result.errorKind = ERR_DECODED_LENGTH_MISMATCH
      result.errorCode = "empty_alphabet_nonzero_length"
      result.message = "Empty alphabet requires zero decoded_length and meaningful_bits"
      return result
    result.status = COMPLETE
    result.errorKind = DECODE_OK
    result.decoded = @[]
    return result

  var dummyFreqs: array[256, int64]
  let assigned = assignCanonicalCodes(lengths, dummyFreqs)
  if not assigned.ok:
    result.status = INVALID_INPUT
    result.errorKind = ERR_INVALID_KRAFT_SUM
    result.errorCode = "canonical_tree_error"
    result.message = "Unable to construct canonical tree"
    return result

  # Build explicit binary trie for decoding
  type TrieNode = object
    left: int
    right: int
    sym: int

  var trie: seq[TrieNode] = @[TrieNode(left: -1, right: -1, sym: -1)]
  for s in 0 .. 255:
    let L = int(lengths[s])
    if L > 0:
      let code = assigned.codes[s]
      var curr = 0
      for shift in countdown(L - 1, 0):
        let bit = (code shr shift) and 1'u16
        if bit == 0'u16:
          if trie[curr].left == -1:
            trie[curr].left = trie.len
            trie.add(TrieNode(left: -1, right: -1, sym: -1))
          curr = trie[curr].left
        else:
          if trie[curr].right == -1:
            trie[curr].right = trie.len
            trie.add(TrieNode(left: -1, right: -1, sym: -1))
          curr = trie[curr].right
      trie[curr].sym = s

  var outDecoded = newSeqOfCap[uint8](int(decodedLen))
  var curr = 0
  var ops = 0

  for bitIdx in 0'u32 ..< meaningfulBits:
    inc ops
    if ops > budget.maxOperations * 20:
      result.status = UNKNOWN_BUDGET
      result.errorKind = ERR_UNKNOWN_BUDGET
      result.errorCode = "decode_budget_exceeded"
      result.message = "Decode operation budget exceeded"
      return result

    let byteIdx = Bcp1HeaderBytes + int(bitIdx shr 3)
    let bitShift = 7 - int(bitIdx and 7'u32)
    let bit = (encoded[byteIdx] shr bitShift) and 1'u8

    curr = (if bit == 0'u8: trie[curr].left else: trie[curr].right)
    if curr == -1:
      result.status = INVALID_INPUT
      result.errorKind = ERR_INCOMPLETE_CODEWORD
      result.errorCode = "invalid_codeword_walk"
      result.message = "Encountered invalid bit path in prefix tree"
      return result

    if trie[curr].sym >= 0:
      outDecoded.add(uint8(trie[curr].sym))
      curr = 0
      if outDecoded.len > int(decodedLen):
        result.status = INVALID_INPUT
        result.errorKind = ERR_DECODED_LENGTH_MISMATCH
        result.errorCode = "decoded_length_overflow"
        result.message = "Decoded symbols exceed declared decoded_length"
        return result

  if curr != 0:
    result.status = INVALID_INPUT
    result.errorKind = ERR_INCOMPLETE_CODEWORD
    result.errorCode = "incomplete_trailing_codeword"
    result.message = "Bitstream ended in the middle of a codeword"
    return result

  if uint32(outDecoded.len) != decodedLen:
    result.status = INVALID_INPUT
    result.errorKind = ERR_DECODED_LENGTH_MISMATCH
    result.errorCode = "decoded_length_mismatch"
    result.message = "Decoded byte count does not match header decoded_length"
    return result

  result.status = COMPLETE
  result.errorKind = DECODE_OK
  result.decoded = outDecoded
  result.operationsUsed = ops
  return result
