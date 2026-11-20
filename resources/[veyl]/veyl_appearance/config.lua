AppearanceConfig = {
    Models = { m = 'mp_m_freemode_01', f = 'mp_f_freemode_01' },

    -- /appearance opens the editor anywhere. Set false once clothing shops exist.
    AllowCommand = true,

    Components = {
        { id = 1, label = 'Mask' }, { id = 2, label = 'Hair' }, { id = 3, label = 'Arms' },
        { id = 4, label = 'Legs' }, { id = 5, label = 'Bag' }, { id = 6, label = 'Shoes' },
        { id = 7, label = 'Accessory' }, { id = 8, label = 'Undershirt' }, { id = 11, label = 'Top' },
    },
    Props = {
        { id = 0, label = 'Hat' }, { id = 1, label = 'Glasses' }, { id = 2, label = 'Ears' },
        { id = 6, label = 'Watch' }, { id = 7, label = 'Bracelet' },
    },

    -- Reasonable clothed defaults for a brand-new character.
    Defaults = {
        m = { components = { [3] = { 15, 0 }, [4] = { 21, 0 }, [6] = { 34, 0 }, [8] = { 15, 0 }, [11] = { 15, 0 } } },
        f = { components = { [3] = { 15, 0 }, [4] = { 15, 0 }, [6] = { 35, 0 }, [8] = { 14, 0 }, [11] = { 18, 0 } } },
    },
}
