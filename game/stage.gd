## The world around the Arena: sky, sun, and the board's tiles. Each kind of tile is
## one MultiMesh (Flyweight made visible: one mesh uploaded once, drawn at a thousand
## transforms in one call). draw_board() redraws them for a new level.
class_name Stage
extends Node3D

const SKY_TOP := Color("1b2f4a")
const HORIZON := Color("e0936a")  # dusk; the fog uses it too, so the floor melts into the sky
const EARTH := Color("3a2f2a")  # warm dark ground beyond the walls
## Ways to keep a thousand copies of a tile from looking stamped, by kind.
const TURNED := ["floor", "wall", "lava"]  # random quarter turns
const STRETCHED := ["wall"]  # random heights, for a ragged skyline
const SUNK := ["floor"]  # a few millimeters up or down, like hand-laid stone
## Kit materials that Godot animates, found by the name Blender gave them.
const SHADERS := {
	"Lava": preload("res://game/lava.gdshader"),
	"Water": preload("res://game/water.gdshader"),
}
## Colors for plain boxes when the kit lacks a kind's mesh. Magenta means "art missing".
const FALLBACK_COLORS := {"floor": Color("9c8a6c"), "wall": Color("4d4038")}

var _kit: Dictionary  # kind name -> the kit's Mesh
var _ready_meshes := {}  # kind name -> that mesh, tintable and animated, made once
var _tiles := Node3D.new()
var _skirt := _make_skirt()


## meshes maps kind names to the kit's meshes. A new kind needs a mesh, not new code here.
func _init(meshes: Dictionary) -> void:
	_kit = meshes
	add_child(_world())
	add_child(_sun())
	add_child(_skirt)
	add_child(_tiles)


## Draw every tile of a board, replacing whatever was drawn before.
func draw_board(board: Board) -> void:
	for old in _tiles.get_children():
		old.free()
	var cells_of := {}  # kind -> the cells that hold it
	for cell in board.tiles:
		cells_of.get_or_add(board.tiles[cell], []).append(cell)
	for kind in cells_of:
		_tiles.add_child(_scatter(kind, cells_of[kind], board))
	_skirt.position = Vector3(board.size.x / 2.0, -0.2, board.size.y / 2.0)


## Sky, ambient light, tonemapping, glow, ambient occlusion, and fog in one resource.
func _world() -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = HORIZON
	sky_material.ground_horizon_color = HORIZON
	sky_material.ground_bottom_color = EARTH
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY  # cool from above
	environment.ambient_light_energy = 0.5
	# AgX keeps hues as they brighten, so embers stay orange instead of going yellow-white.
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_agx_contrast = 1.3
	# The web renderer's color buffer tops out near 1.0, so the glow threshold sits
	# just below that: only emissive things (eyes, embers, sparks) bleed light.
	environment.glow_enabled = true
	environment.glow_hdr_threshold = 0.85
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.03
	environment.adjustment_enabled = true  # AgX mutes greens a little; win them back
	environment.adjustment_saturation = 1.2
	environment.ssao_enabled = true  # dark creases where the dragon meets the floor
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.2
	# Depth fog fades the far floor to the horizon color, hiding the edge of the world.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = HORIZON.darkened(0.2)
	environment.fog_depth_begin = 22.0
	environment.fog_depth_end = 70.0
	environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	return world


## A low warm sun: long soft shadows read as "late afternoon" and show the shapes.
func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color("ffd2a1")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0  # only what the follow camera sees
	return sun


## Ground beyond the walls, just under the tiles, so the arena is not floating in the sky.
func _make_skirt() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = EARTH
	material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.material = material
	var skirt := MeshInstance3D.new()
	skirt.mesh = plane
	return skirt


## One MultiMesh draws a copy of the kind's mesh in every cell. Kit meshes sit at the
## height Blender modeled them (z = 0 is the ground); each cell's variety comes from a
## generator seeded by the cell, so a redrawn board looks exactly the same.
func _scatter(kind: String, cells: Array, board: Board) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true  # must be set before instance_count
	multimesh.mesh = _mesh_for(kind, board)
	multimesh.instance_count = cells.size()
	var lift := 0.0
	if not _kit.has(kind):  # a fallback box is centered, so stand it on or in the ground
		lift = multimesh.mesh.get_aabb().size.y / 2 * (1 if board.is_solid(cells[0]) else -1)
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var noise := RandomNumberGenerator.new()
		noise.seed = hash(cell)
		var yaw := noise.randi_range(0, 3) * PI / 2 if kind in TURNED else 0.0
		if kind == "bridge":
			yaw = _bridge_yaw(cell, board)
		var height := noise.randf_range(0.85, 1.15) if kind in STRETCHED else 1.0
		var y := lift + (noise.randf_range(-0.015, 0.015) if kind in SUNK else 0.0)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1, height, 1))
		multimesh.set_instance_transform(
			i, Transform3D(basis, Vector3(cell.x + 0.5, y, cell.y + 0.5))
		)
		var shade := (1.0 if (cell.x + cell.y) % 2 == 0 else 0.9) * noise.randf_range(0.94, 1.04)
		multimesh.set_instance_color(i, Color(shade, shade, shade))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


## A bridge is modeled running north to south. Turn it east to west when that is
## where the dry land is, so it always spans the river.
func _bridge_yaw(cell: Vector2i, board: Board) -> float:
	var dry := func(c: Vector2i) -> int: return 0 if board.kind_at(c) == "water" else 1
	var along: int = dry.call(cell + Vector2i.UP) + dry.call(cell + Vector2i.DOWN)
	var across: int = dry.call(cell + Vector2i.LEFT) + dry.call(cell + Vector2i.RIGHT)
	return 0.0 if along > across else PI / 2


## The kit's mesh for this kind, made ready to draw once and reused for every redraw.
## A missing model becomes a plain box, so it never stops the game.
func _mesh_for(kind: String, board: Board) -> Mesh:
	if not _ready_meshes.has(kind):
		_ready_meshes[kind] = _prepare(_kit[kind]) if _kit.has(kind) else _fallback(kind, board)
	return _ready_meshes[kind]


## Copy the kit's mesh (the shared one stays untouched) and fix up each material:
## animated ones become their shader, fed the colors Blender chose; the rest multiply
## by vertex color, which is how the MultiMesh's per-cell shading shows.
func _prepare(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for surface in copy.get_surface_count():
		var material := copy.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			continue
		if SHADERS.has(material.resource_name):
			var animated := ShaderMaterial.new()
			animated.shader = SHADERS[material.resource_name]
			animated.set_shader_parameter("albedo", material.albedo_color)
			animated.set_shader_parameter("roughness", material.roughness)
			if material.emission_enabled:
				animated.set_shader_parameter("glow", material.emission)
				animated.set_shader_parameter("energy", material.emission_energy_multiplier)
			copy.surface_set_material(surface, animated)
		elif not material.vertex_color_use_as_albedo:
			material = material.duplicate()
			material.vertex_color_use_as_albedo = true
			copy.surface_set_material(surface, material)
	return copy


func _fallback(kind: String, board: Board) -> Mesh:
	var raised := board.is_solid(board.tiles.find_key(kind))
	var material := StandardMaterial3D.new()
	material.albedo_color = FALLBACK_COLORS.get(kind, Color.MAGENTA)
	material.roughness = 0.9
	material.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.7 if raised else 0.15, 1)
	box.material = material
	return box
