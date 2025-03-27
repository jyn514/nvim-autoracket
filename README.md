# nvim-autoracket

`nvim-autoracket` automatically configures neovim for any `#lang` built on top of the racket ecosystem.

Unlike most ftplugins, this one does not configure a single language.
Instead, it dynamically looks up info about the language at runtime from the racket API.
This allows it to be extensible to any racket language, not just ones that are often used.

Features:
- `filetype`
- `commentstring`
- (optional) LSP config and autostart. Currently only supports the `lspconfig` plugin.
    Supporting other LSP plugins would not be hard; help wanted!
- (planned) `indentexpr`. This is non-trivial because the API DrRacket exposes is a racket function,
    i.e. it requires spawning a racket subprocess for each range we want to indent. This is cumbersome and slow.
