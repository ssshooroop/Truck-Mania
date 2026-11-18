"""Compile the credential-free Godot bridge. HMS SDK/resources stay transitive Maven dependencies."""
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / "tools/android"
PROJECT = ROOT / "plugins/huawei_iap"


def main():
    env = dict(os.environ, JAVA_HOME=str(next((ANDROID / "java").glob("jdk-*"))),
               ANDROID_HOME=str(ANDROID / "sdk"), ANDROID_SDK_ROOT=str(ANDROID / "sdk"),
               GRADLE_USER_HOME=str(ANDROID / "gradle-cache"))
    gradle = next((ANDROID / "gradle-cache/wrapper/dists").rglob("gradle.bat"))
    java = Path(env["JAVA_HOME"]) / "bin"
    test_classes = PROJECT / "build/receipt-tests"
    test_classes.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(java / "javac.exe"), "-d", str(test_classes),
                    str(PROJECT / "src/main/java/org/truckmania/iap/ReceiptVerifier.java"),
                    str(PROJECT / "src/test/java/org/truckmania/iap/ReceiptVerifierTest.java")], check=True)
    subprocess.run([str(java / "java.exe"), "-cp", str(test_classes),
                    "org.truckmania.iap.ReceiptVerifierTest"], check=True)
    log_path = ROOT / "artifacts/huawei-iap-plugin-build.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    # bundleReleaseAar produces the complete Android library manifest/R/consumer rules.
    # This bridge owns no resources; Gradle merges HMS resources from remote AARs at app export.
    with log_path.open("w", encoding="utf-8") as log:
        subprocess.run([str(gradle), "--no-daemon", "--max-workers=2", "bundleReleaseAar"],
                       cwd=PROJECT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    source = PROJECT / "build/outputs/aar/truck-mania-huawei-iap-release.aar"
    with zipfile.ZipFile(source) as aar:
        assert "classes.jar" in aar.namelist() and "AndroidManifest.xml" in aar.namelist()
    destination = ROOT / "addons/huawei_iap/truck-mania-iap.aar"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    print("Huawei IAP bridge built:", destination)


if __name__ == "__main__":
    main()
