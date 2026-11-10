#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"
mkdir -p dist

if [ ! -x "dist/bounded-canonical-prefix" ]; then
    CACHE_TMP="$(mktemp -d /tmp/bcp-demo.XXXXXX)"
    trap 'rm -rf "${CACHE_TMP}"' EXIT
    nim c -d:release --path:src --nimcache:"${CACHE_TMP}" \
        -o:dist/bounded-canonical-prefix src/cli.nim
fi

if [ "$#" -eq 0 ]; then
    ./dist/bounded-canonical-prefix demo --assert
elif [ "$1" = "--assert" ] || [ "$1" = "--json" ]; then
    ./dist/bounded-canonical-prefix demo "$@"
else
    ./dist/bounded-canonical-prefix "$@"
fi
