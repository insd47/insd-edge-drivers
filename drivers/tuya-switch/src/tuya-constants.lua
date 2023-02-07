local tuyaConstants = {
  CLUSTER_ID = 0xEF00,
  SET_DATA = 0x00,
  DPType = {
    RAW = "\x00",
    BOOL = "\x01",
    VALUE = "\x02",
    STRING = "\x03",
    ENUM = "\x04"
  }
}

return tuyaConstants