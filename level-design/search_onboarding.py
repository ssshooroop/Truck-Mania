from functools import lru_cache
from collections import deque, Counter
from fractions import Fraction
from pathlib import Path
import random, json

N=8; K=3; SIDE=8
COLORS=['O','G','O','R','R','G','O','R']
CAP=[4]*N
# Undo the loading batches from the completed level, prepending each unloaded batch.
REVERSE_UNLOADS=[[7],[6],[5],[4],[2,1,3],[],[],[0]]
QUEUE=[]
for undo_step in REVERSE_UNLOADS:
 for vehicle_id in undo_step:
  QUEUE[0:0]=[COLORS[vehicle_id]]*CAP[vehicle_id]
DIRECTIONS={'N':(0,-1),'S':(0,1),'W':(-1,0),'E':(1,0)}
CAND=[]
for direction,(dx,dy) in DIRECTIONS.items():
 for y in range(SIDE):
  for x in range(SIDE):
   cells=[(x-dx*j,y-dy*j) for j in range(2)]
   if not all(0<=a<SIDE and 0<=b<SIDE for a,b in cells):continue
   mask=sum(1<<(b*SIDE+a) for a,b in cells)
   sweep=0;a=x+dx;b=y+dy
   while 0<=a<SIDE and 0<=b<SIDE:
    sweep|=1<<(b*SIDE+a);a+=dx;b+=dy
   CAND.append((x,y,direction,mask,sweep))

def generate(seed):
 rng=random.Random(seed);placed=[];occ=0
 for i in reversed(range(N)):
  valid=[c for c in CAND if not (c[3]&occ or c[4]&occ)]
  if not valid:return None
  # Prefer placements which create a dependency, while retaining open edges.
  weights=[1+2*sum(bool(c[3]&other[4]) for other in placed) for c in valid]
  c=rng.choices(valid,weights)[0];placed.append(c);occ|=c[3]
 return list(reversed(placed))

def analyze(layout, full=True):
 blockers=[sum(1<<j for j,c in enumerate(layout) if j!=i and c[3]&layout[i][4]) for i in range(N)]
 def free(mask):return [i for i in range(N) if mask>>i&1 and not(blockers[i]&mask)]
 def settle(mask,active,q):
  active=dict(active)
  while q<len(QUEUE):
   matches=[i for i in active if COLORS[i]==QUEUE[q]]
   if not matches:break
   i=min(matches,key=lambda j:(-active[j],j));active[i]+=1;q+=1
   if active[i]==CAP[i]:del active[i]
  return mask,tuple(sorted(active.items())),q
 def move(s,i):return settle(s[0]^(1<<i),s[1]+((i,0),),s[2])
 start=((1<<N)-1,(),0);s=start;path=[]
 for i in range(N):
  legal=free(s[0]) if len(s[1])<K else []
  if i not in legal:return None
  nxt=move(s,i)
  path.append({'id':i,'available':legal,'before_buffer':list(s[1]),'after_buffer':list(nxt[1]),'queue_index':nxt[2]})
  s=nxt
 if s!=(0,(),len(QUEUE)):return None
 roots=len(path[0]['available'])
 if roots not in (3,4):return None
 if any(not 2<=len(p['available'])<=4 for p in path[:5]):return None
 if len(path[3]['available'])<2:return None
 @lru_cache(None)
 def visit(s):
  if s[2]==len(QUEUE):return Fraction(1),1,0,None
  legal=free(s[0]) if len(s[1])<K else []
  if not legal:return Fraction(0),0,1,0
  values=[visit(move(s,i)) for i in legal]
  losses=[v[3]+1 for v in values if v[3] is not None]
  return sum((v[0] for v in values),Fraction())/len(values),sum(v[1] for v in values),sum(v[2] for v in values),min(losses) if losses else None
 rate,winpaths,losepaths,mindead=visit(start)
 visited=set();pending=[start];bad_windows=[];edges=0;peak=0
 while pending:
  state=pending.pop()
  if state in visited:continue
  visited.add(state);mask,active,q=state;peak=max(peak,len(active))
  if q==len(QUEUE):continue
  phys=free(mask)
  if not any(COLORS[i] in QUEUE[q:q+K*min(CAP)] for i in phys):bad_windows.append(state)
  if len(active)>=K:continue
  for i in phys:pending.append(move(state,i));edges+=1
 score=(1000 if not losepaths else 0)+float(rate)*100+(mindead or 20)*4+sum(3<=len(p['available'])<=4 for p in path[:5])*10-len(bad_windows)*5
 return {'seed':None,'layout':[(c[0],c[1],c[2]) for c in layout],'blockers':blockers,'path':path,'random_win_rate':str(rate),'win_paths':winpaths,'lose_paths':losepaths,'min_deadlock_moves':mindead,'states':len(visited),'edges':edges,'window_failures':len(bad_windows),'peak_buffer':peak,'score':score}

best=None
for seed in range(20000):
 layout=generate(seed)
 if layout is None:continue
 result=analyze(layout)
 if result is None:continue
 result['seed']=seed
 if best is None or result['score']>best['score']:
  best=result
  Path('level-design/onboarding-search.json').write_text(json.dumps(best,indent=2),encoding='utf-8')
  print('best',seed,'rate',best['random_win_rate'],'dead',best['min_deadlock_moves'],'states',best['states'],'windows',best['window_failures'],'branch',[len(p['available']) for p in best['path']],flush=True)
 if best['lose_paths']==0 and best['window_failures']==0 and all(len(p['available']) in(3,4) for p in best['path'][:5]):break
print('FINAL',json.dumps(best),flush=True)
