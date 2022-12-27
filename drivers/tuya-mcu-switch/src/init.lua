local stDevice = require "st.device"
local capabilities = require "st.capabilities"
local zigbeeDriver = require "st.zigbee"
local zclMessages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local dataTypes = require "st.zigbee.data_types"
local zigbeeConstants = require "st.zigbee.constants"
local genericBody = require "st.zigbee.generic_body"
local _log = require "log"

local deviceCatalog = require "device-catalog"

---------- FIELDS ----------

local GANGS = "gangs"
local DATAPOINTS = "dataPoints"

---------- TUYA MCU COMMUNICATIONS ----------

local TUYA_CLUSTER_ID = 0xEF00 -- Tuya MCU Cluster
local SET_DATA = 0x00

local TuyaDPType = { -- Tuya DataPoint Types
  RAW = "\x00",
  BOOL = "\x01",
  VALUE = "\x02",
  STRING = "\x03",
  ENUM = "\x04"
}

---------- SEND TUYA COMMAND ----------

local PACKET_ID = 0

local function sendTuyaCommand(device, dp, dpType, fncmd)

  -- address header
	local addressHeader = messages.AddressHeader(
		zigbeeConstants.HUB.ADDR,
		zigbeeConstants.HUB.ENDPOINT,
		device:get_short_address(),
		device:get_endpoint(TUYA_CLUSTER_ID),
		zigbeeConstants.HA_PROFILE_ID,
		TUYA_CLUSTER_ID
	)

  -- body
  local headerArgs = {
		cmd = dataTypes.ZCLCommandId(SET_DATA)
	}
	local zclHeader = zclMessages.ZclHeader(headerArgs)
	zclHeader.frame_ctrl:set_cluster_specific()

  PACKET_ID = (PACKET_ID + 1) % 65536
	local fncmd_len = string.len(fncmd)
	local payloadBody = genericBody.GenericBody(string.pack(">I2", PACKET_ID) .. dp .. dpType .. string.pack(">I2", fncmd_len) .. fncmd)
	local messageBody = zclMessages.ZclMessageBody({
		zcl_header = zclHeader,
		zcl_body = payloadBody
	})

  -- send
	local finalMessage = messages.ZigbeeMessageTx({
		address_header = addressHeader,
		body = messageBody
	})
	device:send(finalMessage)
end

---------- UTILITIES ----------

local function getCatalogId(device)
  local catalogId = device:get_manufacturer().."_".. device:get_model()
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
  local gangs = device:get_field(GANGS)
  
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

---------- HANDLERS ----------

local function tuyaMCUHandler(driver, device, zb_rx)
	local rx = zb_rx.body.zcl_body.body_bytes
	local dp = string.byte(rx:sub(3,3))
	local fncmdLen = string.unpack(">I2", rx:sub(5,6))
	local fncmd = string.unpack(">I"..fncmdLen, rx:sub(7))

  local dataPoints = device:get_field(DATAPOINTS)
  local switchIndex = findIndex(dataPoints, 
    function(insideValue)
      if string.byte(insideValue) == dp then return true
      else return false end
    end
  )

  switchEvent(device, switchIndex, fncmd)
end

local function tuyaOnOffHandler(driver, device, capabilityCommand)
  local isParent = device.network_type ~= stDevice.NETWORK_TYPE_CHILD
  local dataPoints = device:get_field(DATAPOINTS)

  local index = isParent and 1 or tonumber(device.parent_assigned_child_key)
  local dataPoint = dataPoints[index]
  local commandName = capabilityCommand.command == "on" and "\x01" or "\x00"
  local parent = isParent and device or device:get_parent_device()

  sendTuyaCommand(parent, dataPoint, TuyaDPType.BOOL, commandName)
end

---------- LIFECYCLES ----------

local function deviceAdded(driver, device)
  if device.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  createChildDevices(driver, device)
end

local function deviceInit(driver, device)
  if device.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  -- store device information
  local gangs = deviceCatalog[getCatalogId(device)].gangs
  local dataPoints = deviceCatalog[getCatalogId(device)].dataPoints

  device:set_field(GANGS, gangs)
  device:set_field(DATAPOINTS, dataPoints)

  device:set_find_child(getChild)
end

---------- DRIVER ----------

local tuyaMCUSwitch = {
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = tuyaOnOffHandler,
      [capabilities.switch.commands.off.NAME] = tuyaOnOffHandler,
    },
  },
  zigbee_handlers = {
    cluster = {
			[TUYA_CLUSTER_ID] = {
				[0x01] = tuyaMCUHandler,
				[0x02] = tuyaMCUHandler
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

local switchDriver = zigbeeDriver("tuya-mcu-switch", tuyaMCUSwitch)
switchDriver:run()