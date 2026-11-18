"""Build a debug APK with Unity test ads. Does not upload anything."""
import json, os, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
workspace = root.parent
android = workspace/'tools/android'
assert json.loads((root/'config/ads.json').read_text())['test_mode'], 'Test APK requires test_mode=true'
subprocess.run([sys.executable,str(root/'tools/build_ads_plugin.py')],check=True)
subprocess.run([sys.executable,str(root/'tools/prepare_android_export.py')],check=True)
env = dict(os.environ, JAVA_HOME=str(next((android/'java').glob('jdk-*'))),
           ANDROID_HOME=str(android/'sdk'), ANDROID_SDK_ROOT=str(android/'sdk'),
           GRADLE_USER_HOME=str(android/'gradle-cache'), GRADLE_OPTS='-Dorg.gradle.workers.max=2')
cmd = [str(workspace/'tools/Godot_v4.5.2-stable_win64_console.exe'), '--headless', '--quit',
       '--path',str(root),'--export-debug','Android','build/android/truck-mania-unity-test.apk']
with (root/'artifacts/unity-apk-build.log').open('w',encoding='utf-8') as log:
    result = subprocess.run(cmd,env=env,stdout=log,stderr=subprocess.STDOUT)
print('APK exporter exit:',result.returncode)
sys.exit(result.returncode)
