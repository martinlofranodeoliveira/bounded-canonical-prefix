## Independent exhaustive length-assignment oracle for small alphabets (n <= 6, L <= 5).
## Does not use package-merge; enumerates all integer length tuples (l_1..l_n) in 1..L
## satisfying Kraft equality sum 2^(L - l_i) == 2^L.

import types
import package_merge

proc bruteForceMinWeightedCost*(freqs: seq[int64], maxLen: int): int64 =
  let n = freqs.len
  if n == 0:
    return 0'i64
  if n == 1:
    return freqs[0]

  let targetKraft = 1 shl maxLen
  var bestCost = high(int64)
  var curLengths = newSeq[int](n)

  proc search(idx: int, currentKraft: int, currentCost: int64) =
    if idx == n:
      if currentKraft == targetKraft and currentCost < bestCost:
        bestCost = currentCost
      return
    let remaining = n - idx
    # Even if all remaining lengths are maxLen (each contributing 1), we need currentKraft + remaining <= targetKraft
    if currentKraft + remaining > targetKraft:
      return
    # Even if all remaining lengths are 1 (each contributing 2^(maxLen-1)), we need currentKraft + remaining * 2^(maxLen-1) >= targetKraft
    if currentKraft + remaining * (1 shl (maxLen - 1)) < targetKraft:
      return

    for L in 1 .. maxLen:
      let kAdd = 1 shl (maxLen - L)
      if currentKraft + kAdd <= targetKraft:
        curLengths[idx] = L
        search(idx + 1, currentKraft + kAdd, currentCost + freqs[idx] * int64(L))

  search(0, 0, 0'i64)
  return bestCost

proc runSmallAlphabetOracleSuite*(): tuple[passed: bool, checkedCases: int] =
  let testVectors: seq[tuple[freqs: seq[int64], maxLen: int]] = @[
    (freqs: @[10'i64, 20'i64], maxLen: 1),
    (freqs: @[5'i64, 9'i64, 12'i64, 13'i64, 16'i64, 45'i64], maxLen: 3),
    (freqs: @[5'i64, 9'i64, 12'i64, 13'i64, 16'i64, 45'i64], maxLen: 4),
    (freqs: @[5'i64, 9'i64, 12'i64, 13'i64, 16'i64, 45'i64], maxLen: 5),
    (freqs: @[1'i64, 1'i64, 2'i64, 3'i64, 5'i64, 8'i64], maxLen: 3),
    (freqs: @[1'i64, 1'i64, 2'i64, 3'i64, 5'i64, 8'i64], maxLen: 4),
    (freqs: @[1'i64, 1'i64, 2'i64, 3'i64, 5'i64, 8'i64], maxLen: 5),
    (freqs: @[1'i64, 100'i64, 1000'i64, 10000'i64, 100000'i64], maxLen: 3),
    (freqs: @[7'i64, 7'i64, 7'i64, 7'i64, 7'i64], maxLen: 3),
    (freqs: @[3'i64, 14'i64, 15'i64, 92'i64, 65'i64, 35'i64], maxLen: 4)
  ]

  var count = 0
  for tv in testVectors:
    let expectedCost = bruteForceMinWeightedCost(tv.freqs, tv.maxLen)
    var fullFreqs: array[256, int64]
    for i, f in tv.freqs:
      fullFreqs[i] = f
    let cb = buildCanonicalCodebook(fullFreqs, tv.maxLen)
    if cb.status != COMPLETE or cb.weightedCost != expectedCost:
      return (false, count)
    inc count

  return (true, count)
