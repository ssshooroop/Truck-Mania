"""Build a signed AppGallery APK with Unity Ads and verified Huawei purchases.

Production ad configuration is applied only during export and then restored.
This does not upload the APK or establish live ad availability/monetization.
Do not run concurrently with another export of this project.
"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "tools/android"
HUAWEI_PACKAGE = "org.truckmania.game.hw"


def check_configuration():
    settings = json.loads((ROOT / "config/huawei_iap.json").read_text(encoding="utf-8-sig"))
    if settings.get("package_name") != HUAWEI_PACKAGE:
        raise SystemExit(f"Huawei IAP configuration must belong to {HUAWEI_PACKAGE}.")
    app_id = settings.get("app_id", "")
    public_key = settings.get("public_key", "")
    if not isinstance(app_id, str) or not isinstance(public_key, str):
        raise SystemExit("The Huawei App ID and public IAP key must be JSON strings.")
    if not app_id or not public_key:
        missing = [label for value, label in ((app_id, "AppGallery App ID"), (public_key, "PUBLIC IAP key")) if not value]
        raise SystemExit(f"Huawei purchases are not configured: add {' and '.join(missing)} for {HUAWEI_PACKAGE} to config/huawei_iap.json. No release APK was built.")
    if not re.fullmatch(r"[1-9][0-9]{3,30}", app_id) or "PRIVATE" in public_key:
        raise SystemExit("Expected the numeric Huawei App ID and a PUBLIC IAP RSA key; never use a private key here.")
    from cryptography.hazmat.primitives.serialization import load_der_public_key
    from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey
    try:
        encoded = "".join(public_key.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").split())
        key = load_der_public_key(base64.b64decode(encoded, validate=True))
        if not isinstance(key, RSAPublicKey) or key.key_size < 2048:
            raise ValueError("Expected RSA 2048 or stronger")
    except (ValueError, TypeError):
        raise SystemExit("The public IAP key is invalid. Copy the complete public RSA key from AppGallery Connect.") from None
    products = json.loads((ROOT / "config/store_catalog.json").read_text(encoding="utf-8-sig"))["products"]
    mapping = settings.get("product_ids", {})
    if not isinstance(mapping, dict):
        raise SystemExit("product_ids must map game product IDs to AppGallery product IDs.")
    ids = [mapping.get(product["id"]) for product in products]
    if any(not isinstance(sku, str) or not sku or sku != sku.strip() for sku in ids) or len(set(ids)) != len(ids):
        raise SystemExit("Configure a unique AppGallery product ID for every item in store_catalog.json.")
    return settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output")
    parser.add_argument("--check-config", action="store_true", help="Validate local Huawei configuration without building.")
    args = parser.parse_args()
    check_configuration()
    if args.check_config:
        print("Huawei IAP public configuration is structurally valid; console activation still requires sandbox verification.")
        return
    subprocess.run([sys.executable, str(ROOT / "tools/prepare_android_export.py")], check=True)
    subprocess.run([sys.executable, str(ROOT / "tools/prepare_huawei_export.py")], check=True)
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
    preset = re.search(r"\[preset\.4\][\s\S]*?(?=\n\[preset\.\d+\]|\Z)", presets)[0]
    version_code = int(re.search(r"^version/code=(\d+)$", preset, re.M)[1])
    version_name = re.search(r'^version/name="([^"]+)"$', preset, re.M)[1]
    date_tag = datetime.now(timezone(timedelta(hours=3))).strftime("%Y%m%d")
    output = (ROOT / (args.output or f"build/android/store-{date_tag}/truck-mania-huawei-v{version_code}.apk")).resolve()
    if not output.is_relative_to(ROOT / "build") or output.suffix != ".apk":
        raise SystemExit("Output must be an .apk under this project build directory.")
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / "tools/build_ads_plugin.py")], check=True)
    subprocess.run([sys.executable, str(ROOT / "tools/build_huawei_iap_plugin.py")], check=True)
    credentials = json.loads((ANDROID / "signing/upload-credentials.json").read_text(encoding="utf-8-sig"))
    env = dict(os.environ, JAVA_HOME=str(next((ANDROID / "java").glob("jdk-*"))),
               ANDROID_HOME=str(ANDROID / "sdk"), ANDROID_SDK_ROOT=str(ANDROID / "sdk"),
               GRADLE_USER_HOME=str(ANDROID / "gradle-cache"),
               GRADLE_OPTS="-Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false",
               GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(ANDROID / "signing/truck-mania-upload.jks"),
               GODOT_ANDROID_KEYSTORE_RELEASE_USER=credentials["alias"],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=credentials["password"])
    ads_path = ROOT / "config/ads.json"
    info_path = ROOT / "config/build_info.json"
    originals = {path: path.read_bytes() for path in (ads_path, info_path)}
    ads = json.loads(originals[ads_path])
    ads["test_mode"] = False
    info = json.loads(originals[info_path])
    info.update(version=f"huawei-v{version_code}-{date_tag}", version_code=version_code,
                version_name=version_name, distribution="huawei_appgallery", ads_mode="live",
                package_name=HUAWEI_PACKAGE, iap_provider="huawei", unlock_all_levels=False)
    try:
        ads_path.write_text(json.dumps(ads, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        info_path.write_text(json.dumps(info, ensure_ascii=False) + "\n", encoding="utf-8")
        cmd = [str(ROOT.parent / "tools/Godot_v4.5.2-stable_win64_console.exe"),
               "--headless", "--quit", "--path", str(ROOT), "--export-release", "Android Huawei", str(output)]
        with (ROOT / "artifacts/huawei-build.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding="utf-8", errors="replace")
            for line in process.stdout:
                log.write(line.replace(credentials["password"], "<REDACTED>"))
                log.flush()
            status = process.wait()
        if status != 0:
            raise SystemExit(f"Huawei exporter failed with exit code {status}; see artifacts/huawei-build.log")
        if not output.is_file():
            raise SystemExit("Exporter did not create the requested APK.")
    finally:
        for path, content in originals.items():
            path.write_bytes(content)
    level_count = len(json.loads((ROOT / "config/campaign.json").read_text(encoding="utf-8-sig"))["levels"])
    subprocess.run([sys.executable, str(ROOT / "tools/verify_store_builds.py"),
                    "--apk", str(output), "--package-name", HUAWEI_PACKAGE,
                    "--require-huawei-iap", "--ads-mode", "live", "--production",
                    "--version-code", str(version_code), "--version-name", version_name,
                    "--expected-level-count", str(level_count),
                    "--output-dir", str(output.parent / f"verification/huawei-v{version_code}")], check=True, env=env)
    print("Verified Huawei APK:", output)


if __name__ == "__main__":
    main()
