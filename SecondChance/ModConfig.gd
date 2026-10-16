extends Node

const MOD_ID := "SecondChance"
const FRIENDLY_NAME := "Second Chance"
const DESCRIPTION := "Token that blocks permadeath once."

const SPAWN_ACTION := "SecondChance_SpawnToken"   # MCM uses this as the InputMap action name
const RARITY_ID := "SecondChance_Rarity"

#default values at runtime
var spawn_token_keycode = KEY_F5
var token_rarity: int = 2

# Values that Main.gd wants to be told about when they change
const TRACKED_IDS := [RARITY_ID]

var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

# Latest known value per tracked ID, filled in by the MCM callback
var values := {}

func _ready():
	if McmHelpers == null:
		push_warning("Second Chance: Mod Configuration Menu not found")
		return

	var _config = MCM_Config.new(
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
	for id in TRACKED_IDS:
		var value = _find_value(config, id)
		if value == null:
			continue
		if values.has(id) and values[id] == value:
			continue   # unchanged
		values[id] = value
		value_changed.emit(id, value)

# MCM files values under a section named after the value type, so search all sections
func _find_value(config: ConfigFile, key: String):
	for section in config.get_sections():
		if config.has_section_key(section, key):
			return config.get_value(section, key)
	return null