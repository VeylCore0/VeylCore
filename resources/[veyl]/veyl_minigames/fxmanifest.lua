fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_minigames'
description 'VeylCore mini games: lockpick (registers, safes, doors), car door tumbler and hotwire'
version '0.1.0'

dependencies { 'veyl_lib', 'veyl_core' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }

ui_page 'web/index.html'
files { 'web/index.html' }
