## Engine adapter: stages the Arena in 3D, plays its sounds, and shows the score.
## All rules live in core/; this file only turns state into pictures and sound.
## The world is built by game/stage.gd and the juice by game/effects.gd.
extends Node3D

const TICK_SECONDS := 0.11
const CAMERA_OFFSET := Vector3(0, 6, 5)
const CAMERA_FRAME := 9.0  # dragons this many cells apart still fit the usual view
const CAMERA_MAX_PULL := 2.5  # times the usual distance; fog and shadows end beyond it
const REPLAY_PATH := "user://last.replay"  # in the browser, user:// lives in IndexedDB
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
var wild_seed := 0  # the seed the Wilds grow from: today's, a shared one, or a new roll
var arena: Arena
var player: PlayerController  # this game's keyboard controller; arrow keys go here
var tape: Replay  # the player's current or last game, recorded as it is played
var watching: Replay = null  # the replay on screen, if one is playing back
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
var _notice_fade: Tween


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
	var shared := _shared_seed()
	wild_seed = shared if shared > 0 else _daily_seed()
	_load_level(_wilds_step() if shared > 0 else 0)


## Input arrives as events, so even a tap shorter than one frame is never missed.
func _unhandled_input(event: InputEvent) -> void:
	var paused := arena.state != Arena.State.PLAYING or _replay_over()
	if paused and event is InputEventKey and event.pressed:
		var choice: int = event.keycode - KEY_1  # number keys pick a level
		if choice >= 0 and choice < mini(campaign.steps.size(), 9):
			_load_level(choice)
			return
		if event.keycode == KEY_R:
			watch(tape if tape.ticks > 0 else Replay.load_file(REPLAY_PATH))
			return
		if _growing() and event.keycode in [KEY_N, KEY_D]:  # another map, or today's
			wild_seed = randi_range(1, 99999) if event.keycode == KEY_N else _daily_seed()
			_new_game()
			return
		if event.keycode == KEY_S and tape.ticks > 0:
			var saved := tape.save(REPLAY_PATH)
			_announce("Replay saved. R watches it, even next time." if saved else "Could not save")
			return
	if watching != null:  # arrow keys do nothing during a replay; Enter goes back to flying
		if event.is_action_pressed("ui_accept"):
			_load_level(tape.level - 1)
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
		if arena.will_move(arena.dragon):  # a wading dragon keeps sliding toward its last move
			hero.before_tick(arena.dragon.body)
		if arena.rival != null and arena.will_move(arena.rival):
			rival.before_tick(arena.rival.body)
		arena.tick()
		if watching == null:
			tape.ticks = arena.ticks
		elif _replay_over():
			break
	if arena.state != Arena.State.PLAYING or _replay_over():
		_clock = 0.0
	var head := hero.draw(arena.dragon.body, _progress(arena.dragon, period), delta, arena.ghost)
	var rival_head := _draw_rival(_progress(arena.rival, period), delta)
	_draw_props(delta)
	_follow(head, rival_head, delta)
	_draw_hud()


func _load_level(index: int) -> void:
	step = campaign.steps[index]
	_new_game()


## A fresh game of this step, recorded from the first key. Its map and rules are read
## fresh, so a fixed typo shows on the next try; a broken file still gives a playable
## field, with its errors on screen. A grown map keeps its seed from try to try (the
## seed is the map); a drawn one rolls a new seed each time.
func _new_game() -> void:
	var seed := wild_seed if _growing() else randi()
	level = step.load_level(seed)
	problems = level.errors.duplicate()
	problems.append_array(step.rulebook().errors)
	for problem in problems:
		push_warning(problem)
	watching = null
	tape = Replay.new()
	tape.level = _number()
	tape.map = step.map
	tape.seed = seed
	player = PlayerController.new()
	tape.turns = player.log  # the same Dictionary: the controller writes, the tape keeps
	_show(step.play(level, tape.seed))
	arena.controller = player


## Play a recording back, through the same rules, from the same seed.
func watch(replay: Replay) -> void:
	var restaged := replay.restage(campaign) if replay.errors.is_empty() else null
	if restaged == null:
		_announce("\n".join(replay.errors))
		return
	step = campaign.steps[replay.level - 1]
	level = step.load_level(replay.seed)
	watching = replay
	_show(restaged)


## Draw a new Arena and listen to it.
func _show(game: Arena) -> void:
	arena = game
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
	banner.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM  # short banners stay clear of notices
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
	if _notice_fade != null:
		_notice_fade.kill()  # or the last message's fade would hide this one early
	_notice_fade = create_tween()
	_notice_fade.tween_interval(3.0)
	_notice_fade.tween_property(notice, "modulate:a", 0.0, 0.8)


## How far a dragon is drawn between its last two cells (0 to 1). On floor that is how
## far the clock is toward the next tick; in water a move is spread over two ticks, so
## the stride it has already taken counts too, and the dragon glides instead of lurching.
func _progress(mover: Dragon, period: float) -> float:
	if mover == null:
		return 0.0
	return minf(mover.stride + _clock / period * arena.board.pace_at(mover.body[0]), 1.0)


## The rival may hatch, or crash, in any tick; the view follows whichever is current.
## Returns where its head is drawn, or the player's head when there is no rival.
func _draw_rival(t: float, delta: float) -> Vector3:
	if arena.rival != _rival_drawn:
		_rival_drawn = arena.rival
		rival.reset(arena.rival.body if arena.rival != null else [] as Array[Vector2i])
	if arena.rival == null:
		return _center(arena.dragon.body[0])
	return rival.draw(arena.rival.body, t, delta)


func _draw_props(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	food_node.position = _center(arena.food) + Vector3.UP * (0.08 + 0.06 * sin(now * 3))
	food_node.rotation.y += delta * 2
	# Two sines at odd ratios read as a flicker without any randomness.
	ember_light.light_energy = 1.8 + 0.35 * sin(now * 13) * sin(now * 7.3)
	pickup_node.visible = arena.pickup != null
	pickup_node.position = _center(arena.pickup_cell) + Vector3.UP * (0.2 + 0.15 * sin(now * 5))
	pickup_node.rotation.y += delta * 3


## Ease toward the head between ticks; framerate-independent thanks to exp(). With a
## rival alive, aim between the two heads and back off as they part, so both stay on
## screen; the same easing smooths the zoom when a rival hatches or falls.
func _follow(head: Vector3, rival_head: Vector3, delta: float) -> void:
	var focus := head
	var pull := 1.0
	if arena.rival != null:
		focus = (head + rival_head) / 2
		pull = clampf(head.distance_to(rival_head) / CAMERA_FRAME, 1.0, CAMERA_MAX_PULL)
	var target := Vector3(focus.x, 0, focus.z) + CAMERA_OFFSET * pull
	camera.position = camera.position.lerp(target, 1 - exp(-3 * delta))
	camera.look_at(camera.position - CAMERA_OFFSET)  # the same angle at any distance


func _draw_hud() -> void:
	var embers := "Embers  %d" % arena.score
	if arena.goal > 0:
		embers += " / %d" % arena.goal
	var lines := [level.title, embers]
	if watching != null:
		lines.append("Replay  %d / %d" % [arena.ticks, watching.ticks])
	if arena.rival != null:
		lines.append(
			"Rival  %d" % arena.rival_score + (" / %d" % arena.goal if arena.goal > 0 else "")
		)
	for powerup in arena.active:
		lines.append("%s  %d" % [powerup.title, powerup.remaining])
	score_label.text = "\n".join(lines)
	if watching != null and (_replay_over() or arena.state != Arena.State.PLAYING):
		var ending := arena.death if arena.state == Arena.State.OVER else "Replay over"
		banner.text = "%s\nR to watch again    Enter to fly    %s" % [ending, _picker()]
		return
	if watching != null:
		banner.text = (
			"Replay of level %d, seed %d    Enter to fly" % [watching.level, watching.seed]
		)
		return
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
			banner.text = (
				"%s\nEnter to fly again    R replay    S save    %s" % [arena.death, _picker()]
			)
		Arena.State.WON:
			if _number() < campaign.steps.size():
				banner.text = (
					"Level clear!\nEnter for level %d    R replay    S save    %s"
					% [_number() + 1, _picker()]
				)
			else:
				banner.text = "You finished %s!\nEnter to start again" % campaign.title
		_:
			banner.text = ""


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


## A replay that reached its last recorded tick without the game ending (a
## file trimmed by hand, say) stops there instead of flying on with no one steering.
func _replay_over() -> bool:
	return watching != null and arena.ticks >= watching.ticks


## This step's place in the campaign, counting from 1 as the player does.
func _number() -> int:
	return campaign.steps.find(step) + 1


func _picker() -> String:
	var keys := "1-%d to pick a level" % mini(campaign.steps.size(), 9)
	return keys + ("    N new seed    D daily" if _growing() else "")


## Whether this step's map grows from a seed (see core/terrain.gd).
func _growing() -> bool:
	return step.map == Terrain.NAME


## The campaign's Wilds step, or the first step if it has none.
func _wilds_step() -> int:
	return maxi(campaign.steps.map(func(s): return s.map).find(Terrain.NAME), 0)


## Today's date as a number, e.g. 20261115: everyone in the Wilds today shares a map.
func _daily_seed() -> int:
	var today := Time.get_date_dict_from_system()
	return today.year * 10000 + today.month * 100 + today.day


## A seed to open the Wilds with, from the page's address (index.html?seed=4821) or
## the command line (godot -- --seed=4821), so a link can share a map. 0 if none.
func _shared_seed() -> int:
	var given := ""
	if OS.has_feature("web"):
		given = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed')"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			given = arg.trim_prefix("--seed=")
	return given.to_int() if given.is_valid_int() else 0
