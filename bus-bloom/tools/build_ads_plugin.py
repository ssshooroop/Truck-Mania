"""Build the reproducible Android SDK bridge; no signing credentials required."""
import io, os, subprocess, zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
android = root.parent / 'tools/android'
env = dict(os.environ, JAVA_HOME=str(next((android/'java').glob('jdk-*'))),
           ANDROID_HOME=str(android/'sdk'), ANDROID_SDK_ROOT=str(android/'sdk'),
           GRADLE_USER_HOME=str(android/'gradle-cache'))
gradle = next((android/'gradle-cache/wrapper/dists').rglob('gradle.bat'))
project = root/'plugins/unity_ads'
with (root/'artifacts/ads-plugin-build.log').open('w', encoding='utf-8') as log:
    subprocess.run([str(gradle), '--no-daemon', '--max-workers=2', 'compileReleaseJavaWithJavac', 'processReleaseManifest'],
                   cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
# Resource-free AAR: package the compiler output directly, without the optional
# external IDE annotation extraction and its unrelated IntelliJ toolchain.
# SDK + transitive dependencies are supplied by EditorExportPlugin to Gradle.
classes = project/'build/intermediates/javac/release/compileReleaseJavaWithJavac/classes'
assert (classes/'org/truckmania/ads/TruckManiaAds.class').is_file()
jar = io.BytesIO()
with zipfile.ZipFile(jar,'w',zipfile.ZIP_DEFLATED) as z:
    for path in sorted(classes.rglob('*.class')):
        z.write(path,path.relative_to(classes).as_posix())
manifest = project/'build/intermediates/merged_manifest/release/processReleaseManifest/AndroidManifest.xml'
with zipfile.ZipFile(root/'addons/unity_ads/truck-mania-ads.aar','w',zipfile.ZIP_DEFLATED) as z:
    z.write(manifest,'AndroidManifest.xml')
    z.writestr('classes.jar',jar.getvalue())
    z.writestr('R.txt','')
    z.write(project/'consumer-rules.pro','proguard.txt')
print('Unity Ads bridge built.')
