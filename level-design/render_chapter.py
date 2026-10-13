from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
from fractions import Fraction

root=Path(__file__).parent/'chapter-01'
im=Image.new('RGB',(1800,740),'#F1F0F4');draw=ImageDraw.Draw(im)
def text(x,y,s,size=18,fill='#243448'):
 draw.text((x,y),s,font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',size),fill=fill)
text(25,15,'ПЕРВЫЕ ПЯТЬ УРОВНЕЙ · схемы логики, 3 открытых места',28)
rows=[];details=[]
for i in range(1,6):
 c=json.loads((root/f'level-{i:03d}.json').read_text(encoding='utf-8'))
 r=json.loads((root/f'level-{i:03d}-verification.json').read_text(encoding='utf-8'))
 ox=20+(i-1)*360;oy=165;side=c['grid']['width'];cell=320/side
 text(ox,70,f"{i}. {c['metadata']['name']}",21)
 caps='/'.join(map(str,sorted({v['capacity'] for v in c['vehicles']})))
 text(ox,106,f"Машин: {len(c['vehicles'])} · Цветов: {c['metadata']['color_count']}",17)
 text(ox,132,f'Вместимость: {caps}',17)
 draw.rectangle((ox,oy,ox+320,oy+320),fill='#B2B0B6')
 for k in range(side+1):
  draw.line((ox+k*cell,oy,ox+k*cell,oy+320),fill='#CDCAD1')
  draw.line((ox,oy+k*cell,ox+320,oy+k*cell),fill='#CDCAD1')
 for v in c['vehicles']:
  x,y=v['position'];dx,dy={'N':(0,-1),'S':(0,1),'W':(-1,0),'E':(1,0)}[v['direction']]
  tx=x-dx*(v['length']-1);ty=y-dy*(v['length']-1)
  box=(ox+min(x,tx)*cell+3,oy+min(y,ty)*cell+3,ox+(max(x,tx)+1)*cell-3,oy+(max(y,ty)+1)*cell-3)
  draw.rounded_rectangle(box,radius=5,fill=v['color'],outline='#243448',width=2)
  cx=ox+(x+.5)*cell;cy=oy+(y+.5)*cell
  draw.line((cx-dx*7,cy-dy*7,cx+dx*7,cy+dy*7),fill='white',width=3)
  draw.polygon([(cx+dx*9,cy+dy*9),(cx-dy*5,cy+dx*5),(cx+dy*5,cy-dx*5)],fill='white')
  text(ox+(tx+.5)*cell-9,oy+(ty+.5)*cell-9,v['id'][1:],14,'white')
 text(ox,500,'Очередь слева направо:',17)
 for j,color in enumerate(c['passenger_queue']):
  x=ox+(j%24)*13;y=530+(j//24)*18
  draw.rectangle((x,y,x+10,y+13),fill=color,outline='#243448')
 rate=float(Fraction(r['random_legal_choice_win_probability']))*100
 text(ox,600,f'{len(c["vehicles"])} вызовов · {len(c["passenger_queue"])} грузов',17)
 text(ox,630,f'Случайный выбор: {rate:.1f}% побед',16)
 text(ox,657,'Без тупиков' if not r['deadlocks'] else f"Тупиковых состояний: {r['deadlocks']}",16)
 rows.append(f"| {i}. {c['metadata']['name']} | {len(c['vehicles'])} | {c['metadata']['color_count']} | {caps} | {len(c['passenger_queue'])} | {rate:.1f}% |")
 proof=['| Вызов | Загрузка за ход | Ожидают после | Всего загружено |','|---|---|---|---|']
 for step in r['golden_path']:
  proof.append(f"| {step['vehicle']} | {step['delivered_this_move']} | {', '.join(v for v,n in step['waiting_after']) or '—'} | {step['queue_consumed']} |")
 dead='Не достижим.' if not r['deadlocks'] else 'Пример: '+' → '.join(r['deadlock_example'])+'.'
 details.append(f"## {i}. {c['metadata']['name']}\n\n{c['metadata']['lesson']}.\n\n"+'\n'.join(proof)+f"\n\nТупик: {dead} Проверено {r['reachable_states']} состояний. Конфиг: [level-{i:03d}.json](level-{i:03d}.json).\n")
text(25,712,'Проценты — математическая модель случайных допустимых вызовов, не прогноз поведения людей.',17)
im.save(root/'chapter-overview.png')
intro='''# Первая глава — расчёт пяти уровней

Это отдельный пакет дизайна. Интерфейс и опубликованная игра не изменялись.

Три места открыты сразу, ещё два покупаются за монеты, полученные за прохождение. Все пять уровней решаются на трёх местах без бустеров. Цены и награды здесь не перебалансировались.

| Уровень | Машин / минимум вызовов | Цветов | Вместимость | Грузов | Победа при случайном допустимом выборе |
|---|---:|---:|---|---:|---:|
'''
notes='''
## Что именно проверено

Полный перебор всех достижимых состояний: сохранение количества грузов каждого цвета, лимит мест по машинам, отсутствие пересечений на сетке, ацикличность блокировок, скользящее окно 3×минимальная вместимость. Для каждого уровня сохранены гарантированный порядок вызовов и обратная сборка из завершённого состояния. Проверка независима от генератора. Отдельно проверены 4 и 5 доступных мест.

Процент рассчитан для стратегии, выбирающей каждый допустимый вызов с одинаковой вероятностью. Это не доля победных последовательностей и не человеческий win-rate. Первые два уровня невозможно проиграть допустимыми вызовами. Дальше появляются ошибочные решения. «Минимум вызовов до тупика» в JSON считает все вызовы от старта, а не число ошибок подряд; его нельзя выдавать за глубину в ошибках.

Очевидный первый ход, два занятых места в середине и быстрый финал предусмотрены в рекомендованном прохождении. Другие решения могут иметь иной темп. Число вариантов естественно уменьшается в конце. Пятый уровень знакомит с длинной машиной; реальную сложность и длительность следует уточнить на игроках.

## Перед подключением к игре

Координаты в JSON — голова машины на логической сетке, начало сверху слева. Длина 2/3/4 клетки соответствует вместимости 2/4/6. Это не пиксельная расстановка и не готовая замена текущих массивов Godot. При переносе нужно сохранить реальные размеры машин, проверить блокировки по их контурам и проезд к перрону. Новая первая расстановка этой главы заменяет прежний отдельный проект онбординга только на уровне дизайна; исходные файлы старого варианта сохранены.

Модель проверяется после завершения автоматической FIFO-погрузки. В игре разрешена отправка во время работы грузчика: при интеграции нужна отдельная проверка резервирования грузов и мест, порядка одновременных событий, отмены и сохранений. Текущие результаты не доказывают безопасность ещё не выполненной интеграции.

Для каждого `level-NNN.json` приложены `-reverse.json`, `-analysis.json`, независимый `-verification.json` и проверки дополнительных мест `-verification-k4.json`, `-verification-k5.json`. Изображение `chapter-overview.png` — схема для обсуждения, не макет интерфейса.
'''
(root/'CHAPTER-DESIGN.md').write_text(intro+'\n'.join(rows)+'\n\n'+'\n'.join(details)+notes,encoding='utf-8')
print('Chapter overview and design document saved')
