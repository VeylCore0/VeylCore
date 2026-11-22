-- veyl_business configuration. Locations assume the popular Bean Machine (West Vinewood) and Burger Shot (Del Perro)
-- interiors: move the points to match your MLOs. Money in whole dollars.

BusinessConfig = {
    LicenceRequired = 'business',   -- metadata.licences key needed to buy a business (sold at City Hall)
    SellBackShare = 0.5,            -- selling a business back returns this share of its price
    OrderGrade = 1,                 -- lowest grade allowed to order ingredients from the business account
    RegisterCommission = 0.10,      -- the employee's share of every register sale
    RegisterMax = 2000,

    Businesses = {
        beanmachine = {
            label = 'Bean Machine', job = 'beanmachine', price = 75000,
            office = vector3(-635.7, 227.9, 81.88),
            stash = vector3(-633.2, 225.1, 81.88),
            register = vector3(-631.2, 233.5, 81.88),
            blip = { sprite = 106, colour = 31 },
            supplies = {
                { item = 'coffee_beans', label = 'Coffee beans', price = 6 },
                { item = 'milk', label = 'Milk', price = 4 },
                { item = 'bread', label = 'Bread', price = 3 },
                { item = 'lettuce', label = 'Lettuce', price = 2 },
            },
            stations = {
                { label = 'Espresso machine', coords = vector3(-627.6, 230.6, 81.88), scenario = 'PROP_HUMAN_BBQ',
                  recipes = { { output = 'coffee', count = 1, seconds = 6, inputs = { coffee_beans = 1, milk = 1 } } } },
                { label = 'Sandwich counter', coords = vector3(-629.4, 227.8, 81.88), scenario = 'PROP_HUMAN_BBQ',
                  recipes = { { output = 'sandwich', count = 1, seconds = 8, inputs = { bread = 1, lettuce = 1 } } } },
            },
        },
        burgershot = {
            label = 'Burger Shot', job = 'burgershot', price = 90000,
            office = vector3(-1178.1, -896.0, 13.97),
            stash = vector3(-1196.4, -903.8, 13.97),
            register = vector3(-1194.9, -893.9, 13.97),
            blip = { sprite = 106, colour = 1 },
            supplies = {
                { item = 'burger_bun', label = 'Burger buns', price = 3 },
                { item = 'raw_patty', label = 'Raw patties', price = 6 },
                { item = 'lettuce', label = 'Lettuce', price = 2 },
                { item = 'potato', label = 'Potatoes', price = 2 },
                { item = 'sprunk', label = 'Sprunk cans', price = 3 },
            },
            stations = {
                { label = 'Grill', coords = vector3(-1202.9, -897.1, 13.97), scenario = 'PROP_HUMAN_BBQ',
                  recipes = { { output = 'burger', count = 1, seconds = 8, inputs = { burger_bun = 1, raw_patty = 1, lettuce = 1 } } } },
                { label = 'Fryer', coords = vector3(-1200.6, -896.6, 13.97), scenario = 'PROP_HUMAN_BBQ',
                  recipes = { { output = 'fries', count = 2, seconds = 6, inputs = { potato = 1 } } } },
            },
        },

        -- Car wash: customers drive into a bay and pay; the money goes to the business account (if it has an owner).
        carwash = {
            label = 'Hands On Car Wash', job = 'carwash', price = 60000,
            office = vector3(49.6, -1384.6, 29.4),
            stash = vector3(45.2, -1386.1, 29.4),
            register = vector3(47.9, -1389.0, 29.4),
            blip = { sprite = 100, colour = 3 },
            supplies = { { item = 'cleaning_kit', label = 'Cleaning kits', price = 8 } },
            stations = {},
            services = {
                { kind = 'wash', label = 'Wash bay 1', coords = vector3(26.5, -1391.9, 29.3), radius = 5.0, price = 60 },
                { kind = 'wash', label = 'Wash bay 2', coords = vector3(22.5, -1391.9, 29.3), radius = 5.0, price = 60 },
            },
        },
        -- Nightclub: bartenders mix drinks and sell them at the register; the door charges cover.
        nightclub = {
            label = 'Bahama Mamas', job = 'nightclub', price = 150000,
            office = vector3(-1371.1, -626.0, 30.8),
            stash = vector3(-1384.6, -627.2, 30.8),
            register = vector3(-1388.9, -606.0, 30.3),
            blip = { sprite = 93, colour = 27 },
            supplies = {
                { item = 'beer', label = 'Beer', price = 5 },
                { item = 'whiskey', label = 'Whiskey', price = 10 },
                { item = 'orange', label = 'Oranges', price = 3 },
                { item = 'sprunk', label = 'Sprunk cans', price = 3 },
            },
            stations = {
                { label = 'Bar', coords = vector3(-1391.3, -603.2, 30.3), scenario = 'PROP_HUMAN_BBQ',
                  recipes = { { output = 'cocktail', count = 1, seconds = 5, inputs = { orange = 1, sprunk = 1 } } } },
            },
            services = {
                { kind = 'cover', label = 'Entrance', coords = vector3(-1388.4, -586.6, 30.2), radius = 2.5, price = 50 },
            },
        },
        -- Pawn shop: anyone can sell valuables at the counter. Owned: the business account pays the full price and the
        -- goods go to the stockroom to resell. No owner: the city pays cityRate of the price and keeps the goods.
        pawnshop = {
            label = 'Pawn & Jewelry', job = 'pawnshop', price = 85000,
            office = vector3(172.0, -1316.5, 29.4),
            stash = vector3(175.1, -1314.0, 29.4),
            register = vector3(180.6, -1318.1, 29.4),
            blip = { sprite = 267, colour = 46 },
            supplies = {},
            stations = {},
            services = {
                { kind = 'pawn', label = 'Pawn counter', coords = vector3(182.6, -1319.7, 29.3), radius = 2.5, cityRate = 0.6,
                  prices = { rolex = 350, gold_chain = 280, diamond_ring = 600, gold_bar = 300, deer_antlers = 150, radio = 90,
                             phone = 120, flashlight = 20, repair_kit = 150, fishing_rod = 50 } },
            },
        },
        -- Tuner shop: tuners install performance kits on a customer's vehicle in the bay, then charge at the register.
        tunershop = {
            label = 'Tuner Shop', job = 'tunershop', price = 175000,
            office = vector3(-196.6, -1318.3, 31.1),
            stash = vector3(-210.0, -1340.0, 31.0),
            register = vector3(-200.4, -1314.9, 31.1),
            blip = { sprite = 446, colour = 5 },
            supplies = {
                { item = 'perf_brakes', label = 'Brake kits', price = 900 },
                { item = 'perf_suspension', label = 'Suspension kits', price = 900 },
                { item = 'perf_transmission', label = 'Transmission kits', price = 1400 },
                { item = 'perf_engine', label = 'Engine kits', price = 2200 },
                { item = 'perf_turbo', label = 'Turbo kits', price = 2500 },
            },
            stations = {},
            services = {
                { kind = 'tune', label = 'Tuning bay', coords = vector3(-212.7, -1324.0, 30.9), radius = 6.0,
                  kits = { perf_engine = { mod = 11 }, perf_brakes = { mod = 12 }, perf_transmission = { mod = 13 },
                           perf_suspension = { mod = 15 }, perf_turbo = { toggle = 18 } } },
            },
        },
    },
}
