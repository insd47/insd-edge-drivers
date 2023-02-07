local stDevice = require "st.device"
local capabilities = require "st.capabilities"
local zigbeeDriver = require "st.zigbee"
local zclClusters = require "st.zigbee.zcl.clusters"
local zclGlobalCommands = require "st.zigbee.zcl.global_commands"
local dataTypes = require "st.zigbee.data_types"
-- local _log = require "log"

local OnOff = zclClusters.OnOff

local handlers = require "handlers"
local tuyaCatalog = require "tuya-catalog"
local utilities = require "utilities"
local tuyaConstants = require "tuya-constants"
local fields = require 'fields'

---------- LIFECYCLES ----------

local function deviceAdded(driver, device)
  if device.network_type ~= stDevice.NETWORK_TYPE_CHILD then -- parent
    local deviceType

    if tuyaCatalog[utilities.tuya.getCatalogId(device)] == nil then
      deviceType = fields.ZCL
    else
      deviceType = fields.TUYA
    end

    device:set_field(fields.DEVICE_TYPE, deviceType, { persist = true })
    utilities[deviceType].createChildDevices(driver, device)

    if deviceType == fields.ZCL then
      device:send(OnOff.attributes.OnOff:read(device):to_endpoint(device.fingerprinted_endpoint_id))
    end
  else -- child
    local parent = device:get_parent_device()
    if parent:get_field(fields.DEVICE_TYPE) == fields.ZCL then
      device:send(OnOff.attributes.OnOff:read(device):to_endpoint(tonumber(device.parent_assigned_child_key))) 
    end
  end
end

local function deviceInit(driver, device)
  if device.network_type == stDevice.NETWORK_TYPE_CHILD then return end;

  local deviceType

  if tuyaCatalog[utilities.tuya.getCatalogId(device)] == nil then
    deviceType = fields.ZCL
  else
    deviceType = fields.TUYA
  end

  if deviceType == fields.ZCL then
    local attrIds = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xFFFE}
    device:send(utilities.zcl.readAttributeFunction(device, dataTypes.ClusterId(0x0000), attrIds))
  end
end

---------- DRIVER ----------

local config = {
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handlers.common.sendOn,
      [capabilities.switch.commands.off.NAME] = handlers.common.sendOff,
    },
  },
  zigbee_handlers = {
    global = {
      [OnOff.ID] = {
        [zclGlobalCommands.DEFAULT_RESPONSE_ID] = handlers.zcl.defaultHandler
      }
    },
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = handlers.zcl.attrHandler
      },
    },
    cluster = {
			[tuyaConstants.CLUSTER_ID] = {
				[0x01] = handlers.tuya.receive,
				[0x02] = handlers.tuya.receive
			}
		}
  },
  lifecycle_handlers = {
    added = deviceAdded,
    init = deviceInit
  },
  supported_capabilities = {
    capabilities.switch
  }
}

local switchDriver = zigbeeDriver("tuya-switch", config)
switchDriver:run()