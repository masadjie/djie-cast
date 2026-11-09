#!/usr/bin/env python3
"""i18n/en.json (Indonesian text -> English) -> <app>/Contents/Resources/{en,id}.lproj/Localizable.strings"""
import json, pathlib, sys
res = pathlib.Path(sys.argv[1])
esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
src = pathlib.Path(__file__).resolve().parent.parent / "i18n" / "en.json"
en = json.loads(src.read_text(encoding="utf-8"))
for lang, table in (("en", en), ("id", {})):
    d = res / f"{lang}.lproj"
    d.mkdir(parents=True, exist_ok=True)
    body = "".join(f'"{esc(k)}" = "{esc(v)}";\n' for k, v in table.items())
    (d / "Localizable.strings").write_text(body or "/* Indonesian is the source language */\n", encoding="utf-8")
print(f"strings: {len(en)} English entries")
