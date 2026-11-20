fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_jobs'
description 'VeylCore jobs: definitions, grades, assignment, duty and server-approved paychecks'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_banking' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
