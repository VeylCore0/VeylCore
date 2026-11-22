fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_hud'
description 'VeylCore HUD (Ocean Drive): player status, voice, money, location, native minimap, vehicle instruments per vehicle type, settings menu and position editor'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
client_scripts {
    '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua',
    'bridge/framework.lua', 'bridge/voice.lua', 'bridge/fuel.lua', 'bridge/seatbelt.lua', 'bridge/postal.lua',
    'client/settings.lua', 'client/minimap.lua', 'client/main.lua',
}

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*', 'data/*.json' }

-- Optional: stream/circlemap.ytd (texture `radarmasksm`) enables the Circle minimap. See docs/HUD.md.
