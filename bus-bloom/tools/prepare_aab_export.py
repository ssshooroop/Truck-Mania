from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]; p=root/'export_presets.cfg';s=p.read_text(encoding='utf-8-sig')
# Maintain the APK preset and derive a separate release bundle preset.
first=s.split('[preset.1]',1)[0]
first=first.replace('[preset.0]', '[preset.3]').replace('[preset.0.options]','[preset.3.options]').replace('name="Android"','name="Android AAB"').replace('runnable=true','runnable=false').replace('build/android/truck-mania.apk','build/android/truck-mania.aab').replace('gradle_build/use_gradle_build=false','gradle_build/use_gradle_build=true').replace('gradle_build/export_format=0','gradle_build/export_format=1')
# The base preset already carries these values. Replace rather than duplicate keys.
for key,value in {'android_source_template':(root.parent/'tools/android/android_source.zip').as_posix(),'min_sdk':'24','target_sdk':'36'}.items():
 pattern=r'^gradle_build/'+key+r'=.*$'
 line='gradle_build/'+key+'="'+value+'"'
 first=re.sub(pattern,lambda _:line,first,flags=re.M) if re.search(pattern,first,re.M) else first+'\n'+line+'\n'
s=re.sub(r'\n\[preset\.3\][\s\S]*?(?=\n\[preset\.\d+\]|\Z)','',s)
p.write_text(s.rstrip()+'\n\n'+first,encoding='utf-8')
p=root/'.gitignore';s=p.read_text();
if '/android/' not in s:s+='\n# Generated Gradle Android project\n/android/\n'
p.write_text(s)

