-- Copyright 2025-2026 Mitchell. See LICENSE.

--- Chat with Large Language Models (LLMs a.k.a. AI) using Textadept.
-- Requires `curl` to be installed. This module can interact with [OpenAI-compatible][] LLM
-- servers, whether they are local (like [mlx_lm][]) or remote. It can also interact with
-- [Ollama][]. Local LLM servers need to be running with one or more local models available.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
-- *modules/* directory, and then putting the following in your *~/.textadept/init.lua*:
--
-- ```lua
-- local llm = require('llm')
-- -- Remote, OpenAI-compatible server config.
-- llm.config.url = 'https://dev.example.com' -- if not OpenAI
-- llm.config.api_key = 'API_KEY'
-- -- Local mlx_lm server config.
-- llm.config.url = 'http://localhost:8080/v1'
-- ```
--
-- Start a chat session from the "Tools > LLM (AI) > Chat..." menu.
--
-- Pressing `Enter` will prompt the model. Pressing `Shift+Enter` adds a new line without prompting
-- the model. Typing `@` will prompt you for an open file to inline as context to the model prompt.
--
-- If you have custom model options you want to use, like `temperature` and `top_p`, each server
-- config has a `models` table with fields you can set. For example:
--
-- ```lua
-- llm.config.model['mlx-community/Qwen3.5-9B-4bit'] = {
-- 	stream = true, temperature = 0.7, top_p = 0.8, top_k = 20, max_tokens = 32768
-- }
-- ```
--
-- The default model options enable streaming.
--
-- [OpenAI-compatible]: https://developers.openai.com/api/reference/overview
-- [mlx_lm]: https://github.com/ml-explore/mlx-lm
-- [Ollama]: https://ollama.com/
-- @module llm
local M = {}

--- Configurations for various LLM servers.
-- @field openai
-- @field ollama
-- @see config
M.configs = {}

--- Returns a new table where unknown keys return the given table as a default.
local function default(t) return setmetatable({}, {__index = function() return t end}) end

M.configs.openai = {
	url = 'https://api.openai.com/v1', --
	models_endpoint = '/models', --
	model_name_key = 'id', --
	chat_endpoint = '/chat/completions', --
	chat_message = function(response) return response.choices[1].delta or response.choices[1].message end, --
	done = function(response) return response.choices[1].finish_reason end,
	curl_headers = {['Content-Type'] = 'application/json'}, --
	api_key = 'API_KEY', --
	model = default{stream = true}
}

M.configs.ollama = {
	url = 'http://localhost:11434', --
	models_endpoint = '/api/tags', --
	model_name_key = 'name', --
	chat_endpoint = '/api/chat', --
	chat_message = function(response) return response.message end,
	done = function(response) return response.done end, --
	curl_headers = {}, --
	model = default{stream = true, think = false}
}

--- The config table in `configs` to use.
-- Note: you may still have to configure things like the URL and API key.
-- The default value is `llm.config.openai`.
-- @field url String URL and port the server is running on.
-- @field models_endpoint String REST endpoint that returns list of available models.
-- @field model_name_key String key whose value is the model name for each model in the REST
--	response for `models_endpoint`.
-- @field chat_endpoint String REST endpoint for chatting with a model.
-- @field chat_message Function that accepts a REST response table from`chat_endpoint` and
--	returns its message object (not a string).
-- @field done Function that accepts a REST streaming response table from `chat_endpoint`
--	and returns whether or not that endpoint is done streaming.
-- @field curl_headers Optional map of HTTP headers to send with curl requests to the server.
-- @field api_key Optional string API authorization key for the server.
--	server does not support this option.
-- @field model Map of model names to maps of model-specific options like 'stream', 'think',
--	'temperature', 'top_p', etc.
-- @usage llm.config = llm.configs.ollama
M.config = {}

M.config = M.configs.openai

--- The marker number for prompt lines.
M.MARK_PROMPT = view.new_marker_number()
--- The indicator number for where the LLM response ends.
M.INDIC_LLM_END = view.new_indic_number()

--- The color of prompt markers.
M.MARK_PROMPT_COLOR = 0x00CC99

local json = require('llm.dkjson')

events.MODEL_RESPONSE = 'model_response'
events.MODEL_RESPONSE_STREAM = 'model_response_stream'

--- Emitted after a model is finished responding.
-- This could be used to provide a notification after a long wait time.
-- Arguments:
-- - *message*: The model's entire response.
-- @field _G.events.MODEL_RESPONSE

--- Emitted after a model emits a streamed response.
-- Arguments:
-- - *text*: Partial model message.
-- - *done*: Whether or not this is the last part of the stream.
-- @field _G.events.MODEL_RESPONSE_STREAM

--- Constructs a curl request to an endpoint.
-- POST requests should append ' -d @-' to the returned result.
-- @param endpoint String endpoint name to send the request to.
-- @param[opt] streaming Whether or not the endpoint is streaming.
local function curl(endpoint, streaming)
	local headers = {}
	if M.config.api_key then
		headers[1] = string.format('-H "Authorization: Bearer %s"', M.config.api_key)
	end
	for k, v in pairs(M.config.curl_headers) do
		headers[#headers + 1] = string.format('-H "%s: %s"', k, v)
	end
	return string.format('curl -s %s %s%s %s', streaming and '-N' or '', M.config.url, endpoint,
		table.concat(headers, ' '))
end

--- Prompts the user to select a model to chat with.
-- @param[opt] allow_system_prompt Whether or not to allow the user to set the model's
--	system prompt. The default value is `false`.
-- @return model name and optional system prompt
local function get_model(allow_system_prompt)
	local p<close> = io.popen(curl(M.config.models_endpoint))
	local response = p:read('a')
	if response == '' then error('cannot fetch model list. Is the LLM server running?') end
	response = json.decode(response)

	local models
	for _, v in pairs(response) do
		if type(v) == 'table' then
			models = v -- assume first list result contains models
			break
		end
	end

	local names = table.map(models, function(mod) return mod[M.config.model_name_key] end)
	if #names == 0 then error('no models to chat with', 2) end
	table.sort(names)
	local i, button = ui.dialogs.list{
		title = _L['Select Model'], items = names, button2 = _L['Cancel'],
		button3 = allow_system_prompt and _L['Set system prompt...'] or nil, return_button = true
	}
	if not i or button == 2 then return end

	return names[i], button == 3 and ui.dialogs.input{title = _L['System Prompt']} or nil
end

--- Marks the last character on the given line to help determine where user prompt starts.
-- @param line Line number to mark.
local function mark_llm_message_end(line)
	buffer.indicator_current = M.INDIC_LLM_END
	buffer:indicator_fill_range(buffer.line_end_position[line] - 1, 1)
end

--- Opens a new chat session with a model.
-- @param[opt] model String model name to chat with. If `nil`, the user is prompted for one.
-- @param[opt] system_prompt String system prompt to use for *model*. If both this and *model*
--	are `nil`, the user has the option to specify a system prompt in the model prompt.
-- @param[opt] current_buffer Whether or not to chat in the current buffer. The default value is
--	`false`.
function M.chat(model, system_prompt, current_buffer)
	if not assert_type(model, 'string/nil', 1) then
		if not system_prompt then
			model, system_prompt = get_model(true)
		else
			model = get_model()
		end
	end
	if not current_buffer then buffer.new() end
	buffer:add_text(string.format('%s %s\n', _L['Chatting with'], model))
	buffer:set_lexer('markdown')
	buffer.llm = {model = model, messages = {}}
	if assert_type(system_prompt, 'string/nil', 2) and system_prompt ~= '' then
		buffer:add_text(string.format('%s: %s\n', _L['System Prompt'], system_prompt))
		buffer.llm.messages[1] = {role = 'system', content = system_prompt}
	end
	mark_llm_message_end(buffer:line_from_position(buffer.current_pos) - 1)
	buffer:empty_undo_buffer()
end

local p
--- Prompts the current chat model with input.
-- A model's response will be printed when it is received.
-- @param input String input to prompt with. Any '@*filename*' references are replaced with
--	their file's contents.
function M.prompt(input)
	assert_type(input, 'string', 1)
	local buffer = buffer
	if not buffer.llm then error('can only prompt inside chat buffer', 2) end
	local model, messages = buffer.llm.model, buffer.llm.messages

	-- Replace @filename references with their file contents.
	input = input:gsub('@(%S+)', function(filename)
		filename = filename:gsub('%p$', '') -- strip trailing punctuation like '.' or ','
		for _, buffer in ipairs(_BUFFERS) do
			if buffer.filename == filename then
				return string.format('```\n%s\n```', buffer:get_text())
			end
		end
		if lfs.attributes(filename) then error('file is not open: ' .. filename) end
	end)

	-- Keep track of the first line of the incoming response so autoscrolling does not skip past it.
	local top_line = buffer:line_from_position(buffer.current_pos) + 1

	local streaming = M.config.model[model].stream
	local thinking = false -- some models always print think tags, even if think is off; ignore them

	-- Outputs the chat response content from an incoming line of JSON output.
	-- @param line String JSON line.
	local function process_line(line)
		-- print('Process:', line)
		if line:find('^%s*%[DONE%]') then return end -- OpenAI stream sentinel
		if line:find('keepalive %d+/%d+') then return end -- mlx_lm.server placeholder
		local response = json.decode(line)
		local ok, message = pcall(M.config.chat_message, response)
		local content = ok and (message.content or '') or
			string.format('error processing line `%s`: %s', line, message)
		if ok then
			if not M.config.model[model].think and (content:find('</?think>') or thinking) then
				if streaming then
					thinking = not content:find('</think>')
					return -- ignore
				end
				content = content:gsub('<think>.-</think>', '')
				message.content = content
			end
			local last_message = messages[#messages]
			if streaming and last_message.role ~= 'user' then
				last_message.content = last_message.content .. content -- combine
			else
				table.insert(messages, message)
				buffer:add_text('\n')
				buffer:annotation_clear_all() -- clear "Awaiting response..."
			end
		end

		buffer:set_empty_selection(buffer.length + 1)
		buffer:add_text(content:gsub('\\n', '\n'))
		if view.buffer == buffer then
			local response_lines = view:visible_from_doc_line(buffer.line_count) -
				view:visible_from_doc_line(top_line)
			if response_lines <= view.lines_on_screen then view:line_scroll_down() end -- auto-scroll
		end

		if streaming then
			local ok, done = pcall(M.config.done, response)
			events.emit(events.MODEL_RESPONSE_STREAM, content, ok and done)
			if ok and not done then return end
		end
		mark_llm_message_end(buffer:line_from_position(buffer.current_pos))
		buffer:add_text('\n\n')
		if response.eval_count then -- Ollama
			ui.statusbar_text = response.eval_count / response.eval_duration * 10^9 .. ' tokens/s'
		end
		events.emit(events.MODEL_RESPONSE, messages[#messages].content)
	end

	local stream_buffer = ''
	p = os.spawn(curl(M.config.chat_endpoint, streaming) .. ' -d @-', function(output)
		-- print('Receive:', output)
		stream_buffer = stream_buffer ~= '' and stream_buffer .. output or output
		repeat
			output, stream_buffer = stream_buffer:match('^([^\r\n]+)[\r\n]*(.*)$')
			output = output:gsub('^data:', '') -- OpenAI does not stream pure JSON objects
			process_line(output)
		until not stream_buffer:find('\n')
	end, nil, function() p, buffer.undo_collection = nil, true end)

	local message = {role = 'user', content = input}
	table.insert(messages, message)
	local data = {model = model, messages = messages}
	for k, v in pairs(M.config.model[model] or {}) do data[k] = v end
	data = json.encode(data)
	-- print('Send:', data)
	p:write(data)
	p:close()
	buffer.annotation_text[buffer.line_count] = _L['Awaiting response...']
	buffer:empty_undo_buffer() -- "commit" user's prompt
	buffer.undo_collection = false -- will be reset when p exits
	rawset(buffer, 'modify', true) -- override Scintilla's understanding of save points
end

--- Undo the most recent chat message you submitted.
-- You will be able to edit and resend it.
function M.undo()
	local mark_bit = 1 << M.MARK_PROMPT - 1
	local line = buffer:marker_previous(buffer.line_count, mark_bit)
	if line == -1 then return end

	local pos = buffer.line_end_position[line]
	buffer:delete_range(pos, buffer.length - pos + 1)

	while buffer:marker_get(line) & mark_bit > 0 do
		buffer:marker_delete(line, M.MARK_PROMPT)
		line = line - 1
	end

	table.remove(buffer.llm.messages) -- assistant
	table.remove(buffer.llm.messages) -- user

	buffer:empty_undo_buffer()
end

local SERIALIZED_MARKER = '-- Textadept LLM serialized chat\n'

-- Serialize the current chat to its filename, instead of saving plain-text.
events.connect(events.FILE_AFTER_SAVE, function(filename)
	if not buffer.llm then return end
	local f<close> = io.open(filename, 'w')
	f:write(SERIALIZED_MARKER)
	f:write('return {\n')
	for _, message in ipairs(buffer.llm.messages) do
		f:write('\t{\n')
		f:write(string.format('role="%s",\n', message.role))
		f:write(string.format('content=[=[%s]=],\n', message.content))
		f:write('\t},\n')
	end
	f:write('}\n')
	buffer.mod_time = os.time() -- prevent modified detection
	rawset(buffer, 'modify', false)
	buffer:set_save_point()
end)

-- Loads a previously saved, serialized chat.
events.connect(events.FILE_OPENED, function(filename)
	if buffer:get_line(1) ~= SERIALIZED_MARKER then return end
	local ok, model = pcall(get_model)
	if not ok then
		ui.dialogs.message{
			title = _L['Error Loading Chat'],
			text = string.format('%s: %s', _L['Unable to select a model to chat with'], model)
		}
		return
	end

	local messages = assert(loadfile(filename, 't', {}))()
	local system_prompt = messages[1].role == 'system' and messages[1].content or nil

	buffer:clear_all()
	M.chat(model, system_prompt, true)
	buffer.llm.messages = messages

	for i, message in ipairs(messages) do
		if i == 1 and messages[1].role == 'system' then goto continue end
		buffer:add_text(message.content:gsub('\\n', '\n'))
		if message.role == 'user' then
			local end_line = buffer:line_from_position(buffer.current_pos)
			local start_line = end_line - select(2, message.content:gsub('\n', ''))
			for j = start_line, end_line do buffer:marker_add(j, M.MARK_PROMPT) end
		elseif message.role == 'assistant' then
			mark_llm_message_end(buffer:line_from_position(buffer.current_pos))
		end
		buffer:add_text('\n\n')
		::continue::
	end

	buffer:empty_undo_buffer()
	buffer:set_save_point()
end)

--- Disables change history for chats.
local function disable_change_history()
	if buffer.llm then view.change_history = view.CHANGE_HISTORY_DISABLED end
end
events.connect(events.FILE_OPENED, disable_change_history)
events.connect(events.BUFFER_AFTER_SWITCH, disable_change_history)
events.connect(events.VIEW_AFTER_SWITCH, disable_change_history)

-- Respond to keypresses in a chat buffer.
-- - `\n` prompts the model with either the current line or selected lines.
-- - `@` presents a list of open files to add to the prompt for context.
events.connect(events.KEYPRESS, function(key)
	if ui.command_entry.active or buffer:auto_c_active() then return end
	if not buffer.llm then return end
	if key == '\n' then
		-- Find where last LLM response ends.
		local pos, indic = buffer.current_pos, 1 << M.INDIC_LLM_END - 1
		while pos > 1 and buffer:indicator_all_on_for(pos) & indic == 0 do pos = pos - 1 end
		-- Skip over blank lines.
		local line = buffer:line_from_position(pos) + 1
		while buffer:position_from_line(line) == buffer.line_end_position[line] do line = line + 1 end
		-- Mark prompt lines.
		for i = line, buffer:line_from_position(buffer.current_pos) do
			buffer:marker_add(i, M.MARK_PROMPT)
		end
		-- Prompt the LLM.
		M.prompt(buffer:text_range(buffer:position_from_line(line), buffer.current_pos))
		buffer:new_line()
		return true
	elseif key == '@' then
		buffer:add_text('@')
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
		if #filenames == 0 then return true end
		local i = ui.dialogs.list{title = _L['Select Context File'], items = filenames, select = select}
		if i then buffer:add_text(filenames[i]) end
		return true
	end
end, 1)

-- Unload local Ollama chat model when closing the chat in order to free up memory.
events.connect(events.BUFFER_DELETED, function(buffer)
	if not buffer.llm or M.config ~= M.configs.ollama then return end
	local p = os.spawn(curl('/api/generate') .. ' -d @-')
	p:write(json.encode{model = buffer.llm.model, keep_alive = 0})
	p:close()
end)

-- Sets view properties for prompt markers.
events.connect(events.VIEW_NEW, function()
	view:marker_define(M.MARK_PROMPT, view.MARK_FULLRECT)
	view.marker_back[M.MARK_PROMPT] = M.MARK_PROMPT_COLOR
	view.indic_style[M.INDIC_LLM_END] = view.INDIC_HIDDEN
end)

-- Add a menu.
-- (Insert 'LLM' menu in alphabetical order.)
_L['LLM (AI)'] = 'LLM (_AI)'
_L['Chat With Model...'] = '_Chat With Model...'
_L['Stop Incoming Message'] = '_Stop Incoming Message'
_L['Undo Last Message'] = '_Undo Last Message'
local m_tools = textadept.menu.menubar['Tools']
local found_area
for i = 1, #m_tools - 1 do
	if not found_area and m_tools[i + 1].title == _L['Bookmarks'] then
		found_area = true
	elseif found_area then
		local label = m_tools[i].title or m_tools[i][1]
		if 'LLM (AI)' < label:gsub('^_', '') or m_tools[i][1] == '' then
			table.insert(m_tools, i, { --
				title = _L['LLM (AI)'], --
				{_L['Chat With Model...'], M.chat}, --
				{''}, --
				{_L['Stop Incoming Message'], function() if p then p:kill() end end}, --
				{_L['Undo Last Message'], M.undo} --
			})
			break
		end
	end
end

return M
