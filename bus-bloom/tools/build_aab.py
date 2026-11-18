"""Build a signed store bundle locally, preserving existing versioned artifacts."""
import argparse,json,os,subprocess,sys,hashlib,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];ws=root.parent;android=ws/'tools/android'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--allow-test-ads',action='store_true',help='Keep Unity test ads for internal/closed testing.')
parser.add_argument('--output',default='build/android/truck-mania.aab')
args=parser.parse_args()
if json.loads((root/'config/ads.json').read_text())['test_mode'] and not args.allow_test_ads:
 raise SystemExit('Unity test ads are enabled. For an internal/closed-test AAB, pass --allow-test-ads. Do not publish test ads to production.')
output=(root/args.output).resolve()
if not output.is_relative_to(root/'build') or output.suffix!='.aab':
 raise SystemExit('Output must be an .aab under this project build directory.')
output.parent.mkdir(parents=True,exist_ok=True)
subprocess.run([sys.executable,str(root/'tools/build_ads_plugin.py')],check=True)
subprocess.run([sys.executable,str(root/'tools/prepare_android_export.py')],check=True)
subprocess.run([sys.executable,str(root/'tools/prepare_aab_export.py')],cwd=ws,check=True)
# Seed the wrapper's official-URL cache from the checksum-verified download.
url='https://services.gradle.org/distributions/gradle-8.11.1-bin.zip'
n=int.from_bytes(hashlib.md5(url.encode()).digest(),'big');digits='0123456789abcdefghijklmnopqrstuvwxyz';cache_id=''
while n:cache_id=digits[n%36]+cache_id;n//=36
cache=android/'gradle-cache/wrapper/dists/gradle-8.11.1-bin'/cache_id
cache.mkdir(parents=True,exist_ok=True)
if not (cache/'gradle-8.11.1/bin/gradle.bat').exists():
 with zipfile.ZipFile(android/'gradle-8.11.1-bin.zip') as z:z.extractall(cache)
(cache/'gradle-8.11.1-bin.zip.ok').touch()
c=json.loads((android/'signing/upload-credentials.json').read_text())
env=dict(os.environ)
env.update(JAVA_HOME=str(next((android/'java').glob('jdk-*'))),ANDROID_HOME=str(android/'sdk'),ANDROID_SDK_ROOT=str(android/'sdk'),GRADLE_USER_HOME=str(android/'gradle-cache'),GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.daemon=false',GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(android/'signing/truck-mania-upload.jks'),GODOT_ANDROID_KEYSTORE_RELEASE_USER=c['alias'],GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=c['password'])
cmd=[str(ws/'tools/Godot_v4.5.2-stable_win64_console.exe'),'--headless','--quit','--path',str(root)]
if not (root/'android/build/build.gradle').exists():
 cmd.append('--install-android-build-template')
cmd+=['--export-release','Android AAB',str(output)]
with (root/'artifacts/aab-build.log').open('w',encoding='utf-8') as log:
 p=subprocess.Popen(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
 for line in p.stdout:
  log.write(line.replace(c['password'],'<REDACTED>'));log.flush()
 result=p.wait()
print('AAB exporter exit:',result)
if result==0:
 if not output.is_file(): raise SystemExit('Exporter did not create the requested AAB.')
 print('AAB:',output)
sys.exit(result)

