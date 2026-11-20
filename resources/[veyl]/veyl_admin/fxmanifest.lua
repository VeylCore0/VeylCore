fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_admin'
description 'VeylCore staff tools: player list, reports, teleports, economy/job/item tools with permission checks and audit logs'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui', 'veyl_banking', 'veyl_jobs', 'veyl_inventory' }

shared_script '@veyl_core/lib/shared.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
