"""Package Godot export with retryable, compressed 8 MiB transport chunks."""
from pathlib import Path
import gzip, json, sys, shutil
root = Path(__file__).resolve().parents[2]
dist = root / "sites/cargo-yard-preview/dist"
build = sys.argv[1]
manifest = {}
for name, mime in [("index.wasm", "application/wasm"), ("index.pck", "application/octet-stream")]:
    raw = (dist/name).read_bytes()
    chunk_size = 8*1024*1024
    for i, start in enumerate(range(0, len(raw), chunk_size)):
        chunk = raw[start:start+chunk_size]
        packed = gzip.compress(chunk, compresslevel=9, mtime=0)
        assert gzip.decompress(packed) == chunk
        
        (dist/(name+f".part{i}.gzdata")).write_bytes(packed)
    manifest[name] = dict(parts=i+1, size=len(raw), mime=mime, chunk_size=chunk_size)
    (dist/name).unlink()
loader = (root/"bus-bloom/web/wasm-loader.js").read_text(encoding="utf-8")
loader = loader.replace("const files = {};", "const files = "+json.dumps(manifest)+";")
loader = loader.replace("tablet2-20261019", build)
translations = json.loads((root/'bus-bloom/web/loading-translations.json').read_text(encoding='utf-8'))
loader = loader.replace('const translations = {};', 'const translations = '+json.dumps(translations, ensure_ascii=False)+';')
(dist/"wasm-loader.js").write_text(loader, encoding="utf-8")
p = dist/"index.html"
s = p.read_text(encoding="utf-8").replace('lang="en"', 'lang="ru"')
s = s.replace('<script src="index.js"></script>', f'<script src="wasm-loader.js?v={build}"></script><script src="index.js?v={build}"></script>')
s = s.replace("console.error(err);", "console.error(err); window.CargoBoot?.fail(err);")
s = s.replace("setStatusMode('hidden');", "window.CargoBoot?.done(); setStatusMode('hidden');")
s = s.replace('<title>Cargo Yard</title>', '<title>Truck Mania</title>')
s = s.replace('</head>', f'<link rel="stylesheet" href="loading-screen.css?v={build}"></head>')
s = s.replace('src="index.png"', 'src="loading-background.png"')
s = s.replace('<progress id="status-progress">', '<img id="loading-logo" src="loading-logo.png" alt="Truck Mania"><progress id="status-progress">')
art = root/'bus-bloom/assets/artwork/load screen'
shutil.copyfile(art/'Load_screen.png',dist/'loading-background.png')
shutil.copyfile(art/'Truck-Mania-Logo.png',dist/'loading-logo.png')
shutil.copyfile(root/'bus-bloom/web/loading-screen.css',dist/'loading-screen.css')
p.write_text(s, encoding="utf-8")
print("Packaged", build, manifest)
