-- xmlhandler.tree companion for xml2lua (MIT License)
-- Simplified tree handler based on https://github.com/manoelcampos/xml2lua

local TreeHandler = {}
TreeHandler.__index = TreeHandler

function TreeHandler:new()
  local obj = {
    root = { _children = {} },
    current = nil,
  }
  setmetatable(obj, self)

  obj.current = obj.root

  return obj
end

function TreeHandler:startElement(name, attrs)
  local node = { _name = name, _attr = attrs or {}, _children = {} }
  node._parent = self.current

  table.insert(self.current._children, node)

  self.current = node
end

function TreeHandler:endElement()
  if self.current._parent then
    self.current = self.current._parent
  end
end

function TreeHandler:text(text)
  text = text or ""
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text ~= "" then
    table.insert(self.current._children, text)
  end
end

function TreeHandler:close()
  while self.current._parent do
    self.current = self.current._parent
  end
end

return TreeHandler
