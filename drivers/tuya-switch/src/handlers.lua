local stDevice = require "st.device"
local capabilities = require "st.capabilities"
local zclClusters = require "st.zigbee.zcl.clusters"
local Status = require "st.zigbee.generated.types.ZclStatus"

local utilities = require 'utilities'
local tuyaCatalog = require 'tuya-catalog'
local tuyaConstants = require 'tuya-constants'
local fields = require 'fields'

local OnOff = zclClusters.OnOff

local handlers = {
  common = {},
  zcl = {},
  tuya = {}
}

---------- COMMON ----------

function handlers.common.sendOn(driver, device)
  local isParent = device.network_type ~= stDevice.NETWORK_TYPE_CHILD
  local parent = isParent and device or device:get_parent_device()

  local deviceType = parent:get_field(fields.DEVICE_TYPE)
  local index

  if isParent then 
    index = deviceType == fields.TUYA and 1 or device.fingerprinted_endpoint_id
  else
    index = tonumber(device.parent_assigned_child_key)
  end

  handlers[deviceType].sendOn(parent, index)
end

function handlers.common.sendOff(driver, device)
  local isParent = device.network_type ~= stDevice.NETWORK_TYPE_CHILD
  local parent = isParent and device or device:get_parent_device()

  local deviceType = parent:get_field(fields.DEVICE_TYPE)
  local index

  if isParent then 
    index = deviceType == fields.TUYA and 1 or device.fingerprinted_endpoint_id
  else
    index = tonumber(device.parent_assigned_child_key)
  end

  handlers[deviceType].sendOff(parent, index)
end

---------- TUYA ----------

function handlers.tuya.receive(driver, parent, zb_rx)

  -- no zcl
  local deviceType = parent:get_field(fields.DEVICE_TYPE)
  if deviceType == fields.ZCL then return end

	local rx = zb_rx.body.zcl_body.body_bytes
	local dp = string.byte(rx:sub(3,3))
	local fncmdLen = string.unpack(">I2", rx:sub(5,6))
	local fncmd = string.unpack(">I"..fncmdLen, rx:sub(7))

  local dataPoints = tuyaCatalog[utilities.tuya.getCatalogId(parent)].dataPoints
  local switchIndex = utilities.common.findIndex(dataPoints, 
    function(insideValue)
      if string.byte(insideValue) == dp then return true
      else return false end
    end
  )

  local device = switchIndex == 1 and parent or utilities.common.getChild(parent, switchIndex)

  if fncmd == 1 then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

function handlers.tuya.sendOn(parent, index)
  local dataPoints = tuyaCatalog[utilities.tuya.getCatalogId(parent)].dataPoints
  local dp = dataPoints[index]

  utilities.tuya.sendTuyaCommand(parent, dp, tuyaConstants.DPType.BOOL, "\x01")
end

function handlers.tuya.sendOff(parent, index)
  local dataPoints = tuyaCatalog[utilities.tuya.getCatalogId(parent)].dataPoints
  local dp = dataPoints[index]

  utilities.tuya.sendTuyaCommand(parent, dp, tuyaConstants.DPType.BOOL, "\x00")
end

---------- ZCL ----------

function handlers.zcl.defaultHandler(driver, parent, zb_rx)
  if parent.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  -- no tuya
  local deviceType = parent:get_field(fields.DEVICE_TYPE)
  if deviceType == fields.TUYA then return end

  local status = zb_rx.body.zcl_body.status.value
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local device = srcEndpoint == parent.fingerprinted_endpoint_id and parent or utilities.common.getChild(parent, srcEndpoint)
  
  if status == Status.SUCCESS then
    local cmd = zb_rx.body.zcl_body.cmd.value

    if cmd == OnOff.server.commands.On.ID then
      device:emit_event(capabilities.switch.switch.on())
    elseif cmd == OnOff.server.commands.Off.ID then
      device:emit_event(capabilities.switch.switch.off())
    end
  end
end

function handlers.zcl.attrHandler(driver, parent, value, zb_rx)
  if parent.network_type == stDevice.NETWORK_TYPE_CHILD then return end

  -- no tuya
  local deviceType = parent:get_field(fields.DEVICE_TYPE)
  if deviceType == fields.TUYA then return end
  
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local attrValue = value.value

  local device = srcEndpoint == parent.fingerprinted_endpoint_id and parent or utilities.common.getChild(parent, srcEndpoint)

  if attrValue == false or attrValue == 0 then
    device:emit_event(capabilities.switch.switch.off())
  elseif attrValue == true or attrValue == 1 then
    device:emit_event(capabilities.switch.switch.on())
  end
end

function handlers.zcl.sendOn(parent, index)
  parent:send(OnOff.server.commands.On(parent):to_endpoint(index))
end

function handlers.zcl.sendOff(parent, index)
  parent:send(OnOff.server.commands.Off(parent):to_endpoint(index))
end

return handlers