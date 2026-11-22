fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_doctor'
description 'VeylCore health check: resources, database, settings and item pictures (console: veylcheck)'
version '1.0.0'

dependencies { 'oxmysql' }

server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
