"""Merge the reviewed ID / Source / Translation workbook without replacing other IDs."""
import collections
import json
import re
import sys
from import_localization import ROOT, LOCALES, read_book

TOKEN = re.compile(r'\{\{[^{}]+\}\}|\{[^{}]+\}|%(?:0?\d+)?[dsf]')

def run(path):
    book = read_book(path)
    runtime_path = ROOT / 'localization/runtime.json'
    catalog_path = ROOT / 'localization/catalog.ru.json'
    data = json.loads(runtime_path.read_text(encoding='utf-8'))
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    entries = {e['id']: e for e in catalog['entries']}
    sources = {r['A']: r['B'] for r in book['EN'] if r.get('A') not in (None, '', 'ID')}
    english = {r['A']: r['C'] for r in book['EN'] if r.get('A') in sources}
    pending = {}
    for sheet, locale in LOCALES.items():
        seen = set()
        for r in book[sheet]:
            key = r.get('A', '')
            if key in ('', 'ID'): continue
            if key not in sources or key in seen: raise ValueError(f'{sheet}: unknown/duplicate {key}')
            seen.add(key)
            source, value = sources[key], r.get('C', '')
            if r.get('B') != (source if sheet == 'EN' else english[key]):
                raise ValueError(f'{sheet}: source mismatch {key}')
            if not value.strip() or collections.Counter(TOKEN.findall(source)) != collections.Counter(TOKEN.findall(value)):
                raise ValueError(f'{sheet}: blank/changed placeholders {key}')
            if key in data['messages'] and data['messages'][key]['source'] != source:
                raise ValueError(f'Source revision requires review: {key}')
            pending.setdefault(key, {})[locale] = value
        if seen != set(sources): raise ValueError(f'{sheet}: missing IDs')
    for key, translations in pending.items():
        source = sources[key]
        item = data['messages'].setdefault(key, {'source': source, 'translations': {}})
        item['translations'].update(translations)
        # Source-based adapters can select either duplicate; keep both consistent.
        for other in data['messages'].values():
            if other['source'] == source: other['translations'].update(translations)
        if key not in entries:
            catalog['entries'].append({'id': key, 'source': source, 'context': 'Crane onboarding' if key.startswith('crane.') else 'Web loading screen', 'scope': 'runtime', 'references': ['scripts/ui/modal_catalog.gd' if key.startswith('crane.') else 'web/wasm-loader.js'], 'placeholders': TOKEN.findall(source), 'translation': '', 'notes': []})
    runtime_path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for locale in ['ru', *LOCALES.values()]:
        lines = ['msgid ""', 'msgstr ""', json.dumps('Language: '+locale+'\n'), '"Content-Type: text/plain; charset=UTF-8\\n"', '']
        for key, item in data['messages'].items():
            value = item['translations'].get(locale, item['source'] if locale == 'ru' else '')
            lines += ['msgctxt '+json.dumps(key), 'msgid '+json.dumps(item['source'], ensure_ascii=False), 'msgstr '+json.dumps(value, ensure_ascii=False), '']
        (ROOT/f'localization/{locale}.po').write_text('\n'.join(lines), encoding='utf-8')
    # Embedded in the loader during export, available before the Godot pack loads.
    boot = {loc: {key: data['messages'][key]['source'] if loc == 'ru' else pending[key][loc] for key in sources if key.startswith('loading.')} for loc in ['ru', *LOCALES.values()]}
    (ROOT/'web/loading-translations.json').write_text(json.dumps(boot, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Imported {len(pending)} IDs in {len(LOCALES)} languages; synchronized source aliases and PO files.')

if __name__ == '__main__': run(sys.argv[1])
