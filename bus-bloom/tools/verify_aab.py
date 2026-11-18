import json,subprocess,zipfile,os,hashlib
from pathlib import Path
ws=Path(__file__).resolve().parents[2];root=ws/'bus-bloom';android=ws/'tools/android';out=root/'build/android';java=next((android/'java').glob('*/bin/java.exe'));bundle=out/'truck-mania.aab';bt=android/'bundletool.jar'
def run(args):
 r=subprocess.run([str(a) for a in args],check=True,capture_output=True,text=True,encoding='utf-8',errors='replace');return r.stdout+r.stderr
print(run([java,'-jar',bt,'validate','--bundle='+str(bundle)]))
manifest=run([java,'-jar',bt,'dump','manifest','--bundle='+str(bundle),'--module=base']);(out/'aab-manifest.xml').write_text(manifest,encoding='utf-8')
assert 'org.truckmania.game' in manifest and 'targetSdkVersion="36"' in manifest
assert 'debuggable="true"' not in manifest
signature=run([java.parent/'jarsigner.exe','-verify',bundle]);assert 'jar verified' in signature
c=json.loads((android/'signing/upload-credentials.json').read_text())
secret=android/'signing/.bundle-validation-password';secret.write_text(c['password'],encoding='utf-8')
try:
 print(run([java,'-jar',bt,'build-apks','--bundle='+str(bundle),'--output='+str(out/'validation.apks'),'--mode=universal','--overwrite','--ks='+str(android/'signing/truck-mania-upload.jks'),'--ks-key-alias='+c['alias'],'--ks-pass=file:'+str(secret),'--key-pass=file:'+str(secret)]))
finally:secret.unlink(missing_ok=True)
with zipfile.ZipFile(out/'validation.apks') as z:(out/'validation-universal.apk').write_bytes(z.read('universal.apk'))
print(run([android/'sdk/build-tools/35.0.1/zipalign.exe','-c','-P','16','4',out/'validation-universal.apk']))
report={'file':bundle.name,'bytes':bundle.stat().st_size,'sha256':hashlib.sha256(bundle.read_bytes()).hexdigest(),'package':'org.truckmania.game','target_sdk':36,'min_sdk':24,'architecture':'arm64-v8a','signing':'release/upload key','checks':['bundletool validate','non-debuggable manifest','JAR signature verified','universal APK generated and 16KB ZIP alignment verified'],'uploaded_to_google_play':False}
(out/'aab-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
