extends RefCounted
## Aim memory for the right stick. You flick it, then swing a moment later with
## the thumb already back at rest. The swing still uses the flick for a short
## while, so a quick release doesn't throw the shot to the default aim.
##
## Works in court axes (x right, y toward their half), real seconds. Nothing
## here is random, the same inputs give the same aim.

## a pushed direction is remembered this long after the stick returns to rest, s
const MEMORY := 0.12

var _last := Vector2.ZERO
var _age := INF


## raw is the stick in court axes, length 0 to 1. Returns the aim to use now:
## the stick while it is pushed, the last push for MEMORY seconds after it
## rests, then ZERO (the caller falls back to the left stick nudge)
func update(raw: Vector2, delta: float, rest := 0.3) -> Vector2:
	if raw.length() >= rest:
		_last = raw
		_age = 0.0
		return raw
	_age += delta
	if _age <= MEMORY:
		return _last
	return Vector2.ZERO
