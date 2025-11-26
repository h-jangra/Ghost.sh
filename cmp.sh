#!/bin/bash

# Ghost completion wrapper for bash
# Add this to your .bashrc or source it

ghost_prompt() {
    while true; do
        # Show your actual PS1 prompt
        echo -ne "${PS1@P}"
        
        # Call the rust binary to get input with ghost completion
        local cmd
        cmd=$(fish-ghost-completion)
        local exit_code=$?
        
        # Handle Ctrl+C or empty input
        if [ $exit_code -eq 130 ] || [ -z "$cmd" ]; then
            echo
            continue
        fi
        
        # Check for exit commands
        if [ "$cmd" = "exit" ] || [ "$cmd" = "quit" ]; then
            break
        fi
        
        # Add to bash history
        history -s "$cmd"
        
        # Execute the command
        eval "$cmd"
    done
}

# Alias to start the ghost completion shell
alias ghost='ghost_prompt'
