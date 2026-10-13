import bpy, math, json
from pathlib import Path
from mathutils import Vector
out=Path('bus-bloom/assets/artwork/menu/props-rendered').resolve(); out.mkdir(exist_ok=True)
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.resolution_x=384; scene.render.resolution_y=384; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'; scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
scene.world=bpy.data.worlds.new('Menu Render World'); scene.world.use_nodes=True
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(0.8,0.87,1,1)
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=0.65
for obj in scene.objects: obj.hide_render=True
camera_data=bpy.data.cameras.new('Menu Camera'); camera=bpy.data.objects.new('Menu Camera',camera_data); scene.collection.objects.link(camera); scene.camera=camera
camera.location=(6,-9,7); target=Vector((0,0,0.85)); camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler(); camera_data.type='ORTHO'; camera_data.ortho_scale=3.0
light_data=bpy.data.lights.new('Menu Key','AREA'); light_data.energy=450; light_data.shape='DISK'; light_data.size=5
light=bpy.data.objects.new('Menu Key',light_data); scene.collection.objects.link(light); light.location=(-3,-4,7); light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
items=[('Tree 1.001','tree-wide'),('Tree 2.001','tree-tall'),('Tree 3.001','tree-round'),('Bench','bench'),('Fire Hydrant','hydrant'),('Street Lamp','lamp'),('Sign1','sign'),('Fountain','fountain'),('Traffic Light1','traffic-light'),('Sign3','sign-alt')]
for name,slug in items:
 if (out/(slug+'.png')).exists(): continue
 obj=bpy.data.objects[name]; original=obj.matrix_world.copy()
 corners=[obj.matrix_world@Vector(c) for c in obj.bound_box]
 lo=Vector(tuple(min(v[i] for v in corners) for i in range(3))); hi=Vector(tuple(max(v[i] for v in corners) for i in range(3)))
 center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z)); factor=2/max(hi-lo)
 from mathutils import Matrix
 obj.matrix_world=Matrix.Scale(factor,4)@Matrix.Translation(-center)@original
 obj.hide_render=False
 scene.render.filepath=str(out/(slug+'.png')); bpy.ops.render.render(write_still=True)
 obj.hide_render=True; obj.matrix_world=original
 print('RENDERED',slug,flush=True)
(out/'provenance.json').write_text(json.dumps({'source':'../props.blend','objects':dict((slug,name) for name,slug in items),'camera':'orthographic; fixed three-quarter view; transparent; original materials'},indent=2),encoding='utf-8')
