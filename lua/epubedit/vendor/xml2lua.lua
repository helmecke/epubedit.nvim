-- xml2lua v1.0.5 (MIT License)
-- Source: https://github.com/manoelcampos/xml2lua (trimmed for project needs)

local xml2lua = {}

local function parseargs(s)
  local arg = {}
  s:gsub("([%-%w_]+)%s*=%s*([\"'])(.-)%2", function(w, _, a)
    arg[w] = a
  end)
  return arg
end

function xml2lua.parser(handler)
  local xml = {}

  function xml.parse(s)
    local stack = { handler.root }
    local top = handler.root
    local i = 1

    while true do
      local ni, j, c, label, xarg, empty = s:find("<(%/?)([%w:_%-%.]+)(.-)(%/?)>", i)
      if not ni then
        break
      end

      local text = s:sub(i, ni - 1)
      if not text:match("^%s*$") then
        handler:text(text)
      end

      if empty == "/" then
        handler:startElement(label, parseargs(xarg))
        handler:endElement(label)
      elseif c == "" then
        handler:startElement(label, parseargs(xarg))
        table.insert(stack, handler.current)
        top = handler.current
      else
        handler:endElement(label)
        table.remove(stack)
        top = stack[#stack]
      end

      i = j + 1
    end

    local text = s:sub(i)
    if not text:match("^%s*$") then
      handler:text(text)
    end

    handler:close()
  end

  return xml
end

return xml2lua
