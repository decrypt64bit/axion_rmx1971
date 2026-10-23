#!/usr/bin/env bash
# AxionOS build for Realme 5 Pro (RMX1971) on Crave.
# Run from the Crave project workspace root after sync.sh.
set -eo pipefail

echo "=== AXION BUILD START $(date -u) ==="
echo "PWD=$(pwd)"
df -h . | tail -1
echo "CPUS=$(nproc) MEM_GB=$(free -g | awk '/^Mem:/{print $2}')"

export LC_ALL=C
export TZ=UTC

echo "=== ENVSETUP ==="
set +u
source build/envsetup.sh
set -u

echo "=== KEYS ==="
gk -s

echo "=== LUNCH ==="
axion RMX1971 userdebug va

echo "=== SETTINGS PRECHECK ==="
set +u
m Settings
set -u
echo "=== SETTINGS PRECHECK OK ==="

echo "=== BUILD ==="
set +u
ax -br -j"$(nproc)"
set -u

echo "=== BUILD OUTPUT ==="
ls -lh out/target/product/RMX1971/*.zip
sha256sum out/target/product/RMX1971/*.zip

echo "=== AXION BUILD DONE $(date -u) ==="
