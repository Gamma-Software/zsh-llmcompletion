
0=${(%):-%N}
typeset -g ZSH_COPILOT_PREFIX=${0:A:h}
# Source .env file if it exists
if [[ -f "$ZSH_COPILOT_PREFIX/.env" ]]; then
    source "$ZSH_COPILOT_PREFIX/.env"
fi

(( ! ${+ZSH_COPILOT_REPO} )) &&
typeset -g ZSH_COPILOT_REPO="https://github.com/Gamma-Software/zsh-copilot"

# Get the corresponding endpoint for your desired model.
(( ! ${+ZSH_COPILOT_API_URL} )) &&
typeset -g ZSH_COPILOT_API_URL="https://api.openai.com/v1/chat/completions"

# Fill up your OpenAI api key here.
if (( ! ${+ZSH_COPILOT_API_KEY} )); then
    echo "Error: ZSH_COPILOT_API_KEY is not set."
    echo "Please reinstall the plugin and follow the setup instructions at:"
    echo "https://github.com/Gamma-Software/zsh-copilot#installation"
    return 1
fi

# Default configurations
(( ! ${+ZSH_COPILOT_MODEL} )) &&
typeset -g ZSH_COPILOT_MODEL="gpt-3.5-turbo"
(( ! ${+ZSH_COPILOT_TOKENS} )) &&
typeset -g ZSH_COPILOT_TOKENS=800
(( ! ${+ZSH_COPILOT_INITIALROLE} )) &&
typeset -g ZSH_COPILOT_INITIALROLE="system"
(( ! ${+ZSH_COPILOT_INITIALPROMPT} )) &&
typeset -g ZSH_COPILOT_INITIALPROMPT="You are a large language model trained by OpenAI. Answer as concisely as possible.\nKnowledge cutoff: {knowledge_cutoff} Current date: {current_date}"


function _zsh_copilot_upgrade() {
  git -C $ZSH_COPILOT_PREFIX remote set-url origin $ZSH_COPILOT_REPO
  if git -C $ZSH_COPILOT_PREFIX pull; then
    source $ZSH_COPILOT_PREFIX/zsh-copilot.zsh
    return 0
  else
    echo "Failed to upgrade."
    return 1
  fi
}

function _zsh_copilot_show_version() {
  cat "$ZSH_COPILOT_PREFIX/VERSION"
}

function llmapi() {
    local api_url=$ZSH_COPILOT_API_URL
    local api_key=$ZSH_COPILOT_API_KEY
    local tokens=$ZSH_COPILOT_TOKENS
    local model=$ZSH_COPILOT_MODEL
    local history=""

    local usefile=false
    local filepath=""
    local requirements=("curl" "jq")
    local debug=false
    local raw=false
    local satisfied=true
    local input=""
    local assistant="assistant"
    while getopts ":hvcdmsiurM:f:t:" opt; do
        case $opt in
            h)
                _zsh_copilot_show_help
                return 0
                ;;
            v)
                _zsh_copilot_show_version
                return 0
                ;;
            u)
                if ! which "git" > /dev/null; then
                    echo "git is required for upgrade."
                    return 1
                fi
                if _zsh_copilot_upgrade; then
                    return 0
                else
                    return 1
                fi
                ;;
            d)
                debug=true
                ;;
            t)
                if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                    echo "Max tokens has to be an valid numbers."
                    return 1
                else
                    tokens=$OPTARG
                fi
                ;;
            f)
                usefile=true
                if ! [ -f $OPTARG ]; then
                    echo "$OPTARG does not exist."
                    return 1
                else
                    if ! which "xargs" > /dev/null; then
                        echo "xargs is required for file."
                        satisfied=false
                    fi
                    filepath=$OPTARG
                fi
                ;;
            M)
                model=$OPTARG
                ;;
            r)
                raw=true
                ;;
            :)
                echo "-$OPTARG needs a parameter"
                return 1
                ;;
        esac
    done

    for i in "${requirements[@]}"
    do
    if ! which $i > /dev/null; then
        echo "zsh-ask \033[0;31merror:\033[0m $i is required."
        return 1
    fi
    done

    shift $((OPTIND-1))

    input=$*

    if $usefile; then
        input="$input$(cat "$filepath")"
    elif ! $raw && [ "$input" = "" ]; then
        echo -n "\033[32muser: \033[0m"
        read -r input
    fi


    while true; do
        history=$history' {"role":"user", "content":"'"$input"'"}'
        if $debug; then
            echo -E "$history"
        fi
        local data='{"messages":['$history'], "model":"'$model'", "stream":'$stream', "max_tokens":'$tokens'}'
        local message=""
        local generated_text=""
        if $stream; then
            local begin=true
            local token=""

            curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $api_key" -d $data $api_url | while read -r token; do
                if [ "$token" = "" ]; then
                    continue
                fi
                if $debug || $raw; then
                    echo -E $token
                fi
                if ! $raw; then
                    token=${token:6}
                    if ! $raw && delta_text=$(echo -E $token | jq -re '.choices[].delta.role'); then
                        assistant=$(echo -E $token | jq -je '.choices[].delta.role')
                        echo -n "\033[0;36m$assistant: \033[0m"
                    fi
                    local delta_text=""
                    if delta_text=$(echo -E $token | jq -re '.choices[].delta.content'); then
                        begin=false
                        echo -E $token | jq -je '.choices[].delta.content'
                        generated_text=$generated_text$delta_text
                    fi
                    if (echo -E $token | jq -re '.choices[].finish_reason' > /dev/null); then
                        echo ""
                        break
                    fi
                fi
            done
            message='{"role":"'"$assistant"'", "content":"'"$generated_text"'"}'
        else
            local response=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $api_key" -d $data $api_url)
            if $debug || $raw; then
                echo -E "$response"
            fi
            if ! $raw; then
                echo -n "\033[0;36m$assistant: \033[0m"
                if echo -E $response | jq -e '.error' > /dev/null; then
                    echo "zsh-ask \033[0;31merror:\033[0m"
                    echo -E $response | jq -r '.error'
                    return 1
                fi
            fi
            assistant=$(echo -E $response | jq -r '.choices[].role')
            message=$(echo -E $response | jq -r '.choices[].message')
            generated_text=$(echo -E $message | jq -r '.content')
            if ! $raw; then
                if $markdown; then
                    echo -E $generated_text | glow
                else
                    echo -E $generated_text
                fi
            fi
        fi
        history=$history', '$message', '
        ZSH_ASK_HISTORY=$history
        if ! $conversation; then
            break
        fi
        echo -n "\033[0;32muser: \033[0m"
        if ! read -r input; then
            break
        fi
    done
}

# Command prediction script using ChatGPT
# This should be saved as a separate file

function predict() {
    local history_size=10  # Number of recent commands to analyze
    local current_dir=$(pwd)

    # Gather recent command history with exit codes
    local history_data=$(fc -l -n -$history_size |
        while IFS= read -r cmd; do
            # Skip the predict-command itself
            if [[ "$cmd" != "predict" ]]; then
                echo "Command: $cmd"
                # You might want to add error messages if available
            fi
        done)

    # Construct the prompt and escape it properly for JSON
    local prompt=$(echo "I am in directory: ${current_dir}

Recent command history:
${history_data}

Based on this history and context, what would be the most likely next command I want to run? Provide just the command without explanation." | jq -Rs .)

    # Remove the outer quotes that jq adds
    prompt=${prompt:1:-1}

    # Use the existing ask function with specific parameters
    llmapi -M "gpt-4" -t 150 "$prompt"
}

# Create a ZLE widget
function predict-widget() {
    # Run prediction
    local result=$(predict-command)

    # Put the result in the command line buffer
    BUFFER="$result"
    CURSOR=${#BUFFER}

    # Redisplay the command line with the prediction
    zle redisplay
}

# Create a function to ask for a specific command
function ask-command() {
    local request="$1"

    # Construct the prompt for command generation
    local prompt=$(echo "I need a command to: $request

Please provide just the command without any explanation. Make it a single line that can be executed in a zsh terminal." | jq -Rs .)

    # Remove the outer quotes that jq adds
    prompt=${prompt:1:-1}

    # Use the existing ask function with specific parameters
    llmapi -M "gpt-4" -t 150 "$prompt"
}

# Create a ZLE widget for ask-command
function ask-command-widget() {
    # Get the current buffer content
    local current_text="$BUFFER"

    # Clear line
    zle kill-whole-line

    # Only proceed if there's text in the buffer
    if [[ -n "$current_text" ]]; then
        # Run ask-command with current text and store result
        local result=$(ask-command "$current_text")

        # Put the result in the command line buffer
        BUFFER="$result"
        CURSOR=${#BUFFER}
    fi

    # Redisplay the command line with the suggestion
    zle redisplay
}

# Register the widget
zle -N predict-widget
zle -N ask-command-widget

# Bind the shortcut
bindkey $ZSH_COPILOT_SHORTCUT_PREDICT predict-widget
bindkey $ZSH_COPILOT_SHORTCUT_ASK ask-command-widget