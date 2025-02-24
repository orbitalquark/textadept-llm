-- Copyright 2025 Mitchell. See LICENSE.

--- Chat with local [Ollama][] models using Textadept.
-- Requires Ollama and `curl` to be installed, and Ollama needs to be running in server mode
-- with one or more local models available.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
-- *modules/* directory, and then putting the following in your *~/.textadept/init.lua*:
--
-- 	require('ollama')
--
-- Start a chat session from the Tools > Ollama > Chat... menu.
--
-- Pressing `Enter` will prompt the model with the current or selected lines. Pressing
-- `Shift+Enter` adds a new line without prompting the model. Typing `@` will prompt you for
-- an open file to inline as context to the model prompt.
--
-- [Ollama]: https://ollama.com/
-- @module ollama
local M = {}

local _L = _L
if not rawget(_L, 'Ollama') then
	_L['Ollama'] = 'Ollama'
	_L['Chat'] = 'Chat'
	_L['Select Model'] = 'Select Model'
	_L['Chatting with'] = 'Chatting with'
	_L['Thinking...'] = 'Thinking...'
	_L['Select Context File'] = 'Select Context File'
	_L['Chat...'] = 'Chat...'
end

--- URL Ollama is running on (http://host:port).
M.url = 'http://localhost:11434'

--- Map of model names with their options.
-- Options are tables that will be encoded into JSON before being sent to Ollama.
M.model_options = {
	['deepseek-coder-v2:16b'] = {num_ctx = 4096}
}

--- The marker number for prompt lines.
M.MARK_PROMPT = view.new_marker_number()

--- The color of prompt markers.
M.MARK_PROMPT_COLOR = 0x00CC99

local json = require('ollama.dkjson')

--- Returns a buffer type for model name *model*.
-- @param model String model name.
local function chat_buffer_type(model) return string.format('[%s - %s]', _L['Chat'], model) end

--- Opens a new chat session with model name *model*, or the user-selected model if none was
-- given.
-- @param[opt] model String model name to chat with.
function M.chat(model)
	if not assert_type(model, 'string/nil', 1) then
		local p<close> = io.popen('curl -s ' .. M.url .. '/api/tags')
		local response = p:read('a')
		if response == '' then error('ollama is not running in server mode') end
		local names = {}
		for i, mod in ipairs(json.decode(response).models) do names[i] = mod.name end
		if #names == 0 then error('no local models to chat with', 2) end
		local i = ui.dialogs.list{title = _L['Select Model'], items = names}
		if not i then return end
		model = names[i]
	end

	ui.print_to(chat_buffer_type(model), string.format('%s %s', _L['Chatting with'], model))
	buffer:set_lexer('markdown')
	buffer.ollama = {model = model, messages = {}}
end

--- Prompts the current chat model with string *input*.
-- Any `@filename` references are replaced with their file's contents.
-- Prints whatever the model responds with when it finishes thinking.
-- @param input String input to prompt with.
function M.prompt(input)
	assert_type(input, 'string', 1)
	if not buffer.ollama then error('can only prompt inside chat buffer', 2) end
	local model, messages = buffer.ollama.model, buffer.ollama.messages

	input = input:gsub('@(%S+)', function(filename)
		filename = filename:gsub('%p$', '') -- strip trailing punctuation like '.' or ','
		for _, buffer in ipairs(_BUFFERS) do
			if buffer.filename == filename then
				return string.format('```\n%s\n```', buffer:get_text())
			end
		end
		error('file is not open: ' .. filename)
	end)

	local p = os.spawn('curl -s ' .. M.url .. '/api/chat -d @-', function(output)
		-- print(output)
		local message = json.decode(output).message
		local content = message.content or output -- in case of error
		if content then table.insert(messages, message) end
		local type = chat_buffer_type(model)
		local buffer = ui.print_silent_to(type) -- newline
		buffer:annotation_clear_all() -- clear "thinking"
		ui.print_silent_to(type, content:gsub('\\n', '\n'))
		ui.print_silent_to(type) -- newline
	end)

	local message = {role = 'user', content = input}
	table.insert(messages, message)
	p:write(json.encode{
		model = model, messages = messages, stream = false, options = M.model_options[model]
	})
	p:close()
	-- print(json.encode(data))
	buffer.annotation_text[buffer.line_count] = _L['Thinking...']
end

-- Respond to keypresses in a chat buffer.
-- - `\n` prompts the model with either the current line or selected lines.
-- - `@` presents a list of open files to add to the prompt for context.
events.connect(events.KEYPRESS, function(key)
	if ui.command_entry.active then return end
	if not buffer.ollama then return end
	if key == '\n' then
		textadept.editing.select_line()
		local input = buffer:get_sel_text()
		M.prompt(input)
		local start_line = buffer:line_from_position(buffer.selection_start)
		local end_line = buffer:line_from_position(buffer.selection_end)
		for i = start_line, end_line do buffer:marker_add(i, M.MARK_PROMPT) end
		buffer:char_right() -- go to selection end (which is also line end)
		buffer:new_line()
		return true
	elseif key == '@' then
		local filenames = {}
		local select = 1
		local other_view = #_VIEWS == 2 and _VIEWS[view == _VIEWS[2] and 1 or 2]
		for _, buffer in ipairs(_BUFFERS) do
			if not buffer.filename then goto continue end
			filenames[#filenames + 1] = buffer.filename
			if other_view and other_view.buffer.filename == buffer.filename then
				select = #filenames -- assume this file is the desired reference
			end
			::continue::
		end
		local i = ui.dialogs.list{title = _L['Select Context File'], items = filenames, select = select}
		if i then buffer:add_text('@' .. filenames[i]) end
		return true
	end
end, 1)

-- Unload chat model when closing the chat in order to free up memory.
events.connect(events.BUFFER_DELETED, function(buffer)
	if not buffer.ollama then return end
	local p = os.spawn('curl -s ' .. M.url .. '/api/generate -d @-')
	p:write(json.encode{model = buffer.ollama.model, keep_alive = 0})
	p:close()
end)

-- Sets view properties for prompt markers.
events.connect(events.VIEW_NEW, function()
	view:marker_define(M.MARK_PROMPT, view.MARK_FULLRECT)
	view.marker_back[M.MARK_PROMPT] = M.MARK_PROMPT_COLOR
end)

-- Add a menu.
-- (Insert 'Ollama' menu in alphabetical order.)
local m_tools = textadept.menu.menubar['Tools']
local found_area
for i = 1, #m_tools - 1 do
	if not found_area and m_tools[i + 1].title == _L['Bookmarks'] then
		found_area = true
	elseif found_area then
		local label = m_tools[i].title or m_tools[i][1]
		if 'Ollama' < label:gsub('^_', '') or m_tools[i][1] == '' then
			table.insert(m_tools, i, { --
				title = _L['Ollama'], --
				{_L['Chat...'], M.chat}
			})
			break
		end
	end
end

return M
