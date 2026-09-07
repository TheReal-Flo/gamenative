#!/usr/bin/env bash
# Linux host test; Android handle functions are replaced only in this test build.
set -eu
repository="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repository/app/build/xr-retirement-test"
g++ -std=c++17 -pthread -Wall -Wextra -Werror     -I "$repository/tools/tests/xr-retirement"     "$repository/tools/tests/xr-retirement/retirement.cpp"     "$repository/app/src/main/cpp/xrimmersive/xr_windows_transport.cpp"     -o "$repository/app/build/xr-retirement-test/test"
"$repository/app/build/xr-retirement-test/test"
