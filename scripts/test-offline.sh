#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORK_TMP="$(mktemp -d /tmp/bcp-test.XXXXXX)"
trap 'rm -rf "${WORK_TMP}"' EXIT

# 1. Compile the independent C11 BCP1 consumer ahead of test execution
gcc -std=c11 -O2 -Wall -Wextra "${PROJECT_ROOT}/tools/bcp1_c_consumer.c" -o "${WORK_TMP}/bcp1_c_consumer"
export BCP1_C_CONSUMER="${WORK_TMP}/bcp1_c_consumer"

# 2. Compile and run the native Nim unit, oracle, mutation & C-consumer test suite
nim c --path:"${PROJECT_ROOT}/src" --nimcache:"${WORK_TMP}/nimcache-test" \
    -o:"${WORK_TMP}/test_all" "${PROJECT_ROOT}/tests/test_all.nim"
"${WORK_TMP}/test_all"

# 3. Build the distributed CLI binary
mkdir -p "${PROJECT_ROOT}/dist"
nim c -d:release --path:"${PROJECT_ROOT}/src" --nimcache:"${WORK_TMP}/nimcache-cli" \
    -o:"${PROJECT_ROOT}/dist/bounded-canonical-prefix" "${PROJECT_ROOT}/src/cli.nim"

# 4. Compile an independent outside-checkout Nim consumer against the library
mkdir -p "${WORK_TMP}/consumer"
cat > "${WORK_TMP}/consumer/consumer.nim" <<'EOF'
import bounded_canonical_prefix

let payload = @[uint8(10), 20, 10, 30, 10, 20]
let enc = encodeBcp1(payload, 4)
doAssert enc.status == COMPLETE
let dec = decodeBcp1(enc.bytes)
doAssert dec.status == COMPLETE
doAssert dec.decoded == payload
EOF

nim c --path:"${PROJECT_ROOT}/src" --nimcache:"${WORK_TMP}/nimcache-consumer" \
    -o:"${WORK_TMP}/consumer/consumer_bin" "${WORK_TMP}/consumer/consumer.nim"
"${WORK_TMP}/consumer/consumer_bin"

# 5. Verify the distributed CLI encoder output with the independent C consumer
printf 'Outside-checkout CLI to C11 consumer verification payload 2026!' > "${WORK_TMP}/sample.bin"
"${PROJECT_ROOT}/dist/bounded-canonical-prefix" encode "${WORK_TMP}/sample.bin" "${WORK_TMP}/sample.bcp1" 8
"${WORK_TMP}/bcp1_c_consumer" "${WORK_TMP}/sample.bcp1" "${WORK_TMP}/sample.bin"
