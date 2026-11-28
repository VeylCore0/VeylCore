fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_admin'
description 'VeylCore staff tools: a custom admin menu (players, self tools, vehicles, world, reports, bans, logs, server) plus the staff commands'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_inventory' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua', 'server/menu.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua', 'client/menu.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
