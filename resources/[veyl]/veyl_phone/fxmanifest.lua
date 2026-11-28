fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_phone'
description 'VeylCore smartphone (base): numbers, settings, apps, notifications, contacts, messages, calls, mail'
version '2.0.0'

dependencies { 'oxmysql', 'veyl_lib', 'veyl_core', 'veyl_inventory' }

shared_scripts { '@veyl_lib/init.lua', '@veyl_core/lib/shared.lua', 'config.lua', 'shared/util.lua' }
server_scripts {
    '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua',
    'server/crypto.lua', 'server/core.lua', 'server/apps.lua', 'server/notify.lua', 'server/contacts.lua', 'server/messages.lua',
    'server/calls.lua', 'server/mail.lua', 'server/share.lua', 'server/security.lua',
    'server/notes.lua', 'server/bank.lua', 'server/garage.lua', 'server/market.lua', 'server/flock.lua', 'server/maps.lua', 'server/services.lua',
    'server/voicemail.lua', 'server/camera.lua', 'server/jobs.lua', 'server/bills.lua', 'server/music.lua', 'server/news.lua', 'server/racing.lua',
    'server/exports.lua', 'server/tablet.lua',
}
client_scripts { '@veyl_core/lib/client.lua', 'client/main.lua', 'client/apps.lua', 'client/tablet.lua' }

ui_page 'web/dist/index.html'
files { 'web/dist/index.html', 'web/dist/assets/*' }
