fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_migrate'
description 'VeylCore migration: import characters, money, jobs, inventories and vehicles from QBCore or QBox (console: veylmigrate)'
version '1.0.0'

dependencies { 'oxmysql', 'veyl_core', 'veyl_inventory' }

server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
