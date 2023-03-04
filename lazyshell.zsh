#!/usr/bin/env zsh

__get_distribution_name() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "$(sw_vers -productName) $(sw_vers -productVersion)" 2>/dev/null
  else
    echo "$(cat /etc/*-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
  fi
}

__preflight_check() {
  if [ -z "$OPENAI_API_KEY" ]; then
    echo ""
    echo "Error: OPENAI_API_KEY is not set"
    echo "Get your API key from https://beta.openai.com/account/api-keys and then run:"
    echo "export OPENAI_API_KEY=<your API key>"
    zle reset-prompt
    return 1
  fi

}

lazyshell_complete() {
  $(__preflight_check) || return 1

  local buffer_context="$BUFFER"

  # Read user input
  # Todo: use zle to read input
  local REPLY
  autoload -Uz read-from-minibuffer
  read-from-minibuffer '> GPT query: '
  BUFFER="$buffer_context"
  CURSOR=$#BUFFER

  local os=$(__get_distribution_name)
  if [[ -n "$os" ]]; then
    os=" for $os"
  else
    os=""
  fi

  local intro="You are a zsh autocomplete script. All your answers are a single command$os, and nothing else. You do not write any human-readable explanations. If you fail to answer, start your reason with \`#\`."

  if [[ -z "$buffer_context" ]]; then
    local prompt="$REPLY"
  else
    local prompt="Alter zsh command \`$buffer_context\` to comply with query \`$REPLY\`"
  fi

  # todo: better escaping
  local escaped_prompt=$(echo "$prompt" | sed 's/"/\\"/g' | sed 's/\n/\\n/g')
  local data='{"messages":[{"role": "system", "content": "'"$intro"'"},{"role": "user", "content": "'"$escaped_prompt"'"}],"model":"gpt-3.5-turbo","max_tokens":256,"temperature":0}'

  # Display a spinner while the API request is running in the background
  local spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  set +m
  local response_file=$(mktemp)
  { curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $OPENAI_API_KEY" -d "$data" https://api.openai.com/v1/chat/completions > "$response_file" } &>/dev/null &
  local pid=$!
  while true; do
    for i in "${spinner[@]}"; do
      if ! kill -0 $pid 2> /dev/null; then
        break 2
      fi
      zle -R "$i GPT query: $REPLY"
      sleep 0.1
    done
  done

  wait $pid
  if [ $? -ne 0 ]; then
    # todo displayed error is erased immediately, find a better way to display it
    zle -R "Error: API request failed"
    return 1
  fi

  # Read the response from file
  # Todo: avoid using temp files
  local response=$(cat "$response_file")
  rm "$response_file"

  local generated_text=$(echo -E $response | jq -r '.choices[0].message.content' | xargs | sed -e 's/^`\(.*\)`$/\1/')
  local error=$(echo -E $response | jq -r '.error.message')

  if [ $? -ne 0 ]; then
    zle -R "Error: Invalid response from API"
    return 1
  fi

  if [[ -n "$error" && "$error" != "null" ]]; then 
    zle -R "Error: $error"
    return 1
  fi

  # Replace the current buffer with the generated text
  BUFFER="$generated_text"
  CURSOR=$#BUFFER
}

lazyshell_explain() {
  $(__preflight_check) || return 1

  local buffer_context="$BUFFER"

  local os=$(__get_distribution_name)
  if [[ -n "$os" ]]; then
    os=" for $os"
  else
    os=""
  fi

  local intro="You are a zsh script explain bot. You are running on $os. You write short and sweet human readable explanations given a zsh script."

  local prompt="This is a zsh command \`$buffer_context\`."

  # todo: better escaping
  local escaped_prompt=$(echo "$prompt" | sed 's/"/\\"/g' | sed 's/\n/\\n/g')
  local data='{"messages":[{"role": "system", "content": "'"$intro"'"},{"role": "user", "content": "'"$escaped_prompt"'"}],"model":"gpt-3.5-turbo","max_tokens":256,"temperature":0}'

  set +m
  local response_file=$(mktemp)
  { curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $OPENAI_API_KEY" -d "$data" https://api.openai.com/v1/chat/completions > "$response_file" } &>/dev/null &
  local pid=$!

  # TODO: show the spinner
  # Display a spinner while the API request is running in the background
  local spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local pid=$!
  while true; do
    for i in "${spinner[@]}"; do
      if ! kill -0 $pid 2> /dev/null; then
        break 2
      fi
      zle -R "$i Fetching explanation..."
      sleep 0.1
    done
  done

  wait $pid
  if [ $? -ne 0 ]; then
    # todo displayed error is erased immediately, find a better way to display it
    zle -R "Error: API request failed"
    return 1
  fi

  # Read the response from file
  # Todo: avoid using temp files
  local response=$(cat "$response_file")
  rm "$response_file"

  local generated_text=$(echo -E $response | jq -r '.choices[0].message.content' | xargs | sed -e 's/^`\(.*\)`$/\1/')

  local error=$(echo -E $response | jq -r '.error.message')

  if [ $? -ne 0 ]; then
    zle -R "Error: Invalid response from API"
    return 1
  fi

  if [[ -n "$error" && "$error" != "null" ]]; then 
    zle -R "Error: $error"
    return 1
  fi

  # Replace the current buffer with the generated text
  BUFFER="$buffer_context # $generated_text"
  CURSOR=$#BUFFER
}

if [ -z "$OPENAI_API_KEY" ]; then
  echo "Warning: OPENAI_API_KEY is not set"
  echo "Get your API key from https://beta.openai.com/account/api-keys and then run:"
  echo "export OPENAI_API_KEY=<your API key>"
fi

# Bind the __lazyshell_complete function to the Alt-g hotkey
zle -N lazyshell_complete
zle -N lazyshell_explain
bindkey '\eg' lazyshell_complete
bindkey '\ee' lazyshell_explain

typeset -ga ZSH_AUTOSUGGEST_CLEAR_WIDGETS
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=( lazyshell_explain )
