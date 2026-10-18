extends Node

const MOD_ID := "SecondChance"
const FRIENDLY_NAME := "Second Chance"
const DESCRIPTION := "Token that blocks permadeath once."

const SPAWN_ACTION := "SecondChance_SpawnToken"   # MCM uses this as the InputMap action name
const RARITY_ID := "SecondChance_Rarity"

signal values_applied

#default values at runtime
var spawn_token_keycode = KEY_F5
var token_rarity: int = 2
var _config = null;
var McmHelpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
var SecondChanceSettings = preload("res://SecondChance/SecondChanceSettings.tres")

func _ready():
	if McmHelpers == null:
		push_warning("Second Chance: Mod Configuration Menu not found")
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
	.setMenuPos(1)


#	_config.CreateKeycodeValue(
#			SPAWN_ACTION,
#			"[DEV] Spawn token key",
#			"Debug key: spawns a Second Chance token in your inventory",
#			KEY_F5, 
#			MCM_Config.MCM_Key_Types.KEY
#		) \
#		.setMenuPos(2)

	_config.RegisterMod()
	_load_saved_values()

func _load_saved_values() -> void:
	var dir: String = _config.FilePath
	var path := dir.path_join("config.ini")
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		apply_values(cf)
	else:
		push_warning("Second Chance: could not read MCM config at " + path)
		if DirAccess.dir_exists_absolute(dir):
			print("Second Chance: files in ", dir, ": ", DirAccess.get_files_at(dir))

func _entry_value(config: ConfigFile, section: String, id: String):
	if not config.has_section_key(section, id):
		return null
	var entry = config.get_value(section, id)
	if entry is Dictionary and entry.has("value"):
		return entry["value"]
	return null

func apply_values(config: ConfigFile):
	var rarity = _entry_value(config, "Int", RARITY_ID)
	var key = _entry_value(config, "Keycode", SPAWN_ACTION)
	if rarity != null:
		SecondChanceSettings.tokenRarity = int(rarity)
	if key != null:
		SecondChanceSettings.keySpawnToken = key
	SecondChanceSettings.keySpawnTokenCode = SPAWN_ACTION
	print("SecondChance: applying values " + str(SecondChanceSettings.keySpawnToken) + " " + str(SecondChanceSettings.tokenRarity))
	values_applied.emit()

# Called by MCM whenever the player changes and saves values
func _on_config_updated(config: ConfigFile):
	print("SecondChance: Config updated by MCM")
	apply_values(config)
