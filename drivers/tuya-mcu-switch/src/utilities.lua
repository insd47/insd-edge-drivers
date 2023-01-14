local capabilities = require "st.capabilities"
local deviceCatalog = require "device-catalog"

local function getCatalogId(device)
  local catalogId = device:get_manufacturer().."/".. device:get_model()
  return catalogId
end

local function getChild(parent, index)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", index))
end

local function switchEvent(parent, index, fncmd)
  local device = index == 1 and parent or getChild(parent, index);

  if fncmd == 1 then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function createChildDevices(driver, device)
  local gangs = deviceCatalog[getCatalogId(device)].gangs
  
  for gangIndex = 2, gangs do
    if getChild(device, gangIndex) == nil then
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

local function findIndex(array, test)
  for i, insideValue in ipairs(array) do
    if test(insideValue) then return i end
  end
end

local utilities = {
  getCatalogId = getCatalogId,
  getChild = getChild,
  switchEvent = switchEvent,
  createChildDevices = createChildDevices,
  findIndex = findIndex
}

return utilities