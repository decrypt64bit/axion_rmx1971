#!/usr/bin/env python3
"""Replace Axion's hanging hostname entropy pipeline in build/make/envsetup.sh.

generate_host_overrides() runs
    ALPHA=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)
at source time, which can block indefinitely (observed on GitHub Actions and
likely the same shell behaviour elsewhere). openssl is already used one line
above for HEX, so use it for the suffix too.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/make/envsetup.sh")
text = path.read_text(encoding="utf-8", errors="surrogateescape")
old = "ALPHA=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)"
new = "ALPHA=$(openssl rand -hex 2)"
if old not in text:
    if new in text:
        print("envsetup already patched:", path)
        sys.exit(0)
    print("ERROR: expected generate_host_overrides line not found in", path, file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new), encoding="utf-8", errors="surrogateescape")
print("patched", path)
