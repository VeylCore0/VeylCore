DealershipConfig = {
    Shop = 'pdm',                                  -- veyl_core/shared/vehicles.lua entries with shop = 'pdm' are for sale
    Label = 'Premium Deluxe Motorsport',
    Subtitle = 'New vehicles, registered to you on purchase.',
    PaymentMethods = { 'cash', 'bank' },
    UseRadius = 3.0,

    -- Salesperson inside the showroom and the delivery bay outside. Adjust if your map edits move the showroom.
    Salesperson = { model = 'cs_siemonyetarian', coords = vector4(-56.48, -1096.32, 26.42, 117.0) },
    Delivery = vector4(-56.79, -1109.85, 26.43, 71.5),
    -- If the delivery bay is blocked, the new vehicle is registered and parked here instead (garage id from veyl_garages).
    FallbackGarage = 'legion',

    Blip = { sprite = 326, colour = 27, scale = 0.75 },

    Categories = {
        { id = 'compacts', label = 'Compacts' }, { id = 'sedans', label = 'Sedans' }, { id = 'coupes', label = 'Coupes' },
        { id = 'suvs', label = 'SUVs' }, { id = 'muscle', label = 'Muscle' }, { id = 'sports', label = 'Sports' },
        { id = 'offroad', label = 'Off-road' }, { id = 'motorcycles', label = 'Motorcycles' }, { id = 'vans', label = 'Vans' },
    },
}
