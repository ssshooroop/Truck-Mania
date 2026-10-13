import bpy, json
from pathlib import Path
out=[]
for obj in bpy.data.objects:
 if obj.type=='MESH':
  out.append({'name':obj.name,'dimensions':list(obj.dimensions),'materials':[{'name':m.name,'color':list(m.diffuse_color),'nodes':[(n.type, n.image.filepath if n.type=='TEX_IMAGE' and n.image else '') for n in m.node_tree.nodes] if m.use_nodes else []} for m in obj.data.materials if m]})
Path('bus-bloom/artifacts/blender-props.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print('PROP_NAMES',[(x['name'],x['dimensions']) for x in out])
print('IMAGES',[(im.name,im.filepath,bool(im.packed_file)) for im in bpy.data.images])
