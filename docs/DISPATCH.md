# Dispatch (`veyl_dispatch`)

Calls, blips and unit status for police and EMS.

```
ensure veyl_dispatch   # after veyl_core and veyl_ui
```

## For on-duty police and EMS

| Key / command | What it does |
|---|---|
| **F6** / `/dispatch` | Dispatch panel: your status, active calls (newest first) and every on-duty unit |
| **Y** | Respond to the newest call: sets GPS and marks you en route |
| **F9** / `/panic` | Panic button: an urgent call with your position to every police and EMS unit (30 s cooldown) |
| `/callsign 1-ADAM-12` | Callsign shown in the panel and on unit blips |

- **New call:** a card slides in at the top right for 9 s (code, title, street, distance) with a sound. Urgent calls are red, panic calls flash. The call gets a map blip and a search radius for 2 minutes.
- **Statuses:** Available, En route, On scene, Busy, On break. Setting Available removes you from the calls you were responding to.
- **Unit blips:** on-duty units see each other on the map (updated every 3 s), coloured by service, named by callsign.

Calls are kept for 15 minutes (at most 60). They are not a record: reports belong in the MDT.

## For everyone

| Command | Goes to |
|---|---|
| `/911 <what is happening>` | Police and EMS (high priority), with your position, name and phone number |
| `/311 <message>` | Police (low priority) |

One public call every 30 s per player. The caller is told whether anyone is on duty.

## For other resources

```lua
exports.veyl_dispatch:Alert({
    services = { 'police' },          -- 'police', 'ems' (see Services in config.lua)
    code = '10-90', title = 'Store robbery', message = 'Silent alarm at 24/7 Innocence Blvd',
    coords = vector3(x, y, z), street = 'Innocence Blvd', priority = 1,   -- 1 urgent, 2 high, 3 low
    blip = { sprite = 161, colour = 1, scale = 1.2 },                       -- optional
})  -- returns the call id
```

`veyl_medical` sends its "Person down" alert through dispatch when dispatch is running.

## Configuration

`config.lua`: services and their jobs, keys, how long cards and blips stay, statuses, unit blips, the public call commands and their cooldown.
