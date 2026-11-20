-- vlib dialogs (client). Both yield the calling thread until the player answers.
--
-- vlib.inputDialog(title, fields, { submitLabel? }) -> values table | nil (cancelled/rejected)
--   fields = { { name, label, type = 'text'|'number'|'select'|'checkbox'|'date', required?, min?, max?, maxLength?,
--               placeholder?, default?, options? = { { value, label } } } }
-- vlib.alertDialog({ title, message, confirmLabel?, cancelLabel?, destructive? }) -> 'confirm' | 'cancel'

local M = {}

local VALID = { text = true, number = true, select = true, checkbox = true, date = true }

function M.inputDialog(title, fields, opts)
    if type(fields) ~= 'table' or #fields == 0 then error('vlib.inputDialog: fields required', 2) end
    local clean = {}
    for i, f in ipairs(fields) do
        if type(f.name) ~= 'string' then error(('vlib.inputDialog: field %d needs a name'):format(i), 2) end
        clean[i] = {
            name = f.name, label = tostring(f.label or f.name), type = VALID[f.type] and f.type or 'text',
            required = f.required == true, min = f.min, max = f.max, maxLength = f.maxLength,
            placeholder = f.placeholder, default = f.default, options = f.options,
        }
    end
    local p = promise.new()
    exports.veyl_lib:OpenForm({ title = tostring(title or 'Enter details'), submitLabel = opts and opts.submitLabel, fields = clean },
        function(result) p:resolve(result) end)
    local result = Citizen.Await(p)
    if type(result) == 'table' and result.type == 'submit' then return result.values end
    return nil
end

function M.alertDialog(data)
    data = type(data) == 'table' and data or {}
    local p = promise.new()
    exports.veyl_lib:OpenAlert({
        title = tostring(data.title or 'Are you sure?'), message = tostring(data.message or ''),
        confirmLabel = data.confirmLabel, cancelLabel = data.cancelLabel, destructive = data.destructive == true,
    }, function(result) p:resolve(result) end)
    local result = Citizen.Await(p)
    return (type(result) == 'table' and result.type == 'confirm') and 'confirm' or 'cancel'
end

return M
