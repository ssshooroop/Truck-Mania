extends Node

const MUSIC = {
	"menu":preload("res://assets/sound/music/menu.ogg"),
	"game":preload("res://assets/sound/music/game.ogg")
}
const PICKUP = [
	preload("res://assets/sound/fx/wood-download-single.wav"),
	preload("res://assets/sound/fx/bricks-download-single.wav"),
	preload("res://assets/sound/fx/cament-download-single.wav"),
	preload("res://assets/sound/fx/cable-download-single.wav"),
	preload("res://assets/sound/fx/pipe-download-single.wav"),
	preload("res://assets/sound/fx/pipe-download-single.wav") # Sheet metal fallback.
]
const FX = {
	"bump":preload("res://assets/sound/fx/bump.wav"),
	"full":preload("res://assets/sound/fx/truck-full.wav"),
	"one":preload("res://assets/sound/fx/upload-one.wav"),
	"two":preload("res://assets/sound/fx/upload-two(play-it-twice).wav"),
	"four":preload("res://assets/sound/fx/upload-four.wav"),
	"many":preload("res://assets/sound/fx/upload-many.wav")
}
var music_enabled = true
var effects_enabled = true
var context = "menu"
var music:AudioStreamPlayer
var voices:Array[AudioStreamPlayer] = []
var repeat_left:Dictionary = {}
var next_voice = 0

func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -16
	add_child(music)
	for i in 10:
		var player = AudioStreamPlayer.new()
		player.volume_db = -9
		add_child(player)
		voices.append(player)
		player.finished.connect(_finished.bind(player))

func _finished(player:AudioStreamPlayer) -> void:
	if effects_enabled and repeat_left.get(player,0)>0:
		repeat_left[player] -= 1
		player.play()
	else: repeat_left.erase(player)

func set_preferences(want_music:bool,want_effects:bool) -> void:
	music_enabled = want_music
	effects_enabled = want_effects
	if not effects_enabled: stop_effects()
	_update_music()

func set_context(value:String) -> void:
	context = value
	_update_music()

func _update_music() -> void:
	if not music: return
	if not music_enabled:
		music.stop()
		return
	var wanted:AudioStream = MUSIC[context]
	if music.stream!=wanted:
		music.stream = wanted
		music.stream.loop = true
		music.play()
	elif not music.playing: music.play()

func play_stream(stream:AudioStream,repeats:int=1) -> void:
	if not effects_enabled or not stream: return
	var player = voices[next_voice]
	next_voice = (next_voice+1)%voices.size()
	player.stop()
	player.stream = stream
	repeat_left[player] = repeats-1
	player.play()

func pickup(material_id:int) -> void:
	play_stream(PICKUP[clampi(material_id,0,PICKUP.size()-1)])

func deposit(count:int) -> void:
	var key = "one" if count==1 else "two" if count==2 else "four" if count==4 else "many"
	play_stream(FX[key],2 if count==2 else 1)

func effect(key:String) -> void:
	play_stream(FX[key])

func stop_effects() -> void:
	repeat_left.clear()
	for player in voices: player.stop()

func pause_effects(value:bool) -> void:
	for player in voices: player.stream_paused = value

func _exit_tree() -> void:
	stop_effects()
	for player in voices: player.stream = null
	if music:
		music.stop()
		music.stream = null

func _notification(what:int) -> void:
	if not music: return
	if what==NOTIFICATION_APPLICATION_PAUSED:
		music.stream_paused = true
		pause_effects(true)
	elif what==NOTIFICATION_APPLICATION_RESUMED:
		music.stream_paused = false
