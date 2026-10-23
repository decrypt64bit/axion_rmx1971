#!/usr/bin/env bash
# AxionOS full pipeline for RMX1971 on Crave: sync then build.
set -euo pipefail

BASE="https://raw.githubusercontent.com/decrypt64bit/device_realme_RMX1971/axion-16/ci"

echo "=== AXION PIPELINE START $(date -u) ==="
curl -fsSL "$BASE/sync.sh" | bash
curl -fsSL "$BASE/build.sh" | bash
echo "=== AXION PIPELINE DONE $(date -u) ==="
