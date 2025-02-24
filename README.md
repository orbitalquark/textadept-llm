<a id="ollama"></a>
# ollama

Chat with local [Ollama][] models using Textadept.
Requires Ollama and `curl` to be installed, and Ollama needs to be running in server mode
with one or more local models available.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

	require('ollama')

Start a chat session from the Tools > Ollama > Chat... menu.

Pressing `Enter` will prompt the model with the current or selected lines. Pressing
`Shift+Enter` adds a new line without prompting the model. Typing `@` will prompt you for
an open file to inline as context to the model prompt.

[Ollama]: https://ollama.com/

## Fields defined by `ollama`

<a id="ollama.MARK_PROMPT"></a>
### `ollama.MARK_PROMPT`

The marker number for prompt lines.

<a id="ollama.MARK_PROMPT_COLOR"></a>
### `ollama.MARK_PROMPT_COLOR`

The color of prompt markers.

<a id="ollama.model_options"></a>
### `ollama.model_options` &lt;table&gt;

Map of model names with their options.
Options are tables that will be encoded into JSON before being sent to Ollama.

<a id="ollama.url"></a>
### `ollama.url`

URL Ollama is running on (http://host:port).


## Functions defined by `ollama`

<a id="ollama.chat"></a>
### `ollama.chat`([*model*])

Opens a new chat session with model name *model*, or the user-selected model if none was
given.

Parameters:

- *model*:  String model name to chat with.

<a id="ollama.prompt"></a>
### `ollama.prompt`(*input*)

Prompts the current chat model with string *input*.
Any `@filename` references are replaced with their file's contents.
Prints whatever the model responds with when it finishes thinking.

Parameters:

- *input*:  String input to prompt with.


---
