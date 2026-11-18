"""Choose launcher artwork before building: python tools/select_app_icon.py billy|truck.

Changes only icon settings; keeps package name, signing and player saves intact.
Original artwork is used without modification.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICONS = {
    "billy": "icon512.png",
    "truck": "Orange Truck Carrying Blue Pipes.png",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("variant", choices=ICONS)
    args = parser.parse_args()
    icon = "res://assets/artwork/store icon/" + ICONS[args.variant]
    if not (ROOT / icon[6:]).is_file():
        raise FileNotFoundError(icon)
    project = ROOT / "project.godot"
    text = project.read_text(encoding="utf-8-sig")
    text, count = re.subn(r'^config/icon=.*$', 'config/icon="' + icon + '"', text, flags=re.M)
    if count != 1:
        raise ValueError("Expected one application icon setting")
    project.write_text(text, encoding="utf-8")
    presets = ROOT / "export_presets.cfg"
    text = presets.read_text(encoding="utf-8-sig")
    # Explicit launcher icon for both APK and AAB. Godot supplies its adaptive
    # fallback from the project icon when separate adaptive layers are absent.
    for index in (0, 3):
        header = f"[preset.{index}.options]"
        if header not in text:
            continue
        start = text.index(header) + len(header)
        end = text.find("\n[preset.", start)
        if end == -1:
            end = len(text)
        section = text[start:end]
        section = re.sub(r'^launcher_icons/main_192x192=.*\n?', '', section, flags=re.M)
        section = '\nlauncher_icons/main_192x192="' + icon + '"\n' + section.lstrip('\n')
        text = text[:start] + section + text[end:]
    presets.write_text(text, encoding="utf-8")
    print(f"App icon selected: {args.variant} ({icon})")


if __name__ == "__main__":
    main()
