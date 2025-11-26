enable -f ./target/release/libghostsh.so ghost_mod

_ghost_completion_hook() {
    local current_word="${READLINE_LINE:0:READLINE_POINT}"
    local current_cmd="${current_word%% *}"

    # Only suggest for non-empty, incomplete commands
    if [[ -z "$current_cmd" || "$current_cmd" =~ [[:space:]] ]]; then
        return 0
    fi

    local suffix
    suffix="$(bash_ghost_completion "$current_cmd")"
    local exit_code=$?
    
    if [[ -n "$suffix" ]]; then
        # Display ghost text (gray color)
        echo -ne "\033[2;90m$suffix\033[0m"
        # Move cursor back to original position
        echo -ne "\033[${#suffix}D"
    fi
    
    # Free the allocated memory
    if [[ -n "$suffix" ]]; then
        bash_free_string "$suffix"
    fi
    
    return 0
}

# Use PROMPT_COMMAND to trigger the hook before the prompt is redrawn
PROMPT_COMMAND="_ghost_completion_hook; $PROMPT_COMMAND"
