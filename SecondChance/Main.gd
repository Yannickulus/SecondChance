extends Node

const MCM_HELPERS = "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"
# Paths
const TOKEN_ITEM_PATH := "res://SecondChance/Items/SecondChanceToken/Second_Chance_Token.tres"
const TOKEN_SCENE_PATH := "res://SecondChance/Items/SecondChanceToken/Second_Chance_Token.tscn"
const CONFIG_PATH := "res://SecondChance/ModConfig.gd"

# Config
const SPAWN_ACTION := "SecondChance_SpawnToken"   # MCM uses this as the InputMap action name
const RARITY_ID := "SecondChance_Rarity"

# used when MCM isn't installed
const SPAWN_FALLBACK_KEY: Key = KEY_F5
const DEFAULT_RARITY := 2   

const TOKEN_ID: String = "Second_Chance_Token"  # == ItemData.file == registry key

var _interface = null
var _lib = null
var _config = null
var _gameData = preload("res://Resources/GameData.tres")
var _settings: Resource = preload("res://SecondChance/SecondChanceSettings.tres")
var _registered := false

var _dying: bool = false # True only while Character.Death() runs
var _permadeathZone: bool = false # True if this death happened in a permadeath zone
var _tokenUsed: bool = false


const DEBUG_LOOT_SCAN := true   # set to false before releasing

# Expected picks per node for [common, rare, legendary], from GenerateLoot()'s roll table
const PICKS_NORMAL := [0.47, 0.035, 0.002]
const PICKS_CORPSE := [1.333, 0.0667, 0.0033]
const PICKS_JOKER := [7.0, 1.5, 0.1]

var _stats := {"nodes": 0, "eligible": 0, "found": 0, "expected": 0.0}
var _notify_box: VBoxContainer = null

func _ready():
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		_register_objects()
		if _lib._is_ready:
			_on_lib_ready()
		else:
			_lib.frameworks_ready.connect(_on_lib_ready)

func _debug_loot_odds() -> void:
	var master: LootTable = load("res://Loot/LT_Master.tres")
	for flag in ["civilian", "industrial", "military"]:
		var counts := [0, 0, 0]   # common, rare, legendary
		for item in master.items:
			if item.rarity == ItemData.Rarity.Null or not item.get(flag):
				continue
			counts[item.rarity] += 1
		print("Second Chance: ", flag, " buckets common=", counts[0], " rare=", counts[1], " legendary=", counts[2])

func _register_objects():
	#var token: Resource = load(TOKEN_ITEM_PATH)  # an ItemData .tres
	#token.rarity = _settings.tokenRarity

	#var tokenScene: Resource = load(TOKEN_SCENE_PATH)
	#print("SecondChance: registering token object " + str(token.rarity))

	#_lib.register(_lib.Registry.ITEMS, TOKEN_ID, token)
	#_lib.register(_lib.Registry.SCENES, TOKEN_ID, tokenScene)
	#_lib.register(_lib.Registry.LOOT, TOKEN_ID, {"item": token, "table": "LT_Master"})

	_lib.register_item({
		TOKEN_ID: {
			"item_path":    TOKEN_ITEM_PATH,     # required
			"scene_path":   TOKEN_SCENE_PATH,     # optional
			"loot_tables":  ["LT_Master"],
		},
	})
	_registered = true
	if DEBUG_LOOT_SCAN:
		get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.has_method("GenerateLoot") and node.has_method("FillBuckets"):
		_check_loot_node.call_deferred(node)   # deferred: let its _ready() generate first

func _check_loot_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var token = _lib.get_entry(_lib.Registry.ITEMS, TOKEN_ID)
	if token == null:
		return
	var is_container := node is LootContainer
	_stats["nodes"] += 1

	var buckets := [node.commonBucket, node.rareBucket, node.legendaryBucket]
	var rarity: int = token.rarity
	var eligible: bool = rarity >= 0 and rarity <= 2 and token in buckets[rarity]
	var visible_now: bool = node.visible if node is Node3D else true

	if eligible and visible_now:
		_stats["eligible"] += 1
		var picks: Array = PICKS_NORMAL
		if node.get("corpse"):
			picks = PICKS_CORPSE
		if node.get("joker"):
			picks = PICKS_JOKER
		_stats["expected"] += picks[rarity] / float(buckets[rarity].size())

	var hits := 0
	for entry in node.loot:
		var data = entry.itemData if is_container else entry
		if data != null and data.file == TOKEN_ID:
			hits += 1
	if hits > 0:
		_stats["found"] += hits
		var label: String = str(node.containerName) if is_container and str(node.containerName) != "" else str(node.name)
		var note := "" if visible_now else " (hidden stash)"
		var p: Vector3 = node.global_position
		_notify("Token x%d in %s%s at (%d, %d, %d)" % [hits, label, note, int(p.x), int(p.y), int(p.z)])
		if visible_now:
			_highlight_hits(node, is_container)

func _highlight_hits(node: Node, is_container: bool) -> void:
	if is_container:
		_add_beacon(node)
		return
	# LootSimulation spawns loose pickups as children: mark the pickup(s) themselves
	for child in node.get_children():
		if child is Node3D and "slotData" in child and child.slotData != null \
				and child.slotData.itemData != null and child.slotData.itemData.file == TOKEN_ID:
			_add_beacon(child)

func _add_beacon(parent: Node3D) -> void:
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(1.0, 0.2, 0.9, 0.7)
	beam_mat.no_depth_test = true

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 6.0
	cyl.material = beam_mat

	var beam := MeshInstance3D.new()
	beam.mesh = cyl
	beam.position = Vector3(0, 3.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.add_to_group("sc_beacon")
	parent.add_child(beam)

	var tag := Label3D.new()
	tag.text = "TOKEN"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0015
	tag.font_size = 48
	tag.modulate = Color(1.0, 0.3, 0.9)
	tag.outline_modulate = Color.BLACK
	tag.position = Vector3(0, 3.3, 0)
	tag.add_to_group("sc_beacon")
	parent.add_child(tag)

func _print_loot_summary() -> void:
	var master: LootTable = load("res://Loot/LT_Master.tres")
	var token = _lib.get_entry(_lib.Registry.ITEMS, TOKEN_ID)
	var in_master :bool = master != null and token != null and token in master.items
	_notify("in LT_Master: %s | loot nodes scanned: %d | token eligible in: %d | expected so far: %.2f | found: %d" % [
		in_master, _stats["nodes"], _stats["eligible"], _stats["expected"], _stats["found"]])

func _notify(msg: String) -> void:
	print("Second Chance: ", msg)
	if _notify_box == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_notify_box = VBoxContainer.new()
		_notify_box.position = Vector2(24, 24)
		layer.add_child(_notify_box)
		get_tree().root.add_child(layer)
	var label := Label.new()
	label.text = "Second Chance: " + msg
	label.add_theme_font_size_override("font_size", 20)
	_notify_box.add_child(label)
	get_tree().create_timer(10.0).timeout.connect(label.queue_free)
	
func _on_lib_ready():
	_lib.hook("character-death-pre", _on_death_pre, 0)# Ensure this triggers before other pre-death events, other mods (ie. RecoverableRemains) can work off of what this mod sets on death
	_lib.hook("character-death-post", _on_death_post, 100)
	_setup_mcm()
	_debug_loot_odds()
	#_apply_rarity(_settings.tokenRarity)
	print("Second Chance: Loaded")

func _setup_mcm():
	var cfg_script = load(CONFIG_PATH)
	if cfg_script != null and cfg_script.can_instantiate():
		_config = cfg_script.new()
		_config.values_applied.connect(_on_settings_changed)   # before add_child
		add_child(_config)

func _on_settings_changed() -> void:
	if _registered:   # at startup the token doesn't exist yet
		_apply_rarity(_settings.tokenRarity)

func _apply_rarity(rarity: int) -> void:
	if rarity < 0 or rarity > 2:
		push_warning("Second Chance: invalid rarity " + str(rarity))
		return

	var b1 = _lib.patch(_lib.Registry.ITEMS, TOKEN_ID, { "rarity": _settings.tokenRarity })
	print("Second Chance: patch result "+ str(b1) + " " + str(rarity))
		
func _input(event: InputEvent) -> void:
	if InputMap.has_action(_settings.keySpawnTokenCode) and event.is_action_pressed(_settings.keySpawnTokenCode) and not event.is_echo():
		_spawn_token()
	elif not InputMap.has_action(_settings.keySpawnTokenCode) and event is InputEventKey and event.pressed and not event.echo and event.keycode == _settings.keySpawnToken:
		_spawn_token()
	if DEBUG_LOOT_SCAN and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_print_loot_summary()
	if DEBUG_LOOT_SCAN and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		get_tree().call_group("sc_beacon", "queue_free")

func _spawn_token() -> void:
	var ui = _get_interface()   # the find_child helper from earlier
	if ui == null:
		print("Second Chance: no Interface (not in a map?)")
		return

	var lib = Engine.get_meta("RTVModLib")
	var token_data = lib.get_entry(lib.Registry.ITEMS, TOKEN_ID)
	if token_data == null:
		push_warning("Second Chance: token item is not registered")
		return

	var grid = ui.inventoryGrid
	print("Second Chance: interface=", ui.get_path(), " grid=", grid.get_path(),
			" grid size=", grid.gridWidth, "x", grid.gridHeight,
			" items before=", grid.items.size())
	print("Second Chance: token file=", token_data.file, " size=", token_data.size)

	var slot = SlotData.new()
	slot.itemData = token_data

	var placed = ui.Create(slot, grid, false)
	print("Second Chance: Create returned ", placed, ", items now=", grid.items.size())
	
func _on_death_pre():
	_dying = true
	_permadeathZone = false
	_tokenUsed = false
	if _gameData.tutorial:
		return
	
	if not _gameData.permadeath:
		return;

	_permadeathZone = true
	print("Second Chance: death in PERMADEATH mode (difficulty " + str(_gameData.difficulty) + ")")
	if consume_token():
		_tokenUsed = true
		_gameData.permadeath = false   # Death() takes the normal path
		print("Second Chance: token consumed, permadeath blocked")
	else:
		print("Second Chance: no token, permadeath proceeds")

func _on_death_post():
	_dying = false
	_permadeathZone = false
	_tokenUsed = false

func _get_interface():
	if is_instance_valid(_interface):
		return _interface
	# Path derived from Interface.gd's own node references
	var direct = get_node_or_null("/root/Map/Core/UI/Interface")
	if direct != null and "inventoryGrid" in direct:
		_interface = direct
		return _interface

	# Fallback: several nodes are named "Interface", so only accept one
	# that really has an inventoryGrid
	for candidate in get_tree().root.find_children("Interface", "", true, false):
		if "inventoryGrid" in candidate:
			_interface = candidate
			return _interface

	return null

func consume_token() -> bool:
	var ui = _get_interface()
	if ui == null:
		print("Second Chance: Interface not found")
		return false
	var grid = ui.inventoryGrid
	for item in grid.items.duplicate():   # copy: Pick() modifies the array
		if not is_instance_valid(item) or item.slotData == null:
			continue
		var data = item.slotData.itemData
		if data == null or data.file != TOKEN_ID:
			continue
		if item.slotData.amount > 1:
			item.slotData.amount -= 1
			item.UpdateDetails()
			return true
		if grid.Pick(item) == null:
			continue
		grid.remove_child(item)   # Pick() leaves the node in the tree
		item.queue_free()
		return true
	return false