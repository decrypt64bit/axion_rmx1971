#!/usr/bin/env bash
# Run from the workspace root. Exercises envsetup -> keys -> lunch with phase
# markers so a hang can be attributed to a phase, then asserts the Axion layer.
set +u

st() { echo "PHASE $1 $(date -u +%H:%M:%S)"; }
st envsetup:start
source build/envsetup.sh
echo "PHASE envsetup:done $(date -u +%H:%M:%S)"

st keys:start
gk -s
echo "PHASE keys:done $(date -u +%H:%M:%S)"

st lunch:start
(
    sleep 1200
    echo "PHASE lunch:watchdog-20min $(date -u +%H:%M:%S)"
) &
WATCHDOG=$!
axion RMX1971 userdebug va
RC=$?
kill "$WATCHDOG" 2>/dev/null || true
echo "PHASE lunch:done $(date -u +%H:%M:%S) rc=$RC"
[ "$RC" -eq 0 ] || exit "$RC"

st vars:start
timeout --signal=KILL 300 get_build_var TARGET_PRODUCT
timeout --signal=KILL 300 get_build_var TARGET_DEVICE
timeout --signal=KILL 300 get_build_var PRODUCT_SHIPPING_API_LEVEL
timeout --signal=KILL 900 get_build_var PRODUCT_PACKAGES > /tmp/packages.txt

for pkg in AxionParts AxionFx AxionIntelligence; do
    if grep -qw "$pkg" /tmp/packages.txt; then
        echo "OK: $pkg in PRODUCT_PACKAGES"
    else
        echo "FAIL: $pkg missing from PRODUCT_PACKAGES"
        exit 1
    fi
done
timeout --signal=KILL 300 get_build_var PRODUCT_SOONG_NAMESPACES | tr ' ' '\n' | grep -qx "device/axion/common" \
    || { echo "FAIL: device/axion/common namespace missing"; exit 1; }
echo "OK: Axion common applied to the product"
