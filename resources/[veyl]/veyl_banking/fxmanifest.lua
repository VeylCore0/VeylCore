fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_banking'
description 'VeylCore banking: cash/bank accounts, ledger, repeat-safe debits, credits and transfers'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_ui', 'veyl_interact' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/ledger.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
