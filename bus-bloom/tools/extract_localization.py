"""Build translator inventories; never overwrite a translated PO file.

Run from any directory: python tools/extract_localization.py
This inventories current source; it does not enable runtime translation.
"""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "localization"
CYRILLIC = re.compile(r"[А-Яа-яЁё]")
TOKENS = re.compile(r'''\#.*?$|//[^\n]*$|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`''', re.M)
PLACEHOLDERS = re.compile(r"%(?:0?\d+)?[dsf]|\$\{[^}]+\}")
FORMATS = {"+%d %s", "%d:%02d", "+%d", "%02d", "%s  %s", "−100"}
ARCHIVE = {"crane_offer.gd", "parking_full.gd", "slot_unlock_mock.gd"}
entries = {}


def add(source, path, line, context, scope="current_source"):
    key = (scope, context, source)
    entry = entries.setdefault(key, {
        "id": context.replace("/", ".") + "." + hashlib.sha256(source.encode()).hexdigest()[:12],
        "source": source, "context": context, "scope": scope,
        "references": [], "placeholders": PLACEHOLDERS.findall(source),
        "translation": "", "notes": [],
    })
    ref = f"{path}:{line}"
    if ref not in entry["references"]:
        entry["references"].append(ref)
    if entry["placeholders"]:
        entry["notes"] = ["Сохранить переменные и их порядок. Не переводить выражения ${…}."]
    if "\n" in source:
        entry["notes"].append("В исходнике есть перенос строки; проверить ширину после перевода.")
    if source in {"монета", "монеты", "монет"}:
        entry["notes"].append("Форма русского множественного числа. При подключении нужен tr_n и правила целевого языка.")


for path in sorted((ROOT / "scripts").rglob("*.gd")) + [ROOT / "web/wasm-loader.js"]:
    content = path.read_text(encoding="utf-8-sig")
    rel = path.relative_to(ROOT).as_posix()
    for match in TOKENS.finditer(content):
        literal = match.group()
        if literal[0] not in "\"'`":
            continue
        value = literal[1:-1].replace(r"\n", "\n").replace(r'\"', '"').replace(r"\'", "'").replace(r"\\", "\\")
        if not (CYRILLIC.search(value) or value in FORMATS):
            continue
        if value.startswith(("res://", "user://")):
            continue
        scope = "legacy_or_mock" if path.name in ARCHIVE else "current_source"
        line = content.count("\n", 0, match.start()) + 1
        add(value, rel, line, path.relative_to(ROOT).with_suffix("").as_posix(), scope)


def walk(value, context, content, rel):
    if isinstance(value, dict):
        identity = value.get("id", "")
        for key, child in value.items():
            if key.startswith("_") or key == "counters":
                continue
            walk(child, context + "/" + str(identity or key) if identity else context + "/" + key, content, rel)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk(child, context + "/" + str(index), content, rel)
    elif isinstance(value, str) and CYRILLIC.search(value):
        encoded = json.dumps(value, ensure_ascii=False)
        offset = content.find(encoded)
        add(value, rel, content.count("\n", 0, offset) + 1, context, "configuration")


for name in ("achievements", "daily_rewards", "store_catalog", "seasonal_events"):
    path = ROOT / f"config/{name}.json"
    content = path.read_text(encoding="utf-8-sig")
    walk(json.loads(content), "config/" + name, content, path.relative_to(ROOT).as_posix())

OUT.mkdir(exist_ok=True)
catalog = sorted(entries.values(), key=lambda e: (e["scope"], e["context"], e["references"][0], e["source"]))
assert len({e["id"] for e in catalog}) == len(catalog), "ID collision"
(OUT / "catalog.ru.json").write_text(json.dumps({
    "source_locale": "ru", "runtime_connected": False,
    "description": "Инвентаризация текущих исходников. configuration — данные; legacy_or_mock — отдельная очередь. translation заполняется в копии файла.",
    "entries": catalog,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for scope, filename in (({"current_source", "configuration"}, "game.pot"), ({"legacy_or_mock"}, "legacy-mock.pot")):
    lines = ['# Cargo Yard translation template. Copy to <locale>.po before translating.', 'msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"MIME-Version: 1.0\\n"', '"Content-Transfer-Encoding: 8bit\\n"', '']
    for entry in catalog:
        if entry["scope"] not in scope:
            continue
        lines += ["#. " + entry["context"] + " [" + entry["scope"] + "]"]
        lines += ["#. " + note for note in entry["notes"]]
        lines += ["#: " + " ".join(entry["references"]),
                  "msgctxt " + json.dumps(entry["id"], ensure_ascii=False),
                  "msgid " + json.dumps(entry["source"], ensure_ascii=False), 'msgstr ""', '']
    (OUT / filename).write_text("\n".join(lines), encoding="utf-8")
print(json.dumps({"total": len(catalog), "by_scope": {scope: sum(e["scope"] == scope for e in catalog) for scope in sorted({e["scope"] for e in catalog})}}, ensure_ascii=False))
