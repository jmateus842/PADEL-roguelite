extends RefCounted
## Slow-mo "focus": hold the button to slow the world. A meter drains while you
## hold it and refills when you let go. Plain object, the match scene feeds it
## real time every tick, so tests can run it without a scene.
##
## While it is on, the ball and the opponent run at WORLD_SCALE and you move at
## PLAYER_SCALE, a bit faster than the world. Your swing stays on the world's
## clock (player.gd), so slow-mo never makes the hit timing harder.

# --- tuning ---
## speed of the ball and the opponent, 1 = normal
const WORLD_SCALE := 0.4
## speed of your movement, 1 = normal. Above WORLD_SCALE, so you gain ground
const PLAYER_SCALE := 0.6
## a full meter lasts this long held, real seconds
const SECONDS := 3.0
## an empty meter takes this long to fill, real seconds
const REFILL := 10.0
## after it runs dry you can't start again until you let go and it holds this much (0 to 1)
const MIN_START := 0.1
## how fast the slow-down eases in and out, per second
const EASE := 8.0

## 0 to 1
var meter := 1.0
var engaged := false
## true after the meter ran dry, until you let go and it holds MIN_START
var locked := false
## 0 normal, 1 fully slowed. Eases, so time doesn't jump
var blend := 0.0
## real seconds spent in slow-mo, for the stats
var used := 0.0


## held: the button is down and slow-mo is allowed right now. dt: real seconds
func update(held: bool, dt: float) -> void:
	if locked and not held and meter >= MIN_START:
		locked = false
	if not engaged and held and not locked and meter >= MIN_START:
		engaged = true
	if engaged and not held:
		engaged = false
	if engaged:
		meter = maxf(meter - dt / SECONDS, 0.0)
		used += dt
		if meter <= 0.0:
			engaged = false
			locked = true
	else:
		meter = minf(meter + dt / REFILL, 1.0)
	blend = move_toward(blend, 1.0 if engaged else 0.0, EASE * dt)


## multiplier for the ball and the opponent
func world_scale() -> float:
	return lerpf(1.0, WORLD_SCALE, blend)


## multiplier for your movement
func player_scale() -> float:
	return lerpf(1.0, PLAYER_SCALE, blend)
