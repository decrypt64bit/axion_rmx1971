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
# Axion's envsetup runs setup_keys() at source time; on a clean tree that calls
# gk -s before lunch, and gk has no default for ANDROID_KEY_PATH. Provide it.
export ANDROID_KEY_PATH="$PWD/vendor/lineage-priv/keys"
mkdir -p "$ANDROID_KEY_PATH"
set +u
source build/envsetup.sh
set -u

echo "=== PRE-BUILD CHECKS ==="
for p in build/make/envsetup.sh device/realme/RMX1971/lineage_RMX1971.mk \
         vendor/realme/RMX1971/RMX1971-vendor.mk \
         kernel/realme/sdm710/arch/arm64/configs/sdm670-perf_defconfig; do
    [ -e "$p" ] || { echo "ERROR: missing $p"; exit 1; }
done
[ -d prebuilts/clang/host/linux-x86 ] || echo "WARN: prebuilts/clang/host/linux-x86 missing"
echo "TARGET_PRODUCT=$(get_build_var TARGET_PRODUCT) TARGET_BUILD_VARIANT=$(get_build_var TARGET_BUILD_VARIANT)"
df -h . | tail -1

echo "=== KEYS ==="
command -v openssl && openssl version || true
KEY_SUBJECT="/C=US/ST=California/L=Los Angeles/O=AxionOS/OU=AxionOS/CN=AxionOS"
if [ ! -f "$ANDROID_KEY_PATH/releasekey.pk8" ]; then
    # Axion's gk uses development/tools/make_key, whose named-pipe setup needs
    # mknod, which is not permitted in the Crave container. Generate the same
    # key set directly with openssl instead.
    for key in nfc bluetooth media networkstack platform releasekey sdk_sandbox shared testkey verifiedboot; do
        openssl genrsa 2048 > "$ANDROID_KEY_PATH/$key.pem" 2>/dev/null \
            && openssl req -new -x509 -sha256 -batch -key "$ANDROID_KEY_PATH/$key.pem" \
                 -out "$ANDROID_KEY_PATH/$key.x509.pem" -days 10000 -subj "$KEY_SUBJECT" \
            && openssl pkcs8 -in "$ANDROID_KEY_PATH/$key.pem" -topk8 -outform DER \
                 -out "$ANDROID_KEY_PATH/$key.pk8" -nocrypt \
            || { echo "ERROR: failed to generate $key"; exit 1; }
        rm -f "$ANDROID_KEY_PATH/$key.pem"
    done
    cat > "$ANDROID_KEY_PATH/keys.mk" <<EOF
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
PRODUCT_MAINLINE_SEPOLICY_DEV_CERTIFICATES := \$(dir \$(PRODUCT_DEFAULT_DEV_CERTIFICATE))
PRODUCT_MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES := \$(dir \$(PRODUCT_DEFAULT_DEV_CERTIFICATE))
EOF
    cat > "$ANDROID_KEY_PATH/BUILD.bazel" <<'EOF'
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
EOF
else
    echo "signing keys already present"
fi
PK8_COUNT=$(ls "$ANDROID_KEY_PATH"/*.pk8 2>/dev/null | wc -l)
PEM_COUNT=$(ls "$ANDROID_KEY_PATH"/*.x509.pem 2>/dev/null | wc -l)
echo "keys: pk8=$PK8_COUNT pem=$PEM_COUNT"
if [ "$PK8_COUNT" -ne 10 ] || [ "$PEM_COUNT" -ne 10 ] || [ ! -s "$ANDROID_KEY_PATH/releasekey.pk8" ] || [ ! -f "$ANDROID_KEY_PATH/keys.mk" ]; then
    echo "ERROR: signing key set incomplete"
    exit 1
fi

echo "=== LUNCH ==="
axion RMX1971 userdebug va

echo "=== SETTINGS PRECHECK ==="
set +u
m Settings || { echo "SETTINGS PRECHECK FAILED"; exit 1; }
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
