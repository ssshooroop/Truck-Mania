from pathlib import Path
import json
exec(Path('bus-bloom/tools/download_aab_dependencies.py').read_text().split('def platform():')[0])
r=json.load(urllib.request.urlopen('https://api.github.com/repos/google/bundletool/releases/latest'))
a=next(a for a in r['assets'] if a['name'].endswith('.jar'))
algorithm,expected=a['digest'].split(':')
fetch('bundletool.jar',a['browser_download_url'],a['size'],algorithm,expected)
print('Bundle validator ready',r['tag_name'],flush=True)
