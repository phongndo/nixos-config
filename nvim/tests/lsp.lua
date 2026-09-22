-- Run with the configured plugins and server executables available:
-- nvim --headless -i NONE -u ./nvim/init.lua -l ./nvim/tests/lsp.lua
local root = vim.fn.tempname()
local published = {}
local original_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  if result then
    published[result.uri] = result.diagnostics
  end
  return original_handler(err, result, ctx, config)
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. path), "p")
  vim.fn.writefile(lines, root .. "/" .. path)
end

local function wait_for(predicate, description)
  assert(vim.wait(20000, predicate, 50), "Timed out: " .. description)
end

local function run()
  for _, executable in ipairs({ "zig", "ocamlformat-rpc" }) do
    assert(vim.fn.executable(executable) == 1, "Missing server companion: " .. executable)
  end
  local diagnostics = vim.diagnostic.config()
  assert(not diagnostics.virtual_text and not diagnostics.virtual_lines, "Inline diagnostics should be quiet")
  assert(diagnostics.signs and diagnostics.underline, "Diagnostics must remain visible")
  assert(not diagnostics.update_in_insert, "Do not update diagnostics during insertion")

  vim.fn.mkdir(root .. "/.git", "p")
  write("Cargo.toml", { '[package]', 'name = "lsp-smoke"', 'version = "0.1.0"', 'edition = "2021"' })
  write("dune-project", { "(lang dune 3.0)" })
  write("package.json", { '{"private":true}' })
  write("tsconfig.json", { '{"compilerOptions":{"jsx":"preserve","noEmit":true}}' })
  write("include/config.h", { "#define CONFIGURED_VALUE 42" })
  write("compile_commands.json", { vim.json.encode({ {
    directory = root,
    file = root .. "/main.cpp",
    arguments = { "clang++", "-std=c++20", "-DANSWER=42", "-I" .. root .. "/include", "-c", root .. "/main.cpp" },
  } }) })

  local cases = {
    { "clangd", "main.cpp", { '#include "config.h"', "static_assert(ANSWER == CONFIGURED_VALUE);", "int main() { return 0; }" } },
    { "clangd", "main.c", { "int main(void) { return 0; }" } },
    { "pyright", "main.py", { "answer: int = 42" } },
    { "rust_analyzer", "src/main.rs", { "fn main() {}" } },
    { "zls", "main.zig", { "pub fn main() void {}" } },
    { "ocamllsp", "main.ml", { "let answer = 42" } },
    { "ocamllsp", "main.mli", { "val answer : int" } },
    { "ts_ls", "main.js", { "const answer = 42;" } },
    { "ts_ls", "component.jsx", { "const Answer = () => <div />;" } },
    { "ts_ls", "main.ts", { "const answer: number = 42;" } },
    { "ts_ls", "component.tsx", { "const Answer = () => <div />;" } },
    { "bashls", "main.sh", { "#!/usr/bin/env bash", "echo hello" } },
    { "cssls", "main.css", { "body { color: red; }" } },
    { "html", "main.html", { "<!doctype html><html><body>Hello</body></html>" } },
    { "jsonls", "main.json", { '{"answer":42}' } },
    { "yamlls", "main.yaml", { "answer: 42" } },
    { "nixd", "main.nix", { "{ answer = 42; }" } },
  }

  for _, case in ipairs(cases) do
    local server, file, lines = unpack(case)
    assert(vim.lsp.is_enabled(server), server .. " is not enabled")
    write(file, lines)
    vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. file))
    local bufnr = vim.api.nvim_get_current_buf()
    wait_for(function()
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = server })
      return #clients == 1 and clients[1].initialized
    end, server .. " attaching to " .. file)
    assert(#vim.lsp.get_clients({ bufnr = bufnr }) == 1, "Duplicate servers attached to " .. file)
    for lhs, callback in pairs({
      gd = vim.lsp.buf.definition,
      gr = vim.lsp.buf.references,
      gi = vim.lsp.buf.implementation,
      ["<Space>r"] = vim.lsp.buf.rename,
      ["<Space>a"] = vim.lsp.buf.code_action,
    }) do
      local mapping = vim.fn.maparg(lhs, "n", false, true)
      assert(mapping.buffer == 1 and mapping.callback == callback, "Wrong or missing mapping: " .. lhs)
    end
    assert(vim.fn.maparg("gr", "n", false, true).nowait == 1, "References should not wait for longer mappings")
    assert(vim.fn.maparg("<Space>a", "x", false, true).callback == vim.lsp.buf.code_action, "Missing selection actions")
    local client = vim.lsp.get_clients({ bufnr = bufnr })[1]
    assert(client.config.capabilities.textDocument.completion.completionItem.snippetSupport, "Missing Blink capabilities")
    print("PASS " .. file .. " -> " .. server)

    if file == "main.cpp" then
      local uri = vim.uri_from_bufnr(bufnr)
      wait_for(function() return published[uri] ~= nil end, "initial C++ diagnostics")
      assert(#published[uri] == 0, "clangd did not use project flags: " .. vim.inspect(published[uri]))
      -- Prove that a quiet display has not disabled genuine diagnostics.
      published[uri] = nil
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'int broken = "not an int";' })
      wait_for(function() return published[uri] and #published[uri] > 0 end, "real C++ error")
      assert(#vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR }) > 0, "Real errors must be retained")
      published[uri] = nil
      vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, {})
      wait_for(function() return published[uri] and #published[uri] == 0 end, "C++ error clearing")
      vim.bo[bufnr].modified = false
      print("PASS C++ project include/define handling and live error reporting")
    end
  end
end

local ok, err = xpcall(run, debug.traceback)
vim.lsp.handlers["textDocument/publishDiagnostics"] = original_handler
for _, client in ipairs(vim.lsp.get_clients()) do
  client:stop(true)
end
vim.wait(3000, function() return #vim.lsp.get_clients() == 0 end, 50)
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
print("LSP smoke tests passed")
vim.cmd("qa!")
