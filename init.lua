-- Copyright 2025 Mitchell. See LICENSE.

--- Chat with local [Ollama][] models using Textadept.
-- Requires Ollama and `curl` to be installed, and Ollama needs to be running in server mode
-- with one or more local models available.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
-- *modules/* directory, and then putting the following in your *~/.textadept/init.lua*:
--
-- ```lua
-- local ollama = require('ollama')
-- ```
--
-- Start a chat session from the "Tools > Ollama > Chat..." menu.
--
-- Pressing `Enter` will prompt the model with the current or selected lines. Pressing
-- `Shift+Enter` adds a new line without prompting the model. Typing `@` will prompt you for
-- an open file to inline as context to the model prompt.
--
-- [Ollama]: https://ollama.com/
--
-- ## Chatting with external models
--
-- You can configure this module to talk to external models that do not use the Ollama API.
-- Here is a sample configuration to talk to an OpenAI-compatible model (tested with [LiteLLM][]):
--
-- ```lua
-- local ollama = require('ollama')
-- ollama.url = 'https://example.com'
-- ollama.models_endpoint = '/models'
-- ollama.model_name_key = 'id'
-- ollama.chat_endpoint = '/chat/completions'
-- ollama.chat_message = function(response)
-- 	return response.choices[1].message or response.choices[1].delta
-- end
-- ollama.done = function(response) return not response.choices[1].delta.content end
-- ollama.curl_headers = {['Content-Type'] = 'application/json'}
-- ollama.api_key = 'API_KEY'
-- ollama.think = nil -- avoid sending this parameter to the endpoint
-- ```
--
-- [LiteLLM]: https://docs.litellm.ai/
-- @module ollama
local M = {}

--- URL Ollama is running on (http://host:port).
-- The default value is `http://localhost:11434` and should only be changed if Ollama is running on
-- a different port, or if you are not using Ollama.
M.url = 'http://localhost:11434'

--- REST endpoint for fetching a list of available models.
-- The default value is '/api/tags' and should only be changed if you are not using Ollama.
M.models_endpoint = '/api/tags'

--- The key whose value is the model name for each model in the REST response for `models_endpoint`.
-- The default value is 'name' and should only be changed if you are not using Ollama.
M.model_name_key = 'name'

--- REST endpoint for chatting with a model.
-- The default value is '/api/chat' and should only be changed if you are not using Ollama.
M.chat_endpoint = '/api/chat'

--- Function to extract the message from the REST response for `chat_endpoint`.
-- This should only be changed if you are not using Ollama.
-- @param response Table containing a model response.
M.chat_message = function(response) return response.message end

--- Function that returns whether or not a REST response from `chat_endpoint` is done streaming.
-- This should only be changed if you are not using Ollama.
-- @param response Table containing a streamed model response.
M.done = function(response) return response.done end

--- Optional map of HTTP headers to send with curl requests to an external model.
-- The default value is an empty map since Ollama does not need any headers.
M.curl_headers = {}

--- API authorization key when chatting with external models.
-- The default value is `nil` since Ollama does not need this.
M.api_key = nil

--- Whether or not to stream model responses in real-time.
-- The default value is `true`.
M.stream = true

--- Whether models with thinking capabilities should think before responding.
-- Use `nil` if your chat endpoint does not support this parameter.
-- The default value is `false`.
M.think = false

--- Map of model names with their options.
-- Options are tables that will be encoded into JSON before being sent to Ollama.
M.model_options = {}

--- The marker number for prompt lines.
M.MARK_PROMPT = view.new_marker_number()

--- The color of prompt markers.
M.MARK_PROMPT_COLOR = 0x00CC99

local json = require('ollama.dkjson')

events.MODEL_RESPONSE = 'model_response'

--- Emitted after a model is finished responding.
-- This could be used to provide a notification after a long wait time.
-- @field _G.events.MODEL_RESPONSE

--- Constructs a curl request to an endpoint.
-- POST requests should append ' -d @-' to the returned result.
-- @param endpoint String endpoint name to send the request to.
local function curl(endpoint)
	local headers = {}
	if M.api_key then headers[1] = string.format('-H "Authorization: Bearer %s"', M.api_key) end
	for k, v in pairs(M.curl_headers) do headers[#headers + 1] = string.format('-H "%s: %s"', k, v) end
	return string.format('curl -s %s %s%s %s', M.stream and '-N' or '', M.url, endpoint,
		table.concat(headers, ' '))
end

--- Returns a buffer type for a model.
-- @param model String model name.
local function chat_buffer_type(model) return string.format('[%s - %s]', _L['Chat'], model) end

--- Opens a new chat session with a model.
-- @param[opt] model String model name to chat with. If `nil`, the user is prompted for one.
-- @param[opt] system_prompt String system prompt to use for *model*. If both this and *model*
--	are `nil`, the user has the option to specify a system prompt in the model prompt.
function M.chat(model, system_prompt)
	if not assert_type(model, 'string/nil', 1) then
		local p<close> = io.popen(curl(M.models_endpoint))
		local response = p:read('a')
		if response == '' then error('cannot fetch model list. Is ollama running in server mode?') end
		response = json.decode(response)

		local models
		for _, v in pairs(response) do
			if type(v) == 'table' then
				models = v -- assume first list result contains models
				break
			end
		end

		local names = table.map(models, function(mod) return mod[M.model_name_key] end)
		if #names == 0 then error('no local models to chat with', 2) end
		local i, button = ui.dialogs.list{
			title = _L['Select Model'], items = names, button3 = _L['Set system prompt...'],
			return_button = true
		}
		if button == 3 then system_prompt = ui.dialogs.input{title = _L['System Prompt']} end
		if not i or button == 2 then return end

		model = names[i]
	end

	ui.print_to(chat_buffer_type(model), string.format('%s %s', _L['Chatting with'], model))
	buffer:set_lexer('markdown')
	buffer.ollama = {model = model, messages = {}}
	if assert_type(system_prompt, 'string/nil', 2) and system_prompt ~= '' then
		ui.print_to(chat_buffer_type(model), string.format('%s: %s', _L['System Prompt'], system_prompt))
		buffer.ollama.messages[1] = {role = 'system', content = system_prompt}
	end
end

--- Prompts the current chat model with input.
-- A model's response will be printed when it is received.
-- @param input String input to prompt with. Any '@*filename*' references are replaced with
--	their file's contents.
function M.prompt(input)
	assert_type(input, 'string', 1)
	local buffer = buffer
	if not buffer.ollama then error('can only prompt inside chat buffer', 2) end
	local model, messages = buffer.ollama.model, buffer.ollama.messages

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

	-- Outputs the chat response content from an incoming line of JSON output.
	-- @param line String JSON line.
	local function process_line(line)
		-- print('Process:', line)
		if line:find('^%s*%[DONE%]') then return end -- OpenAI stream sentinel
		local response = json.decode(line)
		local ok, message = pcall(M.chat_message, response)
		local content = ok and (message.content or '') or
			string.format('error procesing line `%s`: %s', line, message)
		if ok then
			local last_message = messages[#messages]
			if M.stream and last_message.role ~= 'user' then
				last_message.content = last_message.content .. content -- combine
			else
				table.insert(messages, message)
				buffer:add_text('\n')
				buffer:annotation_clear_all() -- clear "Awaiting response..."
			end
		end

		buffer:set_empty_selection(buffer.length + 1)
		buffer:add_text(content:gsub('\\n', '\n'))

		if M.stream then
			local ok, done = pcall(M.done, response)
			if ok and not done then return end
		end
		buffer:add_text('\n\n')
		if response.eval_count then
			ui.statusbar_text = response.eval_count / response.eval_duration * 10^9 .. ' tokens/s'
		end
		events.emit(events.MODEL_RESPONSE)
	end

	local stream_buffer = ''
	local p = os.spawn(curl(M.chat_endpoint) .. ' -d @-', function(output)
		-- print('Receive:', output)
		stream_buffer = stream_buffer ~= '' and stream_buffer .. output or output
		repeat
			output, stream_buffer = stream_buffer:match('^([^\r\n]+)[\r\n]*(.*)$')
			output = output:gsub('^data:', '') -- OpenAI does not stream pure JSON objects
			process_line(output)
		until not stream_buffer:find('\n')
	end)

	local message = {role = 'user', content = input}
	table.insert(messages, message)
	local data = json.encode{
		model = model, messages = messages, stream = M.stream, think = M.think,
		options = M.model_options[model]
	}
	-- print('Send:', data)
	p:write(data)
	p:close()
	buffer.annotation_text[buffer.line_count] = _L['Awaiting response...']
end

-- Respond to keypresses in a chat buffer.
-- - `\n` prompts the model with either the current line or selected lines.
-- - `@` presents a list of open files to add to the prompt for context.
events.connect(events.KEYPRESS, function(key)
	if ui.command_entry.active then return end
	if not buffer.ollama then return end
	if key == '\n' and not buffer:auto_c_active() then
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

-- Unload local chat model when closing the chat in order to free up memory.
events.connect(events.BUFFER_DELETED, function(buffer)
	if not buffer.ollama or not M.url:find('localhost') then return end
	local p = os.spawn(curl('/api/generate') .. ' -d @-')
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
_L['Ollama'] = 'Ollam_a'
_L['Chat...'] = '_Chat...'
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
