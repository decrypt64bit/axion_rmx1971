#!/usr/bin/env bash
# AxionOS full pipeline for RMX1971 on Crave: sync then build.
set -euo pipefail

BASE="https://raw.githubusercontent.com/decrypt64bit/device_realme_RMX1971/axion-16/ci"

fetch() {
    local url="$1" out="$2" i
    for i in 1 2 3 4 5; do
        if curl -fsSL "$url" -o "$out"; then
            return 0
        fi
        echo "fetch failed ($i/5): $url"
        sleep 10
    done
    return 1
}

echo "=== AXION PIPELINE START $(date -u) ==="
fetch "$BASE/sync.sh" /tmp/axion_sync.sh
bash /tmp/axion_sync.sh
fetch "$BASE/build.sh" /tmp/axion_build.sh
bash /tmp/axion_build.sh
echo "=== AXION PIPELINE DONE $(date -u) ==="
