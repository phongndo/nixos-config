-- Run from the repository root with the configured plugins available:
-- nvim --headless -u NONE -i NONE -l ./nvim/tests/completion.lua
-- A child Neovim processes real insert-mode keystrokes between RPC assertions.
local stderr = {}
local child = vim.fn.jobstart({
  vim.v.progpath, "--embed", "--headless", "-i", "NONE", "-u", vim.fn.getcwd() .. "/nvim/init.lua",
}, {
  rpc = true,
  on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
})
assert(child > 0, "Could not start test Neovim")

local function lua(code)
  return vim.rpcrequest(child, "nvim_exec_lua", code, {})
end

local function keys(input)
  vim.rpcrequest(child, "nvim_input", input)
end

local function wait_for(code, description)
  assert(vim.wait(5000, function() return lua(code) end, 20), "Timed out: " .. description)
end

local function start_completion()
  keys("<Esc>")
  wait_for("return vim.fn.mode() == 'n'", "normal mode")
  lua([[
    vim.bo.filetype = 'text'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'foobarbaz', '' })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ]])
  keys("ifo")
  wait_for("return require('blink.cmp').is_menu_visible()", "automatic completion menu")
  assert(lua("return require('blink.cmp').get_selected_item() == nil"), "Nothing should be preselected")
  assert(lua("return vim.api.nvim_get_current_line() == 'fo'"), "Opening the menu must not insert text")
end

local function run()
  assert(lua([[
    local config = require('blink.cmp.config')
    return not config.cmdline.enabled and not config.signature.enabled
      and not config.completion.documentation.auto_show
      and not config.completion.ghost_text.enabled()
  ]]), "Unsolicited auxiliary popups should be disabled")

  start_completion()
  assert(lua("return not require('blink.cmp').is_documentation_visible()"), "Documentation should be on demand")
  assert(lua("return not require('blink.cmp').is_ghost_text_visible()"), "Ghost text should be disabled")
  keys("<CR>")
  wait_for([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return #lines == 3 and lines[2] == 'fo' and lines[3] == ''
  ]], "Enter inserting a newline without accepting a suggestion")
  print("PASS automatic suggestions do not select, insert, or steal Enter")

  start_completion()
  keys("<C-n>")
  wait_for("return require('blink.cmp').get_selected_item() ~= nil", "explicit completion selection")
  assert(lua("return vim.api.nvim_get_current_line() == 'fo'"), "Selecting must not preview-insert text")
  keys("<CR>")
  wait_for("return vim.api.nvim_get_current_line() == 'foobarbaz'", "Enter accepting the selected completion")
  assert(lua("return vim.api.nvim_buf_line_count(0) == 2"), "Accept must not insert a newline")
  print("PASS selecting then pressing Enter accepts the completion")

  start_completion()
  keys("<C-e>")
  wait_for("return not require('blink.cmp').is_visible()", "dismissing completion")
  assert(lua("return vim.api.nvim_get_current_line() == 'fo'"), "Dismissing must preserve typed text")
  keys("<C-Space>")
  wait_for("return require('blink.cmp').is_menu_visible()", "manually reopening completion")
  assert(lua("return require('blink.cmp').get_selected_item() == nil"), "Manual opening must not preselect")
  print("PASS Ctrl-e dismisses and Ctrl-Space reopens suggestions")

  start_completion()
  keys("<Tab>")
  wait_for("return vim.api.nvim_get_current_line() == 'fo  '", "Tab inserting indentation instead of accepting")
  print("PASS Tab retains normal indentation outside snippets")

  keys("<Esc>:ec")
  wait_for("return vim.fn.mode() == 'c'", "command-line mode")
  lua("vim.wait(100)")
  assert(lua("return not require('blink.cmp').is_visible()"), "Command-line completion should be disabled")
  keys("<Esc>")
  print("PASS command-line completion stays disabled")
end

local ok, err = xpcall(run, debug.traceback)
pcall(vim.rpcrequest, child, "nvim_command", "qa!")
vim.fn.jobwait({ child }, 3000)
if not ok then
  io.stderr:write(err .. "\n" .. table.concat(stderr, "\n") .. "\n")
  vim.cmd("cquit 1")
end
print("Completion behavior tests passed")
