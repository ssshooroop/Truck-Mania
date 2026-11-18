from pathlib import Path
exec(Path('bus-bloom/tools/download_aab_dependencies.py').read_text().split('def platform():')[0])
p=fetch('build-tools35.0.1.zip','https://dl.google.com/android/repository/build-tools_r35.0.1_windows.zip',59876477,'sha1','1cbfa5564b62504a1111352edda35914cf723a20')
with zipfile.ZipFile(p) as z:
 prefix=z.namelist()[0].split('/')[0]+'/'
 dest=base/'sdk/build-tools/35.0.1'
 for i in z.infolist():
  if i.is_dir():continue
  q=dest/i.filename.removeprefix(prefix);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(z.read(i))
print('Build tools ready',flush=True)
