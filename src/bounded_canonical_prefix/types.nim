## Core types and constants for Bounded Canonical Prefix (v0.1.0).

const
  MaxSymbolFrequency* = 1_099_511_627_776'i64      ## 2^40
  MaxTotalFrequency* = 281_474_976_710_656'i64     ## 2^48
  MinCodeLengthLimit* = 1
  MaxCodeLengthLimit* = 16
  MaxDecodedPayloadBytes* = 1_048_576              ## 1 MiB
  MaxMeaningfulBits* = 16_777_216                  ## 16 MiB bits
  Bcp1HeaderBytes* = 268                           ## 4 + 4 + 4 + 256
  MaxEncodedFileBytes* = 2_097_420                 ## 268 + 2_097_152
  DefaultMaxPackageNodes* = 65_536
  DefaultMaxOperations* = 1_000_000

type
  BcpStatus* = enum
    COMPLETE = "COMPLETE"
    INFEASIBLE_ALPHABET = "INFEASIBLE_ALPHABET"
    INVALID_INPUT = "INVALID_INPUT"
    UNKNOWN_BUDGET = "UNKNOWN_BUDGET"

  DecodeErrorKind* = enum
    DECODE_OK = "DECODE_OK"
    ERR_TRUNCATED_HEADER = "ERR_TRUNCATED_HEADER"
    ERR_INVALID_MAGIC = "ERR_INVALID_MAGIC"
    ERR_PAYLOAD_LIMIT = "ERR_PAYLOAD_LIMIT"
    ERR_INVALID_CODE_LENGTH = "ERR_INVALID_CODE_LENGTH"
    ERR_INVALID_KRAFT_SUM = "ERR_INVALID_KRAFT_SUM"
    ERR_BYTE_LENGTH_MISMATCH = "ERR_BYTE_LENGTH_MISMATCH"
    ERR_NONZERO_PADDING = "ERR_NONZERO_PADDING"
    ERR_INCOMPLETE_CODEWORD = "ERR_INCOMPLETE_CODEWORD"
    ERR_DECODED_LENGTH_MISMATCH = "ERR_DECODED_LENGTH_MISMATCH"
    ERR_UNKNOWN_BUDGET = "ERR_UNKNOWN_BUDGET"

  BcpBudget* = object
    maxNodes*: int
    maxOperations*: int

  CodebookEntry* = object
    symbol*: uint8
    freq*: int64
    bitLength*: uint8
    canonicalCode*: uint16

  CodebookResult* = object
    status*: BcpStatus
    errorCode*: string
    message*: string
    maxLen*: int
    symbolCount*: int
    weightedCost*: int64
    lengths*: array[256, uint8]
    codes*: array[256, uint16]
    entries*: seq[CodebookEntry]
    nodesUsed*: int
    operationsUsed*: int

  EncodeResult* = object
    status*: BcpStatus
    errorCode*: string
    message*: string
    bytes*: seq[uint8]
    codebook*: CodebookResult
    meaningfulBits*: uint32
    decodedLength*: uint32

  DecodeResult* = object
    status*: BcpStatus
    errorKind*: DecodeErrorKind
    errorCode*: string
    message*: string
    decoded*: seq[uint8]
    operationsUsed*: int

proc defaultBudget*(): BcpBudget =
  BcpBudget(
    maxNodes: DefaultMaxPackageNodes,
    maxOperations: DefaultMaxOperations
  )

proc checkedAddInt64*(a, b: int64, limit: int64, ok: var bool): int64 =
  if a < 0 or b < 0 or a > limit or b > limit - a:
    ok = false
    return 0
  ok = true
  return a + b
