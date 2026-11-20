-- Item definitions. weight in grams. `consume` effects are applied by veyl_needs; `heal` by veyl_inventory.
Items = {
    water_bottle = { label = 'Water bottle', weight = 500, usable = true, consume = { thirst = 35 }, anim = 'drink', useTime = 3000 },
    cola = { label = 'eCola', weight = 350, usable = true, consume = { thirst = 25, stress = -5 }, anim = 'drink', useTime = 3000 },
    coffee = { label = 'Bean Machine coffee', weight = 300, usable = true, consume = { thirst = 15, stress = -10 }, anim = 'drink', useTime = 3000 },
    sandwich = { label = 'Sandwich', weight = 300, usable = true, consume = { hunger = 35 }, anim = 'eat', useTime = 4000 },
    burger = { label = 'Burger', weight = 400, usable = true, consume = { hunger = 50 }, anim = 'eat', useTime = 5000 },
    bandage = { label = 'Bandage', weight = 100, usable = true, heal = 25, anim = 'bandage', useTime = 4000 },
    phone = { label = 'Phone', weight = 200, usable = false },
}
