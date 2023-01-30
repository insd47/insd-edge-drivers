local capabilities = require "st.capabilities"
local deviceCatalog = require "device-catalog"

local utilities = {}

function utilities.getCatalogId(device)
  local catalogId = device:get_manufacturer().."/".. device:get_model()
  return catalogId
end

function utilities.getChild(parent, index)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", index))
end

function utilities.switchEvent(parent, index, fncmd)
  local device = index == 1 and parent or utilities.getChild(parent, index);

  if fncmd == 1 then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

function utilities.createChildDevices(driver, device)
  local gangs = deviceCatalog[utilities.getCatalogId(device)].gangs
  
  for gangIndex = 2, gangs do
    if utilities.getChild(device, gangIndex) == nil then
      local metadata = {
        type = "EDGE_CHILD",
        parent_assigned_child_key = string.format("%02X", gangIndex),
        label = device.label..'/'..gangIndex,
        profile = "child-switch",
        parent_device_id = device.id,
        manufacturer = device:get_manufacturer(),
        model = device:get_model()
      }
      driver:try_create_device(metadata)
    end
  end
end

function utilities.findIndex(array, test)
  for i, insideValue in ipairs(array) do
    if test(insideValue) then return i end
  end
end

return utilities