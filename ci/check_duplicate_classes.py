#!/usr/bin/env python3
"""Fail if two files in Settings' compiled source set declare the same top-level class.

Settings compiles src/ plus the VendorSupport and Personalizations symlinks. A
class provided by more than one of those trees is a javac/kapt duplicate error
that otherwise only appears deep into the build.
"""
import pathlib
import re
import sys

ws = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
settings = ws / "packages" / "apps" / "Settings"
roots = [settings / "src", settings / "VendorSupport", settings / "Personalizations"]

pkg_re = re.compile(r"^\s*package\s+([\w.]+)", re.M)
decl_re = re.compile(
    r"^(?:(?:public|protected|private|final|abstract|open|sealed|data|enum|"
    r"annotation|internal|value)\s+)*(?:class|interface|object)\s+(\w+)",
    re.M,
)

classes = {}
seen = set()
for root in roots:
    if not root.exists():
        print(f"WARN: source root missing: {root}")
        continue
    for path in root.rglob("*"):
        if path.suffix not in (".java", ".kt"):
            continue
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        text = real.read_text(encoding="utf-8", errors="replace")
        m = pkg_re.search(text)
        pkg = m.group(1) if m else ""
        for name in decl_re.findall(text):
            fq = f"{pkg}.{name}" if pkg else name
            classes.setdefault(fq, []).append(str(path))

dups = {k: v for k, v in classes.items() if len(v) > 1}
if dups:
    for fq, files in sorted(dups.items()):
        print(f"DUPLICATE: {fq}")
        for f in files:
            print(f"  {f}")
    sys.exit(1)
print(f"no duplicate classes ({len(classes)} top-level classes scanned)")
