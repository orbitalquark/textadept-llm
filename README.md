# LLM

Chat with Large Language Models (LLMs a.k.a.
AI) using Textadept.
Requires `curl` to be installed. This module can interact with local LLM servers like
[mlx_lm][] or [Ollama][], and remote LLM servers like [LiteLLM][]. Local LLM servers need
to be running with one or more local models available.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

```lua
local llm = require('llm')
```

Start a chat session from the "Tools > LLM (AI) > Chat..." menu.

Pressing `Enter` will prompt the model with the current or selected lines. Pressing
`Shift+Enter` adds a new line without prompting the model. Typing `@` will prompt you for
an open file to inline as context to the model prompt.

If you have custom model options you want to use, like `temperature` and `top_p`, each server
config has a `models` table with fields you can set. For example:

```lua
llm.configs.mlx_lm.model['mlx-community/Qwen3.5-9B-4bit'] = {
	stream = true, temperature = 0.7, top_p = 0.8, top_k = 20, max_tokens = 32768
}
```

The default model options enable streaming.

[mlx_lm]: https://github.com/ml-explore/mlx-lm
[Ollama]: https://ollama.com/
[LiteLLM]: https://docs.litellm.ai/

## Chatting with external models

You can configure this module to talk to external models that use an OpenAI-compatible or
Ollama-compatible API. For example:

```lua
local llm = require('llm')
local config = llm.configs.litellm
config.url = 'https://dev.example.com'
config.api_key = 'API_KEY'
llm.config = config
```

<a id="llm.MARK_PROMPT"></a>
## `llm.MARK_PROMPT`

The marker number for prompt lines.

<a id="llm.MARK_PROMPT_COLOR"></a>
## `llm.MARK_PROMPT_COLOR`

The color of prompt markers.

<a id="events.MODEL_RESPONSE"></a>
## `events.MODEL_RESPONSE`

Emitted after a model is finished responding.

This could be used to provide a notification after a long wait time.
Arguments:
- *message*: The model's entire response.

<a id="events.MODEL_RESPONSE_STREAM"></a>
## `events.MODEL_RESPONSE_STREAM`

Emitted after a model emits a paragraph of streamed response.

Paragraphs are delimitted by consecutive newlines.
This could be used to send the paragraph to a text-to-speech engine.
Arguments:
- *text*: Partial model message.

<a id="llm.chat"></a>
## `llm.chat`([*model*[, *system_prompt*]])

Opens a new chat session with a model.

Parameters:
- *model*:  String model name to chat with. If `nil`, the user is prompted for one.
- *system_prompt*:  String system prompt to use for *model*. If both this and *model*
	are `nil`, the user has the option to specify a system prompt in the model prompt.

<a id="llm.chat_directory"></a>
## `llm.chat_directory`

The directory to save chats to.

The default value is *~/.textadept/chats/*.

<a id="llm.config"></a>
## `llm.config`

The config table in `configs` to use.

Note: you may still have to configure things like the URL and API key.
The default value is `llm.config.ollama`.

Fields:
- `url`:  String URL and port the server is running on.
- `models_endpoint`:  String REST endpoint that returns list of available models.
- `model_name_key`:  String key whose value is the model name for each model in the REST
	response for `models_endpoint`.
- `chat_endpoint`:  String REST endpoint for chatting with a model.
- `chat_message`:  Function that accepts a REST response table from`chat_endpoint` and
	returns its message object (not a string).
- `done`:  Function that accepts a REST streaming response table from `chat_endpoint`
	and returns whether or not that endpoint is done streaming.
- `curl_headers`:  Optional map of HTTP headers to send with curl requests to the server.
- `api_key`:  Optional string API authorization key for the server.
	server does not support this option.
- `model`:  Map of model names to maps of model-specific options like 'stream', 'think',
	'temperature', 'top_p', etc.

Usage:

```lua
llm.config = llm.configs.mlx_lm
```

<a id="llm.configs"></a>
## `llm.configs`

Configurations for various LLM servers.

Fields:
- `ollama`: 
- `litellm`: 
- `mlx_lm`: 

See also: [`llm.config`](#llm.config)

<a id="llm.load"></a>
## `llm.load`([*filename*])

Loads a previously saved chat into the current model, discarding the current chat.

Parameters:
- *filename*:  String filename to load. If `nil`, the user is prompted for one.

<a id="llm.prompt"></a>
## `llm.prompt`(*input*)

Prompts the current chat model with input.

A model's response will be printed when it is received.

Parameters:
- *input*:  String input to prompt with. Any '@*filename*' references are replaced with
	their file's contents.

<a id="llm.save"></a>
## `llm.save`([*filename*])

Saves the current chat.

Parameters:
- *filename*:  String filename to save to. If `nil`, the user is prompted for one.

<a id="llm.undo"></a>
## `llm.undo`()

Undo the most recent chat message you submitted.

You will be able to edit and resend it.



