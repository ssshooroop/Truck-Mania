extends SceneTree
const Model=preload("res://scripts/game_model.gd")
const Contact=preload("res://scripts/collision_feedback.gd")
func _initialize():
 var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/playtest10-before-density.json"))
 var failures:=0
 var maximum:=0.0
 for i in 10:
  var m=Model.new()
  m.load_level(i)
  var links=[]
  for b in m.buses:
   links.append(m.blocking_ids(b.id))
   var hit=Contact.body_contact(m,b.id)
   if not hit.is_empty():maximum=maxf(maximum,hit.distance)
   for other in m.buses:
    if b.id<other.id and m._footprints_overlap(b,other):failures+=1
  # Level 4 now has a redesigned maneuver-aware graph, covered by level4_progression_test.
  if i==3: continue
  for v in before.levels[i].vehicles: m.buses[int(v.id)].position=Vector2(v.x,v.y)
  for b in m.buses:
   if links[b.id]!=m.blocking_ids(b.id): failures+=1
 print("Density regression: ",failures," failures; maximum initial nearest blocker gap: ",maximum)
 quit(failures)
