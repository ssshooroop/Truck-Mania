extends RefCounted
## Persistent economy; behavioural probabilities remain offline simulation inputs.
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/economy_config.json"))
var achievements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://config/achievements.json")).achievements
var state: Dictionary = {"clean_streak":0,"tutorial_done":false,"claimed":[],"counters":{},"inventory":{},"last_login_day":-1,"login_index":0,"failures":{},"daily_calendar":{}}

func base_reward(number:int) -> int:
	var r: Dictionary = config.reward.base
	return mini(int(r.cap),int(r.a)+floori(float(r.b)*sqrt(number)))

func failure(index:int) -> void:
	state.clean_streak = 0
	state.counters.win_streak = 0
	state.counters.speed_win_streak = 0
	state.failures[str(index)] = int(state.failures.get(str(index),0))+1

func completion(index:int,count:int,cargo:int,rescued:bool,peak:int,slots:int) -> Dictionary:
	var reward := base_reward(index+1)
	var bonus := 0
	if not rescued:
		state.clean_streak = int(state.clean_streak)+1
		bonus = int(config.reward.clean_streak.step)*mini(int(config.reward.clean_streak.cap),int(state.clean_streak))
	elif config.reward.rescue_streak_policy == "reset": state.clean_streak = 0
	var counters: Dictionary = state.counters
	counters.levels_completed = count
	counters.cargo_delivered = int(counters.get("cargo_delivered",0))+cargo
	counters.win_streak = int(counters.get("win_streak",0))+1
	counters.speed_win_streak = int(counters.get("speed_win_streak",0))+1 if peak*2<=slots else 0
	if peak==slots-1: counters.clutch_wins = int(counters.get("clutch_wins",0))+1
	if int(state.failures.get(str(index),0))>=3: counters.comeback_wins = int(counters.get("comeback_wins",0))+1
	var chest: int = int(config.chest.coins) if count%int(config.chest.every_levels)==0 else 0
	var achievement_coins := 0
	for a: Dictionary in achievements:
		if a.id in state.claimed or int(counters.get(a.trigger.counter,0))<int(a.trigger.at_least): continue
		state.claimed.append(a.id)
		achievement_coins += int(a.reward.get("coins",0))
		for key in a.reward.get("boosters",{}):
			state.inventory[key] = int(state.inventory.get(key,0))+int(a.reward.boosters[key])
	return {"base":reward,"streak":bonus,"chest":chest,"achievements":achievement_coins,"total":reward+bonus+chest+achievement_coins}

func daily_reward(day:int) -> int:
	if day<=int(state.last_login_day): return 0
	# First session starts with the configured balance; login gifts begin next day.
	if int(state.last_login_day)<0:
		state.last_login_day = day
		return 0
	if day>int(state.last_login_day)+1: state.login_index = 0
	var amount := roundi(float(config.daily_login[int(state.login_index)%config.daily_login.size()])*float(config.daily_login_scale))
	state.login_index = int(state.login_index)+1
	state.last_login_day = day
	return amount

func restore(saved:Dictionary) -> void:
	for key in state:
		if saved.has(key) and typeof(saved[key])==typeof(state[key]): state[key] = saved[key]
