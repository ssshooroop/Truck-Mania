import concurrent.futures,subprocess,hashlib,urllib.request,zipfile
from pathlib import Path
base=Path('tools/android')
def fetch(name,url,size,algorithm,expected):
 target=base/name;parts=base/(name+'.parts');parts.mkdir(exist_ok=True)
 chunk=4*1024*1024
 if target.exists():
  with target.open('rb') as f:
   offset=0
   while data:=f.read(chunk):
    end=min(offset+chunk,size)-1
    if len(data)==end-offset+1:(parts/f'{offset}-{end}').write_bytes(data)
    offset+=len(data)
 def part(start):
  end=min(start+chunk,size)-1;p=parts/f'{start}-{end}'
  if not p.exists() or p.stat().st_size!=end-start+1:
   subprocess.run(['curl.exe','-sS','-L','--fail','--max-time','180','--retry','2','--range',f'{start}-{end}','-o',str(p),url+'?part='+str(start)],check=True)
  assert p.stat().st_size==end-start+1
  print(name,'chunk',start//chunk+1,'ready',flush=True)
  return p
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool: files=list(pool.map(part,range(0,size,chunk)))
 with target.open('wb') as out:
  for p in files:out.write(p.read_bytes())
 assert hashlib.new(algorithm,target.read_bytes()).hexdigest()==expected
 print(name,'verified',flush=True)
 return target
def platform():
 p=fetch('platform35.zip','https://dl.google.com/android/repository/platform-35-ext15_r01.zip',64492044,'sha1','ce757091f933b7ac646bf197ce8957cc73b95614')
 with zipfile.ZipFile(p) as z:
  prefix=z.namelist()[0].split('/')[0]+'/'
  dest=base/'sdk/platforms/android-35'
  for i in z.infolist():
   if i.is_dir():continue
   q=dest/i.filename.removeprefix(prefix);q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(z.read(i))
 print('SDK platform ready',flush=True)
def gradle():
 sha=urllib.request.urlopen('https://services.gradle.org/distributions/gradle-8.11.1-bin.zip.sha256').read().decode().strip()
 p=fetch('gradle-8.11.1-bin.zip','https://github.com/gradle/gradle-distributions/releases/download/v8.11.1/gradle-8.11.1-bin.zip',136920070,'sha256',sha)
 with zipfile.ZipFile(p) as z:z.extractall(base/'gradle')
 print('Gradle ready',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 for result in [pool.submit(platform),pool.submit(gradle)]:result.result()
