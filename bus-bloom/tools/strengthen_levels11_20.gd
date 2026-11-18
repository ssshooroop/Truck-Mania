extends SceneTree
const M=preload("res://scripts/game_model.gd")
const Geometry=preload("res://tools/compact_levels11_20.gd")
var rng=RandomNumberGenerator.new()
func _initialize():
	rng.seed=22102026
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/campaign.json"))
	var targets=[3,3,3,2,3,2,2,3,2,2]
	var report:Array=[]
	for index in range(10,20):
		var m=M.new()
		m.load_level(index)
		var ranks:Array=[]
		for id in data.levels[index].solution:ranks.append(int(id))
		var initial_free:Array=[]
		for b in m.buses:
			if m.blocking_ids(b.id).is_empty():initial_free.append(b.id)
		var remaining:int=initial_free.size()
		# Later solution vehicles can be tucked behind earlier ones without
		# invalidating the existing cargo/parking solution certificate.
		for rank in range(ranks.size()-1,0,-1):
			if remaining<=targets[index-10]:break
			var b:Dictionary=m.buses[ranks[rank]]
			if not m.blocking_ids(b.id).is_empty():continue
			var start:Vector2=b.position
			var angle:float=b.angle
			var best:Dictionary={}
			var score:=INF
			for trial in 12000:
				var anchor:Dictionary=m.buses[ranks[rng.randi_range(0,rank-1)]]
				b.angle=rng.randi_range(0,7)*PI/4
				b.position=anchor.position-m.forward(b)*rng.randf_range(60,240)+Vector2.from_angle(b.angle)*rng.randf_range(-90,90)
				var size:Vector2=m.vehicle_size(b)
				var half:Vector2=(m.forward(b).abs()*size.y+Vector2(cos(b.angle),sin(b.angle)).abs()*size.x)/2
				if not M.YARD_RECT.encloses(Rect2(b.position-half,half*2)):continue
				var valid:=true
				for other in m.buses:
					if other.id==b.id:continue
					if m._rectangles_overlap(b.position,m.forward(b),size+Vector2(4,4),other.position,m.forward(other),m.vehicle_size(other)+Vector2(4,4)):
						valid=false
						break
					if (m._sweep_hits(b,other) and ranks.find(other.id)>rank) or (m._sweep_hits(other,b) and ranks.find(other.id)<rank):
						valid=false
						break
				if not valid or m.blocking_ids(b.id).is_empty():continue
				for other in m.buses:
					if other.id!=b.id and not initial_free.has(other.id) and m.blocking_ids(other.id).is_empty():valid=false
				if not valid:continue
				# Exact turn sweep must remain blocked initially as well.
				if not M.YardManeuver.paths(m,b.id,(1<<m.buses.size())-1).is_empty():continue
				var candidate:float=b.position.distance_to(start)*0.25+b.position.distance_to(Vector2(270,850))*0.1
				# Prefer short, clearly visible contact distances.
				var gap:=INF
				for blocker in m.blocking_ids(b.id):
					gap=minf(gap,contact_gap(m,b,m.buses[blocker]))
				candidate+=maxf(gap-18,0)*12
				if candidate<score:
					score=candidate
					best={"position":b.position,"angle":b.angle}
			b.position=best.get("position",start)
			b.angle=best.get("angle",angle)
			if not best.is_empty():
				initial_free.erase(b.id)
				remaining=0
				for other in m.buses:
					if m.blocking_ids(other.id).is_empty():remaining+=1
		var free:Array=[]
		for b in m.buses:
			if m.blocking_ids(b.id).is_empty():free.append(b.id)
			var v:Dictionary=data.levels[index].vehicles[b.id]
			v.x=b.position.x
			v.y=b.position.y
			v.angle=b.angle
		report.append({"level":index+1,"free":free,"vehicles":m.buses.size()})
	data.revision="levels11-20-challenge-20261022"
	FileAccess.open("res://config/campaign.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	FileAccess.open("res://artifacts/levels11-20-difficulty-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(report)
	quit()
func contact_gap(m,a:Dictionary,b:Dictionary)->float:
	var lo:=0.0
	var hi:=400.0
	# First collision along a straight swept segment, using the model SAT.
	for iteration in 12:
		var distance:float=(lo+hi)/2
		var size:Vector2=m.vehicle_size(a)
		size.y+=distance
		if m._rectangles_overlap(a.position+m.forward(a)*distance/2,m.forward(a),size,b.position,m.forward(b),m.vehicle_size(b)):hi=distance
		else:lo=distance
	return hi

