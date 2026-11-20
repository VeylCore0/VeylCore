fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_fuel'
description 'VeylCore fuel: server-side consumption for VeylCore vehicles, fuel stations, paid refuelling'
version '0.2.0'

dependencies { '/onesync', 'veyl_core', 'veyl_ui', 'veyl_interact', 'veyl_vehicles' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
