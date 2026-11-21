fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_vehicles'
description 'VeylCore vehicle service: authorized server spawns, stable ids, owned-vehicle storage and cleanup ownership'
version '0.3.0'

dependencies { '/onesync', 'oxmysql', 'veyl_core' }

shared_scripts { '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua', 'seatbelt.lua' }

-- Vehicle pictures (one <model>.webp per base-game model) used by the garage and dealership UIs:
-- nui://veyl_vehicles/web/images/<model>.webp
files { 'web/images/*.webp' }
