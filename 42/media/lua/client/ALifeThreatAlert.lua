require "PZAPI/ModOptions"
require "ISUI/ISUIElement"

local MOD_ID = "ALifeThreatAlert"
local DEFAULT_RANGE = 40
local DEFAULT_CLOSE_HOSTILE_RANGE = 10
local DEFAULT_ALARM_SOUND = 2
local DEFAULT_CLOSE_HOSTILE_ALARM_SOUND = 1
local DEFAULT_SPRINTER_ALARM_SOUND = 3
local DEFAULT_REAR_ZOMBIE_RANGE = 20
local DEFAULT_SPRINTER_RANGE = 20
local DEFAULT_SPRINTER_ALARM_DISTANCE = 20
local DEFAULT_SPRINTER_BLINK_DISTANCE = 3
local DEFAULT_REAR_ZOMBIE_ANGLE = 180
local DEFAULT_REAR_ZOMBIE_BLINK_DISTANCE = 1.5
local DEFAULT_RADIAL_INDICATOR_FAR_OPACITY = 35
local DEFAULT_ALARM_VOLUME = 150
local MAX_ALARM_VOLUME = 200
local MIN_RANGE = 5
local MAX_RANGE = 100
local MIN_CLOSE_HOSTILE_RANGE = 1
local MIN_SPRINTER_BLINK_DISTANCE = 0
local MAX_SPRINTER_BLINK_DISTANCE = 10
local SPRINTER_BLINK_DISTANCE_STEP = 0.5
local MIN_REAR_ZOMBIE_BLINK_DISTANCE = 0
local MAX_REAR_ZOMBIE_BLINK_DISTANCE = 10
local REAR_ZOMBIE_BLINK_DISTANCE_STEP = 0.5
local MIN_REAR_ZOMBIE_ANGLE = 30
local MAX_REAR_ZOMBIE_ANGLE = 360
local REAR_ZOMBIE_ANGLE_STEP = 5
local MIN_RADIAL_INDICATOR_ASSET_RADIUS = 96
local MAX_RADIAL_INDICATOR_ASSET_RADIUS = 320
local RADIAL_INDICATOR_ASSET_RADIUS_STEP = 16
local ALERT_DISPLAY_MODE_COMPACT_NEATUI = 1
local ALERT_DISPLAY_MODE_FULL_NEATUI = 2
local ALERT_DISPLAY_MODE_VANILLA = 3
local ALERT_POSITION_FILE = "ViewpointThreatDetectorPosition.txt"
local ALARM_SOUND_OPTIONS = {
    { id = "ViewpointThreatDetectorRadarPing", label = "Radar ping" },
    { id = "ViewpointThreatDetectorHeartbeat", label = "Heartbeat" },
    { id = "ViewpointThreatDetectorSoftBeep", label = "Soft beep" },
    { id = "ViewpointThreatDetectorSonarPing", label = "Sonar ping" },
    { id = "ViewpointThreatDetectorShortAlarm", label = "Short alarm" },
    { id = "ViewpointThreatDetectorSpaceAnchorAction", label = "Space - Anchor action" },
    { id = "ViewpointThreatDetectorSpaceExit", label = "Space - Exit" },
    { id = "ViewpointThreatDetectorSpaceLink", label = "Space - Link" },
    { id = "ViewpointThreatDetectorSpaceMagnetAction", label = "Space - Magnet action" },
    { id = "ViewpointThreatDetectorSpaceMagnetOff", label = "Space - Magnet off" },
    { id = "ViewpointThreatDetectorSpaceMagnetOn", label = "Space - Magnet on" },
    { id = "ViewpointThreatDetectorSpaceMagnetStart", label = "Space - Magnet start" },
    { id = "ViewpointThreatDetectorSpacePart", label = "Space - Part" },
    { id = "ViewpointThreatDetectorSpaceUnlink", label = "Space - Unlink" },
    { id = "ViewpointThreatDetectorSpaceWall", label = "Space - Wall" },
}

local function addAlarmSoundOptions(option, defaultIndex)
    for index, soundOption in ipairs(ALARM_SOUND_OPTIONS) do
        option:addItem(soundOption.label, index == defaultIndex)
    end
end
local SCAN_INTERVAL = 5
local STANCES = { allied = true, friendly = true, neutral = true, careful = true, hostile = true }
local STANCE_PRIORITY = { "hostile", "careful", "neutral", "friendly", "allied" }
local STANCE_OPTION_KEYS = {
    hostile = "EnableHostileWarning",
    careful = "WarnCarefulNPCs",
    neutral = "WarnNeutralNPCs",
    friendly = "WarnFriendlyNPCs",
    allied = "WarnAlliedNPCs",
}
local STANCE_OPTION_DEFAULTS = {
    hostile = false,
    careful = false,
    neutral = false,
    friendly = false,
    allied = false,
}
local STANCE_LABELS = {
    allied = "Allied",
    friendly = "Friendly",
    neutral = "Neutral",
    careful = "Careful",
    hostile = "Hostile",
}
local STANCE_COLOURS = {
    allied = { 0.25, 0.68, 1 },
    friendly = { 0.25, 0.9, 0.35 },
    neutral = { 0.88, 0.88, 0.88 },
    careful = { 1, 0.82, 0.12 },
    hostile = { 1, 0.2, 0.16 },
}
local SPRINTER_COLOUR = { 130 / 255, 0, 129 / 255 }
local SPRINTER_NEAR_COLOUR = { 1, 0, 1 }
local REAR_ZOMBIE_INDICATOR_RED = { 1, 48 / 255, 48 / 255 }
local REAR_ZOMBIE_INDICATOR_YELLOW = { 1, 0.82, 0.12 }
local REAR_ZOMBIE_INDICATOR_RADII = { 128, 176, 224 }
local SHADOW_OFFSETS = { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }
local typeIconTextureCache = {}
local neatPanelTextureCache = {}
local rearZombieIndicatorTextureCache = {}
local rearZombieIndicatorTextureRetryAt = {}
local radialIndicatorOpacity
local TYPE_ICON_TEXTURES = {
    alife = "media/ui/ThreatAlert/alife.png",
    firearm = "media/textures/Item_HandGun3",
}
local NEAT_PANEL_HEADER_TEXTURE = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png"
local NEAT_PANEL_BODY_TEXTURE = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png"

local modOptions
local getOption
local playAlarmSound
local beginAlertPreview
local activeAlertPreview
local alertLayoutPreviewEnabled
local lastConfiguredAlertLayoutPreview

local function stopAlarmAudio(soundInstance)
    if soundInstance == nil then return end
    pcall(function()
        soundInstance.emitter:stopSound(soundInstance.handle)
    end)
end

local function onPreviewAlert(_, _, kind)
    if beginAlertPreview then beginAlertPreview(kind) end
end

if PZAPI and PZAPI.ModOptions then
    modOptions = PZAPI.ModOptions:create(MOD_ID, "Viewpoint Threat Detector")
    modOptions.defaultValues = {}
    modOptions:addTitle("General")
    modOptions:addButton(
        "ResetModOptions",
        "Reset settings to default",
        "Restores this mod's settings to their fresh-install defaults.",
        function()
            for optionId, defaultValue in pairs(modOptions.defaultValues) do
                local option = modOptions:getOption(optionId)
                if option and option.setValue then
                    local value = defaultValue
                    if type(defaultValue) == "table" then
                        value = {}
                        for key, item in pairs(defaultValue) do
                            value[key] = item
                        end
                    end
                    option:setValue(value)
                end
            end
        end
    )
    modOptions:addTitle("A-Life NPC Threats")
    modOptions:addTickBox("EnableHostileWarning", "Warn about nearby hostile NPCs", false)
    modOptions:addTickBox("WarnCarefulNPCs", "Warn about nearby careful NPCs", false)
    modOptions:addTickBox("WarnNeutralNPCs", "Warn about nearby neutral NPCs", false)
    modOptions:addTickBox("WarnFriendlyNPCs", "Warn about nearby friendly NPCs", false)
    modOptions:addTickBox("WarnAlliedNPCs", "Warn about nearby allied NPCs", false)
    modOptions:addTickBox("ShowFirearmWarning", "Identify nearby NPCs carrying firearms", false)
    modOptions:addSlider(
        "WarningDistance",
        "Maximum warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_RANGE,
        "Maximum horizontal distance at which A-Life NPCs trigger a warning."
    )
    modOptions:addTickBox(
        "EnableCloseHostileAlarm",
        "Play a separate alarm for close Hostile A-Life NPCs",
        false,
        "Triggers independently of the regular NPC warning when a Hostile NPC enters the configured distance."
    )
    modOptions:addSlider(
        "CloseHostileAlarmDistance",
        "Hostile A-Life alarm distance (tiles)",
        MIN_CLOSE_HOSTILE_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_CLOSE_HOSTILE_RANGE,
        "Distance for the separate Hostile A-Life alarm, independent of the regular NPC warning range."
    )

    modOptions:addTitle("Rear Zombie Threats")
    modOptions:addTickBox("EnableRearZombieWarning", "Warn when zombies are behind you", true)
    modOptions:addTickBox(
        "RearZombieSameFloorOnly",
        "Detect rear zombies only on the same floor",
        true,
        "When enabled, zombies on other floors do not trigger rear warnings."
    )
    modOptions:addTickBox(
        "RearZombieRequireLineOfSight",
        "Require a clear path to rear zombies",
        true,
        "When enabled, walls and closed doors block rear zombie warnings; low climbable fences do not."
    )
    modOptions:addTickBox(
        "IgnoreFallenZombies",
        "Ignore fallen zombies in rear warnings",
        false,
        "When enabled, zombies on the ground do not trigger the rear zombie warning."
    )
    modOptions:addTickBox(
        "UseBalancedRearZombieRange",
        "Use balanced rear zombie range (Keen Hearing-aware)",
        true,
        "Uses 3.5 tiles normally and 6.5 tiles with Keen Hearing. Disable this to use the custom distance below."
    )
    modOptions:addSlider(
        "RearZombieWarningDistance",
        "Custom rear zombie warning distance (tiles)",
        MIN_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_REAR_ZOMBIE_RANGE,
        "Used only when the balanced rear zombie range is disabled."
    )
    modOptions:addSlider(
        "RearZombieWarningAngle",
        "Rear zombie detection angle (degrees)",
        MIN_REAR_ZOMBIE_ANGLE,
        MAX_REAR_ZOMBIE_ANGLE,
        REAR_ZOMBIE_ANGLE_STEP,
        DEFAULT_REAR_ZOMBIE_ANGLE,
        "Total angle centered behind you. 180 degrees detects the rear half; larger values widen the area."
    )
    modOptions:addSlider(
        "RearZombieBlinkDistance",
        "Critical rear zombie blink distance (tiles)",
        MIN_REAR_ZOMBIE_BLINK_DISTANCE,
        MAX_REAR_ZOMBIE_BLINK_DISTANCE,
        REAR_ZOMBIE_BLINK_DISTANCE_STEP,
        DEFAULT_REAR_ZOMBIE_BLINK_DISTANCE,
        "Radial rear-zombie indicators pulse when their nearest zombie is within this distance. Set to 0 to disable blinking."
    )
    modOptions:addTitle("Radial Indicator Appearance")
    modOptions:addSlider(
        "RadialIndicatorRadius",
        "Radial circle radius (100 = default)",
        75,
        150,
        5,
        100,
        "Scales the indicators' distance from the center of the screen. 100 keeps the current screen-adaptive radius."
    )
    modOptions:addSlider(
        "RadialIndicatorSize",
        "Radial indicator size",
        75,
        125,
        25,
        100,
        "Adjusts the arc width, line thickness, and arrow size without changing the circle radius."
    )
    modOptions:addTickBox(
        "FadeRadialIndicatorsByDistance",
        "Fade indicators as threats get farther away",
        true,
        "Radial indicators are fully opaque nearby and fade with distance. Applies to zombies and sprinters."
    )
    modOptions:addSlider(
        "RadialIndicatorFarOpacity",
        "Opacity at detection range edge (%)",
        0,
        100,
        5,
        DEFAULT_RADIAL_INDICATOR_FAR_OPACITY,
        "Sets the opacity at maximum detection range. Nearby indicators stay fully opaque; 100 disables the fade."
    )
    modOptions:addColorPicker(
        "RearZombieIndicatorNearColour",
        "Zombie indicator color at close range",
        REAR_ZOMBIE_INDICATOR_RED[1], REAR_ZOMBIE_INDICATOR_RED[2],
        REAR_ZOMBIE_INDICATOR_RED[3], 1,
        "The radial zombie indicator smoothly blends from this color to its far-range color."
    )
    modOptions:addColorPicker(
        "RearZombieIndicatorFarColour",
        "Zombie indicator color at far range",
        REAR_ZOMBIE_INDICATOR_YELLOW[1], REAR_ZOMBIE_INDICATOR_YELLOW[2],
        REAR_ZOMBIE_INDICATOR_YELLOW[3], 1,
        "The radial zombie indicator smoothly blends from its close-range color to this color."
    )
    modOptions:addColorPicker(
        "SprinterIndicatorNearColour",
        "Sprinter indicator color at close range",
        SPRINTER_NEAR_COLOUR[1], SPRINTER_NEAR_COLOUR[2], SPRINTER_NEAR_COLOUR[3], 1,
        "The radial sprinter indicator smoothly blends from this color to its far-range color."
    )
    modOptions:addColorPicker(
        "SprinterIndicatorFarColour",
        "Sprinter indicator color at far range",
        SPRINTER_COLOUR[1], SPRINTER_COLOUR[2], SPRINTER_COLOUR[3], 1,
        "The radial sprinter indicator smoothly blends from its close-range color to this color."
    )

    modOptions:addTitle("Radial Indicator Limits")
    modOptions:addSlider(
        "MaxRearZombieIndicators",
        "Maximum rear-zombie indicators",
        1,
        8,
        1,
        3,
        "Shows up to this many directional sectors. Zombies in each sector share one indicator."
    )
    modOptions:addSlider(
        "MaxSprinterIndicators",
        "Maximum sprinter indicators",
        1,
        8,
        1,
        1,
        "Shows up to this many directions around the full compass, with one indicator for the nearest sprinter in each sector."
    )

    modOptions:addTitle("Sprinter Threats")
    modOptions:addTickBox(
        "EnableSprinterWarning",
        "Warn about nearby sprinters",
        true,
        "Displays a separate warning and can play its own alarm when a sprinter enters range."
    )
    modOptions:addSlider(
        "SprinterWarningDistance",
        "Sprinter warning distance (tiles)",
        MIN_CLOSE_HOSTILE_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_SPRINTER_RANGE,
        "Maximum distance for the sprinter warning. The separate alarm distance is configured below."
    )
    modOptions:addSlider(
        "SprinterBlinkDistance",
        "Critical sprinter blink distance (tiles)",
        MIN_SPRINTER_BLINK_DISTANCE,
        MAX_SPRINTER_BLINK_DISTANCE,
        SPRINTER_BLINK_DISTANCE_STEP,
        DEFAULT_SPRINTER_BLINK_DISTANCE,
        "The sprinter alert blinks when the nearest sprinter is within this distance. Set to 0 to disable blinking."
    )
    modOptions:addSlider(
        "SprinterAlarmDistance",
        "Sprinter alarm distance (tiles)",
        MIN_CLOSE_HOSTILE_RANGE,
        MAX_RANGE,
        1,
        DEFAULT_SPRINTER_ALARM_DISTANCE,
        "Maximum distance for the dedicated sprinter alarm, independent of its visual warning range."
    )
    modOptions:addTickBox(
        "SprinterSameFloorOnly",
        "Detect sprinters only on the same floor",
        true,
        "When enabled, sprinters on other floors do not trigger this warning."
    )
    modOptions:addTickBox(
        "SprinterRequireLineOfSight",
        "Require a clear path to sprinters",
        true,
        "When enabled, walls and closed doors block sprinter warnings; low climbable fences do not."
    )
    modOptions:addTickBox(
        "SprinterIgnoreFallen",
        "Ignore fallen sprinters",
        true,
        "When enabled, sprinters on the ground do not trigger the separate warning."
    )

    modOptions:addTitle("Alert Display")
    modOptions:addTickBox(
        "ImmersiveMode",
        "Use immersive audio-only alerts",
        false,
        "Hides all visual alerts and display previews. Threat detection and configured alarm sounds continue unchanged."
    )
    modOptions:addTickBox("ShowDirectionArrow", "Show direction arrows on A-Life alerts", true)
    local alertDisplayOption = modOptions:addComboBox(
        "AlertDisplayMode",
        "A-Life alert display style",
        "Choose how A-Life alerts appear. NeatUI styles require NeatUI_Framework; Vanilla Mode works without it. Zombie and sprinter tracking always uses DayZ-style radial indicators."
    )
    alertDisplayOption:addItem("Compact NeatUI", false)
    alertDisplayOption:addItem("Full NeatUI", false)
    alertDisplayOption:addItem("Vanilla Mode", true)
    modOptions:addTickBox(
        "EnableDragDiagnostics",
        "Log alert drag diagnostics",
        false,
        "Temporarily logs alert hitbox positions and mouse drag events to console.txt. Turn off after testing."
    )
    modOptions:addTitle("Vehicle alert controls")
    modOptions:addTickBox(
        "DisableZombieAlertsInVehicle",
        "Disable zombie alerts while inside a vehicle",
        true,
        "Suppresses rear zombie warnings while you are in a vehicle."
    )
    modOptions:addTickBox(
        "DisableSprinterAlertsInVehicle",
        "Disable sprinter alerts while inside a vehicle",
        true,
        "Suppresses sprinter warnings and their dedicated alarm while you are in a vehicle."
    )
    modOptions:addTickBox(
        "DisableALifeAlertsInVehicle",
        "Disable A-Life alerts while inside a vehicle",
        true,
        "Suppresses A-Life NPC warnings and the close Hostile alarm while you are in a vehicle."
    )
    modOptions:addTitle("Alert previews")
    modOptions:addTickBox(
        "ShowAlertLayoutPreview",
        "Preview all alert types",
        false,
        "Shows sample A-Life cards and zombie/sprinter radial indicators without nearby threats. Drag the A-Life cards to set their HUD position."
    )
    modOptions:addKeyBind(
        "ToggleAlertLayoutPreviewKey",
        "Toggle alert layout preview in-game",
        0,
        "Toggles sample alerts on the HUD. Unassigned by default."
    )
    modOptions:addButton(
        "PreviewALifeAlert",
        "Preview A-Life alerts",
        "Temporarily displays sample Hostile and Friendly A-Life cards on the HUD.",
        onPreviewAlert,
        nil,
        "alife"
    )
    modOptions:addButton(
        "PreviewZombieAlert",
        "Preview zombie radial indicators",
        "Temporarily displays sample rear-zombie radial indicators.",
        onPreviewAlert,
        nil,
        "zombie"
    )
    modOptions:addButton(
        "PreviewSprinterAlert",
        "Preview sprinter radial indicator",
        "Temporarily displays a sample sprinter radial indicator.",
        onPreviewAlert,
        nil,
        "sprinter"
    )

    modOptions:addTitle("Alarm Sounds")
    modOptions:addTickBox(
        "EnableAlarmSound",
        "Play an alarm sound for new threats",
        true,
        "Master switch for all alarm sounds, including the separate close Hostile A-Life and sprinter alarms."
    )
    modOptions:addSlider(
        "AlarmVolume",
        "Alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for this mod's alarm sounds. The default is louder than before."
    )
    modOptions:addTickBox(
        "ZombieAlarmOnly",
        "Play the regular alarm only for zombie warnings",
        true,
        "When enabled, regular A-Life warnings do not trigger the regular alarm. Separate close Hostile A-Life and sprinter alarms are configured independently."
    )
    modOptions:addTickBox(
        "EnableSprinterAlarm",
        "Play a separate alarm for sprinters",
        true,
        "Uses the selected sound and volume below, with the independent alarm distance from Sprinter Threats."
    )
    local alarmSoundOption = modOptions:addComboBox(
        "AlarmSound",
        "Alarm sound",
        "Choose the alarm cue used when a new threat appears."
    )
    addAlarmSoundOptions(alarmSoundOption, DEFAULT_ALARM_SOUND)
    local closeHostileAlarmSoundOption = modOptions:addComboBox(
        "CloseHostileAlarmSound",
        "Close Hostile A-Life alarm sound",
        "Choose a distinct sound cue for Hostile A-Life NPCs that enter the close range."
    )
    addAlarmSoundOptions(closeHostileAlarmSoundOption, DEFAULT_CLOSE_HOSTILE_ALARM_SOUND)
    local sprinterAlarmSoundOption = modOptions:addComboBox(
        "SprinterAlarmSound",
        "Sprinter alarm sound",
        "Choose a distinct sound cue for sprinters entering range."
    )
    addAlarmSoundOptions(sprinterAlarmSoundOption, DEFAULT_SPRINTER_ALARM_SOUND)
    modOptions:addSlider(
        "CloseHostileAlarmVolume",
        "Close Hostile A-Life alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for the separate close Hostile A-Life alarm."
    )
    modOptions:addSlider(
        "SprinterAlarmVolume",
        "Sprinter alarm volume (%)",
        0,
        MAX_ALARM_VOLUME,
        10,
        DEFAULT_ALARM_VOLUME,
        "Volume multiplier for the separate sprinter alarm."
    )
    modOptions:addTitle("In-game sound preview")
    local alarmPreviewTypeOption = modOptions:addComboBox(
        "AlarmPreviewType",
        "Alarm to preview",
        "Choose which configured alarm is played by the preview key while in-game."
    )
    alarmPreviewTypeOption:addItem("Regular alarm", true)
    alarmPreviewTypeOption:addItem("Close Hostile A-Life", false)
    alarmPreviewTypeOption:addItem("Sprinter", false)
    modOptions:addKeyBind(
        "AlarmPreviewKey",
        "Play alarm preview in-game",
        Keyboard.KEY_F9,
        "Press this key during gameplay to play the selected alarm through the same function used by real alerts."
    )
end

if modOptions then
    modOptions.defaultValues = (function(options)
        local defaults = {}
        for _, option in ipairs(options.data) do
            if option.id and option.getValue then
                local value = option:getValue()
                if type(value) == "table" then
                    value = (function(source)
                        local copy = {}
                        for key, item in pairs(source) do
                            copy[key] = item
                        end
                        return copy
                    end)(value)
                end
                defaults[option.id] = value
            end
        end
        return defaults
    end)(modOptions)
end

local SOUND_MIGRATION_MARKER = "migration|ALifeThreatAlert|siren-removed-v1|1"
local VEHICLE_ALERT_MIGRATION_MARKER = "migration|ALifeThreatAlert|vehicle-alerts-split-v1|1"
local VEHICLE_ALERT_OPTION_IDS = {
    "DisableZombieAlertsInVehicle",
    "DisableSprinterAlertsInVehicle",
    "DisableALifeAlertsInVehicle",
}
local VEHICLE_ALERT_OPTION_SET = {
    DisableZombieAlertsInVehicle = true,
    DisableSprinterAlertsInVehicle = true,
    DisableALifeAlertsInVehicle = true,
}
local LEGACY_SOUND_DEFAULTS = {
    AlarmSound = DEFAULT_ALARM_SOUND,
    CloseHostileAlarmSound = DEFAULT_CLOSE_HOSTILE_ALARM_SOUND,
    SprinterAlarmSound = DEFAULT_SPRINTER_ALARM_SOUND,
}

local function readSavedSoundSelections()
    local selections = {}
    local hasMarker = false
    local ok, reader = pcall(function() return getFileReader("ModOptions.ini", true) end)
    if not ok or not reader then return selections, hasMarker end

    while true do
        local readOk, line = pcall(function() return reader:readLine() end)
        if not readOk or line == nil then break end
        if string.find(line, SOUND_MIGRATION_MARKER, 1, true) then hasMarker = true end
        local _, modId, optionId, value = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)")
        if modId == MOD_ID and LEGACY_SOUND_DEFAULTS[optionId] then
            selections[optionId] = tonumber(value)
        end
    end
    pcall(function() reader:close() end)
    return selections, hasMarker
end

local function hasSoundMigrationMarker(lines)
    for _, line in ipairs(lines or {}) do
        if string.find(line, SOUND_MIGRATION_MARKER, 1, true) then return true end
    end
    return false
end

local function readSavedVehicleAlertSettings()
    local settings = { savedOptions = {} }
    local hasMarker = false
    local ok, reader = pcall(function() return getFileReader("ModOptions.ini", true) end)
    if not ok or not reader then return settings, hasMarker end

    while true do
        local readOk, line = pcall(function() return reader:readLine() end)
        if not readOk or line == nil then break end
        if string.find(line, VEHICLE_ALERT_MIGRATION_MARKER, 1, true) then hasMarker = true end
        local _, modId, optionId, value = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)")
        if modId == MOD_ID then
            if optionId == "DisableInVehicle" then
                if value == "true" then settings.legacyDisable = true end
                if value == "false" then settings.legacyDisable = false end
            elseif VEHICLE_ALERT_OPTION_SET[optionId] then
                settings.savedOptions[optionId] = true
            end
        end
    end
    pcall(function() reader:close() end)
    return settings, hasMarker
end

local function hasVehicleAlertMigrationMarker(lines)
    for _, line in ipairs(lines or {}) do
        if string.find(line, VEHICLE_ALERT_MIGRATION_MARKER, 1, true) then return true end
    end
    return false
end

local function migrateLegacySoundIndex(index, default)
    if index == 1 then return 1 end
    if index == 2 then return default end
    if index == 3 then return 2 end
    if index == 4 then return 3 end
    return default
end

if PZAPI and PZAPI.ModOptions and not PZAPI.ModOptions._vtdSirenMigrationInstalled then
    local originalLoad = PZAPI.ModOptions.load
    PZAPI.ModOptions.load = function(self, ...)
        local selections, fileHasMarker = readSavedSoundSelections()
        local vehicleSettings, fileHasVehicleMarker = readSavedVehicleAlertSettings()
        local alreadyMigrated = fileHasMarker
            or hasSoundMigrationMarker(PZAPI.ModOptions.OtherOptions)
        local vehicleAlreadyMigrated = fileHasVehicleMarker
            or hasVehicleAlertMigrationMarker(PZAPI.ModOptions.OtherOptions)
        originalLoad(self, ...)

        if not alreadyMigrated then
            for optionId, default in pairs(LEGACY_SOUND_DEFAULTS) do
                local oldIndex = selections[optionId]
                local option = modOptions and modOptions:getOption(optionId)
                if oldIndex and option then
                    option:setValue(migrateLegacySoundIndex(oldIndex, default))
                end
            end
        end

        if not hasSoundMigrationMarker(PZAPI.ModOptions.OtherOptions) then
            table.insert(PZAPI.ModOptions.OtherOptions, SOUND_MIGRATION_MARKER .. "\r\n")
        end

        if not vehicleAlreadyMigrated and vehicleSettings.legacyDisable ~= nil then
            for _, optionId in ipairs(VEHICLE_ALERT_OPTION_IDS) do
                if not vehicleSettings.savedOptions[optionId] then
                    local option = modOptions and modOptions:getOption(optionId)
                    if option then option:setValue(vehicleSettings.legacyDisable) end
                end
            end
            table.insert(PZAPI.ModOptions.OtherOptions, VEHICLE_ALERT_MIGRATION_MARKER .. "\r\n")
        end
    end
    PZAPI.ModOptions._vtdSirenMigrationInstalled = true
end

local alertPositionX
local alertPositionY
local alertDragHandle
local playerInVehicle = false
local dragDiagnosticsEnabled = false
local activeGlobalDragHandle
local globalDragMouseX
local globalDragMouseY
local warnings = {}
local rearZombieWarning
local rearZombieIndicators = {}
local sprinterWarning
local rearZombieBlinkThreshold = DEFAULT_REAR_ZOMBIE_BLINK_DISTANCE
local sprinterBlinkThreshold = DEFAULT_SPRINTER_BLINK_DISTANCE

local function logDragDiagnostic(message)
    if dragDiagnosticsEnabled then
        print("[Viewpoint Threat Detector][Drag] " .. message)
    end
end

local function loadPosition(fileName)
    if not getFileReader then return end
    local ok, reader = pcall(getFileReader, fileName, false)
    if not ok or not reader then return end

    local readOk, x, y = pcall(function()
        local positionX = tonumber(reader:readLine())
        local positionY = tonumber(reader:readLine())
        reader:close()
        return positionX, positionY
    end)
    if not readOk then
        pcall(function() reader:close() end)
        return nil, nil
    end
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return x, y
    end
    return nil, nil
end

local function savePosition(fileName, x, y)
    if not getFileWriter or not x or not y then return end
    local ok, writer = pcall(getFileWriter, fileName, true, false)
    if not ok or not writer then return end

    pcall(function() writer:write(string.format("%.6f\n%.6f\n", x, y)) end)
    pcall(function() writer:close() end)
end

alertPositionX, alertPositionY = loadPosition(ALERT_POSITION_FILE)

local function saveAlertPosition()
    savePosition(ALERT_POSITION_FILE, alertPositionX, alertPositionY)
end

local AlertDragHandle = ISUIElement:derive("ViewpointThreatDetectorAlertDragHandle")

function AlertDragHandle:new()
    return ISUIElement.new(self, 0, 0, 1, 1)
end

local AlertArrowLayer = ISUIElement:derive("ViewpointThreatDetectorAlertArrowLayer")

function AlertArrowLayer:new()
    return ISUIElement.new(self, 0, 0, 1, 1)
end

local alertArrowLayers = { live = {}, preview = {} }
local arrowLayerCounts = { live = 0, preview = 0 }
local currentArrowLayerPass = "live"
local displayedArrowAngles = {}

local function beginArrowLayerPass(pass)
    currentArrowLayerPass = pass
    arrowLayerCounts[pass] = 0
end

local function finishArrowLayerPass(pass)
    local layers = alertArrowLayers[pass]
    for index = arrowLayerCounts[pass] + 1, #layers do
        local layer = layers[index]
        layer:setVisible(false)
        layer:setX(-10000)
        layer:setY(-10000)
        layer:setWidth(1)
        layer:setHeight(1)
    end
end

local function ensureAlertArrowLayer(pass, index)
    local layers = alertArrowLayers[pass]
    local layer = layers[index]
    if not layer then
        local ok, layer = pcall(function()
            local instance = AlertArrowLayer:new()
            instance:initialise()
            instance:addToUIManager()
            instance:setWantMouseEvents(false)
            instance:setVisible(true)
            return instance
        end)
        if ok then
            layers[index] = layer
        else
            return nil
        end
    end
    return layers[index]
end

local function smoothArrowAngle(key, targetAngle)
    if not key or targetAngle == nil then return targetAngle end
    local previousAngle = displayedArrowAngles[key]
    if previousAngle == nil then
        displayedArrowAngles[key] = targetAngle
        return targetAngle
    end

    local difference = targetAngle - previousAngle
    if difference > math.pi then
        difference = difference - math.pi * 2
    elseif difference < -math.pi then
        difference = difference + math.pi * 2
    end
    local angle = previousAngle + difference * 0.35
    if math.abs(difference) < 0.002 then angle = targetAngle end
    displayedArrowAngles[key] = angle
    return angle
end

local function drawDirectionArrow(centerX, centerY, angle, colour, size, key)
    if angle == nil then return end
    angle = smoothArrowAngle(key, angle)
    local directionX = math.sin(angle)
    local directionY = -math.cos(angle)
    local perpendicularX = math.cos(angle)
    local perpendicularY = math.sin(angle)
    local outerTriangleSize = size + 2
    local radius = math.ceil(outerTriangleSize * 0.53 + 2)
    local layerX = math.floor(centerX - radius)
    local layerY = math.floor(centerY - radius)

    local layerIndex = arrowLayerCounts[currentArrowLayerPass] + 1
    local layer = ensureAlertArrowLayer(currentArrowLayerPass, layerIndex)
    if not layer then return end
    arrowLayerCounts[currentArrowLayerPass] = layerIndex

    layer:setX(layerX)
    layer:setY(layerY)
    layer:setWidth(radius * 2 + 1)
    layer:setHeight(radius * 2 + 1)
    layer:setVisible(true)
    local localCenterX = centerX - layerX
    local localCenterY = centerY - layerY

    local function drawTriangle(triangleSize, r, g, b, alpha)
        local halfLength = triangleSize * 0.5
        local halfWidth = triangleSize * 0.32
        local tipX = localCenterX + directionX * halfLength
        local tipY = localCenterY + directionY * halfLength
        local baseX = localCenterX - directionX * halfLength
        local baseY = localCenterY - directionY * halfLength
        local leftX = baseX - perpendicularX * halfWidth
        local leftY = baseY - perpendicularY * halfWidth
        local rightX = baseX + perpendicularX * halfWidth
        local rightY = baseY + perpendicularY * halfWidth
        layer:drawPolygon(nil, tipX, tipY, leftX, leftY,
            rightX, rightY, rightX, rightY, r, g, b, alpha)
    end

    drawTriangle(size + 2, 0.02, 0.02, 0.02, 0.9)
    drawTriangle(size, colour[1], colour[2], colour[3], 1)
end

local function rearZombieIndicatorBaseRadius(screenHeight)
    local desiredRadius = math.max(128, math.min(224, screenHeight * 0.16))
    local closestRadius = REAR_ZOMBIE_INDICATOR_RADII[1]
    for _, radius in ipairs(REAR_ZOMBIE_INDICATOR_RADII) do
        if math.abs(radius - desiredRadius) < math.abs(closestRadius - desiredRadius) then
            closestRadius = radius
        end
    end
    return closestRadius
end

local function rearZombieIndicatorAssetRadius(screenHeight)
    local radiusScale = tonumber(getOption("RadialIndicatorRadius", 100)) or 100
    radiusScale = math.max(75, math.min(150, radiusScale))
    local desiredRadius = rearZombieIndicatorBaseRadius(screenHeight) * radiusScale / 100
    local closestRadius = MIN_RADIAL_INDICATOR_ASSET_RADIUS
    for radius = MIN_RADIAL_INDICATOR_ASSET_RADIUS, MAX_RADIAL_INDICATOR_ASSET_RADIUS,
            RADIAL_INDICATOR_ASSET_RADIUS_STEP do
        if math.abs(radius - desiredRadius) < math.abs(closestRadius - desiredRadius) then
            closestRadius = radius
        end
    end
    return closestRadius
end

local function rearZombieIndicatorAssetSize()
    local size = tonumber(getOption("RadialIndicatorSize", 100)) or 100
    if size < 88 then return 75 end
    if size > 112 then return 125 end
    return 100
end

local function rearZombieIndicatorTexture(radius, size)
    local path = "media/ui/ThreatAlert/rear_zombie_indicator_white_"
        .. tostring(radius) .. "_" .. tostring(size) .. ".png"
    if type(getTexture) ~= "function"
            and (not Texture or type(Texture.trygetTexture) ~= "function") then
        return nil
    end

    local texture = rearZombieIndicatorTextureCache[path]
    if texture then return texture end

    local now = os and os.time and os.time()
    if now and rearZombieIndicatorTextureRetryAt[path]
            and now < rearZombieIndicatorTextureRetryAt[path] then
        return nil
    end

    local ok, loaded = pcall(function()
        if Texture and type(Texture.trygetTexture) == "function" then
            return Texture.trygetTexture(path)
        end
        return getTexture(path)
    end)
    if ok and loaded then
        local errorTexture
        if Texture and type(Texture.getErrorTexture) == "function" then
            local errorOk, candidate = pcall(Texture.getErrorTexture)
            errorTexture = errorOk and candidate or nil
        end
        if loaded ~= errorTexture then
            rearZombieIndicatorTextureCache[path] = loaded
            rearZombieIndicatorTextureRetryAt[path] = nil
            return loaded
        end
    end

    if now then rearZombieIndicatorTextureRetryAt[path] = now + 1 end
    return nil
end

local function drawRearZombieIndicator(anchorX, anchorY, indicator, radius, key, blinkThreshold, sizeScale, displayColour)
    local iconSize = rearZombieIndicatorAssetSize()
    local texture = rearZombieIndicatorTexture(radius, iconSize)
    if not texture then return false end

    local canvasRadius = math.floor((radius + 16 * iconSize / 100) * (sizeScale or 1))
    local layerX = math.floor(anchorX - canvasRadius)
    local layerY = math.floor(anchorY - canvasRadius)
    local layerIndex = arrowLayerCounts[currentArrowLayerPass] + 1
    local layer = ensureAlertArrowLayer(currentArrowLayerPass, layerIndex)
    if not layer then return false end
    arrowLayerCounts[currentArrowLayerPass] = layerIndex

    layer:setX(layerX)
    layer:setY(layerY)
    layer:setWidth(canvasRadius * 2)
    layer:setHeight(canvasRadius * 2)
    layer:setVisible(true)
    pcall(function() layer:bringToTop() end)
    local angle = smoothArrowAngle(key, indicator.directionAngle)
    local rotation = math.deg(angle) - 180
    local localCenter = canvasRadius
    local alpha = radialIndicatorOpacity(indicator.distance, indicator.activeRange)
    local colour = displayColour or indicator.colour
    if indicator.distance <= (blinkThreshold or rearZombieBlinkThreshold) then
        local timestamp = tonumber(getTimestampMs and getTimestampMs() or 0) or 0
        local pulseAlpha = 0.25 + 0.75
            * (0.5 + 0.5 * math.sin(timestamp / 1000 * math.pi * 4))
        alpha = alpha * pulseAlpha
    end
    local ok = pcall(function()
        layer.javaObject:DrawTextureAngle(texture, localCenter, localCenter, rotation,
            colour[1], colour[2], colour[3], alpha)
    end)
    if not ok then
        ok = pcall(function()
            layer:DrawTextureAngle(texture, localCenter, localCenter, rotation)
        end)
        if not ok then
            layer:setVisible(false)
            arrowLayerCounts[currentArrowLayerPass] = layerIndex - 1
            return false
        end
    end
    return true
end

local function drawRearZombieIndicators(indicators, screenWidth, screenHeight, keyPrefix, blinkThreshold, sizeScale)
    if type(indicators) ~= "table" or #indicators == 0 then return end

    keyPrefix = keyPrefix or "rear-zombie"
    local anchorX = screenWidth * 0.5
    local anchorY = screenHeight * 0.5
    local radius = rearZombieIndicatorAssetRadius(screenHeight)
    local activeSectors = {}
    for index, indicator in ipairs(indicators) do
        activeSectors[indicator.sectorIndex or index] = true
    end
    for sectorIndex = 1, 8 do
        if not activeSectors[sectorIndex] then
            displayedArrowAngles[keyPrefix .. "-sector-" .. tostring(sectorIndex)] = nil
        end
    end
    for index, indicator in ipairs(indicators) do
        drawRearZombieIndicator(anchorX, anchorY, indicator, radius,
            keyPrefix .. "-sector-" .. tostring(indicator.sectorIndex or index),
            blinkThreshold, sizeScale,
            keyPrefix == "sprinter" and indicator.indicatorColour or nil)
    end
end

local function moveAlertDragHandle(handle, dx, dy, source)
    if not handle.dragging then return end
    local core = getCore()
    local screenWidth = core:getScreenWidth()
    local screenHeight = core:getScreenHeight()
    if screenWidth <= 0 or screenHeight <= 0 then return end

    local x = math.max(0, math.min(screenWidth - handle.width, handle.x + dx))
    local y = math.max(0, math.min(screenHeight - handle.height, handle.y + dy))
    handle:setX(x)
    handle:setY(y)
    handle:bringToTop()
    alertPositionX = (x + handle.width * 0.5) / screenWidth
    alertPositionY = y / screenHeight
    handle.dragMoved = true
    handle.dragMoveLogCount = (handle.dragMoveLogCount or 0) + 1
    if handle.dragMoveLogCount == 1 or handle.dragMoveLogCount % 10 == 0 then
        local captureOk, captured = pcall(function() return handle:getIsCaptured() end)
        logDragDiagnostic(string.format(
            "handle-mouse-move source=%s kind=%s delta=(%.1f,%.1f) position=(%.1f,%.1f) captured=%s",
            source, tostring(handle.positionKind), dx, dy, x, y,
            tostring(captureOk and captured)
        ))
    end
end

local function finishAlertDrag(handle, source)
    local wasDragging = handle.dragging == true
    if not wasDragging then return false end
    local moved = handle.dragMoved == true
    handle.dragging = false
    handle.manualDrag = false
    pcall(function() handle:setCapture(false) end)
    if wasDragging and moved then saveAlertPosition() end
    if activeGlobalDragHandle == handle then activeGlobalDragHandle = nil end
    logDragDiagnostic(string.format(
        "handle-mouse-up source=%s kind=%s moved=%s position=(%.1f,%.1f) savedPosition=(%.4f,%.4f)",
        source, tostring(handle.positionKind), tostring(moved), handle.x, handle.y,
        alertPositionX or 0, alertPositionY or 0
    ))
    handle.dragMoved = false
    return wasDragging
end

function AlertDragHandle:onMouseDown(x, y)
    if activeGlobalDragHandle == self then activeGlobalDragHandle = nil end
    self.manualDrag = false
    self.dragging = true
    self.dragMoved = false
    self.dragMoveLogCount = 0
    self.dragOutsideLogged = false
    self:setCapture(true)
    self:bringToTop()
    local captureOk, captured = pcall(function() return self:getIsCaptured() end)
    logDragDiagnostic(string.format(
        "handle-mouse-down kind=%s local=(%.1f,%.1f) bounds=(%.1f,%.1f %.1fx%.1f) captured=%s",
        tostring(self.positionKind), x, y, self.x, self.y, self.width, self.height,
        tostring(captureOk and captured)
    ))
    return true
end

function AlertDragHandle:onMouseMove(dx, dy)
    if self.manualDrag then return end
    moveAlertDragHandle(self, dx, dy, "ui")
end

function AlertDragHandle:onMouseMoveOutside(dx, dy)
    if not self.dragOutsideLogged then
        logDragDiagnostic("handle-mouse-move-outside kind=" .. tostring(self.positionKind))
        self.dragOutsideLogged = true
    end
    self:onMouseMove(dx, dy)
end

function AlertDragHandle:onMouseUp(x, y)
    if self.manualDrag then return false end
    return finishAlertDrag(self, "ui")
end

function AlertDragHandle:onMouseUpOutside(x, y)
    self:onMouseUp(x, y)
end

local function ensureAlertDragHandle()
    if alertDragHandle then return alertDragHandle end
    local ok, handle = pcall(function()
        local instance = AlertDragHandle:new()
        instance.positionKind = "alife"
        instance:initialise()
        instance:addToUIManager()
        instance:setWantMouseEvents(true)
        instance:setAlwaysOnTop(true)
        instance:setVisible(false)
        return instance
    end)
    if ok then
        alertDragHandle = handle
        logDragDiagnostic("handle-created kind=alife")
    end
    return handle
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        ensureAlertDragHandle()
    end)
end

getOption = function(name, fallback)
    if not PZAPI or not PZAPI.ModOptions then return fallback end
    local ok, value = pcall(function()
        local currentOptions = PZAPI.ModOptions:getOptions(MOD_ID) or modOptions
        local option = currentOptions and currentOptions:getOption(name)
        if not option then return nil end
        return option:getValue()
    end)
    if not ok or value == nil then return fallback end
    return value
end

local function alertDisplayMode()
    local value = math.floor(tonumber(getOption("AlertDisplayMode", ALERT_DISPLAY_MODE_VANILLA)) or ALERT_DISPLAY_MODE_VANILLA)
    return math.max(ALERT_DISPLAY_MODE_COMPACT_NEATUI,
        math.min(ALERT_DISPLAY_MODE_VANILLA, value))
end

local function isAlertLayoutPreviewEnabled()
    local configuredValue = getOption("ShowAlertLayoutPreview", false) == true
    if lastConfiguredAlertLayoutPreview == nil
            or configuredValue ~= lastConfiguredAlertLayoutPreview then
        lastConfiguredAlertLayoutPreview = configuredValue
        alertLayoutPreviewEnabled = configuredValue
    end
    return alertLayoutPreviewEnabled == true
end

if Events and Events.OnMouseDown then
    Events.OnMouseDown.Add(function()
        local mouseX = getMouseX and getMouseX() or -1
        local mouseY = getMouseY and getMouseY() or -1
        local function describeHandle(handle)
            if not handle then return "alife=missing" end
            local inside = mouseX >= handle.x and mouseX < handle.x + handle.width
                and mouseY >= handle.y and mouseY < handle.y + handle.height
            local capturedOk, captured = pcall(function() return handle:getIsCaptured() end)
            local visibleOk, visible = pcall(function() return handle:isVisible() end)
            local mouseEventsOk, mouseEvents = pcall(function() return handle:isWantMouseEvents() end)
            return string.format(
                "alife=(alertVisible:%s uiVisible:%s mouseEvents:%s inside:%s captured:%s bounds:%.1f,%.1f %.1fx%.1f)",
                tostring(handle.alertVisible == true), tostring(visibleOk and visible),
                tostring(mouseEventsOk and mouseEvents),
                tostring(inside), tostring(capturedOk and captured),
                handle.x, handle.y, handle.width, handle.height
            )
        end
        if dragDiagnosticsEnabled then
            logDragDiagnostic(string.format(
                "global-mouse-down cursor=(%.1f,%.1f) leftDown=%s alifeWarnings=%d rearZombie=%s sprinters=%s %s",
                mouseX, mouseY,
                tostring(isMouseButtonDown and isMouseButtonDown(0) or false),
                #warnings, tostring(rearZombieWarning ~= nil), tostring(sprinterWarning ~= nil),
                describeHandle(alertDragHandle)
            ))
        end

        if not isMouseButtonDown or not isMouseButtonDown(0) then return end
        local handle = alertDragHandle
        if not handle or handle.dragging then return end
        local inside = mouseX >= handle.x and mouseX < handle.x + handle.width
            and mouseY >= handle.y and mouseY < handle.y + handle.height
        local hasActiveAlert = handle.alertVisible == true and #warnings > 0
        if isAlertLayoutPreviewEnabled() then
            hasActiveAlert = handle.alertVisible == true
        elseif activeAlertPreview then
            hasActiveAlert = false
        end
        logDragDiagnostic(string.format(
            "global-drag-candidate kind=alife inside=%s active=%s bounds=(%.1f,%.1f %.1fx%.1f)",
            tostring(inside), tostring(hasActiveAlert), handle.x, handle.y, handle.width, handle.height
        ))
        if hasActiveAlert and inside then
            activeGlobalDragHandle = handle
            globalDragMouseX = mouseX
            globalDragMouseY = mouseY
            handle.dragging = true
            handle.manualDrag = true
            handle.dragMoved = false
            handle.dragMoveLogCount = 0
            handle.dragOutsideLogged = false
            logDragDiagnostic("global-drag-start kind=alife")
        end
    end)
end

local function updateGlobalAlertDrag()
    local handle = activeGlobalDragHandle
    if not handle then return end
    if not handle.manualDrag then
        activeGlobalDragHandle = nil
        return
    end
    if not isMouseButtonDown or not isMouseButtonDown(0) then
        finishAlertDrag(handle, "global")
        return
    end

    local mouseX = getMouseX and getMouseX()
    local mouseY = getMouseY and getMouseY()
    if not mouseX or not mouseY then return end
    local deltaX = mouseX - globalDragMouseX
    local deltaY = mouseY - globalDragMouseY
    globalDragMouseX = mouseX
    globalDragMouseY = mouseY
    if deltaX ~= 0 or deltaY ~= 0 then
        moveAlertDragHandle(handle, deltaX, deltaY, "global")
    end
end

local function warningRange()
    local value = tonumber(getOption("WarningDistance", DEFAULT_RANGE))
    if not value then return DEFAULT_RANGE end
    return math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function closeHostileAlarmRange()
    local value = tonumber(getOption("CloseHostileAlarmDistance", DEFAULT_CLOSE_HOSTILE_RANGE))
    if not value then return DEFAULT_CLOSE_HOSTILE_RANGE end
    return math.max(MIN_CLOSE_HOSTILE_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function sprinterWarningRange()
    local value = tonumber(getOption("SprinterWarningDistance", DEFAULT_SPRINTER_RANGE))
    if not value then return DEFAULT_SPRINTER_RANGE end
    return math.max(MIN_CLOSE_HOSTILE_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function sprinterAlarmDistance()
    local value = tonumber(getOption("SprinterAlarmDistance", DEFAULT_SPRINTER_ALARM_DISTANCE))
    if not value then return DEFAULT_SPRINTER_ALARM_DISTANCE end
    return math.max(MIN_CLOSE_HOSTILE_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function isSprinter(zombie)
    local speedOk, speedType = pcall(function() return zombie:getSpeedType() end)
    if not speedOk then return false end
    local constantOk, sprinterType = pcall(function() return IsoZombie.SPEED_SPRINTER end)
    if not constantOk or sprinterType == nil then return false end
    local speedNumberOk, numericSpeedType = pcall(function()
        return tonumber(tostring(speedType))
    end)
    local constantNumberOk, numericSprinterType = pcall(function()
        return tonumber(tostring(sprinterType))
    end)
    return speedNumberOk and constantNumberOk and numericSpeedType ~= nil
        and numericSprinterType ~= nil and numericSpeedType == numericSprinterType
end

local function zombieAlertId(zombie)
    local ok, id = pcall(function() return zombie:getID() end)
    if ok and id ~= nil then return tostring(id) end
    ok, id = pcall(function() return zombie:getOnlineID() end)
    if ok and id ~= nil then return tostring(id) end
    return tostring(zombie)
end

local function rearZombieWarningRange(player)
    if getOption("UseBalancedRearZombieRange", true) then
        local ok, hasKeenHearing = pcall(function()
            return player:hasTrait(CharacterTrait.KEEN_HEARING)
        end)
        if ok and hasKeenHearing then return 6.5 end
        return 3.5
    end

    local value = tonumber(getOption("RearZombieWarningDistance", DEFAULT_REAR_ZOMBIE_RANGE))
    if not value then return DEFAULT_REAR_ZOMBIE_RANGE end
    return math.max(MIN_RANGE, math.min(MAX_RANGE, math.floor(value + 0.5)))
end

local function rearZombieWarningAngle()
    local value = tonumber(getOption("RearZombieWarningAngle", DEFAULT_REAR_ZOMBIE_ANGLE))
    if not value then return DEFAULT_REAR_ZOMBIE_ANGLE end
    value = math.max(MIN_REAR_ZOMBIE_ANGLE, math.min(MAX_REAR_ZOMBIE_ANGLE, value))
    return math.floor(value / REAR_ZOMBIE_ANGLE_STEP + 0.5) * REAR_ZOMBIE_ANGLE_STEP
end

local function distanceGradientColour(nearColour, farColour, distance, activeRange)
    if activeRange <= 0 then return farColour end
    local normalizedDistance = math.max(0, math.min(1, distance / activeRange))
    local proximity = 1 - normalizedDistance
    local smoothProximity = proximity * proximity * (3 - 2 * proximity)
    return {
        farColour[1] + (nearColour[1] - farColour[1]) * smoothProximity,
        farColour[2] + (nearColour[2] - farColour[2]) * smoothProximity,
        farColour[3] + (nearColour[3] - farColour[3]) * smoothProximity,
    }
end

radialIndicatorOpacity = function(distance, activeRange)
    activeRange = tonumber(activeRange) or 0
    distance = tonumber(distance) or activeRange
    if not getOption("FadeRadialIndicatorsByDistance", true) or activeRange <= 0 then
        return 1
    end
    local farOpacity = tonumber(getOption(
        "RadialIndicatorFarOpacity", DEFAULT_RADIAL_INDICATOR_FAR_OPACITY
    ))
    if not farOpacity then farOpacity = DEFAULT_RADIAL_INDICATOR_FAR_OPACITY end
    farOpacity = math.max(0, math.min(100, farOpacity)) / 100
    local normalizedDistance = math.max(0, math.min(1, distance / activeRange))
    local smoothDistance = normalizedDistance * normalizedDistance * (3 - 2 * normalizedDistance)
    return 1 - (1 - farOpacity) * smoothDistance
end

local function configuredIndicatorColour(optionId, fallback)
    local colour = getOption(optionId)
    if type(colour) ~= "table" then return fallback end
    local red = tonumber(colour.r)
    local green = tonumber(colour.g)
    local blue = tonumber(colour.b)
    if not red or not green or not blue then return fallback end
    return {
        math.max(0, math.min(1, red)),
        math.max(0, math.min(1, green)),
        math.max(0, math.min(1, blue)),
    }
end

local function rearZombieIndicatorColour(distance, activeRange)
    return distanceGradientColour(
        configuredIndicatorColour("RearZombieIndicatorNearColour", REAR_ZOMBIE_INDICATOR_RED),
        configuredIndicatorColour("RearZombieIndicatorFarColour", REAR_ZOMBIE_INDICATOR_YELLOW),
        distance,
        activeRange
    )
end

local function sprinterIndicatorColour(distance, activeRange)
    return distanceGradientColour(
        configuredIndicatorColour("SprinterIndicatorNearColour", SPRINTER_NEAR_COLOUR),
        configuredIndicatorColour("SprinterIndicatorFarColour", SPRINTER_COLOUR),
        distance,
        activeRange
    )
end

local function rearZombieBlinkDistance()
    local value = tonumber(getOption(
        "RearZombieBlinkDistance", DEFAULT_REAR_ZOMBIE_BLINK_DISTANCE
    ))
    if not value then return DEFAULT_REAR_ZOMBIE_BLINK_DISTANCE end
    value = math.max(MIN_REAR_ZOMBIE_BLINK_DISTANCE,
        math.min(MAX_REAR_ZOMBIE_BLINK_DISTANCE, value))
    return math.floor(value / REAR_ZOMBIE_BLINK_DISTANCE_STEP + 0.5)
        * REAR_ZOMBIE_BLINK_DISTANCE_STEP
end

local function sprinterBlinkDistance()
    local value = tonumber(getOption(
        "SprinterBlinkDistance", DEFAULT_SPRINTER_BLINK_DISTANCE
    ))
    if not value then return DEFAULT_SPRINTER_BLINK_DISTANCE end
    value = math.max(MIN_SPRINTER_BLINK_DISTANCE,
        math.min(MAX_SPRINTER_BLINK_DISTANCE, value))
    return math.floor(value / SPRINTER_BLINK_DISTANCE_STEP + 0.5)
        * SPRINTER_BLINK_DISTANCE_STEP
end

local function signedAngle(angle)
    while angle > math.pi do angle = angle - math.pi * 2 end
    while angle < -math.pi do angle = angle + math.pi * 2 end
    return angle
end

local function rearZombieSectorIndex(directionAngleValue, coneDegrees, sectorCount)
    local coneRadians = math.rad(coneDegrees)
    if coneRadians <= 0 then return 1 end

    local relativeAngle = signedAngle(directionAngleValue - math.pi)
    local normalized = (relativeAngle + coneRadians * 0.5) / coneRadians
    local index = math.floor(normalized * sectorCount) + 1
    return math.max(1, math.min(sectorCount, index))
end

local function sprinterSectorIndex(directionAngleValue, sectorCount)
    local sectorWidth = math.pi * 2 / sectorCount
    local normalized = ((directionAngleValue + math.pi + sectorWidth * 0.5) % (math.pi * 2))
        / (math.pi * 2)
    local index = math.floor(normalized * sectorCount) + 1
    return math.max(1, math.min(sectorCount, index))
end

local function normalizeStance(value)
    if type(value) ~= "string" then return nil end
    value = string.lower(value)
    if value == "suspicious" then return "careful" end
    return STANCES[value] and value or nil
end

local function warningTitle(warning, uppercase)
    local title = (STANCE_LABELS[warning.stance] or "Hostile")
        .. " A-Life " .. (warning.count == 1 and "NPC nearby" or "NPCs nearby (" .. warning.count .. ")")
    return uppercase and string.upper(title) or title
end

local function factionNameFor(project, record)
    local factionId = record.factionId
    if factionId == nil then return nil end

    local catalog = project.Catalog
    if type(catalog) == "table" and type(catalog.faction) == "function" then
        local ok, faction = pcall(catalog.faction, factionId)
        local general = ok and type(faction) == "table" and faction.general or nil
        local name = type(general) == "table" and general.name or nil
        if type(name) == "string" and name:match("%S") then
            return tostring(factionId), name
        end
    end

    local id = tostring(factionId)
    return id, (id:gsub("_", " "))
end

local function warningFactionDetail(warning)
    local names = warning.factionNames
    if type(names) ~= "table" or #names == 0 then return nil end

    local displayed = {}
    local shownCount = math.min(#names, 2)
    for index = 1, shownCount do
        displayed[#displayed + 1] = names[index]
    end
    if #names > shownCount then
        displayed[#displayed + 1] = "+" .. tostring(#names - shownCount)
    end

    local label = #names == 1 and "Faction: " or "Factions: "
    return label .. table.concat(displayed, ", ")
end

local function playerKey(player)
    if type(isClient) == "function" then
        local ok, client = pcall(isClient)
        if ok and client then
            local okUsername, username = pcall(function() return player:getUsername() end)
            if okUsername and username ~= nil and tostring(username) ~= "" then
                return tostring(username)
            end
        end
    end
    local ok, number = pcall(function() return player:getPlayerNum() end)
    return "sp:" .. tostring(math.max(0, math.floor(tonumber(ok and number or 0) or 0)))
end

local function reputationStance(project, factionId)
    local store = project.StatusStore
    local reputation = type(store) == "table" and store.reputation or nil
    local relations = type(reputation) == "table" and reputation.relations or nil
    if type(relations) ~= "table" then return nil end
    for _, row in ipairs(relations) do
        if type(row) == "table" and row.factionId == factionId then
            local stance = normalizeStance(row.status)
            if stance then return stance end
        end
    end
    return nil
end

local function fallbackStance(project, record, player)
    local memory = type(record.memory) == "table" and record.memory or {}
    if memory.hostileOverride == true then return "hostile" end
    local key = playerKey(player)
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[key] == true then
        return "hostile"
    end
    if memory.hostileOverride == false then return "friendly" end

    local catalog = project.Catalog
    local faction
    if type(catalog) == "table" and type(catalog.faction) == "function" then
        local ok, value = pcall(catalog.faction, record.factionId)
        if ok and type(value) == "table" then faction = value end
    end
    local relations = faction and faction.relations or nil
    local declared = type(relations) == "table" and normalizeStance(relations.player) or nil
    local spawn = faction and faction.spawn or nil
    local default = declared or (type(spawn) == "table" and spawn.friendly == true and "friendly" or "hostile")
    local stance = normalizeStance(memory.spawnStance) or default
    return reputationStance(project, record.factionId) or stance
end

local function callStance(method, ...)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    return ok and normalizeStance(value) or nil
end

local function jimmyStance(project, record, player)
    local jimmy = ProjectALifeJimmy
    if type(jimmy) ~= "table" then return nil end

    local relations = project.Relations
    local ownOk, ownPerson = pcall(function()
        return type(jimmy.isOwnPerson) == "function" and jimmy.isOwnPerson(record, player) == true
    end)
    local stance = ownOk and ownPerson and "allied" or nil
    if not stance then
        local crewStanding = jimmy.CrewStanding
        if type(crewStanding) == "table" then
            stance = callStance(crewStanding.labelFor, record, player)
            if not stance and callStance(crewStanding.standingLabel, record, player) == "allied" then
                stance = "allied"
            end
        end
    end
    if not stance then
        local standing = jimmy.StandingService
        local keyOk, key = pcall(function()
            if type(jimmy.playerKey) == "function" then return jimmy.playerKey(player) end
        end)
        if keyOk and key ~= nil and type(standing) == "table" then
            if callStance(standing.labelFor, key, record.factionId) == "allied" then
                stance = "allied"
            end
        end
    end
    if not stance or stance == "hostile" then return stance end

    local hostileOk, hostile = pcall(function()
        return type(relations) == "table" and type(relations.hostileToPlayer) == "function"
            and relations.hostileToPlayer(record, player) == true
    end)
    if hostileOk and hostile then return "hostile" end

    local safety = jimmy.NpcSafety
    local attackingOk, attacking = pcall(function()
        return type(safety) == "table" and type(safety.attacking) == "function"
            and safety.attacking(record, player) == true
    end)
    return attackingOk and attacking and "hostile" or stance
end

local function preserveAlliedStance(project, record, player, stance)
    if stance == "friendly" and fallbackStance(project, record, player) == "allied" then
        return "allied"
    end
    return stance
end

local function stanceOf(project, record, player)
    local relations = project.Relations
    if type(relations) == "table" and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, record, player)
        if ok then
            stance = normalizeStance(stance)
            if stance == "hostile" then return stance end
            local jimmy = jimmyStance(project, record, player)
            if jimmy then return jimmy end
            if stance then return preserveAlliedStance(project, record, player, stance) end
        end
    end

    local jimmy = jimmyStance(project, record, player)
    if jimmy then return jimmy end

    local dots = ALifeStanceDots
    if type(dots) == "table" and type(dots.stanceOf) == "function" then
        local ok, stance = pcall(dots.stanceOf, record, player)
        if ok then
            stance = normalizeStance(stance)
            if stance then return preserveAlliedStance(project, record, player, stance) end
        end
    end
    return fallbackStance(project, record, player)
end

local function actorFor(project, uid)
    local executor = project.Executor
    local mirror = type(executor) == "table" and executor.mirror or nil
    local records = type(mirror) == "table" and mirror.records or nil
    local record = type(records) == "table" and records[uid] or nil
    if type(record) == "table" then return record end

    local registry = project.ActorRegistry
    if type(registry) == "table" and type(registry.read) == "function" then
        local ok, value = pcall(registry.read, uid)
        if ok and type(value) == "table" then return value end
    end
    return nil
end

local function uidOf(project, shell)
    local speech = project.Speech
    if type(speech) == "table" and type(speech.variable) == "function" then
        local ok, uid = pcall(speech.variable, shell, "ALifeUID")
        if ok and uid ~= nil and tostring(uid) ~= "" then return tostring(uid) end
    end
    local ok, data = pcall(function() return shell:getModData() end)
    if ok and type(data) == "table" and type(data.ProjectALifeUID) == "string" then
        return data.ProjectALifeUID
    end
    return nil
end

local function carriesFirearm(project, shell)
    local relay = project.NPCHitRelay
    if type(relay) == "table" and type(relay.carriesFirearm) == "function" then
        local ok, result = pcall(relay.carriesFirearm, shell)
        if ok and result ~= nil then return result == true end
    end

    local ok, result = pcall(function()
        local inventory = shell:getInventory()
        local items = inventory and inventory:getItems() or nil
        for index = 0, (items and items:size() or 0) - 1 do
            local item = items:get(index)
            if item ~= nil and type(item.isAimedFirearm) == "function"
                    and item:isAimedFirearm() == true then
                return true
            end
        end
        return false
    end)
    return ok and result == true
end

local sprinterAlarmZombieIDs = {}
local closeHostileNPCs = {}
local lastCloseHostileNPCs = {}
local lastSprinterAlarmZombieIDs = {}
local errorLogged = false

local function directionAngle(dx, dy, forwardX, forwardY)
    local forward = dx * forwardX + dy * forwardY
    local right = dx * -forwardY + dy * forwardX
    return math.atan2(right, forward)
end

local function cameraForwardDirection(fallbackX, fallbackY)
    local compass = ViewpointCompass
    if not compass or type(compass.getHeading) ~= "function" then
        return fallbackX, fallbackY
    end

    local ok, heading = pcall(compass.getHeading)
    if not ok or type(heading) ~= "number" or heading < 0 or heading >= 360 then
        return fallbackX, fallbackY
    end

    local yaw = math.rad(heading - 90)
    return math.cos(yaw), math.sin(yaw)
end

local function typeIconTexture(kind)
    local texturePath = TYPE_ICON_TEXTURES[kind]
    if not texturePath or not UIManager or not UIManager.DrawTexture then return nil end

    local texture = typeIconTextureCache[texturePath]
    if texture ~= nil then return texture or nil end
    if type(getTexture) ~= "function" then
        typeIconTextureCache[texturePath] = false
        return nil
    end

    local ok, loaded = pcall(getTexture, texturePath)
    typeIconTextureCache[texturePath] = ok and loaded or false
    return typeIconTextureCache[texturePath] or nil
end

local function neatPanelTexture(path)
    local texture = neatPanelTextureCache[path]
    if texture then return texture end

    local ok, loaded = false, nil
    if NinePatchTexture and type(NinePatchTexture.getSharedTexture) == "function" then
        ok, loaded = pcall(function()
            return NinePatchTexture.getSharedTexture(path)
        end)
    end
    if ok and loaded then
        neatPanelTextureCache[path] = loaded
        return loaded
    end

    if type(getTexture) == "function" then
        ok, loaded = pcall(getTexture, path)
        if ok and loaded then
            neatPanelTextureCache[path] = loaded
            return loaded
        end
    end
    return nil
end

local function renderNeatPanelTexture(texture, x, y, width, height, red, green, blue, alpha)
    if not texture then return false end
    local ok = pcall(function()
        texture:render(x, y, width, height, red, green, blue, alpha)
    end)
    if ok then return true end
    if UIManager and UIManager.DrawTexture then
        ok = pcall(function()
            UIManager.DrawTexture(texture, x, y, width, height, alpha)
        end)
        if ok then return true end
    end
    return false
end

local function drawNeatAlertCard(headerTexture, bodyTexture, text, screenWidth, centerX, y,
        title, detail, extraDetail, stance, directionAngleValue, showArrow, colour, iconKind,
        compact, firearmCarriers, arrowKey)
    local typeIcon = typeIconTexture(iconKind)
    local hasArrow = showArrow and directionAngleValue ~= nil
    local firearmIcon = compact and firearmCarriers and firearmCarriers > 0
        and typeIconTexture("firearm") or nil
    local firearmCount = firearmIcon and tostring(firearmCarriers) or nil
    local firearmCountWidth = firearmCount and text:MeasureStringX(UIFont.Small, firearmCount) or 0
    local firearmSize = firearmIcon and 16 or 0
    local padding = 10
    local titleFont = UIFont.Medium
    local smallHeight = text:getFontHeight(UIFont.Small)
    local titleHeight = text:getFontHeight(titleFont)
    local titleWidth = text:MeasureStringX(titleFont, title)
    local detailWidth = text:MeasureStringX(UIFont.Small, detail)
    local extraDetailWidth = extraDetail and text:MeasureStringX(UIFont.Small, extraDetail) or 0
    local arrowSize = 20
    local arrowSpace = hasArrow and arrowSize + 8 or 0
    local iconSize = typeIcon and 20 or 0
    local iconGap = typeIcon and 8 or 0
    local titleSpace = iconSize + iconGap
    local firearmRowWidth = firearmIcon and firearmSize + 3 + firearmCountWidth or 0
    local contentWidth = math.max(titleWidth + titleSpace, detailWidth,
        extraDetailWidth, firearmRowWidth)
    local width = math.min(contentWidth + padding * 2 + arrowSpace, screenWidth - 24)
    local headerHeight = titleHeight + 12
    local lineGap = 4
    local hasExtraLine = extraDetail ~= nil or firearmIcon ~= nil
    local bodyHeight = padding + smallHeight
        + (hasExtraLine and smallHeight + lineGap or 0) + 2
    local x = math.floor(math.max(12, math.min(screenWidth - width - 12, centerX - width * 0.5)))

    renderNeatPanelTexture(headerTexture, x, y, width, headerHeight, 0.08, 0.08, 0.08, 1)
    renderNeatPanelTexture(bodyTexture, x, y + headerHeight, width, bodyHeight, 0.15, 0.15, 0.15, 1)

    local titleY = y + math.floor((headerHeight - titleHeight) * 0.5)
    local titleCenterX = x + padding + titleSpace + titleWidth * 0.5
    if compact then
        local titleStartX = x + padding + titleSpace
        local titleEndX = x + width - padding - arrowSpace
        titleCenterX = (titleStartX + titleEndX) * 0.5
    end
    text:DrawStringCentre(titleFont, titleCenterX,
        titleY, title, colour[1], colour[2], colour[3], 1)
    if typeIcon then
        UIManager.DrawTexture(typeIcon, x + padding,
            y + math.floor((headerHeight - iconSize) * 0.5), iconSize, iconSize, 1)
    end
    if hasArrow then
        drawDirectionArrow(x + width - padding - arrowSize * 0.5,
            y + headerHeight * 0.5, directionAngleValue, colour, arrowSize, arrowKey)
    end

    local detailY = y + headerHeight + math.floor(padding * 0.5)
    local detailCenterX = compact and x + width * 0.5
        or x + padding + detailWidth * 0.5
    text:DrawStringCentre(UIFont.Small, detailCenterX,
        detailY, detail, 0.9, 0.9, 0.9, 1)
    if firearmIcon then
        local firearmY = detailY + smallHeight + lineGap
        local firearmStartX = x + (width - firearmRowWidth) * 0.5
        UIManager.DrawTexture(firearmIcon, firearmStartX, firearmY - 1, firearmSize, firearmSize, 1)
        text:DrawStringCentre(UIFont.Small,
            firearmStartX + firearmSize + 3 + firearmCountWidth * 0.5,
            firearmY, firearmCount, 0.9, 0.9, 0.9, 1)
    end
    if extraDetail then
        local extraY = detailY + smallHeight + lineGap
        local extraDetailCenterX = compact and x + width * 0.5
            or x + padding + extraDetailWidth * 0.5
        text:DrawStringCentre(UIFont.Small, extraDetailCenterX,
            extraY, extraDetail, colour[1], colour[2], colour[3], 1)
    end

    return y + headerHeight + bodyHeight + 6,
        x, width, headerHeight + bodyHeight
end

local function drawMinimalAlertLine(text, screenWidth, centerX, y, count, distance,
        colour, iconKind, directionAngleValue, showArrow, firearmCarriers, arrowKey)
    local icon = typeIconTexture(iconKind)
    local firearmIcon = firearmCarriers and firearmCarriers > 0
        and typeIconTexture("firearm") or nil
    local font = UIFont.Large
    local lineHeight = text:getFontHeight(font)
    local iconSize = icon and 20 or 0
    local firearmSize = firearmIcon and 20 or 0
    local countText = tostring(count)
    local distanceText = tostring(math.floor(distance + 0.5)) .. "t"
    local firearmText = firearmIcon and tostring(firearmCarriers) or nil
    local countWidth = text:MeasureStringX(font, countText)
    local distanceWidth = text:MeasureStringX(font, distanceText)
    local firearmWidth = firearmText and text:MeasureStringX(font, firearmText) or 0
    local hasArrow = showArrow and directionAngleValue ~= nil
    local arrowSize = 20
    local gap = 8
    local width = iconSize + (iconSize > 0 and 4 or 0) + countWidth + gap + distanceWidth
        + (firearmIcon and gap + firearmSize + 3 + firearmWidth or 0)
        + (hasArrow and gap + arrowSize or 0)
    local x = math.floor(math.max(8, math.min(screenWidth - width - 8, centerX - width * 0.5)))
    local cursorX = x

    if icon then
        UIManager.DrawTexture(icon, cursorX, y + math.floor((lineHeight - iconSize) * 0.5), iconSize, iconSize, 1)
        cursorX = cursorX + iconSize + 4
    end
    text:DrawStringCentre(font, cursorX + countWidth * 0.5,
        y, countText, colour[1], colour[2], colour[3], 1)
    cursorX = cursorX + countWidth + gap
    text:DrawStringCentre(font, cursorX + distanceWidth * 0.5,
        y, distanceText, 0.9, 0.9, 0.9, 1)
    cursorX = cursorX + distanceWidth
    if firearmIcon then
        cursorX = cursorX + gap
        UIManager.DrawTexture(firearmIcon, cursorX,
            y + math.floor((lineHeight - firearmSize) * 0.5), firearmSize, firearmSize, 1)
        cursorX = cursorX + firearmSize + 3
        text:DrawStringCentre(font, cursorX + firearmWidth * 0.5,
            y, firearmText, 0.9, 0.9, 0.9, 1)
        cursorX = cursorX + firearmWidth
    end
    if hasArrow then
        drawDirectionArrow(cursorX + gap + arrowSize * 0.5,
            y + lineHeight * 0.5, directionAngleValue, colour, arrowSize, arrowKey)
    end

    return { x = x, y = y, right = x + width, bottom = y + lineHeight }, y + lineHeight + 3
end

local function mergeBounds(bounds, x, y, width, height)
    if not bounds then
        return { x = x, y = y, right = x + width, bottom = y + height }
    end
    bounds.x = math.min(bounds.x, x)
    bounds.y = math.min(bounds.y, y)
    bounds.right = math.max(bounds.right, x + width)
    bounds.bottom = math.max(bounds.bottom, y + height)
    return bounds
end

local function updateAlertDragHandle(bounds, screenWidth, screenHeight)
    local handle = alertDragHandle
    if not bounds then
        if handle and handle.alertVisible then
            handle.alertVisible = false
        end
        if handle and not handle.dragging then
            handle:setVisible(false)
        end
        return
    end

    handle = ensureAlertDragHandle()
    if not handle then return end
    local width = bounds.right - bounds.x
    local height = bounds.bottom - bounds.y
    local x = math.max(0, math.min(math.max(0, screenWidth - width), bounds.x))
    local y = math.max(0, math.min(math.max(0, screenHeight - height), bounds.y))
    if x ~= bounds.x or y ~= bounds.y then
        alertPositionX = (x + width * 0.5) / math.max(screenWidth, 1)
        alertPositionY = y / math.max(screenHeight, 1)
    end
    handle:setX(x)
    handle:setY(y)
    handle:setWidth(math.max(1, width))
    handle:setHeight(math.max(1, height))
    handle:setVisible(true)
    handle:bringToTop()
    handle.alertVisible = true
    local geometry = string.format("%.1f,%.1f %.1fx%.1f", x, y, width, height)
    if handle.diagnosticGeometry ~= geometry then
        local visibleOk, visible = pcall(function() return handle:isVisible() end)
        local mouseEventsOk, mouseEvents = pcall(function() return handle:isWantMouseEvents() end)
        logDragDiagnostic(string.format(
            "handle-bounds kind=alife bounds=%s screen=%dx%d alertVisible=%s uiVisible=%s mouseEvents=%s",
            geometry, screenWidth, screenHeight,
            tostring(handle.alertVisible), tostring(visibleOk and visible),
            tostring(mouseEventsOk and mouseEvents)
        ))
        handle.diagnosticGeometry = geometry
    end
end

local function alertAnchor(screenWidth, screenHeight, defaultY)
    return (alertPositionX or 0.5) * screenWidth,
        alertPositionY and alertPositionY * screenHeight or defaultY or 24
end

local function drawCompactAlertLine(text, screenWidth, centerX, y, message, colour,
        iconKind, directionAngleValue, showArrow, arrowKey)
    local icon = typeIconTexture(iconKind)
    local hasArrow = showArrow and directionAngleValue ~= nil

    local font = UIFont.Small
    local lineHeight = text:getFontHeight(font)
    local iconSize = icon and 16 or 0
    local iconGap = icon and 5 or 0
    local arrowSize = hasArrow and 20 or 0
    local arrowGap = hasArrow and 8 or 0
    local contentHeight = math.max(lineHeight, arrowSize)
    local textY = y + math.floor((contentHeight - lineHeight) * 0.5)
    local messageWidth = text:MeasureStringX(font, message)
    local width = iconSize + iconGap + messageWidth + arrowGap + arrowSize
    local x = math.floor(math.max(8, math.min(screenWidth - width - 8, centerX - width * 0.5)))
    local textLeft = x + iconSize + iconGap
    local textCenter = textLeft + messageWidth * 0.5

    if icon then
        UIManager.DrawTexture(icon, x, y + math.floor((contentHeight - iconSize) * 0.5), iconSize, iconSize, 1)
    end
    for _, offset in ipairs(SHADOW_OFFSETS) do
        text:DrawStringCentre(font, textCenter + offset[1], textY + offset[2], message, 0, 0, 0, 1)
    end
    text:DrawStringCentre(font, textCenter, textY, message, colour[1], colour[2], colour[3], 1)
    if hasArrow then
        drawDirectionArrow(textLeft + messageWidth + arrowGap + arrowSize * 0.5,
            y + contentHeight * 0.5, directionAngleValue, colour, arrowSize, arrowKey)
    end

    return mergeBounds(nil, x, y, width, contentHeight), y + contentHeight + 3
end

local function drawCompactAlertGroup(alertWarnings, text, screenWidth, centerX, startY, compact)
    local bounds
    local y = startY
    for _, warning in ipairs(alertWarnings) do
        local lineBounds, nextY
        if compact then
            lineBounds, nextY = drawMinimalAlertLine(
                text, screenWidth, centerX, y, warning.count, warning.distance,
                STANCE_COLOURS[warning.stance], "alife", warning.directionAngle,
                warning.showArrow, warning.firearmCarriers, "alife:" .. warning.stance
            )
        else
            local message = string.upper(STANCE_LABELS[warning.stance] or "Hostile")
                .. " A-LIFE (" .. tostring(warning.count) .. ") - "
                .. tostring(math.floor(warning.distance + 0.5)) .. " TILES"
            if warning.firearmCarriers and warning.firearmCarriers > 0 then
                message = message .. " - " .. tostring(warning.firearmCarriers) .. " ARMED"
            end
            lineBounds, nextY = drawCompactAlertLine(
                text, screenWidth, centerX, y, message, STANCE_COLOURS[warning.stance],
                "alife", warning.directionAngle, warning.showArrow, "alife:" .. warning.stance
            )
            local factionDetail = warningFactionDetail(warning)
            if factionDetail then
                local factionBounds
                factionBounds, nextY = drawCompactAlertLine(
                    text, screenWidth, centerX, nextY, factionDetail,
                    STANCE_COLOURS[warning.stance], nil, nil, false, nil
                )
                bounds = mergeBounds(bounds, factionBounds.x, factionBounds.y,
                    factionBounds.right - factionBounds.x, factionBounds.bottom - factionBounds.y)
            end
        end
        bounds = mergeBounds(bounds, lineBounds.x, lineBounds.y,
            lineBounds.right - lineBounds.x, lineBounds.bottom - lineBounds.y)
        y = nextY
    end

    return bounds, y
end

local function drawNeatAlertGroup(alertWarnings, headerTexture, bodyTexture,
        text, screenWidth, centerX, startY, compact)
    local bounds
    local y = startY
    for _, warning in ipairs(alertWarnings) do
        local extraDetail
        local title = warningTitle(warning, false)
        local detail = "Distance: " .. tostring(math.floor(warning.distance + 0.5)) .. " tiles"
        local standardExtraDetails = {}
        local factionDetail = warningFactionDetail(warning)
        if factionDetail then
            standardExtraDetails[#standardExtraDetails + 1] = factionDetail
        end
        if warning.firearmCarriers and warning.firearmCarriers > 0 then
            standardExtraDetails[#standardExtraDetails + 1] = tostring(warning.firearmCarriers)
                .. (warning.firearmCarriers == 1 and " firearm carrier nearby"
                    or " firearm carriers nearby")
        end
        if compact then
            title = tostring(warning.count)
            detail = tostring(math.floor(warning.distance + 0.5)) .. "t"
        elseif #standardExtraDetails > 0 then
            extraDetail = table.concat(standardExtraDetails, " | ")
        end
        local nextY, x, width, height = drawNeatAlertCard(
            headerTexture, bodyTexture, text, screenWidth, centerX, y,
            title, detail,
            extraDetail, warning.stance, warning.directionAngle,
            warning.showArrow, STANCE_COLOURS[warning.stance], "alife", compact,
            warning.firearmCarriers, "alife:" .. warning.stance
        )
        bounds = mergeBounds(bounds, x, y, width, height)
        y = nextY
    end

    return bounds
end

beginAlertPreview = function(kind)
    if activeAlertPreview and activeAlertPreview.kind == kind
            and getTimestampMs() < activeAlertPreview.expiresAt then
        activeAlertPreview = nil
        return
    end
    activeAlertPreview = {
        kind = kind,
        expiresAt = getTimestampMs() + 8000,
    }
end

local function drawAlertPreview()
    beginArrowLayerPass("preview")
    if not getSpecificPlayer or not getSpecificPlayer(0) then
        activeAlertPreview = nil
        updateAlertDragHandle(nil, 0, 0)
        finishArrowLayerPass("preview")
        return false
    end
    if getOption("ImmersiveMode", false) then
        activeAlertPreview = nil
        finishArrowLayerPass("preview")
        return false
    end
    local layoutPreview = isAlertLayoutPreviewEnabled()
    if not layoutPreview and not activeAlertPreview then
        finishArrowLayerPass("preview")
        return false
    end
    if not layoutPreview and getTimestampMs() >= activeAlertPreview.expiresAt then
        activeAlertPreview = nil
        finishArrowLayerPass("preview")
        return false
    end

    local liveArrowAngles = displayedArrowAngles
    displayedArrowAngles = {}
    local ok = pcall(function()
        local core = getCore()
        local screenWidth = core:getScreenWidth()
        local screenHeight = core:getScreenHeight()
        local text = getTextManager()
        local alertWarnings = {}
        local rearZombiePreviewIndicators = {}
        local sprinterWarning

        local previewKind = layoutPreview and "all" or activeAlertPreview.kind
        if previewKind == "alife" or previewKind == "all" then
            alertWarnings = {
                {
                    stance = "hostile",
                    count = 2,
                    distance = 6,
                    directionAngle = math.rad(28),
                    firearmCarriers = 1,
                    factionNames = { "Bandits", "Cordon Patrol" },
                    showArrow = true,
                },
                {
                    stance = "careful",
                    count = 1,
                    distance = 18,
                    directionAngle = math.rad(-72),
                    firearmCarriers = 0,
                    factionNames = { "Riverside Survivors" },
                    showArrow = true,
                },
                {
                    stance = "neutral",
                    count = 1,
                    distance = 24,
                    directionAngle = math.rad(96),
                    firearmCarriers = 0,
                    factionNames = { "Unaffiliated Survivor" },
                    showArrow = true,
                },
                {
                    stance = "friendly",
                    count = 3,
                    distance = 34,
                    directionAngle = math.rad(142),
                    firearmCarriers = 0,
                    factionNames = { "Muldraugh Militia" },
                    showArrow = true,
                },
                {
                    stance = "allied",
                    count = 1,
                    distance = 38,
                    directionAngle = math.rad(-152),
                    firearmCarriers = 0,
                    factionNames = { "Your people" },
                    showArrow = true,
                },
            }
        end
        if previewKind == "zombie" or previewKind == "all" then
            rearZombiePreviewIndicators = {
                {
                    count = 2,
                    distance = 4,
                    activeRange = 20,
                    directionAngle = math.rad(-38),
                    colour = rearZombieIndicatorColour(0, 20),
                },
                {
                    count = 1,
                    distance = 14,
                    activeRange = 20,
                    directionAngle = math.rad(34),
                    colour = rearZombieIndicatorColour(20, 20),
                },
            }
        end
        if previewKind == "sprinter" or previewKind == "all" then
            sprinterWarning = {
                indicators = {
                    {
                        sectorIndex = 1,
                        count = 1,
                        distance = 12,
                        activeRange = 20,
                        directionAngle = math.rad(54),
                        indicatorColour = sprinterIndicatorColour(12, 20),
                    },
                },
            }
        end

        drawRearZombieIndicators(rearZombiePreviewIndicators, screenWidth, screenHeight)
        if sprinterWarning then
            drawRearZombieIndicators(sprinterWarning.indicators, screenWidth, screenHeight,
                "sprinter", sprinterBlinkThreshold, 1.2)
        end

        if #alertWarnings > 0 then
            local headerTexture = neatPanelTexture(NEAT_PANEL_HEADER_TEXTURE)
            local bodyTexture = neatPanelTexture(NEAT_PANEL_BODY_TEXTURE)
            local displayMode = alertDisplayMode()
            local compactNeatUI = displayMode == ALERT_DISPLAY_MODE_COMPACT_NEATUI
            local function drawGroup(warningsToDraw, centerX, startY)
                if displayMode ~= ALERT_DISPLAY_MODE_VANILLA
                        and headerTexture and bodyTexture then
                    return drawNeatAlertGroup(
                        warningsToDraw, headerTexture, bodyTexture, text,
                        screenWidth, centerX, startY, compactNeatUI
                    )
                end
                return drawCompactAlertGroup(
                    warningsToDraw, text, screenWidth, centerX, startY, false
                )
            end

            local centerX, startY
            if layoutPreview then
                centerX, startY = alertAnchor(screenWidth, screenHeight, 24)
            else
                centerX, startY = screenWidth * 0.5, screenHeight * 0.62
            end
            local bounds = drawGroup(alertWarnings, centerX, startY)
            updateAlertDragHandle(bounds, screenWidth, screenHeight)
        else
            updateAlertDragHandle(nil, screenWidth, screenHeight)
        end
    end)
    displayedArrowAngles = liveArrowAngles
    if not ok then activeAlertPreview = nil end
    finishArrowLayerPass("preview")
    return ok
end

local function alertPreviewIsActive()
    if isAlertLayoutPreviewEnabled() then return true end
    if not activeAlertPreview then return false end
    if getTimestampMs() >= activeAlertPreview.expiresAt then
        activeAlertPreview = nil
        return false
    end
    return true
end

local function isBlockedBetweenSquares(firstSquare, secondSquare)
    if firstSquare:getZ() == secondSquare:getZ() then
        if firstSquare:getX() < secondSquare:getX()
                and secondSquare:has(IsoFlagType.HoppableW) then return false end
        if firstSquare:getX() > secondSquare:getX()
                and firstSquare:has(IsoFlagType.HoppableW) then return false end
        if firstSquare:getY() < secondSquare:getY()
                and secondSquare:has(IsoFlagType.HoppableN) then return false end
        if firstSquare:getY() > secondSquare:getY()
                and firstSquare:has(IsoFlagType.HoppableN) then return false end
    end
    return firstSquare:isBlockedTo(secondSquare) or secondSquare:isBlockedTo(firstSquare)
end

local function hasClearLineOnSameFloor(startSquare, targetSquare, cell)
    local startX, startY = startSquare:getX(), startSquare:getY()
    local targetX, targetY = targetSquare:getX(), targetSquare:getY()
    local deltaX, deltaY = targetX - startX, targetY - startY
    local stepX = deltaX < 0 and -1 or 1
    local stepY = deltaY < 0 and -1 or 1
    local absDeltaX, absDeltaY = math.abs(deltaX), math.abs(deltaY)
    local maxX = absDeltaX > 0 and 0.5 / absDeltaX or math.huge
    local maxY = absDeltaY > 0 and 0.5 / absDeltaY or math.huge
    local deltaMaxX = absDeltaX > 0 and 1 / absDeltaX or math.huge
    local deltaMaxY = absDeltaY > 0 and 1 / absDeltaY or math.huge
    local x, y = startX, startY
    local currentSquare = startSquare
    local z = startSquare:getZ()

    while x ~= targetX or y ~= targetY do
        if maxX < maxY then
            x = x + stepX
            maxX = maxX + deltaMaxX
            local nextSquare = cell:getGridSquare(x, y, z)
            if nextSquare == nil or isBlockedBetweenSquares(currentSquare, nextSquare) then return false end
            currentSquare = nextSquare
        elseif maxY < maxX then
            y = y + stepY
            maxY = maxY + deltaMaxY
            local nextSquare = cell:getGridSquare(x, y, z)
            if nextSquare == nil or isBlockedBetweenSquares(currentSquare, nextSquare) then return false end
            currentSquare = nextSquare
        else
            local sideX = cell:getGridSquare(x + stepX, y, z)
            local sideY = cell:getGridSquare(x, y + stepY, z)
            local nextSquare = cell:getGridSquare(x + stepX, y + stepY, z)
            if sideX == nil or sideY == nil or nextSquare == nil then return false end
            local pathXClear = not isBlockedBetweenSquares(currentSquare, sideX)
                and not isBlockedBetweenSquares(sideX, nextSquare)
            local pathYClear = not isBlockedBetweenSquares(currentSquare, sideY)
                and not isBlockedBetweenSquares(sideY, nextSquare)
            if not pathXClear and not pathYClear then return false end
            x, y = x + stepX, y + stepY
            maxX = maxX + deltaMaxX
            maxY = maxY + deltaMaxY
            currentSquare = nextSquare
        end
    end

    return true
end

local function passesRearZombieVisibilityFilters(zombie, playerSquare, cell, sameFloorOnly, requireLineOfSight)
    if not sameFloorOnly and not requireLineOfSight then return true end
    if playerSquare == nil then return false end

    local ok, passes = pcall(function()
        local zombieSquare = zombie:getCurrentSquare()
        if zombieSquare == nil then return false end
        if sameFloorOnly and zombieSquare:getZ() ~= playerSquare:getZ() then return false end
        if requireLineOfSight then
            if zombieSquare:getZ() == playerSquare:getZ() then
                if not hasClearLineOnSameFloor(zombieSquare, playerSquare, cell) then return false end
            elseif isBlockedBetweenSquares(zombieSquare, playerSquare) then
                return false
            end
        end
        return true
    end)
    return ok and passes
end

local function scanNearbyThreats()
    warnings = {}
    rearZombieWarning = nil
    rearZombieIndicators = {}
    sprinterWarning = nil
    sprinterAlarmZombieIDs = {}
    closeHostileNPCs = {}
    local stanceEnabled = {}
    local warnALifeNPCs = false
    for _, stance in ipairs(STANCE_PRIORITY) do
        local enabled = getOption(STANCE_OPTION_KEYS[stance], STANCE_OPTION_DEFAULTS[stance])
        stanceEnabled[stance] = enabled
        warnALifeNPCs = warnALifeNPCs or enabled
    end
    local disableZombieAlerts = playerInVehicle and getOption("DisableZombieAlertsInVehicle", true)
    local disableSprinterAlerts = playerInVehicle and getOption("DisableSprinterAlertsInVehicle", true)
    local disableALifeAlerts = playerInVehicle and getOption("DisableALifeAlertsInVehicle", true)
    if disableALifeAlerts then warnALifeNPCs = false end
    local warnRearZombies = getOption("EnableRearZombieWarning", true) and not disableZombieAlerts
    local warnSprinters = getOption("EnableSprinterWarning", true) and not disableSprinterAlerts
    local warnSprinterAlarm = getOption("EnableAlarmSound", true)
        and getOption("EnableSprinterAlarm", true) and not disableSprinterAlerts
    local warnCloseHostileAlarm = getOption("EnableCloseHostileAlarm", false) and not disableALifeAlerts
    if not warnALifeNPCs and not warnRearZombies and not warnCloseHostileAlarm
            and not warnSprinters and not warnSprinterAlarm then return end

    local project = ProjectALife
    if type(project) ~= "table" then
        project = nil
        warnALifeNPCs = false
        warnCloseHostileAlarm = false
    end
    if not warnALifeNPCs and not warnRearZombies and not warnCloseHostileAlarm
            and not warnSprinters and not warnSprinterAlarm then return end
    local player = getSpecificPlayer(0)
    if player == nil or player:isDead() then return end
    local playerSquare = player:getCurrentSquare()
    local cell = getCell()
    local list = cell and cell:getZombieList() or nil
    if list == nil then return end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local forwardX, forwardY = player:getForwardDirectionX(), player:getForwardDirectionY()
    local forwardLength = math.sqrt(forwardX * forwardX + forwardY * forwardY)
    if forwardLength > 0.001 then
        forwardX, forwardY = forwardX / forwardLength, forwardY / forwardLength
    else
        forwardX, forwardY = 1, 0
    end
    local arrowForwardX, arrowForwardY = cameraForwardDirection(forwardX, forwardY)
    local range = warnALifeNPCs and warningRange() or 0
    local rangeSquared = range * range
    local closeHostileRange = warnCloseHostileAlarm and closeHostileAlarmRange() or 0
    local closeHostileRangeSquared = closeHostileRange * closeHostileRange
    local rearRange = warnRearZombies and rearZombieWarningRange(player) or 0
    local rearRangeSquared = rearRange * rearRange
    rearZombieBlinkThreshold = rearZombieBlinkDistance()
    local sprinterRange = warnSprinters and sprinterWarningRange() or 0
    local sprinterRangeSquared = sprinterRange * sprinterRange
    sprinterBlinkThreshold = sprinterBlinkDistance()
    local rearZombieIndicatorLimit = math.max(1, math.min(8,
        math.floor((tonumber(getOption("MaxRearZombieIndicators", 3)) or 3) + 0.5)))
    local sprinterIndicatorLimit = math.max(1, math.min(8,
        math.floor((tonumber(getOption("MaxSprinterIndicators", 1)) or 1) + 0.5)))
    local sprinterAlarmRange = warnSprinterAlarm and sprinterAlarmDistance() or 0
    local sprinterAlarmRangeSquared = sprinterAlarmRange * sprinterAlarmRange
    local rearAngle = rearZombieWarningAngle()
    local rearAngleCos = math.cos(math.rad(rearAngle * 0.5))
    local scanRangeSquared = math.max(rangeSquared, rearRangeSquared,
        closeHostileRangeSquared, sprinterRangeSquared, sprinterAlarmRangeSquared)
    local showDirectionArrow = getOption("ShowDirectionArrow", true)
    local showFirearmWarning = getOption("ShowFirearmWarning", false)
    local ignoreFallenZombies = getOption("IgnoreFallenZombies", false)
    local rearZombieSameFloorOnly = getOption("RearZombieSameFloorOnly", true)
    local rearZombieRequireLineOfSight = getOption("RearZombieRequireLineOfSight", true)
    local sprinterSameFloorOnly = getOption("SprinterSameFloorOnly", true)
    local sprinterRequireLineOfSight = getOption("SprinterRequireLineOfSight", true)
    local sprinterIgnoreFallen = getOption("SprinterIgnoreFallen", true)
    local threatsByStance = {}
    for _, stance in ipairs(STANCE_PRIORITY) do
        threatsByStance[stance] = {
            count = 0,
            nearestDistance = rangeSquared,
            firearmCarriers = 0,
            nearestFirearmDistance = rangeSquared,
            factions = {},
            factionNames = {},
        }
    end
    local rearZombies = 0
    local rearZombieIndicatorsBySector = {}
    local sprinters = 0
    local sprinterIndicatorsBySector = {}
    for index = 0, list:size() - 1 do
        local shell = list:get(index)
        if shell ~= nil and not shell:isDead() then
            local x, y, z = shell:getX(), shell:getY(), shell:getZ()
            local dx, dy = x - px, y - py
            local distanceSquared = dx * dx + dy * dy
            local nearbyFloor = math.abs(z - pz) <= 1
                or ((warnSprinters or warnSprinterAlarm) and not sprinterSameFloorOnly)
            if nearbyFloor and distanceSquared <= scanRangeSquared then
                local rearCandidate = false
                if warnRearZombies and distanceSquared <= rearRangeSquared then
                    local fallen = false
                    if ignoreFallenZombies then
                        local ok, onFloor = pcall(function() return shell:isOnFloor() end)
                        fallen = ok and onFloor == true
                    end
                    if not fallen then
                        local forwardDot = dx * forwardX + dy * forwardY
                        rearCandidate = -forwardDot >= math.sqrt(distanceSquared) * rearAngleCos
                            and passesRearZombieVisibilityFilters(
                                shell,
                                playerSquare,
                                cell,
                                rearZombieSameFloorOnly,
                                rearZombieRequireLineOfSight
                            )
                    end
                end
                local closeHostileCandidate = warnCloseHostileAlarm
                    and distanceSquared <= closeHostileRangeSquared
                local canBeSprinter = (warnSprinters and distanceSquared <= sprinterRangeSquared)
                    or (warnSprinterAlarm and distanceSquared <= sprinterAlarmRangeSquared)
                local sprinterType = canBeSprinter and isSprinter(shell)
                local sprinterCandidate = warnSprinters
                    and distanceSquared <= sprinterRangeSquared and sprinterType
                local sprinterAlarmCandidate = warnSprinterAlarm
                    and distanceSquared <= sprinterAlarmRangeSquared and sprinterType
                if sprinterType and sprinterIgnoreFallen then
                    local ok, onFloor = pcall(function() return shell:isOnFloor() end)
                    if ok and onFloor == true then
                        sprinterCandidate = false
                        sprinterAlarmCandidate = false
                    end
                end
                if sprinterCandidate or sprinterAlarmCandidate then
                    local passesSprinterVisibility = passesRearZombieVisibilityFilters(
                        shell,
                        playerSquare,
                        cell,
                        sprinterSameFloorOnly,
                        sprinterRequireLineOfSight
                    )
                    sprinterCandidate = sprinterCandidate and passesSprinterVisibility
                    sprinterAlarmCandidate = sprinterAlarmCandidate and passesSprinterVisibility
                end
                local alifeCandidate = (warnALifeNPCs and distanceSquared <= rangeSquared)
                    or closeHostileCandidate
                local uid
                if project and (rearCandidate or alifeCandidate or sprinterCandidate
                        or sprinterAlarmCandidate) then
                    uid = uidOf(project, shell)
                end

                if rearCandidate and not sprinterCandidate and uid == nil then
                    rearZombies = rearZombies + 1
                    local rearDirectionAngle = directionAngle(dx, dy, arrowForwardX, arrowForwardY)
                    local sectorIndex = rearZombieSectorIndex(
                        rearDirectionAngle, rearAngle, rearZombieIndicatorLimit
                    )
                    local sector = rearZombieIndicatorsBySector[sectorIndex]
                    if not sector then
                        sector = { count = 0, nearestDistance = distanceSquared }
                        rearZombieIndicatorsBySector[sectorIndex] = sector
                    end
                    sector.count = sector.count + 1
                    if distanceSquared <= sector.nearestDistance then
                        sector.nearestDistance = distanceSquared
                        sector.directionAngle = rearDirectionAngle
                    end
                end

                if sprinterCandidate and uid == nil then
                    sprinters = sprinters + 1
                    local sprinterDirectionAngle = directionAngle(
                        dx, dy, arrowForwardX, arrowForwardY
                    )
                    local sectorIndex = sprinterSectorIndex(
                        sprinterDirectionAngle, sprinterIndicatorLimit
                    )
                    local sector = sprinterIndicatorsBySector[sectorIndex]
                    if not sector then
                        sector = { count = 0, nearestDistance = math.huge }
                        sprinterIndicatorsBySector[sectorIndex] = sector
                    end
                    sector.count = sector.count + 1
                    if distanceSquared < sector.nearestDistance then
                        sector.nearestDistance = distanceSquared
                        sector.directionAngle = sprinterDirectionAngle
                    end
                end
                if sprinterAlarmCandidate and uid == nil then
                    sprinterAlarmZombieIDs[zombieAlertId(shell)] = true
                end

                if alifeCandidate and uid ~= nil then
                    local record = actorFor(project, uid)
                    if record then
                        local stance = stanceOf(project, record, player)
                        if closeHostileCandidate and stance == "hostile" then
                            closeHostileNPCs[uid] = true
                        end
                        if warnALifeNPCs and distanceSquared <= rangeSquared and stanceEnabled[stance] then
                            local threat = threatsByStance[stance]
                            if threat then
                                threat.count = threat.count + 1
                                local factionId, factionName = factionNameFor(project, record)
                                if factionId and not threat.factions[factionId] then
                                    threat.factions[factionId] = true
                                    threat.factionNames[#threat.factionNames + 1] = factionName
                                end
                                if threat.nearestDirectionAngle == nil or distanceSquared < threat.nearestDistance then
                                    threat.nearestDistance = distanceSquared
                                    threat.nearestDirectionAngle = directionAngle(dx, dy, arrowForwardX, arrowForwardY)
                                end
                                if showFirearmWarning and carriesFirearm(project, shell) then
                                    threat.firearmCarriers = threat.firearmCarriers + 1
                                    if threat.nearestFirearmDirectionAngle == nil
                                            or distanceSquared < threat.nearestFirearmDistance then
                                        threat.nearestFirearmDistance = distanceSquared
                                        threat.nearestFirearmDirectionAngle = directionAngle(dx, dy, arrowForwardX, arrowForwardY)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _, stance in ipairs(STANCE_PRIORITY) do
        local threat = threatsByStance[stance]
        if threat.count > 0 then
            local usingFirearmDistance = threat.nearestFirearmDirectionAngle ~= nil
            warnings[#warnings + 1] = {
                stance = stance,
                count = threat.count,
                distance = math.sqrt(usingFirearmDistance
                    and threat.nearestFirearmDistance or threat.nearestDistance),
                directionAngle = threat.nearestFirearmDirectionAngle or threat.nearestDirectionAngle,
                firearmCarriers = threat.firearmCarriers,
                factionNames = threat.factionNames,
                showArrow = showDirectionArrow,
            }
        end
    end

    if rearZombies > 0 then
        rearZombieWarning = true
        for sectorIndex = 1, rearZombieIndicatorLimit do
            local sector = rearZombieIndicatorsBySector[sectorIndex]
            if sector then
                rearZombieIndicators[#rearZombieIndicators + 1] = {
                    sectorIndex = sectorIndex,
                    count = sector.count,
                    distance = math.sqrt(sector.nearestDistance),
                    activeRange = rearRange,
                    directionAngle = sector.directionAngle,
                    colour = rearZombieIndicatorColour(
                        math.sqrt(sector.nearestDistance), rearRange
                    ),
                }
            end
        end
    end
    if sprinters > 0 then
        sprinterWarning = {
            indicators = {},
        }
        for sectorIndex = 1, sprinterIndicatorLimit do
            local sector = sprinterIndicatorsBySector[sectorIndex]
            if sector then
                local distance = math.sqrt(sector.nearestDistance)
                sprinterWarning.indicators[#sprinterWarning.indicators + 1] = {
                    sectorIndex = sectorIndex,
                    count = sector.count,
                    distance = distance,
                    activeRange = sprinterRange,
                    directionAngle = sector.directionAngle,
                    indicatorColour = sprinterIndicatorColour(distance, sprinterRange),
                }
            end
        end
    end
end

local lastAlarmSignature = ""
local activeAlarmSound

local function warningSignature()
    local parts = {}
    for _, warning in ipairs(warnings) do
        parts[#parts + 1] = warning.stance
    end
    if rearZombieWarning then parts[#parts + 1] = "rear-zombies" end
    if sprinterWarning and not (getOption("EnableAlarmSound", true)
            and getOption("EnableSprinterAlarm", true)) then
        parts[#parts + 1] = "sprinters"
    end
    return table.concat(parts, "|")
end

local function alarmSignature()
    if getOption("ZombieAlarmOnly", true) then
        local parts = {}
        if rearZombieWarning then parts[#parts + 1] = "rear-zombies" end
        if sprinterWarning and not (getOption("EnableSprinterAlarm", true)) then
            parts[#parts + 1] = "sprinters"
        end
        return table.concat(parts, "|")
    end
    return warningSignature()
end

playAlarmSound = function(soundOption, volumeOption, selectedSound, selectedVolume)
    local defaultSound = DEFAULT_ALARM_SOUND
    if soundOption == "CloseHostileAlarmSound" then
        defaultSound = DEFAULT_CLOSE_HOSTILE_ALARM_SOUND
    elseif soundOption == "SprinterAlarmSound" then
        defaultSound = DEFAULT_SPRINTER_ALARM_SOUND
    end
    local index = math.floor(tonumber(selectedSound)
        or tonumber(getOption(soundOption or "AlarmSound", defaultSound)) or defaultSound)
    local soundOption = ALARM_SOUND_OPTIONS[index] or ALARM_SOUND_OPTIONS[1]
    local sound = soundOption.id
    local volume = tonumber(selectedVolume)
        or tonumber(getOption(volumeOption or "AlarmVolume", DEFAULT_ALARM_VOLUME))
        or DEFAULT_ALARM_VOLUME
    volume = math.max(0, math.min(MAX_ALARM_VOLUME, volume))
    stopAlarmAudio(activeAlarmSound)
    activeAlarmSound = nil

    local uiSoundMuted = "unknown"
    local managerOk, soundManager = pcall(getSoundManager)
    if managerOk and soundManager ~= nil then
        local mutedOk, muted = pcall(function()
            return soundManager:isUiSoundMuted()
        end)
        if mutedOk then uiSoundMuted = tostring(muted) end
    end

    if not managerOk or soundManager == nil then
        print("[Viewpoint Threat Detector] Alarm playback failed: sound manager unavailable"
            .. " event=" .. tostring(sound) .. " uiSoundMuted=" .. uiSoundMuted)
        return false, soundManager
    end
    local emitterOk, emitter = pcall(function()
        return soundManager:getUIEmitter()
    end)
    if not emitterOk or emitter == nil then
        print("[Viewpoint Threat Detector] Alarm playback failed: UI emitter unavailable"
            .. " event=" .. tostring(sound) .. " uiSoundMuted=" .. uiSoundMuted)
        return false, "UI emitter unavailable"
    end

    local ok, handle = pcall(function()
        return emitter:playSound(sound)
    end)
    if not ok or handle == nil or handle == 0 then
        print("[Viewpoint Threat Detector] Alarm playback failed: " .. tostring(handle)
            .. " event=" .. tostring(sound) .. " uiSoundMuted=" .. uiSoundMuted)
        return false, handle
    end

    local volumeApplied, volumeError = pcall(function()
        emitter:setVolume(handle, volume / 100)
    end)
    activeAlarmSound = { emitter = emitter, handle = handle }
    if not volumeApplied then
        print("[Viewpoint Threat Detector] Alarm volume failed: " .. tostring(volumeError)
            .. " event=" .. tostring(sound))
    end
    return true, sound, handle, volumeApplied, volumeError
end

local ALARM_PREVIEW_OPTIONS = {
    { name = "regular", sound = "AlarmSound", volume = "AlarmVolume" },
    { name = "close-hostile", sound = "CloseHostileAlarmSound", volume = "CloseHostileAlarmVolume" },
    { name = "sprinter", sound = "SprinterAlarmSound", volume = "SprinterAlarmVolume" },
}

local function onAlarmPreviewKeyPressed(key)
    local previewKey = tonumber(getOption("AlarmPreviewKey", Keyboard.KEY_F9))
    if not previewKey or previewKey == 0 or key ~= previewKey then return end
    local playerOk, player = pcall(getPlayer)
    if not playerOk or player == nil then return end

    local previewIndex = math.floor(tonumber(getOption("AlarmPreviewType", 1)) or 1)
    local preview = ALARM_PREVIEW_OPTIONS[previewIndex] or ALARM_PREVIEW_OPTIONS[1]
    local played, sound, handle, volumeApplied, errorMessage =
        playAlarmSound(preview.sound, preview.volume)
    local isPlaying = false
    if activeAlarmSound then
        local isPlayingOk, result = pcall(function()
            return activeAlarmSound.emitter:isPlaying(activeAlarmSound.handle)
        end)
        isPlaying = isPlayingOk and tostring(result) or "unknown"
    end
    local soundManagerOk, soundManager = pcall(getSoundManager)
    local uiSoundMuted = "unknown"
    if soundManagerOk and soundManager ~= nil then
        local mutedOk, muted = pcall(function()
            return soundManager:isUiSoundMuted()
        end)
        if mutedOk then uiSoundMuted = tostring(muted) end
    end
    print("[Viewpoint Threat Detector] In-game alarm preview: target=" .. preview.name
        .. " event=" .. tostring(sound) .. " handle=" .. tostring(handle)
        .. " volumeApplied=" .. tostring(volumeApplied) .. " isPlaying=" .. tostring(isPlaying)
        .. " uiSoundMuted=" .. uiSoundMuted .. " error=" .. tostring(errorMessage)
        .. " played=" .. tostring(played))
end

if Events and Events.OnKeyPressed then
    Events.OnKeyPressed.Add(onAlarmPreviewKeyPressed)
    Events.OnKeyPressed.Add(function(key)
        local previewKey = tonumber(getOption("ToggleAlertLayoutPreviewKey", 0))
        if not previewKey or previewKey == 0 or key ~= previewKey then return end
        if not getSpecificPlayer(0) then return end
        alertLayoutPreviewEnabled = not isAlertLayoutPreviewEnabled()
    end)
end

local function updateWarning()
    local ok, err = pcall(scanNearbyThreats)
    if not ok then
        warnings = {}
        rearZombieWarning = nil
        rearZombieIndicators = {}
        sprinterWarning = nil
        sprinterAlarmZombieIDs = {}
        closeHostileNPCs = {}
        lastAlarmSignature = ""
        lastCloseHostileNPCs = {}
        lastSprinterAlarmZombieIDs = {}
        if not errorLogged then
            print("[Viewpoint Threat Detector] Detection failed: " .. tostring(err))
            errorLogged = true
        end
        return
    end

    local signature = alarmSignature()
    local alarmSoundsEnabled = getOption("EnableAlarmSound", true)
    local closeHostileAlarmEnabled = alarmSoundsEnabled
        and getOption("EnableCloseHostileAlarm", false)
    local sprinterAlarmEnabled = alarmSoundsEnabled and getOption("EnableSprinterAlarm", true)
    local closeHostileAlarmEntered = false
    if closeHostileAlarmEnabled then
        for uid in pairs(closeHostileNPCs) do
            if not lastCloseHostileNPCs[uid] then
                closeHostileAlarmEntered = true
                break
            end
        end
    end
    local sprinterAlarmEntered = false
    if sprinterAlarmEnabled then
        for id in pairs(sprinterAlarmZombieIDs) do
            if not lastSprinterAlarmZombieIDs[id] then
                sprinterAlarmEntered = true
                break
            end
        end
    end
    if signature ~= "" and signature ~= lastAlarmSignature
            and alarmSoundsEnabled and not closeHostileAlarmEntered and not sprinterAlarmEntered then
        playAlarmSound()
    end
    if sprinterAlarmEntered then
        playAlarmSound("SprinterAlarmSound", "SprinterAlarmVolume")
    elseif closeHostileAlarmEntered then
        playAlarmSound("CloseHostileAlarmSound", "CloseHostileAlarmVolume")
    end
    lastAlarmSignature = signature
    lastCloseHostileNPCs = closeHostileAlarmEnabled and closeHostileNPCs or {}
    lastSprinterAlarmZombieIDs = sprinterAlarmEnabled and sprinterAlarmZombieIDs or {}
end

local function drawWarning()
    beginArrowLayerPass("live")
    if getOption("ImmersiveMode", false) then
        displayedArrowAngles = {}
        activeAlertPreview = nil
        updateAlertDragHandle(nil, 0, 0)
        finishArrowLayerPass("live")
        return
    end
    if alertPreviewIsActive() then
        updateAlertDragHandle(nil, 0, 0)
        finishArrowLayerPass("live")
        return
    end
    local hasRadialIndicators = #rearZombieIndicators > 0
        or (sprinterWarning and type(sprinterWarning.indicators) == "table"
            and #sprinterWarning.indicators > 0)
    if #warnings == 0 and not hasRadialIndicators then
        displayedArrowAngles = {}
        updateAlertDragHandle(nil, 0, 0)
        finishArrowLayerPass("live")
        return
    end

    local ok, err = pcall(function()
        local core = getCore()
        local screenWidth = core:getScreenWidth()
        local screenHeight = core:getScreenHeight()
        if #rearZombieIndicators > 0 then
            drawRearZombieIndicators(rearZombieIndicators, screenWidth, screenHeight)
        end
        if sprinterWarning and type(sprinterWarning.indicators) == "table" then
            drawRearZombieIndicators(sprinterWarning.indicators, screenWidth, screenHeight,
                "sprinter", sprinterBlinkThreshold, 1.2)
        end
        if #warnings == 0 then
            updateAlertDragHandle(nil, screenWidth, screenHeight)
            return
        end

        local displayMode = alertDisplayMode()
        local centerX, startY = alertAnchor(screenWidth, screenHeight)
        local text = getTextManager()
        local bounds
        if displayMode ~= ALERT_DISPLAY_MODE_VANILLA then
            local headerTexture = neatPanelTexture(NEAT_PANEL_HEADER_TEXTURE)
            local bodyTexture = neatPanelTexture(NEAT_PANEL_BODY_TEXTURE)
            if headerTexture and bodyTexture then
                bounds = drawNeatAlertGroup(
                    warnings, headerTexture, bodyTexture, text,
                    screenWidth, centerX, startY,
                    displayMode == ALERT_DISPLAY_MODE_COMPACT_NEATUI
                )
            end
        end
        if not bounds then
            bounds = drawCompactAlertGroup(
                warnings, text, screenWidth, centerX, startY, false
            )
        end
        updateAlertDragHandle(bounds, screenWidth, screenHeight)
    end)
    if not ok and not errorLogged then
        updateAlertDragHandle(nil, 0, 0)
        print("[Viewpoint Threat Detector] Warning display failed: " .. tostring(err))
        errorLogged = true
    end
    finishArrowLayerPass("live")
end

local ticks = 0
if Events and Events.OnTick then
    Events.OnTick.Add(function()
        ticks = ticks + 1
        dragDiagnosticsEnabled = getOption("EnableDragDiagnostics", false) == true
        updateGlobalAlertDrag()
        playerInVehicle = false
        local player = getSpecificPlayer(0)
        if player then
            local ok, vehicle = pcall(function() return player:getVehicle() end)
            playerInVehicle = ok and vehicle ~= nil
        end
        if ticks % SCAN_INTERVAL == 0 then updateWarning() end
    end)
end

if Events and Events.OnPreUIDraw then
    Events.OnPreUIDraw.Add(drawWarning)
end
if Events and Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(drawAlertPreview)
end
