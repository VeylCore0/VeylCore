HudConfig = {
    -- Defaults; each player can change these with /hudsettings (saved per player with resource KVP).
    Defaults = { scale = 1.0, showMoney = true, showCompass = true, showStatus = true, showVehicle = true, showBrand = true, unit = 'MPH' },

    -- Voice provider: 'auto' detects pma-voice once at start; otherwise native talking only (range unavailable).
    Voice = 'auto',

    -- Seatbelt provider: 'none' shows "unavailable" (never a fake "safe"); 'statebag' reads LocalPlayer.state.seatbelt (boolean)
    -- set by a seatbelt resource you install.
    Seatbelt = 'none',

    -- Hide these default GTA HUD components (cash, MP cash, cash change, vehicle name, area name, street name, class).
    HideComponents = { 3, 4, 6, 7, 8, 9, 13 },

    -- Weapons are equipped from the inventory, so the GTA weapon wheel (Tab) and scroll-wheel weapon cycling are disabled.
    DisableWeaponWheel = true,
}
