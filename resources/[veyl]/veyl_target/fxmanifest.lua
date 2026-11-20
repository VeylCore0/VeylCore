fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_target'
author 'VeylCore'
description 'VeylCore targeting: entity/model/zone registrations, one raycast loop, custom overlay, display filters'
version '0.3.0'

dependency 'veyl_lib'

shared_scripts { '@veyl_lib/init.lua', 'config.lua' }
client_scripts {
    'client/registry.lua',
    'client/adapters.lua',
    'client/main.lua',
    'client/debug.lua',
}

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
