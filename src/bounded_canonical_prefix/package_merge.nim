## Deterministic Larmore-Hirschberg Package-Merge and Canonical Codebook Assignment.

import std/algorithm
import types

type
  ActiveSym = object
    symbol: uint8
    freq: int64

proc cmpActiveSym(a, b: ActiveSym): int =
  if a.freq != b.freq:
    return (if a.freq < b.freq: -1 else: 1)
  return cmp(int(a.symbol), int(b.symbol))

proc assignCanonicalCodes*(lengths: array[256, uint8], freqs: array[256, int64]): tuple[codes: array[256, uint16], entries: seq[CodebookEntry], cost: int64, ok: bool] =
  type SymLen = tuple[len: uint8, sym: uint8]
  var active: seq[SymLen] = @[]
  for s in 0 .. 255:
    if lengths[s] > 0:
      active.add((len: lengths[s], sym: uint8(s)))

  active.sort(proc(a, b: SymLen): int =
    if a.len != b.len:
      return cmp(int(a.len), int(b.len))
    return cmp(int(a.sym), int(b.sym))
  )

  var codes: array[256, uint16]
  var entries: seq[CodebookEntry] = @[]
  var totalCost = 0'i64
  var ok = true

  if active.len == 0:
    return (codes, entries, 0'i64, true)

  var currentCode = 0'u32
  var prevLen = int(active[0].len)

  for idx, item in active:
    let curLen = int(item.len)
    if idx > 0:
      currentCode = (currentCode + 1'u32) shl (curLen - prevLen)
      prevLen = curLen
    if currentCode >= (1'u32 shl curLen):
      ok = false
      return (codes, entries, 0'i64, false)
    codes[item.sym] = uint16(currentCode)
    let f = freqs[item.sym]
    let term = f * int64(curLen)
    totalCost = checkedAddInt64(totalCost, term, MaxTotalFrequency * 16'i64, ok)
    if not ok:
      return (codes, entries, 0'i64, false)
    entries.add(CodebookEntry(
      symbol: item.sym,
      freq: f,
      bitLength: item.len,
      canonicalCode: uint16(currentCode)
    ))

  return (codes, entries, totalCost, true)

proc buildCanonicalCodebook*(
  frequencies: array[256, int64],
  maxLen: int,
  budget: BcpBudget = defaultBudget()
): CodebookResult =
  result.maxLen = maxLen
  if maxLen < MinCodeLengthLimit or maxLen > MaxCodeLengthLimit:
    result.status = INVALID_INPUT
    result.errorCode = "invalid_max_length"
    result.message = "Maximum code length L must lie in 1..16"
    return result

  if budget.maxNodes <= 0 or budget.maxOperations <= 0:
    result.status = UNKNOWN_BUDGET
    result.errorCode = "budget_exhausted"
    result.message = "Non-positive package-merge budget"
    return result

  var active: seq[ActiveSym] = @[]
  var sumFreq = 0'i64
  var ops = 0

  for s in 0 .. 255:
    inc ops
    if ops > budget.maxOperations:
      result.status = UNKNOWN_BUDGET
      result.errorCode = "operations_budget_exceeded"
      result.message = "Operation limit exceeded during frequency scan"
      result.operationsUsed = ops
      return result

    let f = frequencies[s]
    if f < 0 or f > MaxSymbolFrequency:
      result.status = INVALID_INPUT
      result.errorCode = "invalid_symbol_frequency"
      result.message = "Symbol frequency must lie in 0..2^40"
      return result
    if f > 0:
      var addOk = false
      sumFreq = checkedAddInt64(sumFreq, f, MaxTotalFrequency, addOk)
      if not addOk:
        result.status = INVALID_INPUT
        result.errorCode = "frequency_sum_overflow"
        result.message = "Total frequency sum exceeds 2^48"
        return result
      active.add(ActiveSym(symbol: uint8(s), freq: f))

  let n = active.len
  result.symbolCount = n

  if n == 0:
    result.status = COMPLETE
    result.weightedCost = 0
    result.operationsUsed = ops
    return result

  if n > (1 shl maxLen):
    result.status = INFEASIBLE_ALPHABET
    result.errorCode = "infeasible_alphabet"
    result.message = "Positive-frequency symbol count exceeds 2^L"
    result.operationsUsed = ops
    return result

  if n == 1:
    let sym = active[0].symbol
    result.lengths[sym] = 1'u8
    result.codes[sym] = 0'u16
    result.weightedCost = active[0].freq
    result.entries = @[CodebookEntry(
      symbol: sym,
      freq: active[0].freq,
      bitLength: 1'u8,
      canonicalCode: 0'u16
    )]
    result.nodesUsed = 1
    result.operationsUsed = ops + 1
    result.status = COMPLETE
    return result

  active.sort(cmpActiveSym)
  ops += n
  if ops > budget.maxOperations:
    result.status = UNKNOWN_BUDGET
    result.errorCode = "operations_budget_exceeded"
    result.message = "Operation limit exceeded after sorting alphabet"
    result.operationsUsed = ops
    return result

  # Level-by-level package-merge
  # Store each level's items so we can trace back or accumulate leafmasks directly.
  #Wait: since each level only combines pairs from the previous level, each PmItem's
  # leaf counts can be stored directly in an array[256, uint8] or traced!
  # Storing `counts: seq[uint8]` of length `n` on each PmItem is tiny (at most 256 bytes per item)
  # and avoids any pointer indirection while giving exact per-symbol leaf counts in O(n)!
  type RichItem = object
    weight: int64
    isPackage: bool
    minSymbol: uint8
    counts: seq[uint8]

  proc cmpRich(a, b: RichItem): int =
    if a.weight != b.weight:
      return (if a.weight < b.weight: -1 else: 1)
    if a.isPackage != b.isPackage:
      return (if not a.isPackage: -1 else: 1)
    return cmp(int(a.minSymbol), int(b.minSymbol))

  var prevLevel: seq[RichItem] = @[]
  var totalNodes = 0

  for level in 1 .. maxLen:
    var packages: seq[RichItem] = @[]
    let pairCount = prevLevel.len div 2
    for p in 0 ..< pairCount:
      let left = prevLevel[2 * p]
      let right = prevLevel[2 * p + 1]
      var addOk = false
      let w = checkedAddInt64(left.weight, right.weight, MaxTotalFrequency * 32'i64, addOk)
      if not addOk:
        result.status = INVALID_INPUT
        result.errorCode = "package_weight_overflow"
        result.message = "Package weight overflow during package-merge"
        return result

      var mergedCounts = newSeq[uint8](n)
      for i in 0 ..< n:
        inc ops
        mergedCounts[i] = left.counts[i] + right.counts[i]
      if ops > budget.maxOperations:
        result.status = UNKNOWN_BUDGET
        result.errorCode = "operations_budget_exceeded"
        result.message = "Operation limit exceeded during package construction"
        result.nodesUsed = totalNodes
        result.operationsUsed = ops
        return result

      inc totalNodes
      if totalNodes > budget.maxNodes:
        result.status = UNKNOWN_BUDGET
        result.errorCode = "package_nodes_exceeded"
        result.message = "Package node limit exceeded"
        result.nodesUsed = totalNodes
        result.operationsUsed = ops
        return result

      packages.add(RichItem(
        weight: w,
        isPackage: true,
        minSymbol: min(left.minSymbol, right.minSymbol),
        counts: mergedCounts
      ))

    var leaves = newSeqOfCap[RichItem](n)
    for i in 0 ..< n:
      inc ops
      inc totalNodes
      if ops > budget.maxOperations:
        result.status = UNKNOWN_BUDGET
        result.errorCode = "operations_budget_exceeded"
        result.message = "Operation limit exceeded creating level leaves"
        result.nodesUsed = totalNodes
        result.operationsUsed = ops
        return result
      if totalNodes > budget.maxNodes:
        result.status = UNKNOWN_BUDGET
        result.errorCode = "package_nodes_exceeded"
        result.message = "Package node limit exceeded creating level leaves"
        result.nodesUsed = totalNodes
        result.operationsUsed = ops
        return result

      var c = newSeq[uint8](n)
      c[i] = 1'u8
      leaves.add(RichItem(
        weight: active[i].freq,
        isPackage: false,
        minSymbol: active[i].symbol,
        counts: c
      ))

    # Merge sorted leaves and sorted packages
    var curLevel = newSeqOfCap[RichItem](leaves.len + packages.len)
    var li = 0
    var pi = 0
    while li < leaves.len and pi < packages.len:
      inc ops
      if ops > budget.maxOperations:
        result.status = UNKNOWN_BUDGET
        result.errorCode = "operations_budget_exceeded"
        result.message = "Operation limit exceeded during level merge"
        result.nodesUsed = totalNodes
        result.operationsUsed = ops
        return result
      if cmpRich(leaves[li], packages[pi]) <= 0:
        curLevel.add(leaves[li])
        inc li
      else:
        curLevel.add(packages[pi])
        inc pi
    while li < leaves.len:
      inc ops
      curLevel.add(leaves[li])
      inc li
    while pi < packages.len:
      inc ops
      curLevel.add(packages[pi])
      inc pi

    prevLevel = curLevel

  let needed = 2 * n - 2
  if prevLevel.len < needed:
    result.status = INFEASIBLE_ALPHABET
    result.errorCode = "insufficient_packages"
    result.message = "Package-merge did not produce 2n - 2 items"
    return result

  for k in 0 ..< needed:
    for i in 0 ..< n:
      inc ops
      let sym = active[i].symbol
      result.lengths[sym] = result.lengths[sym] + prevLevel[k].counts[i]

  if ops > budget.maxOperations:
    result.status = UNKNOWN_BUDGET
    result.errorCode = "operations_budget_exceeded"
    result.message = "Operation limit exceeded during code-length extraction"
    result.nodesUsed = totalNodes
    result.operationsUsed = ops
    return result

  let assigned = assignCanonicalCodes(result.lengths, frequencies)
  if not assigned.ok:
    result.status = INVALID_INPUT
    result.errorCode = "canonical_assignment_failed"
    result.message = "Failed to assign valid canonical prefix codes"
    return result

  result.codes = assigned.codes
  result.entries = assigned.entries
  result.weightedCost = assigned.cost
  result.nodesUsed = totalNodes
  result.operationsUsed = ops
  result.status = COMPLETE
  return result
