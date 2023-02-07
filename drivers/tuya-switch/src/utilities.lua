local readAttribute = require "st.zigbee.zcl.global_commands.read_attribute"
local zclClusters = require "st.zigbee.zcl.clusters"
local zclMessages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zigbeeConstants = require "st.zigbee.constants"
local dataTypes = require "st.zigbee.data_types"
local genericBody = require "st.zigbee.generic_body"

local tuyaConstants = require "tuya-constants"
local tuyaCatalog = require "tuya-catalog"

local utilities = {
  common = {},
  zcl = {},
  tuya = {}
}

---------- COMMON ----------

function utilities.common.getChild(parent, index)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", index))
end

function utilities.common.findIndex(array, test)
  for i, insideValue in ipairs(array) do
    if test(insideValue) then return i end
  end
end

function utilities.common.getChildMetadata(device, key)
  return {
    type = "EDGE_CHILD",
    parent_assigned_child_key = string.format("%02X", key),
    label = device.label..' '..key,
    profile = "child-switch",
    parent_device_id = device.id,
    manufacturer = device:get_manufacturer(),
    model = device:get_model()
  }
end

---------- TUYA ----------

local PACKET_ID = 0

function utilities.tuya.sendCommand(device, dp, dpType, fncmd)

  -- address header
	local addressHeader = messages.AddressHeader(
		zigbeeConstants.HUB.ADDR,
		zigbeeConstants.HUB.ENDPOINT,
		device:get_short_address(),
		device:get_endpoint(tuyaConstants.CLUSTER_ID),
		zigbeeConstants.HA_PROFILE_ID,
		tuyaConstants.CLUSTER_ID
	)

  -- body
  local headerArgs = {
		cmd = dataTypes.ZCLCommandId(tuyaConstants.SET_DATA)
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

function utilities.tuya.getCatalogId(device)
  local catalogId = device:get_manufacturer().."/".. device:get_model()
  return catalogId
end

function utilities.tuya.createChildDevices(driver, device)
  local gangs = tuyaCatalog[utilities.tuya.getCatalogId(device)].gangs
  
  for gangIndex = 2, gangs do
    if utilities.common.getChild(device, gangIndex) == nil then
      local metadata = utilities.common.getChildMetadata(device, gangIndex)
      driver:try_create_device(metadata)
    end
  end
end

---------- ZCL ----------

function utilities.zcl.readAttributeFunction(device, clusterId, attrId)
  local readBody = readAttribute.ReadAttribute(attrId)
  local zclh = zclMessages.ZclHeader({
    cmd = dataTypes.ZCLCommandId(readAttribute.ReadAttribute.ID)
  })

  -- address header
  local addrh = messages.AddressHeader(
      zigbeeConstants.HUB.ADDR,
      zigbeeConstants.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(clusterId.value),
      zigbeeConstants.HA_PROFILE_ID,
      clusterId.value
  )

  -- body
  local message_body = zclMessages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = readBody
  })
  
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

function utilities.zcl.createChildDevices(driver, device)
  local epArray = {}

  for _, ep in pairs(device.zigbee_endpoints) do
    for _, clus in ipairs(ep.server_clusters) do
      if clus == zclClusters.OnOff.ID then
        table.insert(epArray, tonumber(ep.id))
        break
      end
    end
  end

  table.sort(epArray)
  
  for i, ep in pairs(epArray) do
    if ep ~= device.fingerprinted_endpoint_id and utilities.common.getChild(device, ep) == nil then
        local metadata = utilities.common.getChildMetadata(device, ep)
        driver:try_create_device(metadata)
    end
  end
end

return utilities