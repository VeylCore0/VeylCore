fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_mechanic'
description 'VeylCore mechanic: on-duty repairs that consume parts, service invoices paid through the core ledger'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory', 'veyl_interact' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
