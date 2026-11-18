"""Read-only static localization inventory; findings require reachability review.
Run from any directory. Does not edit game code or translations.
"""
from pathlib import Path
import collections,json,re
root=Path(__file__).resolve().parents[1]
messages=json.loads((root/'localization/runtime.json').read_text(encoding='utf-8'))['messages']
known={v['source'] for v in messages.values()}
unknown=[]
for path in (root/'scripts').rglob('*.gd'):
 for number,line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(),1):
  if line.lstrip().startswith('#'):continue
  for match in re.finditer(r'"(?:\\.|[^"\\])*"',line):
   try:value=json.loads(match[0])
   except ValueError:continue
   if re.search('[А-Яа-яЁё]',value) and value not in known and not value.startswith('res://'):
    unknown.append({'file':path.relative_to(root).as_posix(),'line':number,'source':value})
groups=collections.defaultdict(list)
for key,item in messages.items():groups[item['source']].append(key)
shadowed=[]
for source,keys in groups.items():
 if len(keys)<2:continue
 last=keys[-1]
 lost=sorted(set().union(*(messages[k]['translations'].keys() for k in keys))-set(messages[last]['translations']))
 if lost:shadowed.append({'source':source,'ids':keys,'selected_id':last,'lost_locales':lost})
report={'scope':'Static code inventory only; unknown literals are candidates, not all visible defects.',
 'unknown_literals':unknown,'shadowed_translations':shadowed,
 'incomplete_entries':[{'id':k,'source':v['source'],'missing':[loc for loc in ['en','de','fr','ja','ko','zh','tr','pl','es','ar'] if not v['translations'].get(loc)]} for k,v in messages.items() if any(not v['translations'].get(loc) for loc in ['en','de','fr','ja','ko','zh','tr','pl','es','ar'])]}
p=root/'artifacts/localization-static-inventory.json';p.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Static inventory:',len(unknown),'candidate literals;',len(shadowed),'shadowed sources;',len(report['incomplete_entries']),'incomplete entries')
