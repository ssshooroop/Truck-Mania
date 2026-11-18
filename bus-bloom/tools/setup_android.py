"""Install portable, official Android build prerequisites into workspace tools.
SDK licenses are accepted separately by sdkmanager with user authorization.
"""
import io, json, zipfile, urllib.request, pathlib, concurrent.futures, hashlib, subprocess
BASE=pathlib.Path(__file__).resolve().parents[2]/'tools/android'
BASE.mkdir(parents=True,exist_ok=True)
def get(url):
    return urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'TruckManiaBuild/1.0'}),timeout=120)
def download(url,path,sha=None):
    if not path.exists():
        with get(url) as response, path.open('wb') as out:
            while chunk:=response.read(1024*1024): out.write(chunk)
    if sha and hashlib.sha256(path.read_bytes()).hexdigest().lower()!=sha.lower():
        raise ValueError('Checksum mismatch: '+str(path))
    print('Downloaded',path.name,path.stat().st_size,flush=True)
def jdk():
    data=json.load(get('https://api.adoptium.net/v3/assets/latest/17/hotspot?architecture=x64&image_type=jdk&os=windows'))
    package=data[0]['binary']['package']
    path=BASE/'jdk17.zip'
    remote=RemoteZip(package['link'],package['size'])
    start=path.stat().st_size if path.exists() else 0
    remote.seek(start)
    data=remote.read()
    with path.open('ab') as out: out.write(data)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=package['checksum']: raise ValueError('Java checksum mismatch')
    with zipfile.ZipFile(path) as z: z.extractall(BASE/'java')
    print('Java ready',flush=True)
def sdk():
    import xml.etree.ElementTree as ET
    root=ET.fromstring(get('https://dl.google.com/android/repository/repository2-1.xml').read())
    package=next(p for p in root.findall('remotePackage') if p.attrib['path']=='cmdline-tools;latest')
    archive=next(a for a in package.findall('archives/archive') if a.findtext('host-os')=='windows')
    url='https://dl.google.com/android/repository/'+archive.findtext('complete/url')
    path=BASE/'cmdline-tools.zip'
    download(url,path)
    checksum=archive.findtext('complete/checksum')
    if checksum and hashlib.sha1(path.read_bytes()).hexdigest()!=checksum: raise ValueError('SDK checksum mismatch')
    with zipfile.ZipFile(path) as z: z.extractall(BASE/'sdk/cmdline-tools')
    extracted=BASE/'sdk/cmdline-tools/cmdline-tools'
    if extracted.exists(): extracted.rename(BASE/'sdk/cmdline-tools/latest')
    print('SDK tools ready',flush=True)
class RemoteZip(io.RawIOBase):
    def __init__(self,url,size): self.url=url;self.size=size;self.pos=0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self,off,whence=0):
        self.pos=off if whence==0 else self.pos+off if whence==1 else self.size+off
        return self.pos
    def read(self,n=-1):
        n=self.size-self.pos if n<0 else min(n,self.size-self.pos)
        if n<=0:return b''
        def part(bounds):
            start,end=bounds
            folder='template-parts' if 'godot-builds' in self.url else 'java-parts'
            cache=BASE/folder/f'{start}-{end}.bin'
            cache.parent.mkdir(exist_ok=True)
            if not cache.exists() or cache.stat().st_size!=end-start+1:
                subprocess.run(['curl.exe','-sS','-L','--fail','--max-time','120','--retry','2','--range',f'{start}-{end}','-o',str(cache),self.url+'?range='+str(start)],check=True)
            if cache.stat().st_size!=end-start+1: raise ValueError('Wrong cached range size')
            return cache.read_bytes()
        chunks=[(start,min(start+4194304,self.pos+n)-1) for start in range(self.pos,self.pos+n,4194304)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            data=b''.join(pool.map(part,chunks))
        if len(data)!=n: raise ValueError('Wrong range size')
        self.pos+=len(data)
        return data
def templates():
    release=json.load(get('https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.5.2-stable'))
    asset=next(a for a in release['assets'] if a['name']=='Godot_v4.5.2-stable_export_templates.tpz')
    with zipfile.ZipFile(RemoteZip(asset['browser_download_url'],asset['size'])) as z:
        for name in ('android_release.apk',):
            info=next(i for i in z.infolist() if i.filename.endswith('/'+name))
            data=z.read(info)
            (BASE/name).write_bytes(data)
            print('Template ready',name,len(data),flush=True)
if __name__=='__main__':
    import sys
    if '--templates-only' in sys.argv:
        templates()
    elif '--java-only' in sys.argv:
        jdk()
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            jobs=[pool.submit(fn) for fn in (jdk,sdk,templates)]
            for job in jobs: job.result()
