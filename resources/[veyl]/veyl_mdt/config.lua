-- veyl_mdt configuration.

MdtConfig = {
    Jobs = { 'police' },     -- on-duty members of these jobs can use the MDT
    Command = 'mdt',
    Key = 'F10',             -- rebindable in Settings > Key Bindings > FiveM
    -- Licences shown on a profile (keys of metadata.licences)
    Licences = {
        { key = 'driver', label = "Driver's licence" },
        { key = 'weapon', label = 'Weapon licence' },
        { key = 'business', label = 'Business licence' },
    },
}
