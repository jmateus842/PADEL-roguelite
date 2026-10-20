extends CanvasLayer
## Match menu. Start or Esc opens it and pauses the match.
## Pick a mode and the match restarts in it, with a fresh score.
## Moves with the D-pad, stick or arrows, picks with A or Enter,
## closes with Start, Esc or B. Built in code, so match.tscn stays small.

signal mode_picked(demo: bool)

var _panel: PanelContainer
var _first: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the match is paused
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.18, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_first = _button(box, "Resume", close)
	_button(box, "Play vs the opponent", func() -> void: _pick(false))
	_button(box, "Watch opponent vs opponent", func() -> void: _pick(true))
	var hint := Label.new()
	hint.text = "A / Enter pick     Start / Esc / B close"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	visible = false


func _button(box: VBoxContainer, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	_first.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _pick(demo: bool) -> void:
	close()
	mode_picked.emit(demo)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
