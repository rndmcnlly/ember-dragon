## Engine adapter: stages the Arena in 3D, plays its sounds, and shows the score.
## All rules live in core/; this file only turns state into pictures and sound.
## The world is built by game/stage.gd and the juice by game/effects.gd.
extends Node3D

const TICK_SECONDS := 0.11
const CAMERA_OFFSET := Vector3(0, 6, 5)
const DIRECTIONS := {
	"ui_up": Vector2i.UP,
	"ui_down": Vector2i.DOWN,
	"ui_left": Vector2i.LEFT,
	"ui_right": Vector2i.RIGHT,
}

var campaign: Campaign = preload("res://levels/campaign.gd").ember_trail()
var step: Campaign.Step  # where we are in the campaign
var level: Level  # that step's map
var problems: Array[String] = []  # mistakes in the level or rules file, shown on the banner
var arena: Arena
var player: PlayerController  # this game's keyboard controller; arrow keys go here
var stage: Stage
var meshes := {}  # piece name -> Mesh, shared by every node that shows it (Flyweight)
var sounds := {}  # sound name -> AudioStreamPlayer
var hero: DragonView
var rival: DragonView
var food_node := MeshInstance3D.new()
var ember_light := OmniLight3D.new()
var pickup_node := MeshInstance3D.new()
var camera := Camera3D.new()
var effects := Effects.new(camera)
var score_label := Label.new()
var banner := Label.new()
var notice := Label.new()  # what the level's rules say during play
var _clock := 0.0
var _rival_drawn: Dragon  # the rival the view is drawing, to notice one hatching


func _ready() -> void:
	_load_meshes()
	_load_sounds()
	stage = Stage.new(meshes)
	add_child(stage)
	hero = DragonView.new(meshes)
	rival = DragonView.new(meshes, "rival_")  # same shapes, the rival's palette
	add_child(hero)
	add_child(rival)
	_build_props()
	_build_hud()
	_load_level(0)


## Input arrives as events, so even a tap shorter than one frame is never missed.
func _unhandled_input(event: InputEvent) -> void:
	if arena.state != Arena.State.PLAYING and event is InputEventKey and event.pressed:
		var choice: int = event.keycode - KEY_1  # number keys pick a level
		if choice >= 0 and choice < mini(campaign.steps.size(), 9):
			_load_level(choice)
			return
	if arena.state == Arena.State.OVER or arena.state == Arena.State.WON:
		if event.is_action_pressed("ui_accept") and arena.state == Arena.State.WON:
			_load_level(_number() % campaign.steps.size())  # the next level, or the first again
		elif event.is_action_pressed("ui_accept"):
			_new_game()
		return
	for action in DIRECTIONS:
		if event.is_action_pressed(action):
			arena.start()
			player.press(DIRECTIONS[action])


## Rules tick at a fixed rate; drawing happens every frame, between ticks too.
func _process(delta: float) -> void:
	var period := TICK_SECONDS / arena.pace()
	_clock += delta
	while _clock >= period and arena.state == Arena.State.PLAYING:
		_clock -= period
		hero.before_tick(arena.dragon.body)
		if arena.rival != null:
			rival.before_tick(arena.rival.body)
		arena.tick()
	if arena.state != Arena.State.PLAYING:
		_clock = 0.0
	var head := hero.draw(arena.dragon.body, _clock / period, delta, arena.ghost)
	_draw_rival(_clock / period, delta)
	_draw_props(delta)
	_follow(head, delta)
	_draw_hud()


## Read a campaign step's map from levels/ and draw its ground. A broken file still
## gives a playable field, with its errors on screen so the designer can fix them.
func _load_level(index: int) -> void:
	step = campaign.steps[index]
	level = Level.load_file("res://levels/%s.txt" % step.map)
	if not level.errors.is_empty():
		level.board = Board.bordered(Vector2i(42, 42))
	_new_game()


func _new_game() -> void:
	arena = Arena.new(level.board.copy(), randi())  # a copy: rules may change the ground
	player = PlayerController.new()
	arena.controller = player
	step.prepare(arena)
	problems = level.errors.duplicate()
	if not step.rules.is_empty():
		var rulebook := Rulebook.load_file("res://levels/%s.rules" % step.rules)
		rulebook.attach(arena)
		problems.append_array(rulebook.errors)
	for problem in problems:
		push_warning(problem)
	stage.draw_board(arena.board)
	arena.announced.connect(_announce)
	notice.modulate.a = 0.0
	arena.ate.connect(func(_cell): sounds["eat"].play())
	arena.powered.connect(func(_powerup): sounds["power"].play())
	arena.died.connect(func(_reason): sounds["crash"].play())
	arena.won.connect(func(): sounds["power"].play())
	arena.rival_ate.connect(func(_cell): sounds["rival_eat"].play())
	arena.rival_crashed.connect(func(_cell): sounds["crash"].play())
	effects.watch(arena)
	_clock = 0.0
	hero.reset(arena.dragon.body)
	_draw_rival(0.0, 0.0)
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


## sfx/*.wav come from tools/build_sfx.py.
func _load_sounds() -> void:
	for sound_name in ["eat", "power", "crash"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://sfx/%s.wav" % sound_name)
		add_child(player)
		sounds[sound_name] = player
	var growl := AudioStreamPlayer.new()  # the rival eats with a deeper crunch
	growl.stream = sounds["eat"].stream
	growl.pitch_scale = 0.7
	add_child(growl)
	sounds["rival_eat"] = growl


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
	for label in [score_label, banner, notice]:
		label.add_theme_color_override("font_color", Color("fff4e0"))
		label.add_theme_color_override("font_outline_color", Color("1a1410"))
		label.add_theme_constant_override("outline_size", 10)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		label.add_theme_constant_override("shadow_offset_y", 3)
		layer.add_child(label)
	score_label.position = Vector2(20, 14)
	score_label.add_theme_font_size_override("font_size", 30)
	# The camera keeps the head at screen center, so messages sit below it, clear of
	# the score in the corner.
	banner.anchor_right = 1.0
	banner.offset_left = 40
	banner.offset_right = -40
	banner.anchor_top = 0.58
	banner.anchor_bottom = 0.95
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 28)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long level blurbs wrap
	notice.anchor_right = 1.0
	notice.anchor_top = 0.72
	notice.offset_left = 40
	notice.offset_right = -40
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 26)
	notice.add_theme_color_override("font_color", Color("ffd27a"))
	add_child(layer)


## Show a line from the level's rules below the dragon, then let it fade.
func _announce(text: String) -> void:
	notice.text = text
	notice.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(notice, "modulate:a", 0.0, 0.8)


## The rival may hatch, or crash, in any tick; the view follows whichever is current.
func _draw_rival(t: float, delta: float) -> void:
	if arena.rival != _rival_drawn:
		_rival_drawn = arena.rival
		rival.reset(arena.rival.body if arena.rival != null else [] as Array[Vector2i])
	if arena.rival != null:
		rival.draw(arena.rival.body, t, delta)


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
	var embers := "Embers  %d" % arena.score
	if arena.goal > 0:
		embers += " / %d" % arena.goal
	var lines := [level.title, embers]
	if arena.rival != null:
		lines.append(
			"Rival  %d" % arena.rival_score + (" / %d" % arena.goal if arena.goal > 0 else "")
		)
	for powerup in arena.active:
		lines.append("%s  %d" % [powerup.title, powerup.remaining])
	score_label.text = "\n".join(lines)
	match arena.state:
		Arena.State.READY:
			var intro := [
				"Level %d of %d: %s" % [_number(), campaign.steps.size(), level.title],
				level.blurb,
				"Eat %d embers to clear it" % arena.goal if arena.goal > 0 else "No goal: fly free",
			]
			if arena.rival != null:
				intro.append("A rival dragon races you for them. Head-on, the longer dragon wins.")
			intro.append_array(problems)
			intro.append("Arrow keys to fly    %s" % _picker())
			banner.text = "\n".join(intro)
		Arena.State.OVER:
			banner.text = "%s\nEnter to fly again    %s" % [arena.death, _picker()]
		Arena.State.WON:
			if _number() < campaign.steps.size():
				banner.text = "Level clear!\nEnter for level %d    %s" % [_number() + 1, _picker()]
			else:
				banner.text = "You finished %s!\nEnter to start again" % campaign.title
		_:
			banner.text = ""


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


## This step's place in the campaign, counting from 1 as the player does.
func _number() -> int:
	return campaign.steps.find(step) + 1


func _picker() -> String:
	return "1-%d to pick a level" % mini(campaign.steps.size(), 9)
