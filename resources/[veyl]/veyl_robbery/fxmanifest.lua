fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_robbery'
description 'VeylCore store robberies: registers at gunpoint, safes with a lockpick, police minimum, cooldowns, silent alarm to dispatch'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }
