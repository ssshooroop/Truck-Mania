import sys,json,zipfile
from pathlib import Path
sys.path.insert(0,str(Path('bus-bloom/tools').resolve()))
from setup_android import get,RemoteZip,BASE
release=json.load(get('https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.5.2-stable'))
a=next(x for x in release['assets'] if x['name']=='Godot_v4.5.2-stable_export_templates.tpz')
with zipfile.ZipFile(RemoteZip(a['browser_download_url'],a['size'])) as z:
 info=next(x for x in z.infolist() if x.filename.endswith('/android_source.zip'))
 data=z.read(info)
 (BASE/'android_source.zip').write_bytes(data)
 print('Android Gradle template:',len(data),flush=True)
with zipfile.ZipFile(BASE/'android_source.zip') as z:
 z.extractall('bus-bloom/android/build')
 print('Template extracted',flush=True)
