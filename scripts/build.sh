#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
moon check --target js
moon build --target js --release
