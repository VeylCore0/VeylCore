fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_departments'
description 'VeylCore departments: police and EMS vehicle garages (rank-locked, keys included) and supply lockers'
version '1.0.0'

dependencies { 'veyl_lib', 'veyl_core', 'veyl_ui', 'veyl_vehicles', 'veyl_inventory', 'veyl_interact', 'veyl_target' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server/main.lua' }
client_scripts { '@veyl_core/lib/client.lua', '@veyl_core/modules/playerdata.lua', 'client/main.lua' }
