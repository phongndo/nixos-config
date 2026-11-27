rex.bind("cmd+n", "session.new")
rex.bind("shift+cmd+n", "client.window.new")
rex.bind("cmd+;", "client.palette.toggle")

rex.bind("ctrl+h", "pane.focus.left")
rex.bind("ctrl+j", "pane.focus.down")
rex.bind("ctrl+k", "pane.focus.up")
rex.bind("ctrl+l", "pane.focus.right")

-- A Codex review agent: GPT-6.2-Sol at xhigh reasoning on the ultrafast tier,
-- reviewing the focused pane's repository in a pane beside it.
local codex_review = { model = "gpt-6.2-sol", effort = "xhigh", tier = "ultrafast" }

-- The directory of whatever runs in a pane, else of its shell.
local function pane_dir(ctx)
  local ok, process = pcall(rex.call, "block.method", {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    method = "process",
  })
  if not ok or type(process) ~= "table" then return nil end
  return (process.foreground and process.foreground.cwd) or (process.child and process.child.cwd)
end

rex.action({
  name = "codex_review",
  title = "Codex Review: GPT-6.2 xhigh, ultrafast",
  args = {
    type = "object",
    properties = {
      -- What to review: uncommitted changes (default), the branch against base, or one commit.
      scope = { type = "string", enum = { "uncommitted", "base", "commit" } },
      base = { type = "string" },
      commit = { type = "string" },
      -- Extra instructions for the reviewer.
      prompt = { type = "string" },
      -- The repository; defaults to the focused pane's directory.
      dir = { type = "string" },
    },
    additionalProperties = false,
  },
  run = function(ctx, args)
    args = args or {}
    if not ctx.session_id then error("codex_review needs a session: run it from a pane") end
    local dir = args.dir or pane_dir(ctx)
    if not dir then error("codex_review: no directory; pass dir=PATH") end

    local command = {
      "codex", "review",
      "-c", string.format("model=%q", codex_review.model),
      "-c", string.format("model_reasoning_effort=%q", codex_review.effort),
      "-c", string.format("service_tier=%q", codex_review.tier),
    }
    local scope = args.scope or (args.commit and "commit") or (args.base and "base") or "uncommitted"
    if scope == "uncommitted" then
      table.insert(command, "--uncommitted")
    elseif scope == "base" then
      table.insert(command, "--base")
      table.insert(command, args.base or "main")
    elseif scope == "commit" then
      if not args.commit then error("codex_review: scope=commit needs commit=SHA") end
      table.insert(command, "--commit")
      table.insert(command, args.commit)
    end
    if args.prompt and args.prompt ~= "" then table.insert(command, args.prompt) end

    local split = {
      session_id = ctx.session_id,
      direction = "horizontal",
      side = "after",
      focus = true,
      layout = {
        block = {
          flavor = "com.superlogical.terminal.shell",
          label = "codex review",
          -- The review stays on screen after Codex finishes.
          options = { command = command, cwd = dir, exit = { on_completion = false } },
        },
      },
    }
    if ctx.block_id then split.anchor_id = ctx.block_id end
    local created = rex.call("session.new_split", split)
    return { block_id = created.block_ids and created.block_ids[1], dir = dir, command = table.concat(command, " ") }
  end,
})
