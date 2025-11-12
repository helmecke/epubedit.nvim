---Simple XML writer for generating well-formed XML
local M = {}
M.__index = M

function M:new()
  local obj = {
    output = {},
    stack = {},
  }
  setmetatable(obj, self)
  return obj
end

function M:writeProcessingInstruction(target, data)
  table.insert(self.output, string.format("<?%s %s?>", target, data))
end

function M:startElement(name)
  if self.pending_start then
    table.insert(self.output, ">")
    self.pending_start = false
  end

  table.insert(self.stack, name)
  table.insert(self.output, string.format("<%s", name))
  self.pending_start = true
  self.pending_attributes = {}
end

function M:writeAttribute(name, value)
  if not self.pending_start then
    error("Cannot write attribute without an open element")
  end

  -- Escape attribute value
  local escaped =
    tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")

  table.insert(self.output, string.format(' %s="%s"', name, escaped))
end

function M:text(content)
  if self.pending_start then
    table.insert(self.output, ">")
    self.pending_start = false
  end

  -- Escape text content
  local escaped = tostring(content):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")

  table.insert(self.output, escaped)
end

function M:endElement()
  if #self.stack == 0 then
    error("Cannot end element: no open elements")
  end

  local name = table.remove(self.stack)

  if self.pending_start then
    -- Empty element
    table.insert(self.output, "/>")
    self.pending_start = false
  else
    table.insert(self.output, string.format("</%s>", name))
  end
end

function M:toString()
  if #self.stack > 0 then
    error("Cannot convert to string: unclosed elements")
  end

  return table.concat(self.output, "")
end

return M
