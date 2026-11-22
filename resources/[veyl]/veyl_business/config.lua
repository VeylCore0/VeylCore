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
    },
}
