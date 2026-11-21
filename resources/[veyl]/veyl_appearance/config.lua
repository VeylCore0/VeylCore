AppearanceConfig = {
    Models = { m = 'mp_m_freemode_01', f = 'mp_f_freemode_01' },

    -- /appearance opens the full editor anywhere, free. 'admin' = only players with the veyl.admin ACE; true = everyone
    -- (development only); false = off.
    AllowCommand = 'admin',

    -- Which category groups each mode may change. The server enforces this; everything else is kept from the saved look.
    Modes = {
        create   = { groups = { 'character', 'face', 'skin', 'hair', 'clothing', 'accessories' } },
        admin    = { groups = { 'character', 'face', 'skin', 'hair', 'clothing', 'accessories' } },
        clothing = { groups = { 'clothing', 'accessories' } },
        barber   = { groups = { 'hair' } },
    },

    -- Every editable category. key = stable name (used for prices and the UI); camera = where the camera focuses.
    -- kind: component/prop = clothing slot, overlay = head overlay (beard, makeup, ...), plus the special
    -- heritage/features/eyes editors. color = 'hair' or 'makeup' palette; color2 = second colour (hair highlight).
    Categories = {
        { key = 'heritage',  group = 'character',   label = 'Heritage',      icon = 'dna',      camera = 'head', kind = 'heritage' },
        { key = 'features',  group = 'face',        label = 'Face shape',    icon = 'face',     camera = 'head', kind = 'features' },
        { key = 'eyes',      group = 'face',        label = 'Eye colour',    icon = 'eye',      camera = 'head', kind = 'eyes' },
        { key = 'blemishes', group = 'skin',        label = 'Blemishes',     icon = 'face',     camera = 'head', kind = 'overlay', id = 0 },
        { key = 'ageing',    group = 'skin',        label = 'Ageing',        icon = 'face',     camera = 'head', kind = 'overlay', id = 3 },
        { key = 'complexion',group = 'skin',        label = 'Complexion',    icon = 'face',     camera = 'head', kind = 'overlay', id = 6 },
        { key = 'sundamage', group = 'skin',        label = 'Sun damage',    icon = 'face',     camera = 'head', kind = 'overlay', id = 7 },
        { key = 'freckles',  group = 'skin',        label = 'Moles & freckles', icon = 'face',  camera = 'head', kind = 'overlay', id = 9 },
        { key = 'hair',      group = 'hair',        label = 'Hairstyle',     icon = 'scissors', camera = 'head', kind = 'component', id = 2, color = 'hair', color2 = true },
        { key = 'beard',     group = 'hair',        label = 'Beard',         icon = 'beard',    camera = 'head', kind = 'overlay', id = 1, color = 'hair' },
        { key = 'eyebrows',  group = 'hair',        label = 'Eyebrows',      icon = 'eye',      camera = 'head', kind = 'overlay', id = 2, color = 'hair' },
        { key = 'chesthair', group = 'hair',        label = 'Chest hair',    icon = 'user',     camera = 'body', kind = 'overlay', id = 10, color = 'hair' },
        { key = 'makeup',    group = 'hair',        label = 'Eye makeup',    icon = 'sparkle',  camera = 'head', kind = 'overlay', id = 4 },
        { key = 'blush',     group = 'hair',        label = 'Blush',         icon = 'sparkle',  camera = 'head', kind = 'overlay', id = 5, color = 'makeup' },
        { key = 'lipstick',  group = 'hair',        label = 'Lipstick',      icon = 'sparkle',  camera = 'head', kind = 'overlay', id = 8, color = 'makeup' },
        { key = 'tops',      group = 'clothing',    label = 'Jackets & tops',icon = 'shirt',    camera = 'body', kind = 'component', id = 11 },
        { key = 'undershirt',group = 'clothing',    label = 'Undershirts',   icon = 'shirt',    camera = 'body', kind = 'component', id = 8 },
        { key = 'arms',      group = 'clothing',    label = 'Arms & gloves', icon = 'hand',     camera = 'body', kind = 'component', id = 3 },
        { key = 'legs',      group = 'clothing',    label = 'Pants',         icon = 'pants',    camera = 'legs', kind = 'component', id = 4 },
        { key = 'shoes',     group = 'clothing',    label = 'Shoes',         icon = 'shoe',     camera = 'feet', kind = 'component', id = 6 },
        { key = 'bag',       group = 'clothing',    label = 'Bags',          icon = 'bag',      camera = 'body', kind = 'component', id = 5 },
        { key = 'neck',      group = 'clothing',    label = 'Chains & ties', icon = 'jewel',    camera = 'body', kind = 'component', id = 7 },
        { key = 'mask',      group = 'clothing',    label = 'Masks',         icon = 'mask',     camera = 'head', kind = 'component', id = 1 },
        { key = 'hat',       group = 'accessories', label = 'Hats',          icon = 'hat',      camera = 'head', kind = 'prop', id = 0 },
        { key = 'glasses',   group = 'accessories', label = 'Glasses',       icon = 'glasses',  camera = 'head', kind = 'prop', id = 1 },
        { key = 'ears',      group = 'accessories', label = 'Earrings',      icon = 'jewel',    camera = 'head', kind = 'prop', id = 2 },
        { key = 'watch',     group = 'accessories', label = 'Watches',       icon = 'watch',    camera = 'body', kind = 'prop', id = 6 },
        { key = 'bracelet',  group = 'accessories', label = 'Bracelets',     icon = 'jewel',    camera = 'body', kind = 'prop', id = 7 },
    },

    -- Price per changed category in clothing stores and barbers (whole dollars). A change back to something in one of your
    -- saved outfits is free.
    Prices = {
        tops = 60, undershirt = 30, arms = 20, legs = 45, shoes = 40, bag = 35, neck = 25, mask = 30,
        hat = 25, glasses = 30, ears = 40, watch = 80, bracelet = 50,
        hair = 30, beard = 20, eyebrows = 10, chesthair = 10, makeup = 15, blush = 10, lipstick = 10,
    },
    PaymentMethods = { 'cash', 'bank' },
    MaxOutfits = 20,

    -- Store locations. radius = how close you must be to open it (the server allows a little extra for latency).
    Stores = {
        clothing = {
            label = 'Clothing Store', subtitle = 'Clothes and accessories', icon = 'shirt', option = 'Browse clothing', radius = 3.0,
            blip = { sprite = 73, colour = 27, scale = 0.7 },
            locations = {
                vector3(75.95, -1392.89, 29.38), vector3(-712.22, -155.35, 37.42), vector3(-162.66, -303.40, 39.73),
                vector3(425.24, -806.01, 29.49), vector3(-822.19, -1074.13, 11.33), vector3(-1450.71, -236.83, 49.81),
                vector3(4.25, 6512.81, 31.88), vector3(121.76, -224.60, 54.56), vector3(1693.45, 4823.17, 42.10),
                vector3(615.18, 2762.93, 42.09), vector3(1196.79, 2709.56, 38.22), vector3(-1192.94, -772.69, 17.33),
                vector3(-3171.45, 1043.86, 20.86), vector3(-1100.96, 2710.21, 19.11), vector3(-1207.65, -1456.88, 4.38),
            },
        },
        barber = {
            label = 'Barber Shop', subtitle = 'Hair, beards and makeup', icon = 'scissors', option = 'Get a haircut', radius = 3.0,
            blip = { sprite = 71, colour = 27, scale = 0.7 },
            locations = {
                vector3(-814.3, -183.8, 37.6), vector3(136.8, -1708.4, 29.3), vector3(-1282.6, -1116.8, 7.0),
                vector3(1931.5, 3729.7, 32.8), vector3(1212.8, -472.9, 66.2), vector3(-32.9, -152.3, 57.1),
                vector3(-278.1, 6228.5, 31.7),
            },
        },
    },

    -- Camera framing per focus: z = height offset from the ped's root, dist = distance in front, fov.
    Cameras = {
        head = { z = 0.65, dist = 0.75, fov = 38.0 },
        body = { z = 0.25, dist = 1.45, fov = 42.0 },
        legs = { z = -0.45, dist = 1.35, fov = 42.0 },
        feet = { z = -0.85, dist = 1.05, fov = 40.0 },
        full = { z = 0.0, dist = 2.6, fov = 45.0 },
    },

    -- Reasonable clothed defaults for a brand-new character.
    Defaults = {
        m = { components = { [3] = { 15, 0 }, [4] = { 21, 0 }, [6] = { 34, 0 }, [8] = { 15, 0 }, [11] = { 15, 0 } } },
        f = { components = { [3] = { 15, 0 }, [4] = { 15, 0 }, [6] = { 35, 0 }, [8] = { 14, 0 }, [11] = { 18, 0 } } },
    },
}
