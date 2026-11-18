"""Pure fixtures for store identity and Huawei packaging; no SDK or payment calls."""
import ast
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import unittest
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("store_verifier", ROOT / "tools/verify_store_builds.py")
V = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(V)


def preset_fixture():
    pieces = []
    for index, name, package, feature, output_format, code, version in (
        (0, "Android", V.PACKAGE, "", 0, 7, "0.1.2"),
        (1, "iOS", "unused.ios", "", 0, 1, "0.1.0"),
        (2, "Web", "unused.web", "", 0, 1, "0.1.0"),
        (3, "Android AAB", V.PACKAGE, "", 1, 7, "0.1.2"),
        (4, "Android Huawei", V.HUAWEI_PACKAGE, "huawei_appgallery", 0, 8, "0.1.3"),
    ):
        pieces.append(f'''[preset.{index}]
name="{name}"
runnable=true
custom_features="{feature}"
export_path="build/android/truck-mania.apk"
[preset.{index}.options]
package/unique_name="{package}"
gradle_build/use_gradle_build=true
gradle_build/export_format={output_format}
version/code={code}
version/name="{version}"
''')
    return "\n".join(pieces)


def manifest_xml(package=V.HUAWEI_PACKAGE, app_id="123456", bridge=V.HUAWEI_CLASS):
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
 package="{package}" android:versionCode="8" android:versionName="0.1.3">
 <application>
 <meta-data android:name="{V.HUAWEI_PLUGIN}" android:value="{bridge}"/>
 <meta-data android:name="{V.HUAWEI_APP_ID_METADATA}" android:value="appid={app_id}"/>
 </application></manifest>'''


def run_prepare_in_memory(filename, files, invoke=None):
    """Execute the real preparer with only its Path dependency replaced."""
    class MemoryPath:
        def __init__(self, value):
            self.path = PurePosixPath(str(value))

        def __truediv__(self, value):
            return MemoryPath(self.path / value)

        def resolve(self):
            return self

        @property
        def parent(self):
            return MemoryPath(self.path.parent)

        @property
        def parents(self):
            return [MemoryPath(value) for value in self.path.parents]

        def as_posix(self):
            return self.path.as_posix()

        def read_text(self, *args, **kwargs):
            return files[self.as_posix()]

        def write_text(self, value, *args, **kwargs):
            files[self.as_posix()] = value
            return len(value)

    source = (ROOT / "tools" / filename).read_text(encoding="utf-8-sig")
    tree = ast.parse(source, filename=filename)
    tree.body = [node for node in tree.body if not isinstance(node, ast.ImportFrom) or node.module != "pathlib"]
    namespace = {"__name__": "fixture", "__file__": "/fixture/bus-bloom/tools/" + filename, "Path": MemoryPath}
    with contextlib.redirect_stdout(io.StringIO()):
        exec(compile(tree, filename, "exec"), namespace)
        if invoke:
            namespace["prepare"](**invoke)
    return namespace


class StoreVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # A throwaway key is generated only in memory; never used for billing,
        # written to disk, or printed. Only its public half enters fixtures.
        der = rsa.generate_private_key(public_exponent=65537, key_size=2048).public_key().public_bytes(
            Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
        cls.settings = {"package_name": V.HUAWEI_PACKAGE, "app_id": "123456",
                        "public_key": base64.b64encode(der).decode("ascii"),
                        "product_ids": {"coins": "huawei.coins", "starter": "huawei.starter"}}
        cls.catalog = {"products": [{"id": "coins", "kind": "coins"}, {"id": "starter", "once": True}]}
        cls.info = {"package_name": V.HUAWEI_PACKAGE, "iap_provider": "huawei", "distribution": "huawei_appgallery"}

    def assets(self):
        return {"project.binary": b"ECFG\x00custom_features\x00huawei_appgallery",
                "config/huawei_iap.json": json.dumps(self.settings).encode(),
                "config/store_catalog.json": json.dumps(self.catalog).encode()}

    def test_distinct_apk_package_and_version(self):
        google = "package: name='org.truckmania.game' versionCode='8' versionName='0.1.3'"
        huawei = google.replace("org.truckmania.game'", "org.truckmania.game.hw'")
        V.verify_package_badging(google, V.PACKAGE, 8, "0.1.3")
        V.verify_package_badging(huawei, V.HUAWEI_PACKAGE, 8, "0.1.3")
        for badging, package, code in ((google, V.HUAWEI_PACKAGE, 8), (huawei, V.PACKAGE, 8), (huawei, V.HUAWEI_PACKAGE, 7)):
            with self.subTest(package=package, code=code), self.assertRaises(RuntimeError):
                V.verify_package_badging(badging, package, code, "0.1.3")

    def test_distinct_aab_package(self):
        document = ET.fromstring(manifest_xml())
        V.verify_package_manifest(document, V.HUAWEI_PACKAGE, 8, "0.1.3")
        with self.assertRaises(RuntimeError):
            V.verify_package_manifest(document, V.PACKAGE, 8, "0.1.3")

    def test_huawei_xml_metadata_matches_config(self):
        V.verify_iap_manifest(manifest_xml(), V.HUAWEI_PACKAGE, {"app_id": "123456"})
        for app_id, bridge in (("other", V.HUAWEI_CLASS), ("123456", "wrong.Bridge")):
            with self.subTest(app_id=app_id), self.assertRaises(RuntimeError):
                V.verify_iap_manifest(manifest_xml(app_id=app_id, bridge=bridge), V.HUAWEI_PACKAGE, {"app_id": "123456"})

    def test_apk_xmltree_metadata_and_parent_scope(self):
        text = f'''N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=1)
    A: package="{V.HUAWEI_PACKAGE}"
      E: application (line=2)
          E: meta-data (line=3)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="{V.HUAWEI_PLUGIN}"
            A: http://schemas.android.com/apk/res/android:value(0x01010024)="{V.HUAWEI_CLASS}"
          E: meta-data (line=4)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="{V.HUAWEI_APP_ID_METADATA}"
            A: http://schemas.android.com/apk/res/android:value(0x01010024)="appid=123456"
          E: provider (line=5)
              E: meta-data (line=6)
                A: http://schemas.android.com/apk/res/android:name(0x01010003)="provider-only"
                A: http://schemas.android.com/apk/res/android:value(0x01010024)="ignored"
'''
        V.verify_iap_manifest(text, V.HUAWEI_PACKAGE, {"app_id": "123456"})
        self.assertNotIn("provider-only", V.application_metadata(text))

    def test_google_manifest_rejects_huawei_leak(self):
        with self.assertRaises(RuntimeError):
            V.verify_iap_manifest(manifest_xml(package=V.PACKAGE), V.PACKAGE)
        V.verify_iap_manifest('<manifest><application/></manifest>', V.PACKAGE)

    def test_duplicate_app_metadata_rejected(self):
        text = manifest_xml().replace("</application>", f'<meta-data android:name="{V.HUAWEI_APP_ID_METADATA}" android:value="appid=999"/></application>')
        with self.assertRaises(RuntimeError):
            V.application_metadata(text)

    def test_huawei_public_configuration(self):
        result = V.verify_huawei_configuration(self.settings, self.catalog, V.HUAWEI_PACKAGE)
        self.assertEqual(result["registered_product_count"], 2)
        self.assertEqual(result["app_id"], "123456")
        self.assertEqual(len(result["public_key_sha256"]), 64)
        self.assertNotIn("public_key", result)

    def test_invalid_huawei_configuration_fails_closed(self):
        variants = [dict(self.settings, app_id=""), dict(self.settings, app_id="12x"),
                    dict(self.settings, package_name=V.PACKAGE), dict(self.settings, public_key=""),
                    dict(self.settings, public_key="-----BEGIN PRIVATE KEY-----"),
                    dict(self.settings, public_key="invalid base64"),
                    dict(self.settings, product_ids={"coins": "same", "starter": "same"}),
                    dict(self.settings, product_ids={"coins": "only-one"})]
        for index, settings in enumerate(variants):
            with self.subTest(index=index), self.assertRaises(RuntimeError):
                V.verify_huawei_configuration(settings, self.catalog, V.HUAWEI_PACKAGE)

    def test_huawei_sdk_content_and_product_metadata(self):
        assets = self.assets()
        dex = [b"\x00".join(V.HUAWEI_DEX_MARKERS)]
        result = V.verify_iap_content(assets.__getitem__, dex, self.info, V.HUAWEI_PACKAGE, True)
        self.assertEqual(result["app_id"], "123456")
        for missing in V.HUAWEI_DEX_MARKERS:
            with self.subTest(missing=missing), self.assertRaises(RuntimeError):
                V.verify_iap_content(assets.__getitem__, [b"\x00".join(x for x in V.HUAWEI_DEX_MARKERS if x != missing)], self.info, V.HUAWEI_PACKAGE, True)
        with self.assertRaises(RuntimeError):
            V.verify_iap_content(assets.__getitem__, dex, dict(self.info, iap_provider="google"), V.HUAWEI_PACKAGE, True)

    def test_google_sdk_and_runtime_features_are_isolated(self):
        assets = self.assets()
        assets["project.binary"] = b"ECFG\x00google-only"
        self.assertIsNone(V.verify_iap_content(assets.__getitem__, [b"Lcom/unity3d/ads/UnityAds;"], {}, V.PACKAGE, False))
        with self.assertRaises(RuntimeError):
            V.verify_iap_content(assets.__getitem__, [V.HUAWEI_DEX_MARKERS[0]], {}, V.PACKAGE, False)
        assets["project.binary"] += b"huawei_appgallery"
        with self.assertRaises(RuntimeError):
            V.verify_iap_content(assets.__getitem__, [], {}, V.PACKAGE, False)

    def test_source_presets_cannot_cross_store_boundaries(self):
        text = preset_fixture()
        report = V.verify_export_presets(text)
        self.assertEqual(report["Android Huawei"]["package"], V.HUAWEI_PACKAGE)
        self.assertFalse(report["Android AAB"]["huawei_feature"])
        for corrupted in (text.replace(V.HUAWEI_PACKAGE, V.PACKAGE),
                          text.replace('custom_features=""', 'custom_features="huawei_appgallery"', 1)):
            with self.assertRaises(RuntimeError):
                V.verify_export_presets(corrupted)

    def test_preparers_preserve_each_other_in_both_orders(self):
        for order in (("aab", "huawei", "aab"), ("huawei", "aab", "huawei")):
            with self.subTest(order=order):
                files = {"/fixture/bus-bloom/export_presets.cfg": preset_fixture(), "/fixture/bus-bloom/.gitignore": ""}
                original_base = files["/fixture/bus-bloom/export_presets.cfg"].split("[preset.1]", 1)[0]
                for action in order:
                    filename = "prepare_aab_export.py" if action == "aab" else "prepare_huawei_export.py"
                    run_prepare_in_memory(filename, files, {"version_code": 9, "version_name": "0.1.4"} if action == "huawei" else None)
                output = files["/fixture/bus-bloom/export_presets.cfg"]
                report = V.verify_export_presets(output)
                self.assertEqual(report["Android AAB"]["version_code"], 7)
                self.assertEqual(report["Android Huawei"]["version_code"], 9)
                self.assertEqual(report["Android Huawei"]["version_name"], "0.1.4")
                self.assertEqual(output.split("[preset.1]", 1)[0], original_base)
                self.assertIn('name="iOS"', output)
                self.assertIn('name="Web"', output)


if __name__ == "__main__":
    unittest.main()
