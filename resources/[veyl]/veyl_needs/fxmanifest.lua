fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_needs'
description 'VeylCore needs: decay and consumable effects on core metadata (hunger, thirst, stress)'
version '0.2.0'

dependency 'veyl_core'

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
