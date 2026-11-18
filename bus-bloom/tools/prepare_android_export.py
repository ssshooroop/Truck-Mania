"""Refresh Android resource roots, including resources loaded by constructed paths.

Keeps source assets intact. Run before Android export after adding content.
Godot adds transitive scene/script/resource dependencies to these explicit roots.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
roots = {"res://main.tscn", "res://assets/fonts/game_theme.tres"}
inputs = [ROOT / "project.godot"]
for folder in ("scripts", "scenes", "config"):
    inputs.extend(p for p in (ROOT / folder).rglob("*") if p.suffix in (".gd", ".tscn", ".tres", ".json"))
for p in inputs:
    content = p.read_text(encoding="utf-8-sig")
    for path in re.findall(r'res://[^"\n\r]+', content):
        if path.startswith(("res://assets/", "res://scenes/", "res://scripts/")) and (ROOT / path[6:]).is_file():
            roots.add(path)
    # Menu buttons, store products and reward icons use bare filenames.
    for name in re.findall(r'"([^"/]+\.png)"', content):
        candidate = ROOT / "assets/artwork/menu" / name
        if candidate.is_file():
            roots.add("res://" + candidate.relative_to(ROOT).as_posix())
for directory, pattern in (("assets/artwork/thief", "*.png"), ("assets/fonts/localization", "*.ttf")):
    for p in (ROOT / directory).rglob(pattern):
        roots.add("res://" + p.relative_to(ROOT).as_posix())
for weight in ("Medium", "Bold", "ExtraBold", "Black"):
    roots.add(f"res://assets/fonts/MPLUSRounded1c-{weight}.ttf")
# JSON is included as raw data by include_filter, not as a resource root.
roots = sorted(p for p in roots if not p.endswith(".json"))
preset = ROOT / "export_presets.cfg"
text = preset.read_text(encoding="utf-8-sig")
android, other = text.split("[preset.1]", 1)
android = android.replace('export_filter="all_resources"', 'export_filter="resources"')
android = re.sub(r'^export_files=.*\n', '', android, flags=re.M)
android = android.replace('export_filter="resources"', 'export_filter="resources"\nexport_files=PackedStringArray(' + ', '.join(json.dumps(p, ensure_ascii=False) for p in roots) + ')')
android = android.replace('architectures/x86_64=true', 'architectures/x86_64=false')
android = re.sub(r'package/name="[^"]*"', 'package/name="Truck Mania"', android)
android = android.replace('export_path="build/android/cargo-yard.apk"', 'export_path="build/android/truck-mania.apk"')
android = re.sub(r'exclude_filter="([^"]*)"', lambda m: 'exclude_filter="' + m[1] + ',build/*,web/*,export_templates/*,feature_profiles/*,script_templates/*,text_editor_themes/*,*.psd,*.blend,*.blend1,*.xlsx,*.zip,*.bak"', android) if 'build/*' not in android else android
preset.write_text(android + "[preset.1]" + other, encoding="utf-8")
out = ROOT / "build/android/resource-roots.json"
out.parent.mkdir(parents=True, exist_ok=True)
# Prevent nested checkouts and exported assets from polluting Godot's UID cache.
(ROOT / "build/.gdignore").touch(exist_ok=True)
out.write_text(json.dumps(roots, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Android ARM64: {len(roots)} resource roots; source art preserved.")
