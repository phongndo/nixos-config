# Neovim language support

Neovim's built-in LSP uses server defaults from `nvim-lspconfig`; Blink
(`blink.cmp`) handles completion. Nix installs the server executables; Lazy
installs the plugins. There is no Mason, extra lint provider, or automatic
formatting on save.

## Activate

Apply the host's Nix configuration using the usual rebuild workflow. On Mac `y`,
from the repository root:

```sh
./bin/bootstrap
```

This applies the **whole system configuration**, not just Neovim. On Linux `z`,
use its NixOS rebuild workflow instead. Reopen Neovim, then run `:Lazy restore`
to synchronize installed plugins with `lazy-lock.json`, and restart Neovim.
`:checkhealth vim.lsp` shows enabled servers and attached clients.

## Everyday use

| Key | Action |
| --- | --- |
| `gd` | Go to definition |
| `gr` | References (without waiting for longer `gr` mappings) |
| `gi` | Go to implementation |
| `K` | Hover documentation |
| `<Space>r` | Rename |
| `<Space>a` | Code actions (also works on a visual selection) |
| `[d` / `]d` | Previous / next diagnostic |
| `<Space>d` | Show diagnostics on this line |
| `<Space>q` | Diagnostics from loaded buffers in the quickfix list |
| `Ctrl-Space` (insert mode) | Open completion, or documentation for a selected item |
| `Ctrl-n` / `Ctrl-p` or arrows | Select a completion without inserting it |
| `Enter` | Newline normally; accept only an explicitly selected completion |
| `Ctrl-e` | Dismiss completion |
| `Tab` | Normal indentation; jump forward inside an active snippet |

Suggestions appear automatically, but nothing is preselected or preview-inserted.
Completion uses LSP, paths, and buffer words. Documentation is on demand, and
signature popups, ghost text, and command-line completion are disabled. Blink's
Lua matcher avoids a separate native binary download/build on either Nix host.

Diagnostics retain gutter signs and underlines, but do not add inline messages
or update during insertion.

## Project environments

Launch Neovim from the environment used to build/run the project:

```sh
nix develop -c nvim
```

For projects without a Nix shell, activate their normal environment first.
Servers are resolved through `PATH`, so a project can supply versions instead of
using the global defaults. In particular:

- **Python:** activate the virtual environment before launching Neovim. If an
  interpreter is still misidentified, use `:LspPyrightSetPythonPath /path/to/python`
  or the project's Pyright configuration rather than suppressing import errors.
- **Rust:** the project's Rust toolchain (`cargo`, `rustc`, and matching `rust-src`)
  must be available. The global server is not a replacement for a Rust toolchain.
- **Zig:** keep ZLS and Zig compatible. The global defaults are paired in Nix;
  projects using other Zig releases should supply the corresponding ZLS too.
- **OCaml:** build the Dune project (`dune build`, or `dune build --watch`) and use
  a server compatible with its compiler. For opam projects, launch with the
  intended switch, e.g. `opam exec -- nvim`, with `ocaml-lsp-server` installed in
  that switch. A global server cannot supply a project's dependencies.
- **TypeScript / React:** install project dependencies and keep `tsconfig.json`
  or `jsconfig.json` in the project. JSX and TSX use the same server as JS/TS;
  React does not need another server. Project React type packages are still needed.

### C / C++ with CMake

Enable `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` in the project's existing CMake
configuration (Ninja or Makefiles generator). For a new conventional build:

```sh
# llama.cpp, from the checkout root:
cmake -S . -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# LLVM, from the llvm-project checkout root:
cmake -S llvm -B build -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Retain any existing toolchain, generator, and project options. Build the targets
you work on so required generated headers exist.

Ensure clangd can find `compile_commands.json` for the **active build**. For a
custom build directory, a root-level symlink is a simple option (only create it
if there isn't already a database/link there):

```sh
ln -s build/compile_commands.json compile_commands.json
```

Keep that link local to the checkout, and update it when switching build
directories. Don't hardcode a global C++ standard, include path, or warning
suppression in the editor. A database from a different build, missing generated
headers, or mismatched compiler discovery can still produce incorrect errors.
See [clangd's compilation database guide](https://clangd.llvm.org/installation#compile_commandsjson).

## Add a language

Add its server package to the language-tools block in `../home/packages.nix`
and its `nvim-lspconfig` name to `vim.lsp.enable` in `init.lua`. Rebuild once;
project roots, filetypes, and launch commands normally come from lspconfig.
Only add custom settings for a demonstrated need.

## Smoke test

With the configured plugins, servers, and Rust toolchain available, run from the
repository root:

```sh
nvim --headless -i NONE -u ./nvim/init.lua -l ./nvim/tests/lsp.lua
nvim --headless -u NONE -i NONE -l ./nvim/tests/completion.lua
```

The LSP test uses temporary projects to check real server attachment, duplicate
clients, shared keybindings, completion capabilities, and diagnostic display
policy. Its C++ fixture checks that clangd consumes project include paths/defines
and reports then clears a real type error. It does not validate an actual
LLVM/llama.cpp build or every language's project/toolchain integration.

The completion test drives real keystrokes in a child Neovim: automatic
suggestions do not preselect or insert text, Enter remains a newline until
selection, Tab indents outside snippets, and completion can be dismissed and
manually reopened. It also checks that command-line completion stays disabled.
