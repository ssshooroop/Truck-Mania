extends RefCounted
## Rewarded-video seam. No ad SDK is connected yet, so `is_ready()` is false and
## the windows show their "ролик готовится" state; nothing is granted without a
## finished video. `simulate` (command line `--fake-ads`) plays a fake 1.2 s
## video so the flows can be tested end to end.
## To connect an SDK: implement is_ready() / show_rewarded() with it and keep
## the contract — show_rewarded() resolves true only after the reward callback.

var simulate := false
var watching := false

func is_ready() -> bool:
	return simulate and not watching

func show_rewarded() -> bool:
	if not is_ready(): return false
	watching = true
	await Engine.get_main_loop().create_timer(1.2).timeout
	watching = false
	return true
