-- veyl_hud configuration (server owner). Each player's own preferences are made in the /hud menu and saved on
-- their computer; `Defaults` below is what a new player starts with and what "Reset defaults" returns to.

HudConfig = {
    MenuCommand = 'hud',               -- /hud opens the settings menu
    MenuKey = '',                      -- optional key for the menu (players can bind it in Settings > Key Bindings > FiveM)

    -- Providers. 'auto' picks the first one that is running.
    Voice = 'auto',                    -- 'auto' | 'pma-voice' | 'native' (talking only)
    Fuel = 'auto',                     -- 'auto' | 'veyl_fuel' | 'native' (GTA fuel level) | 'none'
    Seatbelt = 'statebag',             -- 'statebag' (LocalPlayer.state.seatbelt, set by veyl_vehicles) | 'none'
    -- Postal codes: 'none' hides the postal everywhere. 'file' reads a JSON list [{ "code": "8042", "x": 0.0, "y": 0.0 }, ...]
    -- from this resource (e.g. data/postals.json from your postal map). Codes are never invented.
    Postal = { provider = 'none', file = 'data/postals.json' },

    -- Vehicle layouts by GTA vehicle class; model overrides win. Layouts: car, motorcycle, boat, heli, bicycle, none.
    -- Planes (16) have no layout yet: they show no instruments rather than pretending to be a helicopter.
    VehicleClasses = {
        [0] = 'car', [1] = 'car', [2] = 'car', [3] = 'car', [4] = 'car', [5] = 'car', [6] = 'car', [7] = 'car',
        [8] = 'motorcycle', [9] = 'car', [10] = 'car', [11] = 'car', [12] = 'car', [13] = 'bicycle', [14] = 'boat',
        [15] = 'heli', [16] = 'none', [17] = 'car', [18] = 'car', [19] = 'car', [20] = 'car', [21] = 'none', [22] = 'car',
    },
    ModelOverrides = {
        -- [`seashark`] = 'boat',
    },
    -- Vehicle classes where a seatbelt exists (matches veyl_vehicles/seatbelt.lua).
    BeltClasses = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
        [9] = true, [10] = true, [11] = true, [12] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true },
    BoatRpm = false,                   -- GTA's RPM value for boats is not meaningful telemetry; off unless you want it
    SeatbeltAlertMph = 12,             -- beep when unbuckled above this speed

    -- Hide these default GTA HUD components (cash, MP cash, cash change, vehicle name, area name, street name, class).
    HideComponents = { 3, 4, 6, 7, 8, 9, 13 },
    -- Weapons are equipped from the inventory, so the GTA weapon wheel (Tab) and scroll-wheel cycling stay disabled.
    DisableWeaponWheel = true,
    -- GTA draws health/armour bars under the minimap; the HUD shows them instead.
    HideNativeBars = true,

    -- Circle minimap needs a streamed texture dictionary `circlemap` with a texture `radarmasksm` (stream/circlemap.ytd).
    -- Without it the Circle option is shown as unavailable. See docs/HUD.md.
    CircleTextureDict = 'circlemap',

    Defaults = {
        enabled = true, scale = 1.0, opacity = 0.82, borderOpacity = 0.35, showPercent = false, reducedMotion = false,
        colors = { primary = '#A5F3D0', secondary = '#F3A6C8', text = '#F7FAFC' },
        player = {
            health = true, armor = true, hunger = true, thirst = true, stress = true, stamina = true, oxygen = true, voice = true,
            cash = true, bank = true, playerId = true, clock = true, location = true, postal = true,
            hideFull = false, layout = 'list',            -- 'list' (bars beside the map) | 'compact' (icons with rings)
        },
        thresholds = { health = 25, armor = 0, hunger = 20, thirst = 20, stress = 80, stamina = 20, oxygen = 30 },
        minimap = { shape = 'square', mode = 'always', northUp = false, scale = 1.0, offsetX = 0.0, offsetY = 0.0,
            street = true, direction = true, postal = true },
        vehicle = {
            auto = true, modes = { car = true, motorcycle = true, boat = true, heli = true, bicycle = true },
            roadUnit = 'MPH', airSeaUnit = 'KTS', altUnit = 'FT', vsUnit = 'FPM', altMode = 'AGL',
            fuel = true, engine = true, rpm = true, gear = true, bikeStamina = true, seatbelt = true, seatbeltAlert = true,
        },
        positions = {},                                    -- normalized { x, y } per group, set by the position editor
        snap = true,
    },
}
