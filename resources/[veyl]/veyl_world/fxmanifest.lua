fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_world'
description 'VeylCore shared clock and weather, ambient population settings'
version '0.1.0'

dependency 'veyl_core'

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
