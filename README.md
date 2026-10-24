# AxionOS 16 for Realme 5 Pro (RMX1971)

Android 16 build of [AxionOS](https://github.com/AxionAOSP) on the LineageOS 23.2 base, vanilla (no GMS) variant, for the Realme 5 Pro (RMX1971).

This repository holds the build pipeline, the local manifest that pins every source, and the release artifacts.

## Sources

| Component | Repository | Branch |
| --- | --- | --- |
| ROM manifest | [AxionAOSP/android](https://github.com/AxionAOSP/android) | `lineage-23.2` |
| Device tree | [decrypt64bit/device_realme_RMX1971](https://github.com/decrypt64bit/device_realme_RMX1971) | `axion-16` |
| Kernel | [decrypt64bit/android_kernel_mystralis](https://github.com/decrypt64bit/android_kernel_mystralis) | `mystralis-clean` |
| Vendor | [kaderbava/vendor_realme_RMX1971](https://gitlab.com/kaderbava/vendor_realme_RMX1971) | `16` |
| Face unlock | [decrypt64bit/android_packages_apps_AxFaceUnlock](https://github.com/decrypt64bit/android_packages_apps_AxFaceUnlock) | `axion-16` |
| Settings | [decrypt64bit/android_packages_apps_Settings](https://github.com/decrypt64bit/android_packages_apps_Settings) | `lineage-23.2` |
| Frameworks base | [decrypt64bit/android_frameworks_base](https://github.com/decrypt64bit/android_frameworks_base) | `axion-16-fix` |

Everything is pinned in [`ci/local_manifest.xml`](ci/local_manifest.xml).

## Device feature work

The device tree carries the integration work Axion needs on this platform:

- **High brightness mode** — kernel node `/sys/kernel/oppo_display/hbm` exposed through `persist.sys.ax_hbm_supp` / `persist.sys.ax_hbm_file`; `HbmService` is started by system server and the Settings screen (`hbm_settings.xml`) drives auto HBM with on/off lux thresholds. SELinux allows system server and init on the node.
- **Kernel manager (AxKM)** — `ax_kernel_manager.xml` for the two CPU policies and the KGSL devfreq block, shipped on both `vendor/etc` and `system_ext/etc` so the settings app and AxDiagnostics both find it.
- **Bypass charging** — the Lineage health HAL gets write access to the battery supply nodes; with the toggle provider it drives `mmi_charging_enable` at the configured limit.
- **Face unlock** — `AxFaceUnlock` with the analyzer path optimised (GPU/NNAPI, buffer reuse, anti-spoof only after a match).
- **Settings** — restored preference classes, the HBM screen, power-off verification, and the language entry point for this tree.

## Kernel policy

No kernel changes are made by this project. The kernel is used exactly as published on `mystralis-clean`. Any kernel change, if ever needed, is proposed for approval first and is not part of this tree.

## Building

The pipeline runs on [Crave](https://foss.crave.io) in a LineageOS 23.2 project workspace and is split into two steps so each gets its own job:

```bash
curl -fsSL https://raw.githubusercontent.com/decrypt64bit/device_realme_RMX1971/axion-16/ci/run.sh "|" bash
```

That script runs `ci/sync.sh` (repo init against the Axion manifest, install the local manifest, sync, verify the forked commits and device configuration) and then `ci/build.sh` (lunch `lineage_RMX1971`, build Settings as a precheck, then `ax -br`).

## Verification

A GitHub Actions preflight (`.github/workflows/preflight.yml`) runs before any long Crave build. It syncs the Axion manifest plus every forked project, applies the same fork and device checks as the Crave pipeline, compiles the touched XML resources with aapt2 and the new Settings classes with javac/kotlinc, then runs `lunch` and asserts that `AxionParts`, `AxThemePicker`, `AxThemeStore`, `EdgeLauncher` and `AxDiagnostics` are in `PRODUCT_PACKAGES` and that `device/axion/common` is in the Soong namespaces.

It also applies `ci/patch_envsetup.py`: Axion's `build/make/envsetup.sh` calls `generate_host_overrides` while being sourced, and its `cat /dev/urandom | tr | fold | head` pipeline can block indefinitely. The patch replaces that line with `openssl rand -hex 2`.

What the preflight cannot confirm: the full Soong/Ninja compile, image packaging and signing — those only happen in the real build.

## Releases

A release is published here once a build completes: the ROM zip, boot and dtbo images where applicable, and a SHA-256 manifest. Builds that are queued or still running are not published.

## Credits

AxionOS, LineageOS and the maintainers of the RMX1971 device, kernel and vendor trees.
