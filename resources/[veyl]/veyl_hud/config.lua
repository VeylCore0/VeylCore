HudConfig = {
    -- Defaults; each player can change these with /hudsettings (saved per player with resource KVP).
    Defaults = { scale = 1.0, showMoney = true, showCompass = true, showStatus = true, showVehicle = true, showBrand = true, unit = 'MPH' },

    -- Voice provider: 'auto' detects pma-voice once at start; otherwise native talking only (range unavailable).
    Voice = 'auto',

    -- Seatbelt provider: 'statebag' reads LocalPlayer.state.seatbelt (set by veyl_vehicles' seatbelt, key B); 'none' shows "unavailable".
    -- Any seatbelt resource that sets LocalPlayer.state.seatbelt works too.
    Seatbelt = 'statebag',

    -- Hide these default GTA HUD components (cash, MP cash, cash change, vehicle name, area name, street name, class).
    HideComponents = { 3, 4, 6, 7, 8, 9, 13 },

    -- Weapons are equipped from the inventory, so the GTA weapon wheel (Tab) and scroll-wheel weapon cycling are disabled.
    DisableWeaponWheel = true,

    -- Minimap layout. GTA's own health/armour bars are hidden (the HUD status row replaces them) and the map is raised so the
    -- status row sits underneath it instead of on top of it. All values are fractions of the screen height.
    Minimap = {
        hideHealthArmour = true,
        raise = 0.045,     -- how far the map is moved up from GTA's default position
        barStrip = 0.014,  -- strip under the map where GTA drew its bars; kept out of the frame
        -- Fine-tune the frame if it is off by a few pixels at your resolution (fractions of screen width/height).
        frameNudge = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 },
    },
}
