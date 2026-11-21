rex.bind("cmd+n", "session.new")
rex.bind("shift+cmd+n", "client.window.new")

-- Ctrl-h/j/k/l move between panes. In a pane running Neovim, the key goes to
-- Neovim instead, which moves between its own windows and hands focus back
-- (rex focus) at its edge; see config/nvim/init.lua.
local terminal = "com.superlogical.terminal"
local function runs_nvim(block_id)
  local info = block_id and rex.block.call(terminal, "process", { block_id = block_id })
  return info ~= nil and info.foreground ~= nil and info.foreground.name == "nvim"
end
for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, function(ctx)
    if runs_nvim(ctx.block_id) then
      return false
    end
    rex.session.focus_direction({ direction = direction })
    return true
  end)
end
