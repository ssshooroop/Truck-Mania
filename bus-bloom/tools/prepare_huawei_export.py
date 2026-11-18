"""Maintain a separate AppGallery preset, preserving the Google Play package."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "org.truckmania.game.hw"


def prepare(version_code=None, version_name=None):
    path = ROOT / "export_presets.cfg"
    text = path.read_text(encoding="utf-8-sig")
    base = text.split("[preset.1]", 1)[0].strip()
    previous = re.search(r"\[preset\.4\][\s\S]*?(?=\n\[preset\.\d+\]|\Z)", text)
    previous_text = previous[0] if previous else ""
    old_code = re.search(r"^version/code=(\d+)$", previous_text, re.M)
    old_name = re.search(r'^version/name="([^"]+)"$', previous_text, re.M)
    code = version_code if version_code is not None else (int(old_code[1]) if old_code else 8)
    name = version_name or (old_name[1] if old_name else "0.1.3")
    huawei = base.replace("[preset.0]", "[preset.4]").replace("[preset.0.options]", "[preset.4.options]")
    values = {
        "name": '"Android Huawei"', "runnable": "false",
        "custom_features": '"huawei_appgallery"',
        "export_path": f'"build/android/truck-mania-huawei-v{code}.apk"',
        "package/unique_name": f'"{PACKAGE}"',
        "version/code": str(code), "version/name": f'"{name}"',
        "gradle_build/export_format": "0", "gradle_build/use_gradle_build": "true",
    }
    for key, value in values.items():
        pattern = r"^" + re.escape(key) + r"=.*$"
        if not re.search(pattern, huawei, re.M):
            raise RuntimeError(f"Android preset is missing {key}")
        huawei = re.sub(pattern, lambda _: key + "=" + value, huawei, flags=re.M)
    text = re.sub(r"\n?\[preset\.4\][\s\S]*?(?=\n\[preset\.\d+\]|\Z)", "", text)
    path.write_text(text.rstrip() + "\n\n" + huawei + "\n", encoding="utf-8")
    print(f"Huawei preset: {PACKAGE}, {name} ({code}), Huawei IAP enabled for this preset only.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version-code", type=int)
    parser.add_argument("--version-name")
    args = parser.parse_args()
    prepare(args.version_code, args.version_name)
