## Engine adapter: stages the Arena in 3D, plays its sounds, and shows the score.
## All rules live in core/; this file only turns state into pictures and sound.
## The world is built by game/stage.gd and the juice by game/effects.gd.
extends Node3D

const GRID := Vector2i(40, 40)
const TICK_SECONDS := 0.11
const CAMERA_OFFSET := Vector3(0, 6, 5)
const WAVE_HEIGHT := 0.06  # how far each segment rises and falls
const WAVE_SPEED := 8.0  # radians per second
const WAVE_STEP := 0.8  # radians between neighbors, so the wave runs head to tail
const DIRECTIONS := {
	"ui_up": Vector2i.UP,
	"ui_down": Vector2i.DOWN,
	"ui_left": Vector2i.LEFT,
	"ui_right": Vector2i.RIGHT,
}

var arena: Arena
var meshes := {}  # piece name -> Mesh, shared by every node that shows it (Flyweight)
var sounds := {}  # sound name -> AudioStreamPlayer
var segments: Array[MeshInstance3D] = []
var food_node := MeshInstance3D.new()
var ember_light := OmniLight3D.new()
var pickup_node := MeshInstance3D.new()
var camera := Camera3D.new()
var effects := Effects.new(camera)
var score_label := Label.new()
var banner := Label.new()
var _clock := 0.0
var _previous: Array[Vector2i] = []  # the body before the latest tick, to draw in-between
var _head_yaw := 0.0


func _ready() -> void:
	_load_meshes()
	_load_sounds()
	add_child(Stage.new(_board(), meshes))
	_build_props()
	_build_hud()
	_new_game()


## Input arrives as events, so even a tap shorter than one frame is never missed.
func _unhandled_input(event: InputEvent) -> void:
	if arena.state == Arena.State.OVER:
		if event.is_action_pressed("ui_accept"):
			_new_game()
		return
	for action in DIRECTIONS:
		if event.is_action_pressed(action):
			arena.start()
			arena.dragon.turn(DIRECTIONS[action])


## Rules tick at a fixed rate; drawing happens every frame, between ticks too.
func _process(delta: float) -> void:
	var period := TICK_SECONDS / arena.speed
	_clock += delta
	while _clock >= period and arena.state == Arena.State.PLAYING:
		_clock -= period
		_previous = arena.dragon.body.duplicate()
		arena.tick()
	if arena.state != Arena.State.PLAYING:
		_clock = 0.0
	var head := _draw_dragon(_clock / period, delta)
	_draw_props(delta)
	_follow(head, delta)
	_draw_hud()


func _new_game() -> void:
	arena = Arena.new(GRID, randi())
	arena.ate.connect(func(_cell): sounds["eat"].play())
	arena.powered.connect(func(_powerup): sounds["power"].play())
	arena.died.connect(func(_reason): sounds["crash"].play())
	effects.watch(arena)
	_clock = 0.0
	_previous = arena.dragon.body.duplicate()
	_head_yaw = Kit.layout(arena.dragon.body)[0][1] * PI / 2
	camera.position = _center(arena.dragon.body[0]) + CAMERA_OFFSET


## art/dragon_kit.glb holds one object per piece: head, straight, turn, tail, food,
## pickup, and (in newer kits) floor and wall.
func _load_meshes() -> void:
	var kit: Node = load("res://art/dragon_kit.glb").instantiate()
	for child in kit.find_children("*", "MeshInstance3D"):
		meshes[String(child.name)] = child.mesh
		_use_vertex_colors(child.mesh)
	kit.free()


## glTF says vertex colors (COLOR_0) tint the base color, but Godot's importer
## only turns that on for some materials. Blender bakes groove shading and stone
## mottling into vertex colors, so switch it on wherever a surface has them.
func _use_vertex_colors(mesh: Mesh) -> void:
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material and mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR] != null:
			material.vertex_color_use_as_albedo = true


## The kind of tile in each cell: floor inside the arena, a ring of wall around it.
## Drawn up here for now; later it can become rules data (lava, water, bridges).
func _board() -> Dictionary:
	var board := {}
	for x in range(-1, GRID.x + 1):
		for y in range(-1, GRID.y + 1):
			var inside := Rect2i(Vector2i.ZERO, GRID).has_point(Vector2i(x, y))
			board[Vector2i(x, y)] = "floor" if inside else "wall"
	return board


## sfx/*.wav come from tools/build_sfx.py.
func _load_sounds() -> void:
	for sound_name in ["eat", "power", "crash"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://sfx/%s.wav" % sound_name)
		add_child(player)
		sounds[sound_name] = player


func _build_props() -> void:
	food_node.mesh = meshes["food"]
	pickup_node.mesh = meshes["pickup"]
	# A warm light rides on the ember so it lights the floor around it. No shadow:
	# shadowed omni lights are expensive, especially in the browser.
	ember_light.light_color = Color(1.0, 0.55, 0.25)
	ember_light.omni_range = 3.5
	ember_light.position.y = 0.6
	food_node.add_child(ember_light)
	var arcane_light := OmniLight3D.new()
	arcane_light.light_color = Color(0.6, 0.4, 1.0)
	arcane_light.light_energy = 1.2
	arcane_light.omni_range = 2.5
	arcane_light.position.y = 0.6
	pickup_node.add_child(arcane_light)
	add_child(food_node)
	add_child(pickup_node)
	add_child(camera)
	add_child(effects)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	for label in [score_label, banner]:
		label.add_theme_color_override("font_color", Color("fff4e0"))
		label.add_theme_color_override("font_outline_color", Color("1a1410"))
		label.add_theme_constant_override("outline_size", 10)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		label.add_theme_constant_override("shadow_offset_y", 3)
		layer.add_child(label)
	score_label.position = Vector2(20, 14)
	score_label.add_theme_font_size_override("font_size", 30)
	# The camera keeps the head at screen center, so messages sit above it.
	banner.anchor_right = 1.0
	banner.anchor_top = 0.08
	banner.anchor_bottom = 0.4
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 34)
	add_child(layer)


## Draw the dragon partway between its last two ticks (t from 0 to 1). The cells in
## between already form a continuous body, so only the ends need to move: the head
## slides out of the neck, and the old tail slides into the cell it leaves behind.
## Returns where the head is drawn, for the camera.
func _draw_dragon(t: float, delta: float) -> Vector3:
	var body := arena.dragon.body
	var path: Array[Vector2i] = body.duplicate()
	var old_tail: Vector2i = _previous.back()
	var tail_slides := (old_tail - body[-1]).length_squared() == 1  # not growing or trimmed
	if tail_slides:
		path.append(old_tail)
	while segments.size() < path.size():
		var segment := MeshInstance3D.new()
		add_child(segment)
		segments.append(segment)

	var placed := Kit.layout(path)
	var now := Time.get_ticks_msec() / 1000.0
	for i in segments.size():
		var segment := segments[i]
		segment.visible = i < path.size()
		if not segment.visible:
			continue
		segment.mesh = meshes[Kit.Piece.keys()[placed[i][0]].to_lower()]
		segment.position = _center(path[i])
		segment.rotation.y = placed[i][1] * PI / 2
		segment.transparency = 0.5 if arena.ghost else 0.0
		# The wave's phase follows each cell's age (i + t), so it never jumps on a tick.
		segment.position.y = WAVE_HEIGHT * (1 + sin(now * WAVE_SPEED - (i + t) * WAVE_STEP))

	var head := segments[0]
	if (_previous[0] - body[0]).length_squared() == 1:
		head.position = _center(_previous[0]).lerp(_center(body[0]), t)
		head.position.y = WAVE_HEIGHT * (1 + sin(now * WAVE_SPEED))
	_head_yaw = lerp_angle(_head_yaw, head.rotation.y, 1 - exp(-30 * delta))
	head.rotation.y = _head_yaw
	if tail_slides:
		var tail := segments[path.size() - 1]
		var lift := tail.position.y
		tail.position = _center(old_tail).lerp(_center(body[-1]), t) + Vector3.UP * lift
	return head.position


func _draw_props(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	food_node.position = _center(arena.food) + Vector3.UP * (0.08 + 0.06 * sin(now * 3))
	food_node.rotation.y += delta * 2
	# Two sines at odd ratios read as a flicker without any randomness.
	ember_light.light_energy = 1.8 + 0.35 * sin(now * 13) * sin(now * 7.3)
	pickup_node.visible = arena.pickup != null
	pickup_node.position = _center(arena.pickup_cell) + Vector3.UP * (0.2 + 0.15 * sin(now * 5))
	pickup_node.rotation.y += delta * 3


## Ease toward the head between ticks; framerate-independent thanks to exp().
func _follow(head: Vector3, delta: float) -> void:
	var target := Vector3(head.x, 0, head.z) + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, 1 - exp(-3 * delta))
	camera.look_at(camera.position - CAMERA_OFFSET)


func _draw_hud() -> void:
	var lines := ["Embers  %d" % arena.score]
	for powerup in arena.active:
		lines.append("%s  %d" % [powerup.title, powerup.remaining])
	score_label.text = "\n".join(lines)
	match arena.state:
		Arena.State.READY:
			banner.text = "Arrow keys to fly\nEat embers to grow. Purple orbs do strange things."
		Arena.State.OVER:
			banner.text = "You ran into %s\nPress Enter to fly again" % arena.death
		_:
			banner.text = ""


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)
