# Bash Ghost Suggestions

A pure Bash implementation of ghost text suggestions (like Fish shell) that shows autocomplete suggestions from your command history as you type.

<img width="407" height="170" alt="image" src="https://github.com/user-attachments/assets/48d529c7-cb2a-44e3-a217-6b559619ce25" />

## Features

- **Automatic suggestions** - Shows suggestions in gray text as you type
- **Real-time updates** - Suggestions update instantly with each keystroke
- **History-based** - Suggests commands from your bash history
- **Visual feedback** - Gray ghost text that won't interfere with your input
- **Simple controls** - Just press Tab to accept

## Installation

1. Save the script as `ghost.sh`
2. Add to your `~/.bashrc`:
   ```bash
   source /path/to/ghost.sh
   ```
3. Reload your shell:
   ```bash
   source ~/.bashrc
   ```

## Usage

- **Type normally** - Ghost suggestions appear automatically in gray
- **Press Tab** - Accept the current suggestion
- **Press Backspace** - Remove characters and update suggestion
- **Continue typing** - Ghost text updates to match your input

## How It Works

The script searches your bash history (from newest to oldest) and shows the first matching command that starts with what you've typed. The matching portion appears in gray text after your cursor.

## Requirements

- Bash 4.0 or later
- Terminal with ANSI escape sequence support
- Readable `~/.bash_history` file

## Configuration

You can customize these variables at the top of the script:

- `_ghost_history_file` - Path to history file (default: `~/.bash_history`)
- `_ghost_max_entries` - Maximum history entries to search (default: 10000)

## Limitations

- Only supports basic printable characters (letters, numbers, common symbols)
- Suggestions are based on exact prefix matching
- May not work with all terminal emulators
- Leaves chars behind if `Ctrl-c`

## Troubleshooting

**No suggestions appearing:**
- Ensure your bash history file exists and has commands
- Try typing the beginning of a command you've used before

**Weird characters on screen:**
- Your terminal may not support ANSI escape sequences
- Try a different terminal emulator

**Characters not appearing:**
- Make sure you've sourced the script correctly
- Restart your shell session
