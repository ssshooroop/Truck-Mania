"""Register new menu copy without replacing existing translation rows."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
rows={
 'menu.language.title':('Язык','Language'),
 'menu.support.title':('Поддержка','Support'),
 'menu.support.intro':('Нашли ошибку или есть идея?\nНапишите — читаем каждое письмо.','Found a bug or have an idea?\nSend us a message — we read every one.'),
 'menu.support.metadata':('Версия: %s\nID: %s','Build: %s\nID: %s'),
 'menu.support.compose':('Открыть письмо','Open email'),
 'menu.support.copy':('Скопировать сообщение','Copy message'),
 'menu.support.placeholder':('Ваше сообщение…','Your message…'),
 'menu.support.required':('Напишите сообщение','Please enter a message'),
 'menu.support.copied':('Сообщение скопировано','Message copied'),
 'menu.support.finish':('Завершите отправку в почтовом приложении','Finish sending in your email app'),
}
p=root/'localization/runtime.json'
data=json.loads(p.read_text(encoding='utf-8'))
catalog_path=root/'localization/catalog.ru.json'
catalog=json.loads(catalog_path.read_text(encoding='utf-8'))
known={e['id'] for e in catalog['entries']}
for key,(ru,en) in rows.items():
    data['messages'].setdefault(key,{'source':ru,'translations':{'en':en}})
    if key not in known:
        catalog['entries'].append({'id':key,'source':ru,'context':'Main menu','scope':'runtime','references':['scripts/ui/menu_windows.gd'],'placeholders':['%s','%s'] if '%s' in ru else [],'translation':'','notes':[]})
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
catalog_path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for locale in ['ru','en']:
    po=root/f'localization/{locale}.po'
    content=po.read_text(encoding='utf-8')
    for key,pair in rows.items():
        if key in content:continue
        content+='\nmsgctxt '+json.dumps(key)+'\nmsgid '+json.dumps(pair[0],ensure_ascii=False)+'\nmsgstr '+json.dumps(pair[locale=='en'],ensure_ascii=False)+'\n'
    po.write_text(content,encoding='utf-8')
