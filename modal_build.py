"""Run the RMX1971 Axion build on Modal's free compute.

Usage:
    modal run modal_build.py

The build runs in a remote 32-core / 64 GiB / 500 GiB container. Artifacts and
the build log are saved to the Modal volume `axion-rmx1971-artifacts`; download
them with:
    modal volume ls axion-rmx1971-artifacts
    modal volume get axion-rmx1971-artifacts <filename> .
"""

import glob
import hashlib
import os
import shutil
import subprocess
import sys

import modal

app = modal.App("axion-rmx1971-build")

image = (
    modal.Image.from_registry("ubuntu:24.04", add_python="3.12")
    .apt_install(
        "git", "curl", "wget", "python3", "python3-pip", "unzip", "zip",
        "openssl", "rsync", "bc", "bison", "flex", "libssl-dev", "libelf-dev",
        "make", "gcc", "g++", "git-lfs", "openjdk-17-jdk-headless", "ccache",
        "libncurses-dev", "zlib1g-dev", "libxml2-utils", "xsltproc", "lzop",
        "ca-certificates",
    )
    .run_commands(
        "curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo "
        "-o /usr/local/bin/repo && chmod +x /usr/local/bin/repo",
        "git lfs install",
        "git config --global user.name 'Axion Builder' && "
        "git config --global user.email 'builder@axion.local'",
    )
)

volume = modal.Volume.from_name("axion-rmx1971-artifacts", create_if_missing=True)

RUN_URL = (
    "https://raw.githubusercontent.com/decrypt64bit/device_realme_RMX1971/"
    "axion-16/ci/run.sh"
)


@app.function(
    image=image,
    cpu=32,
    memory=65536,
    disk=500 * 1024,
    timeout=12 * 3600,
    volumes={"/artifacts": volume},
)
def build():
    os.makedirs("/workspace", exist_ok=True)
    os.chdir("/workspace")

    env = os.environ.copy()
    env["LANG"] = "C.UTF-8"
    env["LC_ALL"] = "C.UTF-8"
    env["USE_CCACHE"] = "0"

    cmd = f"curl -fsSL --retry 5 --retry-delay 5 {RUN_URL} | bash"
    log_path = "/workspace/build.log"
    with open(log_path, "w") as log:
        proc = subprocess.run(
            ["bash", "-c", cmd],
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
        )
    rc = proc.returncode

    outdir = "/workspace/out/target/product/RMX1971"
    copied = []
    for pattern in ("*.zip", "boot.img", "dtbo.img", "recovery.img", "vendor_boot.img"):
        for path in glob.glob(os.path.join(outdir, pattern)):
            dest = os.path.join("/artifacts", os.path.basename(path))
            try:
                shutil.copy2(path, dest)
                copied.append(dest)
            except OSError as exc:
                print(f"copy failed: {path}: {exc}")

    sums = []
    for dest in copied:
        if dest.endswith(".zip") or dest.endswith(".img"):
            h = hashlib.sha256()
            with open(dest, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    h.update(chunk)
            sums.append(f"{h.hexdigest()}  {os.path.basename(dest)}")
    if sums:
        with open("/artifacts/SHA256SUMS", "w") as fh:
            fh.write("\n".join(sums) + "\n")

    shutil.copy2(log_path, "/artifacts/build.log")
    volume.commit()

    print(f"BUILD_RC={rc}")
    print(f"ARTIFACTS={copied}")
    sys.exit(rc)


@app.local_entrypoint()
def main():
    build.remote()
