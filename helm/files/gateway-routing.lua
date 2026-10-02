local function is_valid_engine(s)
  if s == nil or #s == 0 or #s > 63 then return false end
  if not string.match(s, "^[%l%d][-%l%d]*$") then return false end
  if string.sub(s, -1) == "-" then return false end
  return true
end

local function url_decode(value)
  local decoded = {}
  local i = 1
  while i <= #value do
    local c = string.sub(value, i, i)
    if c == "%" then
      local hex = string.sub(value, i + 1, i + 2)
      if #hex ~= 2 or not string.match(hex, "^%x%x$") then
        return nil
      end
      table.insert(decoded, string.char(tonumber(hex, 16)))
      i = i + 3
    elseif c == "+" then
      table.insert(decoded, " ")
      i = i + 1
    else
      table.insert(decoded, c)
      i = i + 1
    end
  end
  return table.concat(decoded)
end

-- Extracts exactly one engine query parameter and
-- removes it without decoding or re-encoding any
-- other parameter. The downstream SQL endpoint
-- interprets query parameters as settings and does
-- not support the routing-only engine setting.
local function extract_engine_from_path(path)
  if path == nil then return nil, path, nil end

  local query_start = string.find(path, "?", 1, true)
  if query_start == nil then return nil, path, nil end

  local base = string.sub(path, 1, query_start - 1)
  local query = string.sub(path, query_start + 1)
  local kept = {}
  local engine = nil
  local engine_count = 0

  for part in string.gmatch(query .. "&", "(.-)&") do
    local raw_key, raw_value = string.match(part, "^([^=]*)=(.*)$")
    if raw_key == nil then
      raw_key = part
      raw_value = ""
    end

    local key = url_decode(raw_key)
    if key == "engine" then
      engine_count = engine_count + 1
      if engine_count > 1 then
        return nil, path, "multiple engine query parameters"
      end
      engine = url_decode(raw_value)
      if engine == nil then
        return nil, path, "invalid engine query parameter encoding"
      end
    else
      table.insert(kept, part)
    end
  end

  if engine_count == 0 then return nil, path, nil end

  local stripped_query = table.concat(kept, "&")
  if stripped_query == "" then
    return engine, base, nil
  end
  return engine, base .. "?" .. stripped_query, nil
end

function envoy_on_request(handle)
  local headers = handle:headers()
  local header_engine = headers:get("x-firebolt-engine")
  local query_engine, stripped_path, query_error =
    extract_engine_from_path(headers:get(":path"))

  if query_error ~= nil then
    handle:respond({[":status"] = "400"}, query_error)
    return
  end

  local engine = query_engine
  if header_engine ~= nil then
    if not is_valid_engine(header_engine) then
      handle:respond({[":status"] = "400"}, "invalid X-Firebolt-Engine header")
      return
    end
    if query_engine ~= nil and query_engine ~= header_engine then
      handle:respond({[":status"] = "400"}, "conflicting engine selectors")
      return
    end
    engine = header_engine
  end

  if not is_valid_engine(engine) then
    handle:respond({[":status"] = "400"}, "invalid or missing engine selector")
    return
  end

  if query_engine ~= nil then
    headers:replace(":path", stripped_path)
  end
  headers:replace("x-firebolt-engine", engine)
  -- Keep the chart's supported-engine compatibility setting.
  local path = headers:get(":path")
  headers:replace(":path", path .. (path:find("?", 1, true) and "&" or "?") .. "advanced_mode=true")
  headers:replace(":authority", "{{ include "fbinstance.fullname" . }}-engine-" .. engine .. "-ready.{{ .Release.Namespace }}.svc.cluster.local:3473")

end
