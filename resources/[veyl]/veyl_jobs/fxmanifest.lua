fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_jobs'
description 'VeylCore job UI: duty toggle, multijob primary selection and quitting open jobs (core owns the data)'
version '0.2.0'

dependencies { 'veyl_core', 'veyl_ui' }

shared_script '@veyl_core/lib/shared.lua'
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client.lua' }
