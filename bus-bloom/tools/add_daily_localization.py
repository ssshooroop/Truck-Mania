"""Register new menu copy without replacing existing translation rows."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
rows={'daily.title': ('Ежедневный бонус', 'Daily rewards'), 'daily.tomorrow': ('Завтра: %s', 'Tomorrow: %s'), 'daily.next_week': ('Новая неделя начнётся завтра!', 'A new week starts tomorrow!'), 'daily.invitation': ('Заходи каждый день — награды растут!', 'Come back daily for bigger rewards!'), 'daily.claim': ('Забрать', 'Claim'), 'daily.missed': ('Пропущен', 'Missed'), 'daily.today': ('Сегодня', 'Today'), 'daily.day': ('День %d', 'Day %d'), 'daily.item.undo': ('отмена хода ×%d', 'Undo ×%d'), 'daily.item.extra_slot': ('место ×%d', 'Extra slot ×%d'), 'daily.item.crane': ('кран ×%d', 'Crane ×%d'), 'daily.item.shuffle': ('перемешивание ×%d', 'Shuffle ×%d'), 'daily.item.gift': ('подарок ×%d', 'Gift ×%d')}
p=root/'localization/runtime.json'
data=json.loads(p.read_text(encoding='utf-8'))
catalog_path=root/'localization/catalog.ru.json'
catalog=json.loads(catalog_path.read_text(encoding='utf-8'))
known={e['id'] for e in catalog['entries']}
for key,(ru,en) in rows.items():
    data['messages'].setdefault(key,{'source':ru,'translations':{'en':en}})
    if key not in known:
        catalog['entries'].append({'id':key,'source':ru,'context':'Daily rewards','scope':'runtime','references':['scripts/ui/modal_catalog.gd'],'placeholders':['%s','%s'] if '%s' in ru else [],'translation':'','notes':[]})
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
catalog_path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for locale in ['ru','en']:
    po=root/f'localization/{locale}.po'
    content=po.read_text(encoding='utf-8')
    for key,pair in rows.items():
        if key in content:continue
        content+='\nmsgctxt '+json.dumps(key)+'\nmsgid '+json.dumps(pair[0],ensure_ascii=False)+'\nmsgstr '+json.dumps(pair[locale=='en'],ensure_ascii=False)+'\n'
    po.write_text(content,encoding='utf-8')
