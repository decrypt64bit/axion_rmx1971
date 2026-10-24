#!/usr/bin/env bash
# Preflight for the RMX1971 Axion build: validates manifest, forks, device config,
# resources and the new Settings classes without running a full AOSP build.
# usage: preflight.sh <workspace> <merged-manifest> <meta-repo>
set -euo pipefail

WS="${1:?workspace root}"
MERGED="${2:?merged manifest xml}"
META="${3:?meta repo root}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

DEV="$WS/device/realme/RMX1971"
SETTINGS="$WS/packages/apps/Settings"
FB="$WS/frameworks/base"
FACE="$WS/packages/apps/FaceUnlock"

echo "=== 1. script syntax ==="
for f in "$META"/ci/*.sh; do
    bash -n "$f" || fail "syntax error in $f"
done
for f in "$META"/ci/*.sh "$META"/ci/local_manifest.xml; do
    if grep -q $'\r' "$f"; then fail "CRLF line endings in $f"; fi
done
ok "scripts parse and use LF"

echo "=== 2. merged manifest ==="
python3 - "$MERGED" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
paths = {p.get('path') for p in root.findall('project')}
need = [
    'device/realme/RMX1971',
    'kernel/realme/sdm710',
    'vendor/realme/RMX1971',
    'packages/apps/FaceUnlock',
    'packages/apps/Settings',
    'frameworks/base',
]
missing = [n for n in need if n not in paths]
if missing:
    sys.exit('missing from merged manifest: %s' % missing)
print('all %d fork projects present in merged manifest' % len(need))
PY
ok "manifest"

echo "=== 3. synced fork commits ==="
test -d "$DEV/.git" || fail "device tree not synced"
test -d "$SETTINGS/.git" || fail "Settings not synced"
test -d "$FB/.git" || fail "frameworks/base not synced"
test -d "$FACE/.git" || fail "FaceUnlock not synced"

git -C "$SETTINGS" log --oneline -1 | grep -q "Restore missing Axion preferences" \
    || fail "Settings fork does not carry the restore commit"
git -C "$FB" log --oneline -1 | grep -q "pass the changed setting key" \
    || fail "frameworks/base fork does not carry the HBM key fix"
git -C "$FACE" log --oneline -3 | grep -q "replace analyzer frame pixels" \
    || fail "FaceUnlock fork does not carry the analyzer optimisation"
ok "fork commits"

echo "=== 4. Settings files and resources ==="
test -f "$SETTINGS/src/com/android/settings/preferences/BasePreferenceFragment.kt" || fail "BasePreferenceFragment.kt missing"
test -f "$SETTINGS/src/com/android/settings/preferences/SecureSettingSeekBarPreference.java" || fail "SecureSettingSeekBarPreference.java missing"
test -f "$SETTINGS/src/com/android/settings/security/PowerOffVerify.java" || fail "PowerOffVerify.java missing"
test -f "$SETTINGS/res/xml/hbm_settings.xml" || fail "hbm_settings.xml missing"
grep -q "auto_hbm_lux_on" "$SETTINGS/res/xml/hbm_settings.xml" || fail "hbm_settings.xml lost the lux preference"
grep -q "HbmSettingsPreferenceController" "$SETTINGS/res/xml/display_settings.xml" || fail "HBM entry not in display settings"
grep -q "class Hbm : BasePreferenceFragment(R.xml.hbm_settings)" "$SETTINGS/src/com/android/settings/display/Hbm.kt" || fail "Hbm fragment mismatch"
test -f "$SETTINGS/src/com/android/settings/applications/appinfo/AppsLocalePreferenceController.java" || fail "AppsLocalePreferenceController missing"
ok "Settings files"

python3 - "$SETTINGS" "$FB" <<'PY'
import os, re, sys, pathlib, xml.etree.ElementTree as ET
settings = pathlib.Path(sys.argv[1])
settingslib = pathlib.Path(sys.argv[2]) / 'packages' / 'SettingsLib'
xmls = [
    'res/xml/hbm_settings.xml',
    'res/xml/display_settings.xml',
    'res/xml/configure_notification_settings.xml',
    'res/xml/security_lockscreen_settings.xml',
    'res/xml/language_and_input.xml',
]
names = set()
roots = [settings / 'res', settings / 'res-product', settingslib]
for root in roots:
    if not root.is_dir():
        continue
    for dirpath, dirnames, filenames in os.walk(root):
        if os.path.basename(dirpath) != 'values' and not os.path.basename(dirpath).startswith('values-'):
            continue
        for fn in filenames:
            if not fn.endswith('.xml'):
                continue
            try:
                tree = ET.parse(os.path.join(dirpath, fn))
            except ET.ParseError as e:
                print('WARN: cannot parse %s: %s' % (os.path.join(dirpath, fn), e))
                continue
            names.update(a.get('name') for a in tree.getroot().iter() if a.get('name'))
missing = []
for rel in xmls:
    text = (settings / rel).read_text()
    for ref in set(re.findall(r'@string/([A-Za-z0-9_]+)', text)):
        if ref not in names:
            missing.append('%s: %s' % (rel, ref))
if missing:
    sys.exit('unresolved string refs: %s' % missing)
print('all string refs in %d xml files resolve (app + res-product + SettingsLib)' % len(xmls))
PY
ok "string resources"

echo "=== 5. device configuration ==="
grep -q "persist.sys.hbmservice_file=/sys/kernel/oppo_display/hbm" "$DEV/device.mk" || fail "HBM node property missing"
grep -q "TARGET_SHIPS_AXION_KERNEL_MODULES := false" "$DEV/BoardConfig.mk" || fail "kernel modules flag missing"
grep -q "TARGET_DISABLES_LIBPERF := false" "$DEV/lineage_RMX1971.mk" || fail "libperf flag missing"
grep -q "ax_kernel_manager.xml:\$(TARGET_COPY_OUT_SYSTEM_EXT)" "$DEV/device.mk" || fail "kernel manager system_ext copy missing"
grep -q "sysfs_oppo_display:file" "$DEV/sepolicy/vendor/system_server.te" || fail "HBM sepolicy missing"
grep -q "hal_health_default sysfs_battery_supply:file" "$DEV/sepolicy/vendor/hal_health_default.te" || fail "health HAL charging policy missing"
ok "device greps"

python3 - "$DEV" <<'PY'
import os, re, sys
dev = sys.argv[1]
mk = open(os.path.join(dev, 'device.mk')).read()
missing = []
seen = set()
for m in re.finditer(r'\$\(LOCAL_PATH\)/([^:\s\\]+):', mk):
    rel = m.group(1).strip()
    if rel in seen:
        continue
    seen.add(rel)
    if not os.path.exists(os.path.join(dev, rel)):
        missing.append(rel)
if missing:
    sys.exit('PRODUCT_COPY_FILES sources missing: %s' % missing)
print('all %d PRODUCT_COPY_FILES sources exist' % len(seen))
PY
ok "device copy files"

echo "=== 6. sepolicy types ==="
test -f "$WS/device/qcom/sepolicy_vndr/SEPolicy.mk" || fail "qcom sepolicy pickup (hardware/qcom-caf/common linkfile) missing"

type_defined() {
    local t="$1"
    for d in "$WS/system/sepolicy" "$WS/device/qcom/sepolicy_vndr" "$WS/device/lineage/sepolicy" "$DEV/sepolicy"; do
        [ -d "$d" ] || continue
        grep -rq "type $t," "$d" && return 0
    done
    return 1
}
for t in sysfs_battery_supply sysfs_devices_system_cpu sysfs_gpu sysfs_oppo_display; do
    type_defined "$t" || fail "type $t is not defined in system, qcom, lineage or device policy"
done
grep -rq "type hal_health_default, domain" "$WS/system/sepolicy" || fail "hal_health_default domain not defined"
ok "sepolicy types"

echo "=== 7. aapt2 compile ==="
AAPT2="$(find "${ANDROID_HOME:-/usr/local/lib/android/sdk}" -type f -name aapt2 2>/dev/null | sort | tail -1)"
[ -n "$AAPT2" ] || fail "aapt2 not found in the runner SDK"
OUT="$(mktemp -d)"
for f in hbm_settings display_settings configure_notification_settings security_lockscreen_settings language_and_input; do
    "$AAPT2" compile -o "$OUT" "$SETTINGS/res/xml/$f.xml" || fail "aapt2 compile failed: $f.xml"
done
ok "aapt2 compiled 5 xml files"

echo "=== 8. javac Settings preferences ==="
ANDROID_JAR="$(find "${ANDROID_HOME:-/usr/local/lib/android/sdk}/platforms" -name android.jar -type f 2>/dev/null | sort -V | tail -1)"
[ -n "$ANDROID_JAR" ] || fail "android.jar not found"
curl -fsSL https://dl.google.com/android/maven2/androidx/preference/preference/1.2.1/preference-1.2.1.aar -o /tmp/pref.aar || fail "androidx.preference download failed"
rm -rf /tmp/pref && mkdir -p /tmp/pref && unzip -q /tmp/pref.aar classes.jar -d /tmp/pref

# The SDK android.jar has no hidden APIs; the platform build compiles against
# framework.jar. Stub only what our files touch so javac still checks them.
STUBS=/tmp/stubs-src
rm -rf "$STUBS" /tmp/stubs && mkdir -p "$STUBS/android/os" "$STUBS/android/app/settings" \
    "$STUBS/com/android/settings" "$STUBS/androidx/fragment/app"
cat > "$STUBS/android/os/SystemProperties.java" <<'JAVA'
package android.os;
public class SystemProperties {
    public static String get(String key) { return null; }
    public static String get(String key, String def) { return def; }
    public static boolean getBoolean(String key, boolean def) { return def; }
    public static int getInt(String key, int def) { return def; }
    public static long getLong(String key, long def) { return def; }
    public static void set(String key, String val) { }
}
JAVA
cat > "$STUBS/android/app/settings/SettingsEnums.java" <<'JAVA'
package android.app.settings;
public final class SettingsEnums {
    public static final int SECURITY = 1;
}
JAVA
cat > "$STUBS/com/android/settings/R.java" <<'JAVA'
package com.android.settings;
public final class R {
    public static final class string {
        public static final int power_off_verify_title = 1;
        public static final int power_off_verify_summary = 2;
    }
    public static final class xml {
        public static final int hbm_settings = 3;
    }
}
JAVA
cat > "$STUBS/com/android/settings/SettingsPreferenceFragment.java" <<'JAVA'
package com.android.settings;
import android.content.Context;
import android.os.Bundle;
import androidx.preference.PreferenceManager;
import androidx.preference.PreferenceScreen;
public class SettingsPreferenceFragment {
    public void onCreate(Bundle savedInstanceState) { }
    public Context requireContext() { return null; }
    public PreferenceManager getPreferenceManager() { return null; }
    public void setPreferenceScreen(PreferenceScreen screen) { }
    public int getMetricsCategory() { return 0; }
}
JAVA
cat > "$STUBS/androidx/fragment/app/Fragment.java" <<'JAVA'
package androidx.fragment.app;
public class Fragment { }
JAVA
javac -proc:none -nowarn -cp "$ANDROID_JAR:/tmp/pref/classes.jar" -d /tmp/stubs \
    $(find "$STUBS" -name '*.java') || fail "stub compilation failed"

mkdir -p /tmp/javac-out
javac -proc:none -nowarn -cp "$ANDROID_JAR:/tmp/pref/classes.jar:/tmp/stubs" -d /tmp/javac-out \
    "$SETTINGS/src/com/android/settings/preferences/SecureSettingSwitchPreference.java" \
    "$SETTINGS/src/com/android/settings/preferences/SecureSettingSeekBarPreference.java" \
    "$SETTINGS/src/com/android/settings/preferences/SecureSettingListPreference.java" \
    "$SETTINGS/src/com/android/settings/preferences/SystemSettingSwitchPreference.java" \
    "$SETTINGS/src/com/android/settings/preferences/SystemPropertySwitchPreference.java" \
    "$SETTINGS/src/com/android/settings/security/PowerOffVerify.java" \
    || fail "javac failed for preference classes"
ok "javac (6 classes)"

echo "=== 9. kotlinc fragments ==="
curl -fsSL -o /tmp/kotlin.zip https://github.com/JetBrains/kotlin/releases/download/v2.0.21/kotlin-compiler-2.0.21.zip || fail "kotlinc download failed"
rm -rf /tmp/kotlinc && unzip -q /tmp/kotlin.zip -d /tmp/kotlinc
ANN=""
for u in \
    https://dl.google.com/android/maven2/androidx/annotation/annotation-jvm/1.8.0/annotation-jvm-1.8.0.jar \
    https://repo1.maven.org/maven2/androidx/annotation/annotation-jvm/1.8.0/annotation-jvm-1.8.0.jar; do
    if curl -fsSL "$u" -o /tmp/annotation.jar; then ANN=/tmp/annotation.jar; break; fi
done
[ -n "$ANN" ] || fail "androidx annotation jar not found"
/tmp/kotlinc/kotlinc/bin/kotlinc -nowarn -classpath "$ANDROID_JAR:/tmp/pref/classes.jar:$ANN:/tmp/stubs" \
    -d /tmp/kotlin-out \
    "$SETTINGS/src/com/android/settings/preferences/BasePreferenceFragment.kt" \
    "$SETTINGS/src/com/android/settings/display/Hbm.kt" \
    || fail "kotlinc failed for fragment classes"
ok "kotlinc (BasePreferenceFragment, Hbm)"

echo "=== 10. remote scripts and kernel ==="
for f in run.sh sync.sh build.sh local_manifest.xml; do
    curl -fsSL "https://raw.githubusercontent.com/decrypt64bit/device_realme_RMX1971/axion-16/ci/$f" -o "/tmp/$f" \
        || fail "cannot fetch $f from the device fork"
    cmp -s "/tmp/$f" "$META/ci/$f" || fail "$f in the release repo differs from the device fork"
done
test -f "$WS/development/tools/make_key" || fail "development/tools/make_key missing (gk cannot sign)"
git ls-remote https://github.com/decrypt64bit/android_kernel_mystralis mystralis-clean | grep -q . \
    || fail "kernel branch mystralis-clean not found"
curl -fsSL https://raw.githubusercontent.com/decrypt64bit/android_kernel_mystralis/mystralis-clean/arch/arm64/configs/sdm670-perf_defconfig -o /dev/null \
    || fail "kernel defconfig not found"
ok "remote scripts and kernel"

echo "=== PREFLIGHT PASSED ==="
