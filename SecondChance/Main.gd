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

func _ready():
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
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
	var token: Resource = load(TOKEN_ITEM_PATH)  # an ItemData .tres
	token.rarity = _settings.tokenRarity

	var tokenScene: Resource = load(TOKEN_SCENE_PATH)
	print("SecondChance: registering token object " + str(token.rarity))

	_lib.register(_lib.Registry.ITEMS, TOKEN_ID, token)
	_lib.register(_lib.Registry.SCENES, TOKEN_ID, tokenScene)
	_lib.register(_lib.Registry.LOOT, TOKEN_ID, {"item": token, "table": "LT_Master"})
	_registered = true

func _on_lib_ready():
	_lib.hook("character-death-pre", _on_death_pre, 0)# Ensure this triggers before other pre-death events, other mods (ie. RecoverableRemains) can work off of what this mod sets on death
	_lib.hook("character-death-post", _on_death_post, 100)
	_setup_mcm()
	_register_objects()
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