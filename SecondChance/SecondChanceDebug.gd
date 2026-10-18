extends Node

# Debug helpers for Second Chance. Main.gd creates this node only when DEBUG_TOOLS is on.
#
#   Spawn key (MCM action, or F5 without MCM)   spawn a token in your inventory
#   F6   print the loot scan summary
#   F7   clear all beacons
#   F8   print loot bucket sizes and per-container odds for the token
#   F9   check the registered token scene

const FALLBACK_SPAWN_KEY := KEY_F5
const KEY_SUMMARY := KEY_F6
const KEY_CLEAR := KEY_F7
const KEY_ODDS := KEY_F8
const KEY_SCENE := KEY_F9

# Expected picks per loot node for [common, rare, legendary], from GenerateLoot()'s roll table
const PICKS_NORMAL := [0.47, 0.035, 0.002]
const PICKS_CORPSE := [1.333, 0.0667, 0.0033]
const PICKS_JOKER := [7.0, 1.5, 0.1]

var _lib = null
var _token_id := ""
var _settings = null
var _get_interface: Callable

var _stats := {"nodes": 0, "eligible": 0, "found": 0, "expected": 0.0}
var _notify_box: VBoxContainer = null


func setup(lib, token_id: String, settings, interface_getter: Callable) -> void:
	_lib = lib
	_token_id = token_id
	_settings = settings
	_get_interface = interface_getter


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	print("Second Chance: debug tools active")


func _input(event: InputEvent) -> void:
	# Spawn key: the MCM action if it exists, otherwise the fallback key
	var action: String = _settings.keySpawnTokenCode if _settings != null else ""
	if action != "" and InputMap.has_action(action):
		if event.is_action_pressed(action) and not event.is_echo():
			_spawn_token()
			return
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == FALLBACK_SPAWN_KEY:
		_spawn_token()
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SUMMARY:
		_print_loot_summary()
	elif event.keycode == KEY_CLEAR:
		get_tree().call_group("sc_beacon", "queue_free")
	elif event.keycode == KEY_ODDS:
		_print_loot_odds()
	elif event.keycode == KEY_SCENE:
		_check_token_scene()


# ---------------------------------------------------------------- spawning

func _spawn_token() -> void:
	var ui = _get_interface.call()
	if ui == null:
		print("Second Chance: no Interface (not in a map?)")
		return
	var token_data = _lib.get_entry(_lib.Registry.ITEMS, _token_id)
	if token_data == null:
		push_warning("Second Chance: token item is not registered")
		return

	var slot = SlotData.new()
	slot.itemData = token_data

	var grid = ui.inventoryGrid
	if not ui.AutoStack(slot, grid):
		# useDrop = true: if the inventory is full, the token drops at your feet
		ui.Create(slot, grid, true)
	print("Second Chance: spawned token")


# ---------------------------------------------------------------- loot scan

func _on_node_added(node: Node) -> void:
	# LootSimulation has no class_name, so detect loot nodes by their methods
	if node.has_method("GenerateLoot") and node.has_method("FillBuckets"):
		_check_loot_node.call_deferred(node)   # deferred: let its _ready() generate first


func _check_loot_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var token = _lib.get_entry(_lib.Registry.ITEMS, _token_id)
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
		if data != null and data.file == _token_id:
			hits += 1
	if hits > 0:
		_stats["found"] += hits
		var label: String = str(node.containerName) if is_container and str(node.containerName) != "" else str(node.name)
		var note := "" if visible_now else " (hidden stash)"
		var p: Vector3 = node.global_position
		_notify("Token x%d in %s%s at (%d, %d, %d)" % [hits, label, note, int(p.x), int(p.y), int(p.z)])
		if visible_now:
			_highlight_hits(node, is_container)


func _print_loot_summary() -> void:
	var master: LootTable = load("res://Loot/LT_Master.tres")
	var token = _lib.get_entry(_lib.Registry.ITEMS, _token_id)
	var in_master: bool = master != null and token != null and token in master.items
	_notify("in LT_Master: %s | loot nodes scanned: %d | token eligible in: %d | expected so far: %.2f | found: %d" % [
		in_master, _stats["nodes"], _stats["eligible"], _stats["expected"], _stats["found"]])


# ---------------------------------------------------------------- beacons

func _highlight_hits(node: Node, is_container: bool) -> void:
	if is_container:
		_add_beacon(node)
		return
	# LootSimulation spawns loose pickups as children: mark the pickup(s) themselves
	for child in node.get_children():
		if child is Node3D and "slotData" in child and child.slotData != null \
				and child.slotData.itemData != null and child.slotData.itemData.file == _token_id:
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


# ---------------------------------------------------------------- odds

func _print_loot_odds() -> void:
	var master: LootTable = load("res://Loot/LT_Master.tres")
	var token = _lib.get_entry(_lib.Registry.ITEMS, _token_id)
	if master == null or token == null:
		print("Second Chance: odds: master table or token missing")
		return
	var rarity: int = token.rarity
	for flag in ["civilian", "industrial", "military"]:
		var counts := [0, 0, 0]   # common, rare, legendary
		for item in master.items:
			if item.rarity == ItemData.Rarity.Null or not item.get(flag):
				continue
			counts[item.rarity] += 1
		print("Second Chance: ", flag, " buckets common=", counts[0], " rare=", counts[1], " legendary=", counts[2])
		if rarity < 0 or rarity > 2 or counts[rarity] == 0:
			continue
		# counts[rarity] already includes the token (it is registered in LT_Master with all flags)
		var n: int = counts[rarity]
		var normal := _chance(rarity, n, "normal")
		var corpse := _chance(rarity, n, "corpse")
		print("Second Chance:   token chance per container: %.3f%% (1 in %d), per corpse: %.3f%% (1 in %d)" % [
			normal * 100.0, int(round(1.0 / normal)), corpse * 100.0, int(round(1.0 / corpse))])


func _p_hit(n: int, k: int) -> float:
	return 1.0 - pow(1.0 - 1.0 / float(n), k)


func _avg_hit(n: int, k_from: int, k_to: int) -> float:
	var total := 0.0
	for k in range(k_from, k_to + 1):
		total += _p_hit(n, k)
	return total / float(k_to - k_from + 1)


# Chance of at least one token in a node, given the token's rarity and its bucket size n
func _chance(rarity: int, n: int, mode: String) -> float:
	if rarity == 0:
		if mode == "corpse":
			return (20.0 / 30.0) * _avg_hit(n, 0, 4)
		return 0.20 * _avg_hit(n, 0, 4) + 0.01 * _avg_hit(n, 4, 10)
	if rarity == 1:
		if mode == "corpse":
			return (4.0 / 30.0) * _avg_hit(n, 0, 1)
		return 0.04 * _avg_hit(n, 0, 1) + 0.01 * _avg_hit(n, 1, 2)
	if mode == "corpse":
		return (1.0 / 30.0) * 0.1 / float(n)
	return 0.02 * 0.1 / float(n)


# ---------------------------------------------------------------- scene check

func _check_token_scene() -> void:
	var scene = Database.get(_token_id)
	print("Second Chance: Database scene = ", scene, " path = ", scene.resource_path if scene else "none")
	if scene == null:
		return
	var inst = scene.instantiate()
	print("Second Chance: root = ", inst.name, " children = ", inst.get_children())
	var m = inst.get_node_or_null("Mesh")
	print("Second Chance: mesh = ", m.mesh if m else null)
	print("Second Chance: slotData item = ", inst.slotData.itemData.file if inst.slotData and inst.slotData.itemData else "none")
	inst.free()


# ---------------------------------------------------------------- on-screen messages

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