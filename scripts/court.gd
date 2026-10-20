extends Node2D
## Top-down grey box court. 1 m = PPM pixels. Screen up is the opponent's side.
## Glass draws thick and blue, mesh thin and grey, same colors as the sim plots.

const BallModel := preload("res://scripts/ball_model.gd")
const PPM := 30.0

const FLOOR := Color("#2f6f9f")
const LINE := Color(1, 1, 1, 0.8)
const GLASS := Color("#3a8fd6")
const MESH := Color("#888888")


static func to_screen(x: float, y: float) -> Vector2:
	return Vector2(x * PPM, (BallModel.L - y) * PPM)


func _draw() -> void:
	var W := BallModel.W
	var L := BallModel.L
	var NY := BallModel.NET_Y
	var s := BallModel.SERVICE_FROM_NET
	draw_rect(Rect2(to_screen(0, L), Vector2(W, L) * PPM), FLOOR)
	# service lines and the center line between them
	for sy in [NY - s, NY + s]:
		draw_line(to_screen(0, sy), to_screen(W, sy), LINE, 2)
	draw_line(to_screen(W / 2, NY - s), to_screen(W / 2, NY + s), LINE, 2)
	# net
	draw_line(to_screen(-0.3, NY), to_screen(W + 0.3, NY), Color.BLACK, 4)
	# back walls: glass at floor level
	for wy in [0.0, L]:
		draw_line(to_screen(0, wy), to_screen(W, wy), GLASS, 6)
	# side walls, half a meter at a time so the glass/mesh split shows
	for wx in [0.0, W]:
		var y0 := 0.0
		while y0 < L:
			var glass := BallModel.wall_at("side", y0 + 0.25).x > 0.0
			draw_line(to_screen(wx, y0), to_screen(wx, y0 + 0.5), GLASS if glass else MESH, 6 if glass else 2)
			y0 += 0.5
