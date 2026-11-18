"""Validate signed store exports without uploading them or claiming live ad delivery.

With no artifact arguments, validates the Google Play closed-test bundle. Pass
--apk and/or --aab to validate other artifacts, and --ads-mode live only for a
build that is intended to use production ads. Signing passwords never appear
in command arguments or reports.
"""
import argparse
import base64
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "tools/android"
DEFAULT_OUTPUT = ROOT / "build/android/store-20261111"
PACKAGE = "org.truckmania.game"
HUAWEI_PACKAGE = "org.truckmania.game.hw"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
HUAWEI_PLUGIN = "org.godotengine.plugin.v2.TruckManiaIap"
HUAWEI_CLASS = "org.truckmania.iap.TruckManiaIap"
HUAWEI_APP_ID_METADATA = "com.huawei.hms.client.appid"
HUAWEI_DEX_MARKERS = (
    b"Lorg/truckmania/iap/TruckManiaIap;", b"Lorg/truckmania/iap/ReceiptVerifier;",
    b"Lcom/huawei/hms/iap/Iap;", b"Lcom/huawei/hms/iap/IapClient;",
)
GAME_ID = "800430064"
REWARDED = {
    "shortfall": "25_coins_level", "shop": "25_coins_store",
    "double": "double_reward", "slot": "open_slot", "undo": "undo",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_export_presets(text):
    """Check source preset boundaries without exporting or reading credentials."""
    config = configparser.ConfigParser(interpolation=None, delimiters=("=",), strict=True)
    config.optionxform = str
    config.read_string(text.lstrip("\ufeff"))
    presets = {}
    for section in config.sections():
        if not re.fullmatch(r"preset\.\d+", section):
            continue
        name = json.loads(config[section]["name"])
        require(name not in presets, f"Duplicate export preset name: {name}")
        presets[name] = (config[section], config[section + ".options"])
    result = {}
    for name, package, huawei, export_format in (
        ("Android", PACKAGE, False, "0"), ("Android AAB", PACKAGE, False, "1"),
        ("Android Huawei", HUAWEI_PACKAGE, True, "0"),
    ):
        require(name in presets, f"Missing export preset: {name}")
        preset, options = presets[name]
        features = {feature.strip() for feature in json.loads(preset.get("custom_features", '""')).split(",")}
        require(json.loads(options["package/unique_name"]) == package, f"{name}: wrong package identity")
        require(("huawei_appgallery" in features) == huawei, f"{name}: Huawei feature isolation failed")
        require(options["gradle_build/export_format"] == export_format, f"{name}: wrong Android export format")
        require(options["gradle_build/use_gradle_build"] == "true", f"{name}: SDK plugins require Gradle export")
        result[name] = {"package": package, "huawei_feature": huawei,
                        "format": "AAB" if export_format == "1" else "APK",
                        "version_code": int(options["version/code"]),
                        "version_name": json.loads(options["version/name"])}
    return result


def verify_package_badging(badging, package, version_code, version_name):
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']*)'", badging, re.M)
    require(match is not None and match.groups() == (package, str(version_code), version_name),
            "APK package or version mismatch")


def verify_package_manifest(document, package, version_code, version_name):
    require(document.get("package") == package and
            document.get(ANDROID_NS + "versionCode") == str(version_code) and
            document.get(ANDROID_NS + "versionName") == version_name,
            "AAB package or version mismatch")


def application_metadata(manifest):
    """Read literal application metadata from bundletool XML or aapt2 xmltree."""
    values = {}

    def add(name, value):
        if not name:
            return
        require(name not in values, f"Duplicate application metadata: {name}")
        values[name] = value

    if manifest.lstrip().startswith("<"):
        document = ET.fromstring(manifest)
        for node in document.findall("application/meta-data"):
            add(node.get(ANDROID_NS + "name"), node.get(ANDROID_NS + "value"))
        return values
    stack = []
    current = None
    for line in manifest.splitlines():
        element = re.match(r"^(\s*)E: ([\w-]+)\b", line)
        if element:
            indent, tag = len(element[1]), element[2]
            while stack and stack[-1][0] >= indent:
                stack.pop()
            if current is not None and indent <= current["indent"]:
                add(current.get("name"), current.get("value"))
                current = None
            if tag == "meta-data" and [item[1] for item in stack] == ["manifest", "application"]:
                current = {"indent": indent}
            stack.append((indent, tag))
            continue
        if current is not None:
            attribute = re.match(r'^\s*A: (?:http://schemas.android.com/apk/res/android:|android:)(name|value)(?:\([^)]*\))?="([^"]*)"', line)
            if attribute:
                current[attribute[1]] = attribute[2]
    if current is not None:
        add(current.get("name"), current.get("value"))
    return values


def verify_huawei_configuration(settings, catalog, package):
    require(package == HUAWEI_PACKAGE, "Huawei IAP checks require the separate Huawei package")
    require(isinstance(settings, dict) and settings.get("package_name") == package,
            "Packaged Huawei IAP configuration belongs to another package")
    app_id = settings.get("app_id")
    require(isinstance(app_id, str) and re.fullmatch(r"[0-9]+", app_id) is not None,
            "Packaged Huawei App ID must be a nonempty numeric string")
    public_key = settings.get("public_key")
    require(isinstance(public_key, str) and public_key.strip() and "PRIVATE" not in public_key,
            "Packaged Huawei IAP configuration requires a public RSA key")
    try:
        from cryptography.hazmat.primitives.serialization import load_der_public_key
        from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey
        encoded = "".join(public_key.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").split())
        der = base64.b64decode(encoded, validate=True)
        key = load_der_public_key(der)
        require(isinstance(key, RSAPublicKey) and key.key_size >= 2048, "Huawei IAP key must be RSA 2048 or stronger")
    except (ValueError, TypeError) as error:
        raise RuntimeError("Packaged Huawei IAP public key is invalid") from error
    require(isinstance(catalog, dict) and isinstance(catalog.get("products"), list) and catalog["products"],
            "Packaged store catalog is missing")
    mapping = settings.get("product_ids")
    require(isinstance(mapping, dict), "Packaged Huawei product mapping is missing")
    logical_ids = [product.get("id") for product in catalog["products"] if isinstance(product, dict)]
    require(len(logical_ids) == len(catalog["products"]) and
            all(isinstance(product_id, str) and product_id for product_id in logical_ids) and
            len(set(logical_ids)) == len(logical_ids), "Packaged catalog product IDs are invalid")
    ids = [mapping.get(product_id) for product_id in logical_ids]
    require(all(isinstance(product_id, str) and product_id.strip() for product_id in ids) and len(set(ids)) == len(ids),
            "Each packaged catalog product needs a unique Huawei product ID")
    return {"app_id": app_id, "registered_product_count": len(ids),
            "public_key_sha256": hashlib.sha256(der).hexdigest()}


def verify_iap_manifest(manifest, package, iap=None):
    metadata = application_metadata(manifest)
    if package == PACKAGE:
        require(HUAWEI_PLUGIN not in metadata and HUAWEI_APP_ID_METADATA not in metadata,
                "Huawei IAP manifest entries leaked into the Google Play package")
    if iap is not None:
        require(package == HUAWEI_PACKAGE, "Huawei IAP manifest requires the Huawei package")
        require(metadata.get(HUAWEI_PLUGIN) == HUAWEI_CLASS, "Huawei Godot IAP plugin registration is missing")
        require(metadata.get(HUAWEI_APP_ID_METADATA) == "appid=" + iap["app_id"],
                "Manifest Huawei App ID does not match packaged IAP configuration")


def verify_iap_content(asset, dex_data, info, package, required):
    present = {marker: any(marker in data for data in dex_data) for marker in HUAWEI_DEX_MARKERS}
    project = asset("project.binary")
    if package == PACKAGE:
        require(not any(present.values()) and b"huawei_appgallery" not in project,
                "Huawei native IAP or runtime feature leaked into the Google Play package")
    if not required:
        return None
    require(package == HUAWEI_PACKAGE, "--require-huawei-iap requires the Huawei package")
    require(all(present.values()), "Huawei IAP bridge, receipt verifier or HMS SDK is missing from DEX")
    require(b"huawei_appgallery" in project, "Huawei runtime export feature is missing from project.binary")
    require(info.get("package_name") == package and info.get("iap_provider") == "huawei" and
            info.get("distribution") == "huawei_appgallery", "Build metadata does not identify the Huawei IAP release")
    return verify_huawei_configuration(json.loads(asset("config/huawei_iap.json")),
                                       json.loads(asset("config/store_catalog.json")), package)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def elf_alignment(data, name):
    require(data[:4] == b"\x7fELF" and data[4] == 2 and data[5] == 1,
            f"{name}: expected a 64-bit little-endian ELF library")
    require(struct.unpack_from("<H", data, 18)[0] == 183,
            f"{name}: expected the ARM64 ELF machine type")
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", data, 54)
    require(phentsize >= 56, f"{name}: invalid ELF program header size")
    segments = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        require(offset + 56 <= len(data), f"{name}: truncated ELF program header")
        p_type, _, p_offset, p_vaddr, _, _, _, p_align = struct.unpack_from("<IIQQQQQQ", data, offset)
        if p_type != 1:  # PT_LOAD
            continue
        require(p_align >= 16384 and (p_offset - p_vaddr) % 16384 == 0,
                f"{name}: PT_LOAD segment {index} is not 16 KB compatible")
        segments.append(p_align)
    require(segments, f"{name}: no ELF load segments")
    return {"file": name, "load_segment_alignment_bytes": segments}


def inspect_archive(path, ads_mode, package=PACKAGE, require_huawei_iap=False):
    is_bundle = path.suffix.lower() == ".aab"
    prefix = "base/" if is_bundle else ""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), f"{path.name}: duplicate ZIP entries")
        def asset(name):
            # Godot puts AAB game content in the install-time asset pack.
            suffix = "assets/" + name
            matches = [entry for entry in names if entry == suffix or
                       (is_bundle and entry.endswith("/" + suffix))]
            require(len(matches) == 1, f"{path.name}: expected one packaged {name}")
            return archive.read(matches[0])

        config = json.loads(asset("config/ads.json"))
        require(config.get("test_mode") is (ads_mode == "test"),
                f"{path.name}: packaged test_mode does not match --ads-mode {ads_mode}")
        require(config.get("android_game_id") == GAME_ID, f"{path.name}: incorrect Unity Game ID")
        require(config.get("rewarded") == REWARDED, f"{path.name}: unexpected rewarded ad units")
        require(config.get("interstitial") == "BP_Interstitial_Android",
                f"{path.name}: unexpected interstitial ad unit")
        info = json.loads(asset("config/build_info.json"))
        require(isinstance(info, dict) and info.get("version"), f"{path.name}: missing build version metadata")
        native_names = [name for name in names if name.startswith(prefix + "lib/") and name.endswith(".so")]
        require(native_names, f"{path.name}: no native libraries")
        require(all(name.startswith(prefix + "lib/arm64-v8a/") for name in native_names),
                f"{path.name}: unexpected native architecture")
        native = [elf_alignment(archive.read(name), name) for name in native_names]
        dex_names = [name for name in names if name.endswith(".dex")]
        markers = {b"Lorg/truckmania/ads/TruckManiaAds;": False,
                   b"Lcom/unity3d/ads/UnityAds;": False}
        dex_data = []
        for name in dex_names:
            data = archive.read(name)
            dex_data.append(data)
            for marker in markers:
                markers[marker] |= marker in data
        require(all(markers.values()), f"{path.name}: ads bridge or Unity SDK missing from DEX")
        iap = verify_iap_content(asset, dex_data, info, package, require_huawei_iap)
    report = {
        "file": path.name, "bytes": path.stat().st_size, "sha256": sha256(path),
        "ads_test_mode": config["test_mode"], "unity_game_id": GAME_ID,
        "build_info": info, "native_libraries": native,
        "checks": ["packaged ads configuration", "build metadata present",
                   "Unity Ads SDK and Godot bridge in DEX", "ARM64 ELF load segments support 16 KB pages"],
    }
    if iap is not None:
        report["huawei_iap"] = iap
        report["checks"] += ["Huawei IAP native bridge, receipt verifier and HMS SDK in DEX",
                             "Huawei runtime feature and release metadata",
                             "packaged Huawei App ID, public RSA key and unique product mapping"]
    elif package == PACKAGE:
        report["checks"].append("Huawei native IAP and runtime feature absent from Google Play package")
    return report


def archive_assets(archive):
    """Map logical res:// paths for an AAB, APK, or Godot export ZIP."""
    mapping = {}
    is_android = "AndroidManifest.xml" in archive.namelist() or "BundleConfig.pb" in archive.namelist()
    for member in archive.infolist():
        entry = member.filename
        if entry.endswith("/"):
            continue
        # Godot's ZIP writer uses UTF-8 filenames without always setting bit 11.
        # Android/Java interprets these as UTF-8; Python otherwise uses CP437.
        if not member.flag_bits & 0x800:
            try:
                entry = entry.encode("cp437").decode("utf-8")
            except (UnicodeEncodeError, UnicodeDecodeError):
                pass
        if "BundleConfig.pb" in archive.namelist():
            match = re.match(r"[^/]+/assets/(.+)", entry)
            if not match:
                continue
            relative = match[1]
        elif is_android:
            if not entry.startswith("assets/"):
                continue
            relative = entry[len("assets/"):]
        else:
            relative = entry.removeprefix("res://")
        require(relative not in mapping, f"Duplicate packaged asset: {relative}")
        mapping[relative] = member.filename
    return mapping


def production_sources_snapshot():
    files = [ROOT / "project.godot", ROOT / "export_presets.cfg", ROOT / "localization/runtime.json"]
    for folder, pattern in (("scripts", "*.gd"), ("scenes", "*"), ("config", "*.json")):
        files.extend(path for path in (ROOT / folder).rglob(pattern) if path.is_file())
    return {path.relative_to(ROOT).as_posix(): sha256(path) for path in sorted(set(files))}


def prepare_source_pack(output, run, reuse=False, package=PACKAGE):
    """Independently export current sources so compressed .gdc bytes can be compared."""
    snapshot = production_sources_snapshot()
    reference = output / "current-source-reference.zip"
    source_hashes = output / "verified-source-hashes.json"
    reference_profile = output / "current-source-profile.json"
    preset = "Android Huawei" if package == HUAWEI_PACKAGE else "Android AAB"
    if reuse:
        require(reference.is_file() and source_hashes.is_file() and reference_profile.is_file(),
                "Reference export, source hashes and profile are required for reuse")
        require(json.loads(reference_profile.read_text(encoding="utf-8")) == {"package": package, "preset": preset},
                "Reference pack belongs to a different export preset; repeat export")
        require(json.loads(source_hashes.read_text(encoding="utf-8")) == snapshot,
                "Sources changed since reference export; run without --reuse-source-reference")
        roots = json.loads((ROOT / "build/android/resource-roots.json").read_text(encoding="utf-8"))
        require(all((ROOT / resource.removeprefix("res://")).stat().st_mtime <= reference.stat().st_mtime for resource in roots),
                "A selected resource was modified after the reference export; repeat export")
        print("Reusing completed current-source export; source hashes are unchanged.", flush=True)
        return reference, snapshot
    reference.unlink(missing_ok=True)
    print("Exporting current-source reference pack...", flush=True)
    log = run([ROOT.parent / "tools/Godot_v4.5.2-stable_win64_console.exe", "--headless", "--quit",
               "--path", ROOT, "--export-pack", preset, reference], output / "current-source-export.log")
    require(reference.is_file() and "SCRIPT ERROR:" not in log and "\nERROR:" not in log,
            "Current-source reference export failed; inspect current-source-export.log")
    require(production_sources_snapshot() == snapshot, "Sources changed during reference export; repeat verification")
    source_hashes.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    reference_profile.write_text(json.dumps({"package": package, "preset": preset}, indent=2) + "\n", encoding="utf-8")
    return reference, snapshot


def verify_production_content(path, result, reference, source_snapshot, expected_level_count, package=PACKAGE):
    info = result["build_info"]
    distribution = "huawei_appgallery" if package == HUAWEI_PACKAGE else "google_play_production"
    require(info.get("distribution") == distribution, f"{path.name}: incorrect production distribution")
    require(info.get("unlock_all_levels") is False, f"{path.name}: production build must explicitly disable unlock_all_levels")
    require(result["ads_test_mode"] is False, f"{path.name}: production must use live ads")
    require(production_sources_snapshot() == source_snapshot, "Sources changed after reference export; repeat verification")
    with zipfile.ZipFile(path) as actual, zipfile.ZipFile(reference) as fresh:
        actual_assets, expected_assets = archive_assets(actual), archive_assets(fresh)
        # Platform feature flags can change project.binary. Ads/build metadata
        # are validated against explicit release requirements, independently of
        # any development configuration restored after the production export.
        excluded = {"project.binary", "config/ads.json", "config/build_info.json"}
        comparable = set(expected_assets) - excluded
        require(comparable, "Current-source export contained no comparable resources")
        missing = sorted(comparable - set(actual_assets))
        require(not missing, f"{path.name}: missing current runtime resources: {missing[:12]}")
        mismatches = [name for name in sorted(comparable)
                      if actual.read(actual_assets[name]) != fresh.read(expected_assets[name])]
        require(not mismatches, f"{path.name}: packaged resources differ from current sources: {mismatches[:12]}")
        script_names = sorted(name for name in comparable if name.startswith("scripts/") and name.endswith((".gd", ".gdc")))
        require(script_names, f"{path.name}: no game scripts in reference export")
        campaign_bytes = actual.read(actual_assets["config/campaign.json"])
        require(campaign_bytes == (ROOT / "config/campaign.json").read_bytes(),
                f"{path.name}: campaign differs from current source")
        campaign = json.loads(campaign_bytes)
        levels = campaign.get("levels", [])
        require(levels, f"{path.name}: campaign contains no levels")
        if expected_level_count is not None:
            require(len(levels) == expected_level_count, f"{path.name}: expected {expected_level_count} campaign levels, found {len(levels)}")
        level_numbers = [level.get("campaign", {}).get("level") for level in levels]
        require(level_numbers == list(range(1, len(levels) + 1)), f"{path.name}: campaign level numbers are not sequential")
        roots = json.loads((ROOT / "build/android/resource-roots.json").read_text(encoding="utf-8"))
        for resource in roots:
            relative = resource.removeprefix("res://")
            candidates = [relative, relative + ".remap", relative + ".import"]
            present = [name for name in candidates if name in actual_assets]
            require(present, f"{path.name}: selected runtime root missing: {resource}")
            for name in present:
                if not name.endswith((".remap", ".import")):
                    continue
                remap = actual.read(actual_assets[name]).decode("utf-8")
                for target in re.findall(r'^path(?:\.[^=]+)?="res://([^"]+)"', remap, re.M):
                    require(target in actual_assets, f"{path.name}: missing remapped resource: {target}")
    result["production_content"] = {
        "distribution": info["distribution"], "unlock_all_levels": info["unlock_all_levels"],
        "campaign_level_count": len(levels), "campaign_revision": campaign.get("revision"),
        "campaign_sha256": hashlib.sha256(campaign_bytes).hexdigest(),
        "campaign_levels_marked_solver_verified": sum(level.get("solver_verified") is True for level in levels),
        "compiled_game_scripts_matching_current_source": len(script_names),
        "runtime_files_matching_current_export": len(comparable), "selected_resource_roots_verified": len(roots),
        "current_source_reference_sha256": sha256(reference),
    }
    result["checks"] += ["production distribution and level-unlock override disabled",
                         "campaign bytes and sequential level count match current source",
                         "game scripts and runtime resources match independent current-source export",
                         "selected runtime roots and remap targets are present"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aab", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--ads-mode", choices=("test", "live"), default="test")
    parser.add_argument("--version-code", type=int, default=4)
    parser.add_argument("--version-name", default="0.1.1")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--package-name", choices=(PACKAGE, HUAWEI_PACKAGE),
                        help="Expected Android identity (defaults to Google Play, or Huawei with --require-huawei-iap)")
    parser.add_argument("--require-huawei-iap", action="store_true",
                        help="Verify packaged Huawei IAP SDK, configuration, runtime feature and matching manifest App ID")
    parser.add_argument("--check-export-presets", action="store_true",
                        help="Check Google/Huawei source preset isolation without artifacts, signing keys or export")
    parser.add_argument("--production", action="store_true",
                        help="Require production metadata, normal level progression, and current-source resource parity")
    parser.add_argument("--expected-level-count", type=int,
                        help="Expected packaged campaign size (requires --production)")
    parser.add_argument("--reuse-source-reference", action="store_true",
                        help="Resume production verification using a completed export with unchanged source hashes")
    args = parser.parse_args()
    args.package_name = args.package_name or (HUAWEI_PACKAGE if args.require_huawei_iap else PACKAGE)
    require(not args.require_huawei_iap or args.package_name == HUAWEI_PACKAGE,
            "--require-huawei-iap is only valid for org.truckmania.game.hw")
    if args.check_export_presets:
        print(json.dumps(verify_export_presets((ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")), indent=2))
        print("Source preset isolation verified; no APK/AAB, payment credentials or runtime purchase was checked.")
        return
    require(not args.production or args.ads_mode == "live", "--production requires --ads-mode live")
    require(args.expected_level_count is None or args.production, "--expected-level-count requires --production")
    require(not args.reuse_source_reference or args.production, "--reuse-source-reference requires --production")
    if args.aab is None and args.apk is None:
        require(args.package_name == PACKAGE, "Supply --apk or --aab for the Huawei artifact")
        args.aab = DEFAULT_OUTPUT / "truck-mania-google-play-closed-v4.aab"
    artifacts = [path.resolve() for path in (args.aab, args.apk) if path is not None]
    for path in artifacts:
        require(path.is_file(), f"Artifact not found: {path}")
    output = (args.output_dir or artifacts[0].parent).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report_path = output / "verification-report.json"
    # Do not leave a stale successful report after a failed repeat validation.
    report_path.unlink(missing_ok=True)
    java = next((ANDROID / "java").glob("jdk-*/bin/java.exe"))
    build_tools = ANDROID / "sdk/build-tools/35.0.1"
    bundletool = ANDROID / "bundletool.jar"
    credentials = json.loads((ANDROID / "signing/upload-credentials.json").read_text(encoding="utf-8-sig"))
    env = dict(os.environ, JAVA_HOME=str(java.parent.parent),
               ANDROID_HOME=str(ANDROID / "sdk"), ANDROID_SDK_ROOT=str(ANDROID / "sdk"),
               TRUCK_MANIA_VERIFY_KEY_PASSWORD=credentials["password"])

    def run(arguments, log_path=None):
        if log_path is not None:
            with log_path.open("w", encoding="utf-8") as log:
                process = subprocess.Popen([str(arg) for arg in arguments], env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
                lines = []
                for line in process.stdout:
                    line = line.replace(credentials["password"], "<REDACTED>")
                    log.write(line)
                    log.flush()
                    lines.append(line)
                code, combined = process.wait(), "".join(lines)
        else:
            result = subprocess.run([str(arg) for arg in arguments], env=env, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace")
            code = result.returncode
            combined = (result.stdout + result.stderr).replace(credentials["password"], "<REDACTED>")
        if code:
            raise RuntimeError(f"{Path(str(arguments[0])).name} failed ({code}):\n{combined}")
        return combined

    def bundle(*arguments):
        return run([java, "-jar", bundletool, *arguments])

    reference, source_snapshot = prepare_source_pack(output, run, args.reuse_source_reference, args.package_name) if args.production else (None, None)

    certificate = run([java.parent / "keytool.exe", "-J-Duser.language=en", "-J-Duser.country=US",
                       "-list", "-v", "-keystore", ANDROID / "signing/truck-mania-upload.jks",
                       "-alias", credentials["alias"], "-storepass:env", "TRUCK_MANIA_VERIFY_KEY_PASSWORD"])
    match = re.search(r"SHA256:\s*([0-9A-Fa-f:]{64,95})", certificate)
    require(match is not None, "Cannot read release signing certificate fingerprint")
    expected_certificate = match[1].replace(":", "").lower()

    def verify_build_info(result):
        info = result["build_info"]
        require(info.get("version_code") == args.version_code and info.get("version_name") == args.version_name,
                f"{result['file']}: build metadata version does not match manifest expectations")
        require(info.get("ads_mode") == args.ads_mode,
                f"{result['file']}: build metadata ads_mode does not match packaged ads configuration")
        require("package_name" not in info or info["package_name"] == args.package_name,
                f"{result['file']}: build metadata belongs to another package")
        result["checks"].append("build metadata version and ads mode match export")

    def verify_apk(path):
        result = inspect_archive(path, args.ads_mode, args.package_name, args.require_huawei_iap)
        verify_build_info(result)
        if args.production:
            verify_production_content(path, result, reference, source_snapshot, args.expected_level_count, args.package_name)
        badging = run([build_tools / "aapt2.exe", "dump", "badging", path])
        verify_package_badging(badging, args.package_name, args.version_code, args.version_name)
        require("minSdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging,
                f"{path.name}: incorrect Android SDK levels")
        require("application-debuggable" not in badging, f"{path.name}: debug build")
        manifest = run([build_tools / "aapt2.exe", "dump", "xmltree", path, "--file", "AndroidManifest.xml"])
        verify_iap_manifest(manifest, args.package_name, result.get("huawei_iap"))
        require("org.godotengine.plugin.v2.TruckManiaAds" in manifest and
                "com.unity3d.services.core.configuration.AdsSdkInitializer" in manifest,
                f"{path.name}: ads plugin registration missing from manifest")
        for permission in ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
                           "com.google.android.gms.permission.AD_ID"):
            require(permission in badging, f"{path.name}: {permission} missing")
        (output / (path.stem + "-manifest.txt")).write_text(manifest, encoding="utf-8")
        signature = run([java, "-jar", build_tools / "lib/apksigner.jar", "verify", "--verbose", "--print-certs", path])
        fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]+)", signature)
        require([value.lower() for value in fingerprints] == [expected_certificate],
                f"{path.name}: signing certificate does not match the release key")
        run([build_tools / "zipalign.exe", "-c", "-P", "16", "4", path])
        result["signing_certificate_sha256"] = expected_certificate
        result["checks"] += ["package and version", "min SDK 24 / target SDK 36",
                             "non-debuggable release manifest", "ads manifest registrations and permissions",
                             "APK signature verified against release key", "16 KB native ZIP alignment"]
        if args.require_huawei_iap:
            result["checks"].append("Huawei plugin manifest registration and matching App ID")
        elif args.package_name == PACKAGE:
            result["checks"].append("Huawei IAP application metadata absent from Google Play manifest")
        return result

    results = []
    if args.aab is not None:
        path = args.aab.resolve()
        result = inspect_archive(path, args.ads_mode, args.package_name, args.require_huawei_iap)
        verify_build_info(result)
        if args.production:
            verify_production_content(path, result, reference, source_snapshot, args.expected_level_count, args.package_name)
        bundle("validate", "--bundle=" + str(path))
        manifest = bundle("dump", "manifest", "--bundle=" + str(path), "--module=base")
        (output / (path.stem + "-manifest.xml")).write_text(manifest, encoding="utf-8")
        document = ET.fromstring(manifest)
        verify_package_manifest(document, args.package_name, args.version_code, args.version_name)
        verify_iap_manifest(manifest, args.package_name, result.get("huawei_iap"))
        sdk = document.find("uses-sdk")
        require(sdk is not None and sdk.get(ANDROID_NS + "minSdkVersion") == "24" and
                sdk.get(ANDROID_NS + "targetSdkVersion") == "36", f"{path.name}: incorrect SDK levels")
        application = document.find("application")
        require(application is not None and application.get(ANDROID_NS + "debuggable", "false") == "false",
                f"{path.name}: debug build")
        config = json.loads(bundle("dump", "config", "--bundle=" + str(path)))
        (output / (path.stem + "-bundle-config.json")).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        alignment = config.get("optimizations", {}).get("uncompressNativeLibraries", {}).get("alignment")
        require(alignment == "PAGE_ALIGNMENT_16K", f"{path.name}: bundle is not configured for 16 KB alignment")
        signature = run([java.parent / "jarsigner.exe", "-J-Duser.language=en", "-J-Duser.country=US", "-verify", path])
        require("jar verified" in signature and "unsigned entries" not in signature.lower(),
                f"{path.name}: bundle signature was not fully verified")
        certificate = run([java.parent / "keytool.exe", "-J-Duser.language=en", "-J-Duser.country=US",
                           "-printcert", "-jarfile", path])
        fingerprints = re.findall(r"SHA256:\s*([0-9A-Fa-f:]{64,95})", certificate)
        require([value.replace(":", "").lower() for value in fingerprints] == [expected_certificate],
                f"{path.name}: bundle certificate does not match release key")
        apk_set = output / (path.stem + "-validation.apks")
        universal_apk = output / (path.stem + "-validation-universal.apk")
        with tempfile.TemporaryDirectory(prefix="truck-mania-verify-") as temp:
            password_file = Path(temp) / "signing-password.txt"
            password_file.write_text(credentials["password"], encoding="utf-8")
            bundle("build-apks", "--bundle=" + str(path), "--output=" + str(apk_set),
                   "--mode=universal", "--overwrite", "--ks=" + str(ANDROID / "signing/truck-mania-upload.jks"),
                   "--ks-key-alias=" + credentials["alias"], "--ks-pass=file:" + str(password_file),
                   "--key-pass=file:" + str(password_file))
        with zipfile.ZipFile(apk_set) as archive:
            universal_apk.write_bytes(archive.read("universal.apk"))
        result["universal_apk_validation"] = verify_apk(universal_apk)
        result["signing_certificate_sha256"] = expected_certificate
        result["checks"] += ["bundletool validate", "non-debuggable release manifest and expected version",
                             "JAR signature verified against release key", "bundle PAGE_ALIGNMENT_16K",
                             "generated universal APK signature, manifest, packaged config and 16 KB alignment"]
        results.append(result)
    if args.apk is not None:
        results.append(verify_apk(args.apk.resolve()))
    report = {
        "package": args.package_name, "version_code": args.version_code, "version_name": args.version_name,
        "min_sdk": 24, "target_sdk": 36, "architectures": ["arm64-v8a"],
        "ads_mode": args.ads_mode, "production_checks": args.production, "artifacts": results,
        "huawei_iap_required": args.require_huawei_iap,
        "runtime_ads_not_tested": True, "runtime_purchases_not_tested": True, "uploaded_to_store": False,
        "limitations": ["Static packaging checks do not establish ad delivery, successful real purchases on a physical device, or store acceptance."],
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Validated {len(results)} store artifact(s); report: {report_path}")
    for result in results:
        print(f"{result['file']}: {result['bytes']} bytes, SHA256 {result['sha256']}")


if __name__ == "__main__":
    main()
