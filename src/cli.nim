## CLI entry point for Bounded Canonical Prefix.

import std/[os, strutils]
import bounded_canonical_prefix
import ../tests/test_all

proc main() =
  let args = commandLineParams()
  if args.len == 0 or "--help" in args or "-h" in args:
    echo "Bounded Canonical Prefix v0.1.0 - Package-Merge & BCP1 Codec"
    echo "Usage:"
    echo "  bounded-canonical-prefix demo [--assert] [--json]"
    echo "  bounded-canonical-prefix encode <input.bin> <output.bcp1> [<max_len>]"
    echo "  bounded-canonical-prefix decode <input.bcp1> <output.bin>"
    quit(0)

  let cmd = args[0]
  if cmd == "demo":
    let doAssert = "--assert" in args
    let asJson = "--json" in args
    let cBin = getEnv("BCP1_C_CONSUMER", "")
    let testsOk = runAllBcpTests(cBin)
    let oracleRes = runSmallAlphabetOracleSuite()
    if doAssert and (not testsOk or not oracleRes.passed):
      stderr.writeLine("Demo assertions failed")
      quit(1)

    let sampleText = "LOFRANO_TECNOLOGIA_PACKAGE_MERGE_BCP1_DEMO_2026"
    var raw = newSeq[uint8](sampleText.len)
    for i, c in sampleText:
      raw[i] = uint8(c)
    let enc = encodeBcp1(raw, 6)
    let dec = decodeBcp1(enc.bytes)
    if enc.status != COMPLETE or dec.status != COMPLETE or dec.decoded != raw:
      stderr.writeLine("Demo encode/decode verification failed")
      quit(1)

    if asJson:
      echo "{\"status\":\"PASS\",\"oracle_cases\":" & $oracleRes.checkedCases &
           ",\"sample_decoded_bytes\":" & $enc.decodedLength &
           ",\"sample_meaningful_bits\":" & $enc.meaningfulBits &
           ",\"sample_encoded_bytes\":" & $enc.bytes.len & "}"
    else:
      echo "PASS status=COMPLETE oracle_cases=" & $oracleRes.checkedCases &
           " decoded_bytes=" & $enc.decodedLength &
           " meaningful_bits=" & $enc.meaningfulBits &
           " encoded_bytes=" & $enc.bytes.len
    quit(0)

  elif cmd == "encode":
    if args.len < 3:
      stderr.writeLine("Usage: bounded-canonical-prefix encode <in> <out> [<max_len>]")
      quit(2)
    let maxLen = (if args.len >= 4: parseInt(args[3]) else: 16)
    let dataStr = readFile(args[1])
    var raw = newSeq[uint8](dataStr.len)
    for i, ch in dataStr:
      raw[i] = uint8(ch)
    let enc = encodeBcp1(raw, maxLen)
    if enc.status != COMPLETE:
      stderr.writeLine("Encode failed: " & $enc.status & " (" & enc.errorCode & ")")
      quit(1)
    var f = open(args[2], fmWrite)
    if enc.bytes.len > 0:
      discard f.writeBuffer(unsafeAddr enc.bytes[0], enc.bytes.len)
    f.close()
    echo "Encoded " & $enc.decodedLength & " bytes into " & $enc.bytes.len & " BCP1 bytes"
    quit(0)

  elif cmd == "decode":
    if args.len < 3:
      stderr.writeLine("Usage: bounded-canonical-prefix decode <in.bcp1> <out.bin>")
      quit(2)
    let encStr = readFile(args[1])
    var encBytes = newSeq[uint8](encStr.len)
    for i, ch in encStr:
      encBytes[i] = uint8(ch)
    let dec = decodeBcp1(encBytes)
    if dec.status != COMPLETE:
      stderr.writeLine("Decode failed: " & $dec.errorKind & " (" & dec.errorCode & ")")
      quit(1)
    var f = open(args[2], fmWrite)
    if dec.decoded.len > 0:
      discard f.writeBuffer(unsafeAddr dec.decoded[0], dec.decoded.len)
    f.close()
    echo "Decoded " & $dec.decoded.len & " bytes"
    quit(0)

  else:
    stderr.writeLine("Unknown command: " & cmd)
    quit(2)

when isMainModule:
  main()
