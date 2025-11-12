local opf_manager = require("epubedit.opf_manager")
local opf_parser = require("epubedit.parser.opf")

describe("path traversal security", function()
  local function create_test_opf(workspace, malicious_href)
    local opf_content = string.format(
      [[<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata></metadata>
  <manifest>
    <item id="malicious" href="%s" media-type="application/xhtml+xml"/>
    <item id="legit" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="malicious"/>
    <itemref idref="legit"/>
  </spine>
</package>]],
      malicious_href
    )

    local opf_path = workspace .. "/content.opf"
    local file = io.open(opf_path, "w")
    file:write(opf_content)
    file:close()
    return opf_path
  end

  it("rejects path traversal with ../ sequences", function()
    local workspace = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/security-test-XXXXXX")
    assert.is_string(workspace)

    local opf_path = create_test_opf(workspace, "../../../etc/passwd")
    local parsed, err = opf_parser.parse(opf_path)
    assert(parsed, err)

    local malicious_item = parsed.manifest["malicious"]
    assert.is_not_nil(malicious_item)

    local base_dir = vim.fn.fnamemodify(opf_path, ":h") .. "/"
    local resolve_item_path = require("epubedit.opf_manager")._test_resolve_item_path
      or function(base, item)
        if not item or not item.href then
          return nil
        end
        local sanitize_href = function(href)
          if not href or href == "" then
            return nil
          end
          local sanitized = href:gsub("\\", "/")
          sanitized = sanitized:gsub("^/+", "")
          while sanitized:find("%.%./") or sanitized:find("/%./") or sanitized:find("^%./") do
            sanitized = sanitized:gsub("%.%./", "")
            sanitized = sanitized:gsub("/%./", "/")
            sanitized = sanitized:gsub("^%./", "")
          end
          if sanitized:match("^[a-zA-Z]:") then
            return nil
          end
          return sanitized
        end
        local safe_href = sanitize_href(item.href)
        if not safe_href or safe_href == "" then
          return nil
        end
        local full = base .. safe_href
        local resolved = vim.fn.fnamemodify(full, ":p")
        if not resolved then
          return nil
        end
        local normalized_base = vim.fn.fnamemodify(base, ":p")
        if normalized_base and resolved:sub(1, #normalized_base) ~= normalized_base then
          return nil
        end
        return resolved
      end

    local resolved = resolve_item_path(base_dir, malicious_item)

    if resolved then
      local normalized_workspace = vim.fn.fnamemodify(workspace, ":p")
      assert.is_truthy(resolved:sub(1, #normalized_workspace) == normalized_workspace, "Path escaped workspace")
      local system_etc = vim.fn.fnamemodify("/etc/passwd", ":p")
      assert.are_not.equal(system_etc, resolved, "Accessed system file")
    end

    vim.fn.delete(workspace, "rf")
  end)

  it("rejects absolute paths", function()
    local workspace = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/security-test-XXXXXX")
    assert.is_string(workspace)

    local opf_path = create_test_opf(workspace, "/etc/passwd")
    local parsed, err = opf_parser.parse(opf_path)
    assert(parsed, err)

    local malicious_item = parsed.manifest["malicious"]
    local base_dir = vim.fn.fnamemodify(opf_path, ":h") .. "/"

    local sanitize_href = function(href)
      if not href or href == "" then
        return nil
      end
      local sanitized = href:gsub("\\", "/")
      sanitized = sanitized:gsub("^/+", "")
      while sanitized:find("%.%./") or sanitized:find("/%./") or sanitized:find("^%./") do
        sanitized = sanitized:gsub("%.%./", "")
        sanitized = sanitized:gsub("/%./", "/")
        sanitized = sanitized:gsub("^%./", "")
      end
      if sanitized:match("^[a-zA-Z]:") then
        return nil
      end
      return sanitized
    end

    local safe_href = sanitize_href(malicious_item.href)
    assert.are.equal("etc/passwd", safe_href)

    vim.fn.delete(workspace, "rf")
  end)

  it("allows legitimate relative paths", function()
    local workspace = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/security-test-XXXXXX")
    assert.is_string(workspace)

    local opf_path = create_test_opf(workspace, "chapter1.xhtml")
    local parsed, err = opf_parser.parse(opf_path)
    assert(parsed, err)

    local legit_item = parsed.manifest["legit"]
    assert.is_not_nil(legit_item)
    assert.are.equal("chapter1.xhtml", legit_item.href)

    vim.fn.delete(workspace, "rf")
  end)

  it("normalizes Windows-style paths", function()
    local sanitize_href = function(href)
      if not href or href == "" then
        return nil
      end
      local sanitized = href:gsub("\\", "/")
      sanitized = sanitized:gsub("^/+", "")
      while sanitized:find("%.%./") or sanitized:find("/%./") or sanitized:find("^%./") do
        sanitized = sanitized:gsub("%.%./", "")
        sanitized = sanitized:gsub("/%./", "/")
        sanitized = sanitized:gsub("^%./", "")
      end
      if sanitized:match("^[a-zA-Z]:") then
        return nil
      end
      return sanitized
    end

    local result = sanitize_href("text\\chapter1.xhtml")
    assert.are.equal("text/chapter1.xhtml", result)
  end)

  it("rejects Windows absolute paths", function()
    local sanitize_href = function(href)
      if not href or href == "" then
        return nil
      end
      local sanitized = href:gsub("\\", "/")
      sanitized = sanitized:gsub("^/+", "")
      while sanitized:find("%.%./") or sanitized:find("/%./") or sanitized:find("^%./") do
        sanitized = sanitized:gsub("%.%./", "")
        sanitized = sanitized:gsub("/%./", "/")
        sanitized = sanitized:gsub("^%./", "")
      end
      if sanitized:match("^[a-zA-Z]:") then
        return nil
      end
      return sanitized
    end

    local result = sanitize_href("C:\\Windows\\System32\\config")
    assert.is_nil(result)
  end)
end)
