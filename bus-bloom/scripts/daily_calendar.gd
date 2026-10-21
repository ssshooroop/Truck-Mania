extends RefCounted
## Calendar days supplied by the caller. No wall-clock or reward amounts inside.
const DAYS=7
var state:Dictionary={"start":-1,"last_visit":-1,"claimed":[],"version":1,"week":0}
func restore(saved:Dictionary):
	if int(saved.get("version",0))!=1: return
	if not saved.get("claimed",[]) is Array: return
	state.week=maxi(0,int(saved.get("week",0)))
	state.start=int(saved.get("start",-1))
	state.last_visit=int(saved.get("last_visit",-1))
	state.claimed=[]
	for day in saved.claimed:
		if day is int and day>=0 and day<DAYS and day not in state.claimed: state.claimed.append(day)
func visit(day:int)->Dictionary:
	if int(state.last_visit)>day:
		return view(int(state.last_visit)) # Clock rollback cannot reopen a reward.
	var reset:bool=int(state.start)<0 or day-int(state.last_visit)-1>3
	if reset:
		state.start=day
		state.claimed=[]
	elif day-int(state.start)>=DAYS:
		state.week+=int((day-int(state.start))/DAYS)
		state.start=day-((day-int(state.start))%DAYS)
		state.claimed=[]
	state.last_visit=day
	return view(day)
func view(day:int)->Dictionary:
	var index:int=clampi(day-int(state.start),0,DAYS-1)
	var cards:Array=[]
	for i in DAYS:
		cards.append("claimed" if i in state.claimed else ("missed" if i<index else ("available" if i==index else "locked")))
	return {"index":index,"cards":cards,"can_claim":index not in state.claimed}
func claim(day:int)->int:
	if day<int(state.last_visit): return -1
	var info=visit(day)
	if not info.can_claim: return -1
	state.claimed.append(info.index)
	return info.index
