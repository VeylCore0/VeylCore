fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_spawn'
description 'VeylCore spawn pipeline: bounded stages, last-location recovery, fallbacks and basic death/respawn'
version '0.2.0'

dependencies { 'veyl_core', 'veyl_ui', 'veyl_appearance' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
