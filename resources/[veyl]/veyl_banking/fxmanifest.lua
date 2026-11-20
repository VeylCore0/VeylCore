fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_banking'
description 'VeylCore banking UI: bank counters, deposits, withdrawals, transfers and history over veyl_core money'
version '0.2.0'

dependencies { 'veyl_core', 'veyl_ui', 'veyl_interact' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client.lua' }
