"""Validate workbook IDs/tokens and merge translations without deleting absent rows.
Usage: python tools/import_localization.py path/to/workbook.xlsx
Only nonempty translations update existing entries. No spreadsheet writes.
"""
import json, re, sys, zipfile, collections
from pathlib import Path
from xml.etree import ElementTree as ET

NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
ROOT = Path(__file__).resolve().parents[1]
TOKENS = re.compile(r'%(?:0?\d+)?[dsf]|\$\{[^}]+\}')
LOCALES = {'EN':'en','DE':'de','FR':'fr','JA':'ja','KO':'ko','ZH':'zh','TR':'tr','PL':'pl','ES':'es','AR':'ar'}

def read_book(path):
    with zipfile.ZipFile(path) as z:
        strings = [''.join(n.itertext()) for n in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si', NS)]
        rels = {n.get('Id'): n.get('Target') for n in ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
        result = {}
        for sheet in ET.fromstring(z.read('xl/workbook.xml')).findall('m:sheets/m:sheet', NS):
            target = rels[sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            rows = []
            for row in ET.fromstring(z.read(target)).findall('m:sheetData/m:row', NS):
                values = {'row': int(row.get('r'))}
                for cell in row.findall('m:c', NS):
                    val = cell.find('m:v', NS)
                    value = val.text if val is not None else ''
                    if cell.get('t') == 's': value = strings[int(value)]
                    elif cell.get('t') == 'inlineStr': value = ''.join(cell.find('m:is', NS).itertext())
                    values[re.sub(r'\d', '', cell.get('r'))] = value
                rows.append(values)
            result[sheet.get('name')] = rows
        return result

def run(path):
    book = read_book(path)
    catalog = json.loads((ROOT/'localization/catalog.ru.json').read_text(encoding='utf-8'))
    entries = {e['id']:e for e in catalog['entries'] if e['scope'] != 'legacy_or_mock'}
    output = ROOT/'localization/runtime.json'
    data = json.loads(output.read_text(encoding='utf-8')) if output.exists() else {'schema_version':1,'source_locale':'ru','messages':{}}
    for key, entry in entries.items():
        item = data['messages'].setdefault(key, {'source':entry['source'],'translations':{}})
        if item['source'] != entry['source']: raise ValueError('Source revision requires review: '+key)
    for sheet, locale in LOCALES.items():
        seen = set()
        for row in book[sheet]:
            key = row.get('C','')
            if not key or key == 'ID / msgctxt': continue
            if key in seen or key not in entries: raise ValueError(f'{sheet}!C{row["row"]}: duplicate/unknown ID')
            seen.add(key)
            value = row.get('B','')
            if not value.strip(): continue
            if collections.Counter(TOKENS.findall(value)) != collections.Counter(TOKENS.findall(entries[key]['source'])):
                raise ValueError(f'{sheet}!B{row["row"]}: changed placeholders')
            icons = re.findall(r'\{\{([^{}]+)\}\}', value)
            if any(icon != 'coin' for icon in icons): raise ValueError(f'Unknown icon in {sheet}!B{row["row"]}')
            data['messages'][key]['translations'][locale] = value
    # Keep Russian price labels consistent with translated icon labels.
    for item in data['messages'].values():
        source = item['source']
        if '{{coin}}' in item['translations'].get('en',''):
            item['translations']['ru'] = re.sub(r'монет[аы]?', '{{coin}}', source)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for locale in ['ru', *LOCALES.values()]:
        lines=['msgid ""','msgstr ""',json.dumps('Language: '+locale+'\n'), '"Content-Type: text/plain; charset=UTF-8\\n"','']
        for key,item in data['messages'].items():
            value=item['translations'].get(locale,item['source'] if locale=='ru' else '')
            lines += ['msgctxt '+json.dumps(key,ensure_ascii=False),'msgid '+json.dumps(item['source'],ensure_ascii=False),'msgstr '+json.dumps(value,ensure_ascii=False),'']
        (ROOT/f'localization/{locale}.po').write_text('\n'.join(lines),encoding='utf-8')
    print(f'Imported {len(entries)} IDs / {len(LOCALES)} translations; existing missing rows retained.')

if __name__ == '__main__': run(sys.argv[1])
