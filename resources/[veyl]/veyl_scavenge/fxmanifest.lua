fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_scavenge'
description 'VeylCore dumpster diving: search every trash can, dumpster and garbage bag for configurable loot'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
