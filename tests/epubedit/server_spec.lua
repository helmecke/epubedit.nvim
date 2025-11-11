local server = require("epubedit.server")

describe("Server", function()
  after_each(function()
    -- Ensure server is stopped after each test
    if server.is_running() then
      server.stop()
    end
  end)

  it("should not be running initially", function()
    assert.is_false(server.is_running())
    assert.is_nil(server.get_port())
  end)

  it("should start server on available port", function()
    -- Create a temporary directory to serve
    local tmp_dir = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/server-test-XXXXXX")
    assert.is_string(tmp_dir)

    local ok, err = server.start(tmp_dir)
    assert.is_true(ok, err)
    assert.is_nil(err)
    assert.is_true(server.is_running())
    assert.is_not_nil(server.get_port())
    assert.is_true(server.get_port() >= 8080)

    server.stop()
    assert.is_false(server.is_running())

    vim.fn.delete(tmp_dir, "rf")
  end)

  it("should reuse running server", function()
    local tmp_dir = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/server-test-XXXXXX")
    assert.is_string(tmp_dir)

    -- Start server first time
    local ok1, err1 = server.start(tmp_dir)
    assert.is_true(ok1, err1)
    local port1 = server.get_port()

    -- Start server second time (should reuse)
    local ok2, err2 = server.start(tmp_dir)
    assert.is_true(ok2, err2)
    local port2 = server.get_port()

    -- Should be same port (reused)
    assert.equals(port1, port2)

    server.stop()
    vim.fn.delete(tmp_dir, "rf")
  end)

  it("should detect browser command for current OS", function()
    -- Just verify it doesn't error
    -- The actual command depends on the OS
    local url = "http://127.0.0.1:8080/test.html"
    local ok, err = server.open_browser(url)

    -- Should succeed on Linux (including WSL), macOS, and Windows
    -- In WSL2 it should detect powershell.exe or cmd.exe
    assert.is_true(ok, err or "Browser detection failed")
  end)
end)
