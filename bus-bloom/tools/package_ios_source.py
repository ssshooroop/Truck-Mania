"""Package a portable Godot project for iOS export on a Mac. Does not build an IPA."""
import fnmatch
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/ios"
OUT.mkdir(parents=True, exist_ok=True)
text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8-sig")
ios = text.split("[preset.1]", 1)[1].split("[preset.2]", 1)[0]
ios = "[preset.0]" + ios.replace("[preset.1.options]", "[preset.0.options]")
extra_excludes = "build/*,tools/*,web/*,android/*,*.blend,*.blend1,*.psd,*.xlsx,*.zip,*.bak"
ios = re.sub(r'exclude_filter="([^"]*)"', lambda m: 'exclude_filter="' + m[1] + ',' + extra_excludes + '"', ios)
patterns = re.search(r'exclude_filter="([^"]*)"', ios)[1].split(',')
suffixes = {'.png', '.jpg', '.jpeg', '.webp', '.svg', '.ogg', '.wav', '.mp3',
            '.ttf', '.otf', '.gd', '.gdshader', '.tscn', '.tres', '.res',
            '.json', '.po', '.import', '.uid', '.glb', '.gltf', '.bin'}
files = [ROOT / 'project.godot', ROOT / 'main.tscn']
for folder in ('assets', 'scripts', 'scenes', 'config', 'localization', 'generated_levels'):
    for p in (ROOT / folder).rglob('*'):
        if not p.is_file() or p.suffix.lower() not in suffixes:
            continue
        rel = p.relative_to(ROOT).as_posix()
        # An excluded image's import sidecar is also unnecessary.
        source = rel[:-7] if rel.endswith('.import') else rel
        if any(fnmatch.fnmatchcase(source, pattern) for pattern in patterns):
            continue
        files.append(p)

readme = '''Truck Mania — iOS source handoff (not an installable IPA)

1. On a Mac, install Xcode and open it once to finish setup.
2. Install Godot 4.5.2 standard and its matching export templates.
3. Extract this archive and open project.godot. Wait for asset import.
4. Project > Export > iOS: enter your Apple App Store Team ID.
   Bundle ID: org.truckmania.game. iPhone and iPad, portrait, iOS 14+.
5. Export Project to build/ios/truck-mania.zip (create that folder first).
   Export Project Only is enabled: this generates the Xcode project.
6. Extract the export, open its .xcodeproj in Xcode, select your team
   under Signing & Capabilities, and let Xcode manage signing.
7. Select a connected iPhone/iPad and Run for device testing.
   For distribution: Product > Archive, then export using the appropriate
   provisioning method. Upload to TestFlight/App Store only when requested.

Apple signing credentials are intentionally not included. A distribution
build needs your Apple Developer account and matching provisioning.
Neither compilation in Xcode nor device testing has been performed yet.
Check safe areas, scrolling road, loading screen, audio, crane and thieves.
The Billy icon uses icon512.png; Godot resizes it for iOS icon sizes.
For a sharper App Store icon, replace with the same artwork at 1024x1024.
No ads SDK is integrated; advertising buttons require separate integration.
'''
archive = OUT / 'truck-mania-ios-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in sorted(set(files)):
        z.write(p, p.relative_to(ROOT).as_posix())
    z.writestr('export_presets.cfg', ios)
    z.writestr('IOS-README.txt', readme)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names = set(z.namelist())
    for p in ('project.godot', 'main.tscn', 'scenes/loading_screen.tscn',
              'localization/runtime.json', 'assets/artwork/store icon/icon512.png'):
        assert p in names, p
    assert not any(n.endswith(('.jks', '.keystore', '.p12', '.mobileprovision')) for n in names)
    # Check literal resource references in source files against the archive.
    missing = set()
    for p in files:
        if p.suffix not in {'.gd', '.tscn', '.tres', '.godot', '.json'}:
            continue
        content = p.read_text(encoding='utf-8-sig')
        # Screenshot output paths are not input resources.
        content = re.sub(r'\.save_png\("[^"]+"\)', '', content)
        for ref in re.findall(r'res://[^"\n\r]+', content):
            candidate = ROOT / ref[6:]
            if candidate.is_file() and ref[6:] not in names:
                missing.add(ref)
    assert not missing, sorted(missing)
report = {'artifact': archive.name, 'bytes': archive.stat().st_size,
          'files': len(names), 'bundle_id': 'org.truckmania.game',
          'type': 'Godot source project, NOT IPA or Xcode export',
          'zip_integrity': 'passed', 'literal_resource_references': 'passed',
          'xcode_build': 'requires macOS and Apple signing', 'uploaded': False}
(OUT / 'ios-source-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
