extends Node
## Every input action in the game, keyboard and gamepad, in one table.
## Runs as the "Controls" autoload, so the bindings live here and not in
## project.godot. Tests call register() directly to check them.
##
## Gamepad names follow Godot's Xbox layout. PlayStation and Switch pads use
## the same positions: A is the bottom face button (cross on PlayStation).
##
## Lab controls stay off the face buttons, the left stick and WASD on
## purpose. Those belong to the player, so the lab and the player can
## share a scene without fighting over buttons.

signal device_changed(using_gamepad: bool)
signal pads_changed

## stick travel ignored before it counts as movement (0 to 1)
const STICK_DEADZONE := 0.25

const ACTIONS := {
	# ball lab
	"lab_next": {"keys": [KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER]},
	"lab_prev": {"keys": [KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER]},
	"lab_replay": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_RIGHT_STICK]},
	"lab_speed": {"keys": [KEY_T], "buttons": [JOY_BUTTON_DPAD_UP]},
	"lab_auto": {"keys": [KEY_R], "buttons": [JOY_BUTTON_DPAD_DOWN]},
	"lab_check": {"keys": [KEY_C], "buttons": [JOY_BUTTON_BACK]},
	# player movement: WASD or the left stick. The lab stays off these keys.
	"move_left": {"keys": [KEY_A], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"move_right": {"keys": [KEY_D], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	"move_up": {"keys": [KEY_W], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"move_down": {"keys": [KEY_S], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	# player shots. A (cross on PlayStation) or J
	"swing": {"keys": [KEY_J], "buttons": [JOY_BUTTON_A]},
	# opens and closes the match menu. Inside the menu, Godot's built-in ui_*
	# actions move and pick (arrows or D-pad or stick, Enter or A, Esc or B)
	"menu": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START]},
}

## true once the last thing you touched was a gamepad. The HUD uses it
## to show the right button names.
var using_gamepad := false


static func register() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, STICK_DEADZONE)
		var a: Dictionary = ACTIONS[action]
		for k in a.get("keys", []):
			var e := InputEventKey.new()
			e.keycode = k
			InputMap.action_add_event(action, e)
		for b in a.get("buttons", []):
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.device = -1   # any pad
			InputMap.action_add_event(action, e)
		if a.has("axis"):
			var e := InputEventJoypadMotion.new()
			e.axis = a.axis[0]
			e.axis_value = a.axis[1]
			e.device = -1
			InputMap.action_add_event(action, e)


	# Godot's built-in menu actions have no gamepad pick/back by default.
	# Add A to pick and B to go back, once, so menus work on a controller
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var e := InputEventJoypadButton.new()
		e.button_index = pair[1]
		e.device = -1
		if InputMap.has_action(pair[0]) and not InputMap.action_has_event(pair[0], e):
			InputMap.action_add_event(pair[0], e)


## WASD or left stick as a vector, deadzone applied, length 0 to 1
static func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


static func pad_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for id in Input.get_connected_joypads():
		names.append(Input.get_joy_name(id))
	return names


func _ready() -> void:
	register()
	Input.joy_connection_changed.connect(func(_id: int, _connected: bool) -> void: pads_changed.emit())
	using_gamepad = not Input.get_connected_joypads().is_empty()


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton \
		or (event is InputEventJoypadMotion and absf(event.axis_value) > STICK_DEADZONE)
	var keys := event is InputEventKey or event is InputEventMouseButton
	if (pad and not using_gamepad) or (keys and using_gamepad):
		using_gamepad = pad
		device_changed.emit(using_gamepad)
