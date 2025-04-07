# Ollama

Chat with local [Ollama][] models using Textadept.

Requires Ollama and `curl` to be installed, and Ollama needs to be running in server mode
with one or more local models available.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

```lua
local ollama = require('ollama')
```

Start a chat session from the "Tools > Ollama > Chat..." menu.

Pressing `Enter` will prompt the model with the current or selected lines. Pressing
`Shift+Enter` adds a new line without prompting the model. Typing `@` will prompt you for
an open file to inline as context to the model prompt.

[Ollama]: https://ollama.com/

## Chatting with external models

You can configure this module to talk to external models that do not use the Ollama API.
Here is a sample configuration to talk to an OpenAI-compatible model (tested with [LiteLLM][]):

```lua
local ollama = require('ollama')
ollama.url = 'https://example.com'
ollama.models_endpoint = '/models'
ollama.model_name_key = 'id'
ollama.chat_endpoint = '/chat/completions'
ollama.chat_message = function(response) return response.choices[1].message end
ollama.curl_headers = {['Content-Type'] = 'application/json'}
ollama.api_key = 'API_KEY'
```

[LiteLLM]: https://docs.litellm.ai/

<a id="ollama.MARK_PROMPT"></a>
## `ollama.MARK_PROMPT`

The marker number for prompt lines.

<a id="ollama.MARK_PROMPT_COLOR"></a>
## `ollama.MARK_PROMPT_COLOR`

The color of prompt markers.

<a id="events.MODEL_RESPONSE"></a>
## `events.MODEL_RESPONSE`

Emitted after a model responds.

This could be used to provied a notification after a long thinking window.

<a id="ollama.api_key"></a>
## `ollama.api_key`

API authorization key when chatting with external models.

The default value is `nil` since Ollama does not need this.

<a id="ollama.chat"></a>
## `ollama.chat`([*model*])

Opens a new chat session with a model.

Parameters:
- *model*:  String model name to chat with. If `nil`, the user is prompted for one.

<a id="ollama.chat_endpoint"></a>
## `ollama.chat_endpoint`

REST endpoint for chatting with a model.

The default value is '/api/chat' and should only be changed if you are not using Ollama.

<a id="ollama.chat_message"></a>
## `ollama.chat_message`(*response*)

Function to extract the message from the REST response for `chat_endpoint`.

This should only be changed if you are not using Ollama.

Parameters:
- *response*:  Table containing a model response.

<a id="ollama.curl_headers"></a>
## `ollama.curl_headers`

Optional map of HTTP headers to send with curl requests to an external model.

The default value is an empty map since Ollama does not need any headers.

<a id="ollama.model_name_key"></a>
## `ollama.model_name_key`

The key whose value is the model name for each model in the REST response for `models_endpoint`.

The default value is 'name' and should only be changed if you are not using Ollama.

<a id="ollama.model_options"></a>
## `ollama.model_options`

Map of model names with their options.

Options are tables that will be encoded into JSON before being sent to Ollama.

<a id="ollama.models_endpoint"></a>
## `ollama.models_endpoint`

REST endpoint for fetching a list of available models.

The default value is '/api/tags' and should only be changed if you are not using Ollama.

<a id="ollama.prompt"></a>
## `ollama.prompt`(*input*)

Prompts the current chat model with input.

A model's response will be printed when it finishes thinking.

Parameters:
- *input*:  String input to prompt with. Any '@*filename*' references are replaced with
	their file's contents.

<a id="ollama.url"></a>
## `ollama.url`

URL Ollama is running on (http://host:port).

The default value is `http://localhost:11434` and should only be changed if Ollama is running on
a different port, or if you are not using Ollama.



