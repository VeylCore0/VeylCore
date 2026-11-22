fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_medical'
description 'VeylCore medical: downed and unconscious states, EMS revives and treatment, first aid, hospital respawn and check-in'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_inventory', 'veyl_interact', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua', 'server/injuries.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua', 'client/injuries.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
