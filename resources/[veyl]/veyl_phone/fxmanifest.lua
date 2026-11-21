fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_phone'
description 'VeylCore smartphone: identity, contacts, notifications, messages, voice-adapter calls (milestones 1-3)'
version '0.1.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server/core.lua', 'server/notify.lua', 'server/contacts.lua',
    'server/messages.lua', 'server/calls.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
