extends Node

const MCM_HELPERS = "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"

# Config
const MOD_ID := "SecondChance"
const FRIENDLY_NAME := "Second Chance"
const DESCRIPTION := "Token that blocks permadeath once."

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

var _dying: bool = false # True only while Character.Death() runs
var _permadeathZone: bool = false # True if this death happened in a permadeath zone
var _tokenUsed: bool = false

func _ready():
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		_register_objects()
		if _lib._is_ready:
			_on_lib_ready()
		else:
			_lib.frameworks_ready.connect(_on_lib_ready)

func _register_objects():
	# var token: Resource = load("res://SecondChance/Second_Chance_Token.tres")  # an ItemData .tres
	var result: Dictionary = _lib.register_item({
		TOKEN_ID: {
			"item_path":   "res://SecondChance/Second_Chance_Token.tres",
			"scene_path":  "res://SecondChance/Second_Chance_Token.tscn",
			"loot_tables": ["LT_Master"],
		},
	})

func _on_lib_ready():
	_lib.hook("character-death-pre", _on_death_pre, 0)# Ensure this triggers before other pre-death events, other mods (ie. RecoverableRemains) can work off of what this mod sets on death
	_lib.hook("character-death-post", _on_death_post, 100)
	_setup_mcm()
	print("Second Chance: Loaded")

func _setup_mcm():
	var McmHelpers = load(MCM_HELPERS)
	if McmHelpers == null:
		push_warning("Second Chance: Mod Configuration Menu not found. Using defaults")
		return

	_config = MCM_Config.new(
		MOD_ID,                     # The mods unique ID
		FRIENDLY_NAME,              # The mods name that will be displayed within the MCM
		DESCRIPTION,                # A short description of the mod
		_on_config_updated,               # The callback function that will handle all value updates for your mod
		self                        # The object to call for individual value `on_value_changed` callbacks
	)
	
	_config.CreateIntValue(
		RARITY_ID,
		"Token Rarity",
		"How rarely the Second Chance token appears in loot. 0 - Common, 1 - Rare, 2 - Legendary",
		2
	) \
	.setMinRange(0) \
	.setMaxRange(2) \
	.setOnValueChanged("_rarity_changed") \
	.setMenuPos(1)

	_config.CreateKeycodeValue(
			SPAWN_ACTION,
			"[DEV] Spawn token key",
			"Debug key: spawns a Second Chance token in your inventory",
			KEY_F5, 
			MCM_Config.MCM_Key_Types.KEY
		) \
		.setMenuPos(2)
	
	_config.RegisterMod()

# Called by MCM whenever the player changes and saves values
func _on_config_updated(config: ConfigFile):
	pass

func _rarity_changed(valueId, newValue, menu):
	print("Second chance: applying rarity: " + str(newValue))
	_apply_rarity(newValue)

# MCM files values under a section named after the value type, so search all sections
func _find_value(config: ConfigFile, key: String):
	for section in config.get_sections():
		if config.has_section_key(section, key):
			return config.get_value(section, key)
	return null

func _apply_rarity(rarity: int) -> void:
	if rarity < 0 or rarity > 2:
		push_warning("Second Chance: invalid rarity " + str(rarity))
		return
	var b1 = _lib.patch(_lib.Registry.ITEMS, TOKEN_ID, { "rarity": rarity })
	print("Second Chance: patch result "+ str(b1))
	if(b1 == false):
		push_warning("Second Chance: failed to patch token rarity")
		
func _input(event: InputEvent) -> void:
	if SPAWN_ACTION != "" and InputMap.has_action(SPAWN_ACTION):
		# MCM registered the action: honor whatever key the player set
		if event.is_action_pressed(SPAWN_ACTION) and not event.is_echo():
			_spawn_token()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == SPAWN_FALLBACK_KEY:
		# No MCM action available: plain F5
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