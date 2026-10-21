extends RefCounted
const Calendar=preload("res://scripts/daily_calendar.gd")
var calendar=Calendar.new()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://config/daily_rewards.json"))
func definitions()->Array:
	return config.weeks[int(calendar.state.week)%config.weeks.size()].days
func restore(saved:Dictionary):
	calendar.restore(saved)
func claim(day:int,inventory:Dictionary)->Dictionary:
	var index:int=calendar.claim(day)
	if index<0:return {"index":-1,"coins":0}
	var coins:=0
	for reward in definitions()[index].rewards:
		var quantity:int=int(reward.quantity)
		if reward.item=="coins":coins+=quantity
		else:inventory[reward.item]=int(inventory.get(reward.item,0))+quantity
	return {"index":index,"coins":coins}
