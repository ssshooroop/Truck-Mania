extends SceneTree
const Probe=preload("res://tests/motion_probe.gd")
func _initialize(): run.call_deferred()
func run():
 var game=Probe.new()
 root.add_child(game)
 var failures=0
 for target in [3,6]:
  game._load_level(3)
  for id in [0,4,8,2,1]: await game._dispatch(id)
  # The revised layout keeps both greens locked until their neighbours leave.
  if game.model.can_dispatch(3) or game.model.can_dispatch(6): failures+=1
  await game._dispatch(5)
  if not game.model.can_dispatch(6): failures+=1
  if target==3: await game._dispatch(6)
  print("Green scenario ",target," before=",game.model.buses[target].status," blocker=",game.model.blocking_ids(target))
  await game._dispatch(target)
  if game.model.buses[target].status=="yard": failures+=1
  print("Green scenario after=",game.model.buses[target].status," hint=",game.model.find_hint())
  if not game.history.is_empty():
   var state=game.history.back().state
   if not game.model.restore(state): failures+=1
   if game.model.buses[target].status!="yard": failures+=1
 print("Live dispatch + undo failures: ",failures," collisions=",game.collision_segments)
 var failed=failures>0 or game.collision_segments>0
 game.queue_free()
 await process_frame
 quit(1 if failed else 0)
