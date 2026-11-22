fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_crafting'
description 'VeylCore crafting: benches, recipes from job materials, crafting levels'
version '0.1.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_interact', 'veyl_inventory' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
