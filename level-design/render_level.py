from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
root=Path('level-design');c=json.loads((root/'level-001-easy.json').read_text(encoding='utf-8'))
S=2;im=Image.new('RGB',(700*S,930*S),'#F3F1F5');d=ImageDraw.Draw(im)
fontpath='C:/Windows/Fonts/arial.ttf'
def text(x,y,value,size=18,color='#25303B',center=False):
 f=ImageFont.truetype(fontpath,size*S)
 if center:
  box=d.textbbox((0,0),value,font=f);x-= (box[2]-box[0])/(2*S)
 d.text((x*S,y*S),value,font=f,fill=color)
def box(coords,fill,outline=None,width=1,radius=0):
 d.rounded_rectangle(tuple(v*S for v in coords),radius=radius*S,fill=fill,outline=outline,width=width*S)
text(350,22,'ПЕРВАЯ ОТГРУЗКА',28,center=True)
text(350,61,'EASY · 8 машин · по 4 груза',18,center=True)
for i in range(5):
 x=78+i*111;locked=i>=3
 box((x,102,x+99,173),'#D9D6DD' if locked else '#FFFFFF','#A8A4AF',2,10)
 text(x+50,112,str(i+1),23,center=True)
 text(x+50,148,('60 монет' if i==3 else '100 монет') if locked else 'открыто',14,center=True)
text(350,186,'3 открытых места + 2 покупаемых',16,center=True)
ox,oy,cell=94,258,64
box((ox,oy,ox+512,oy+512),'#B2B0B6',radius=8)
for n in range(9):
 d.line((ox*S,(oy+n*cell)*S,(ox+512)*S,(oy+n*cell)*S),fill='#CFCDD3',width=S)
 d.line(((ox+n*cell)*S,oy*S,(ox+n*cell)*S,(oy+512)*S),fill='#CFCDD3',width=S)
for i in range(8):
 text(ox+i*cell+cell/2,230,str(i),15,center=True)
 text(68,oy+i*cell+22,str(i),15,center=True)
dirs={'N':(0,-1),'S':(0,1),'W':(-1,0),'E':(1,0)}
for v in c['vehicles']:
 x,y=v['position'];dx,dy=dirs[v['direction']];tx,ty=x-dx,y-dy
 left=ox+min(x,tx)*cell+7;top=oy+min(y,ty)*cell+7
 right=ox+(max(x,tx)+1)*cell-7;bottom=oy+(max(y,ty)+1)*cell-7
 box((left+2,top+3,right+2,bottom+3),'#8B8991',radius=9)
 box((left,top,right,bottom),v['color'],'#2B3038',2,9)
 hx=ox+(x+.5)*cell;hy=oy+(y+.5)*cell
 a=(hx-dx*13,hy-dy*13);b=(hx+dx*13,hy+dy*13)
 d.line((a[0]*S,a[1]*S,b[0]*S,b[1]*S),fill='white',width=4*S)
 perp=(-dy,dx)
 pts=[b,(b[0]-dx*10+perp[0]*7,b[1]-dy*10+perp[1]*7),(b[0]-dx*10-perp[0]*7,b[1]-dy*10-perp[1]*7)]
 d.polygon([(int(a*S),int(b*S)) for a,b in pts],fill='white')
 text(ox+(tx+.5)*cell,oy+(ty+.5)*cell-10,v['id'],16,'white',True)
 if v['id']=='V01':
  d.rounded_rectangle(((left-4)*S,(top-4)*S,(right+4)*S,(bottom+4)*S),radius=12*S,outline='#FFD34E',width=3*S)
text(350,791,'Очередь грузов: слева направо',17,center=True)
for i,color in enumerate(c['passenger_queue']):
 x=94+i*16
 box((x,825,x+13,846),color,'#3D4148',1,2)
text(350,867,'Жёлтый контур — первый рекомендуемый ход',15,center=True)
text(350,894,'Награда: 20 монет. Цены мест — стартовый вариант.',14,center=True)
im.resize((700,930),Image.Resampling.LANCZOS).save(root/'level-001-plan.png')
print('Level plan saved.')
