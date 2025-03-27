---@brief [[
--- `nvim-autoracket` automatically configures neovim for any `#lang` built on top of the racket ecosystem.
---
--- Unlike most ftplugins, this one does not configure a single language.
--- Instead, it dynamically looks up info about the language at runtime from the racket API.
--- This allows it to be extensible to any racket language, not just ones that are often used.
---
--- Features:
--- - `filetype`
--- - `commentstring`
--- - (optional) LSP config and autostart. Currently only supports the `lspconfig` plugin.
---              Supporting other LSP plugins would not be hard; help wanted!
--- - (planned) `indentexpr`. This is non-trivial because the API DrRacket exposes is a racket function,
---             i.e. it requires spawning a racket subprocess for each range we want to indent. This is cumbersome and slow.
--- ]]

local M = {}

local disable_lsp = false
local loaded_exts = false
local lang_info = {}

local function run_racket(look_ma_i_know_lisp, on_err)
	local out = vim.system({'racket', '-e', look_ma_i_know_lisp }):wait()
	if out.stderr ~= '' then
		error(on_err..': '..out.stderr)
	end
	return out.stdout
end

local function sniff_lang(buf)
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 3, false)) do
		local _, _, lang = string.find(line, "#lang ([^ ]+)")
		if lang ~= nil then return lang end
	end
	return nil
end

local function load_filetype(file, buf)
	local lang = sniff_lang(buf)
	if lang == nil then
		error("missing #lang for "..file)
		return
	end
	if lang_info[lang] ~= nil then return lang end
	local lisp = [[
		(define comments ((read-language (open-input-string "#lang ]]..lang..[[")) 'drracket:comment-delimiters #f))
		(for-each displayln (cdar (filter (lambda x (equal? (caar x) 'line  )) comments)))
		(for-each displayln (cdar (filter (lambda x (equal? (caar x) 'region)) comments)))
	]]
  local comments = {}
	for part in string.gmatch(run_racket(lisp, "failed to load comments for #lang "..lang), "[^\n]+") do
		comments[#comments+1] = part
	end
	local ln_start, ln_pad, block_start, block_continue, block_end, block_pad = unpack(comments)
	-- TODO: handle languages without line comments
	-- Unfortunately vim doesn't have an API for block comments. `Comment.nvim` does, but we can't assume it's installed.
	local commentstring = ln_start..ln_pad..'%s'
	lang_info[lang] = {commentstring}

	local ok, lsplang = pcall(require, 'lspconfig.configs')

	if ok and not lsplang[lang] then
		lsplang[lang] = {
			default_config = {
				cmd = {"racket",  "-l", "racket-langserver"},
				filetypes = { lang },
				root_dir = vim.fs.dirname,  -- apparently racket-langserver just ignores this, so don't try too hard to be smart
				settings = {},
			},
		}
		if not disable_lsp then
			require('lspconfig')[lang].setup {}
			vim.cmd.LspStart 'lang'
		end
	end

	-- TODO: handle indent
	return lang
end

local function set_buf_opts(file, buf)
	local lang = load_filetype(file, buf)
	vim.bo.filetype = lang
	vim.bo.commentstring = lang_info[lang][0]
	return lang
end

local function load_exts(file, buf)
	local exts = {}
	local stdout = run_racket(
		'(require compiler/module-suffix) (for-each displayln (get-module-suffixes))',
		"failed to detect file extensions for installed racket languages"
	)
	for line in string.gmatch(stdout, "[^\n]+") do
		-- TODO: maybe use `get-info/full` here so we can have a proper mapping instead of looking this up dynamically?
		exts[line] = set_buf_opts
		if string.match(file, '%.'..line..'$') then
			set_buf_opts(file, buf)  -- do this right away. `filetype` only applies for future files, not the one we're currently opening.
		end
	end
	vim.filetype.add({ extension = exts })
end

local function maybe_load_exts(args)
	if not sniff_lang(args.buf) then return end  -- don't try to run racket if this isn't a racket-like lang
	if not loaded_exts then
		load_exts(args.file, args.buf)
		loaded_exts = true
	end
	return true  -- delete this autocommand now that we've loaded the extensions
end

---@tag nvim-autoconfig
---@config { ["name"] = "SETUP" }

--- Usage:
--- ```lua
--- require('nvim-autoconfig').setup {}
--- ```
--- @param opts table: Configuration options. Keys:
---   - disable_lsp: Disables autostarting the LSP when a buffer is opened for the first time.
---     You can still manually configure `lspconfig.lang.default_config`, but this plugin won't do that automatically.
M.setup = function(opts)
	disable_lsp = opts.disable_lsp or false
	vim.api.nvim_create_augroup('nvim-autoracket', {})
	vim.api.nvim_create_autocmd('BufReadPost', {
		desc = 'Detect if this is a language built on racket',
		group = 'nvim-autoracket',
		callback = maybe_load_exts,
	})
end

return M
