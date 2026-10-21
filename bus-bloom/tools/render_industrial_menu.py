import bpy, math, json
from pathlib import Path
from mathutils import Vector, Matrix
root=Path('bus-bloom').resolve()
out=root/'assets/artwork/menu/props-rendered'
atlas=bpy.data.images.load(str(root/'assets/artwork/3D/Industrial Water Tank Texture Atlas.png'),check_existing=True)
mat=bpy.data.materials.new('Menu Industrial Atlas');mat.use_nodes=True
nodes=mat.node_tree.nodes
tex=nodes.new('ShaderNodeTexImage');tex.image=atlas;tex.interpolation='Linear'
bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
bs.inputs['Roughness'].default_value=.78
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
scene.world=bpy.data.worlds.new('Industrial Menu World');scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.8,.87,1,1);bg.inputs[1].default_value=.8
for ob in scene.objects:ob.hide_render=True
camdata=bpy.data.cameras.new('Industrial Camera');cam=bpy.data.objects.new('Industrial Camera',camdata);scene.collection.objects.link(cam);scene.camera=cam
cam.location=(6,-9,6);target=Vector((0,0,.85));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=3
ld=bpy.data.lights.new('Industrial Key','AREA');ld.energy=400;ld.size=5
light=bpy.data.objects.new('Industrial Key',ld);scene.collection.objects.link(light);light.location=(-3,-4,7);light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
items=[('FACTORY 1','factory'),('warehouse 1','warehouse'),('water tower','water-tower')]
for name,slug in items:
 obj=bpy.data.objects[name];mesh=obj.data
 original=obj.matrix_world.copy()
 points=[original@v.co for v in mesh.vertices]
 lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
 # Existing models have a palette UV map; replace it with architectural planar mapping.
 uv=mesh.uv_layers.active or mesh.uv_layers.new(name='MenuAtlas')
 mesh.materials.clear();mesh.materials.append(mat)
 for poly in mesh.polygons:
  poly.material_index=0
  n=(original.to_3x3().inverted().transposed()@poly.normal).normalized()
  axis=max(range(3),key=lambda i:abs(n[i]))
  axes=[i for i in range(3) if i!=axis]
  if axis!=2: axes=[axes[0],2]
  rect=(1045,30,1305,448) if slug=='water-tower' else ((550,20,880,250) if axis==2 else ((15,420,720,660) if axis==1 else (16,20,520,385)))
  x0,y0,x1,y1=rect
  for li in poly.loop_indices:
   p=points[mesh.loops[li].vertex_index]
   u=(p[axes[0]]-lo[axes[0]])/max(hi[axes[0]]-lo[axes[0]],.0001)
   v=(p[axes[1]]-lo[axes[1]])/max(hi[axes[1]]-lo[axes[1]],.0001)
   uv.data[li].uv=((x0+u*(x1-x0))/1536,1-(y1-v*(y1-y0))/1024)
 center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 obj.matrix_world=Matrix.Scale(2/max(hi-lo),4)@Matrix.Translation(-center)@original
 obj.hide_render=False;scene.render.filepath=str(out/(slug+'.png'));bpy.ops.render.render(write_still=True)
 obj.hide_render=True;obj.matrix_world=original
 print('RENDERED',slug,flush=True)
atlas.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(root/'artifacts/menu-industrial-textured.blend'))
