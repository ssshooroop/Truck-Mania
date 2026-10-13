"""Deterministic reverse-built opening chapter; no edits to game/UI files."""
from pathlib import Path
from functools import lru_cache
from fractions import Fraction
from collections import Counter
import json,random

OUT=Path(__file__).parent/'chapter-01';OUT.mkdir(exist_ok=True)
PALETTE=['#FF8614','#FF3535','#7C828A','#078FFF']
DIR={'N':(0,-1),'S':(0,1),'W':(-1,0),'E':(1,0)}
PROFILES=[
 dict(name='Первая отгрузка',n=8,side=8,caps=[4]*8,colors=[0,2,0,1,1,2,0,1],groups=[[0],[1,2,3],[4],[5],[6],[7]],chunk=4,target=(1,1),depth=99,lesson='Цвет груза, свободный выезд и ожидание на перроне'),
 dict(name='Освободи дорогу',n=8,side=9,caps=[4]*8,colors=[0,1,2,0,2,1,0,1],groups=[[0],[1,2],[3,4,5],[6],[7]],chunk=4,target=(1,1),depth=99,lesson='Сначала убрать машину, которая перекрывает выезд'),
 dict(name='Разная вместимость',n=9,side=9,caps=[2,4,2,4,2,4,2,4,2],colors=[0,1,2,0,1,2,0,1,2],groups=[[0],[1,2],[3,4,5],[6],[7],[8]],chunk=2,target=(.90,1),depth=4,lesson='Маленькая машина уезжает раньше большой; учитывать остаток мест'),
 dict(name='Оставь место',n=10,side=10,caps=[2,4,2,4,2,4,2,4,2,4],colors=[0,1,2,3,0,1,2,3,0,1],groups=[[0],[1,2],[3,4,5],[6,7],[8],[9]],chunk=2,target=(.80,.98),depth=4,lesson='Четвёртый материал и сохранение свободного места для головы очереди'),
 dict(name='Большая поставка',n=12,side=11,caps=[2,4,2,6,4,2,4,6,2,4,2,4],colors=[0,1,2,3,0,1,2,3,0,1,2,3],groups=[[0],[1,2],[3,4,5],[6,7,8],[9],[10],[11]],chunk=2,target=(.85,.95),depth=3,lesson='Большая машина на шесть грузов и чередование коротких пачек'),
]

def candidates(side,length):
 result=[]
 for direction,(dx,dy) in DIR.items():
  for y in range(side):
   for x in range(side):
    cells=[(x-dx*j,y-dy*j) for j in range(length)]
    if any(not(0<=a<side and 0<=b<side) for a,b in cells):continue
    body=sum(1<<(b*side+a) for a,b in cells);ray=0;a=x+dx;b=y+dy
    while 0<=a<side and 0<=b<side:
     ray|=1<<(b*side+a);a+=dx;b+=dy
    result.append((x,y,direction,body,ray))
 return result

def queue_plan(p):
 # Undo the prescribed completed batches from last to first; prepend to FIFO.
 batches=[]
 for group in p['groups']:
  remaining={i:p['caps'][i] for i in group}
  order=list(reversed(group))
  while any(remaining.values()):
   for i in order:
    count=min(p['chunk'],remaining[i])
    if count:batches.append((i,count));remaining[i]-=count
 queue=[]
 for i,count in reversed(batches):queue[0:0]=[p['colors'][i]]*count
 return queue

def analyze(p,layout,queue):
 n=p['n'];caps=p['caps'];colors=p['colors'];k=3
 blockers=[sum(1<<j for j,c in enumerate(layout) if j!=i and c[3]&layout[i][4]) for i in range(n)]
 def physical(mask):return tuple(i for i in range(n) if mask>>i&1 and not(blockers[i]&mask))
 def moves(s):return physical(s[0]) if len(s[1])<k else ()
 def advance(s,i):
  mask,active,q=s;active=dict(active);active[i]=0;events=[]
  while q<len(queue):
   matching=[j for j in active if colors[j]==queue[q]]
   if not matching:break
   j=min(matching,key=lambda j:(-active[j],j));active[j]+=1;q+=1
   if events and events[-1][0]==j:events[-1][1]+=1
   else:events.append([j,1])
   if active[j]==caps[j]:del active[j]
  return (mask^(1<<i),tuple(sorted(active.items())),q),events
 start=((1<<n)-1,(),0);s=start;path=[]
 for i in range(n):
  legal=moves(s)
  if i not in legal:return None
  nxt,events=advance(s,i)
  path.append(dict(vehicle=i,choices=list(legal),waiting=list(nxt[1]),cursor=nxt[2],events=events));s=nxt
 if s!=(0,(),len(queue)):return None
 if len(path[0]['choices']) not in (3,4):return None
 if not any(len(x['waiting'])==2 for x in path[2:-2]):return None
 if any(x['waiting'] for x in path[-2:]):return None
 if not any(colors[i]==queue[0] for i in path[0]['choices']):return None
 # At most four early choices; a natural taper is allowed near completion.
 if any(not 2<=len(x['choices'])<=4 for x in path[:n//2]):return None
 seen=set();dead=[];badwindows=0;edges=0
 @lru_cache(None)
 def visit(s):
  nonlocal badwindows,edges
  seen.add(s)
  if s[2]==len(queue):return Fraction(1),1,0,None
  if not any(colors[i] in queue[s[2]:s[2]+3*min(caps)] for i in physical(s[0])):badwindows+=1
  legal=moves(s)
  if not legal:dead.append(s);return Fraction(0),0,1,0
  edges+=len(legal);children=[visit(advance(s,i)[0]) for i in legal]
  depths=[c[3]+1 for c in children if c[3] is not None]
  return sum((c[0] for c in children),Fraction())/len(legal),sum(c[1] for c in children),sum(c[2] for c in children),min(depths) if depths else None
 probability,wins,losses,depth=visit(start)
 if badwindows or not p['target'][0]<=float(probability)<=p['target'][1]:return None
 if depth is not None and depth<p['depth']:return None
 # Also verify the exact same level with each optional purchased buffer size.
 extra={}
 for slots in [4,5]:
  k=slots;visit.cache_clear();seen.clear();dead.clear();badwindows=0;edges=0
  prob,_,_,_=visit(start);extra[str(slots)]=str(prob)
 k=3;visit.cache_clear();seen.clear();dead.clear();badwindows=0;edges=0
 probability,wins,losses,depth=visit(start)
 return dict(path=path,blockers=blockers,probability=str(probability),states=len(seen),edges=edges,wins=wins,losses=losses,deadlocks=len(dead),minimum_calls_to_deadlock=depth,optional_slots=extra,window_failures=badwindows)

def build(index,p):
 lengths=[{2:2,4:3,6:4}[c] for c in p['caps']]
 choices={length:candidates(p['side'],length) for length in set(lengths)}
 queue=queue_plan(p)
 for seed in range(50000):
  rng=random.Random(seed+index*100000);occupied=0;placed=[]
  for i in reversed(range(p['n'])):
   valid=[c for c in choices[lengths[i]] if not(c[3]&occupied or c[4]&occupied)]
   if not valid:break
   weights=[1+3*sum(bool(c[3]&j[4]) for j in placed) for c in valid]
   c=rng.choices(valid,weights)[0];placed.append(c);occupied|=c[3]
  if len(placed)!=p['n']:continue
  layout=list(reversed(placed));report=analyze(p,layout,queue)
  if report is None:continue
  save(index,p,layout,queue,report,seed+index*100000)
  return
 raise RuntimeError(f'No suitable level {index}; constraints must not be silently weakened')


def save(index,p,layout,queue,report,seed):
 prefix=f'level-{index:03d}'
 config=dict(metadata=dict(id=index,name=p['name'],difficulty='EASY' if index<5 else 'MEDIUM',buffer_slots=3,max_buffer_slots=5,color_count=len(set(p['colors'])),seed=seed,lesson=p['lesson'],coordinate_system='logical_grid_head_top_left'),grid=dict(width=p['side'],height=p['side'],walls=[],obstacles=[]),vehicles=[dict(id=f'V{i+1:02d}',color=PALETTE[p['colors'][i]],capacity=p['caps'][i],position=list(c[:2]),direction=c[2],length={2:2,4:3,6:4}[p['caps'][i]]) for i,c in enumerate(layout)],passenger_queue=[PALETTE[c] for c in queue],golden_path=[f'V{i+1:02d}' for i in range(p['n'])])
 reverse=dict(initial_state='all_vehicles_departed_and_queue_empty',undo_steps=[dict(return_vehicle=f"V{step['vehicle']+1:02d}",prepend_unloaded_batches=[dict(vehicle_id=f'V{i+1:02d}',color=PALETTE[p['colors'][i]],count=count) for i,count in reversed(step['events'])]) for step in reversed(report['path'])])
 for suffix,data in [('',config),('-reverse',reverse),('-analysis',report)]:
  (OUT/f'{prefix}{suffix}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
 print(prefix,'seed',seed,'states',report['states'],'rate',float(Fraction(report['probability'])),'deadlock depth',report['minimum_calls_to_deadlock'],flush=True)

def extend(index,base_index,added_caps,added_colors):
 old=json.loads((OUT/f'level-{base_index:03d}.json').read_text(encoding='utf-8'))
 p=PROFILES[index-1].copy()
 p.update(side=10,caps=[v['capacity'] for v in old['vehicles']]+added_caps,colors=[PALETTE.index(v['color']) for v in old['vehicles']]+added_colors)
 base=[]
 for v in old['vehicles']:
  base.append(next(c for c in candidates(p['side'],v['length']) if list(c[:2])==v['position'] and c[2]==v['direction']))
 queue=[PALETTE.index(c) for c in old['passenger_queue']]
 for color,cap in zip(added_colors,added_caps):queue.extend([color]*cap)
 options=[candidates(p['side'],{2:2,4:3,6:4}[cap]) for cap in added_caps]
 rng=random.Random(index*100000)
 for seed in range(50000):
  layout=list(base)
  for opts in options:
   occupied=0;rays=0
   for c in layout:occupied|=c[3];rays|=c[4]
   valid=[c for c in opts if not(c[3]&occupied or c[3]&rays)]
   if not valid:break
   layout.append(rng.choice(valid))
  if len(layout)!=p['n']:continue
  report=analyze(p,layout,queue)
  if report:
   save(index,p,layout,queue,report,index*100000+seed);return
 raise RuntimeError(f'Extension {index} did not pass constraints')


def upgrade_fleet():
 old=json.loads((OUT/'level-004.json').read_text(encoding='utf-8'))
 p=PROFILES[4].copy()
 p.update(n=len(old['vehicles']),side=10,caps=[v['capacity'] for v in old['vehicles']],colors=[PALETTE.index(v['color']) for v in old['vehicles']],target=(.80,.95))
 p['caps'][0]=6
 p['lesson']='Первой загрузить машину на шесть грузов; затем применить знакомые правила ожидания'
 layout=[]
 turn={'N':'E','E':'S','S':'W','W':'N'}
 for i,v in enumerate(old['vehicles']):
  x,y=v['position'];head=[9-y,x];direction=turn[v['direction']]
  layout.append(next(c for c in candidates(10,4 if i==0 else v['length']) if list(c[:2])==head and c[2]==direction))
 assert all(not(a[3]&c[3]) for i,a in enumerate(layout) for c in layout[i+1:])
 queue=[p['colors'][0]]*4+[PALETTE.index(c) for c in old['passenger_queue']]
 report=analyze(p,layout,queue)
 assert report is not None
 save(5,p,layout,queue,report,500000)

if __name__=='__main__':
 for index,p in enumerate(PROFILES[:3],1):build(index,p)
 extend(4,3,[4],[3])
 upgrade_fleet()
