fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'veyl_qbexample'
description 'Example: a QBCore-style resource running on VeylCore through the qb-core shim'
version '0.2.0'

dependencies { 'qb-core', 'veyl_core' }

shared_script '@qb-core/shared/locale.lua'
server_script 'server.lua'
client_script 'client.lua'
