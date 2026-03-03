# Bash Ghost Suggestions
![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Dependencies](https://img.shields.io/badge/Dependencies-None-brightgreen)
![Status](https://img.shields.io/badge/Status-Stable-success)

A lightweight, fast, pure Bash ghost text suggestion system.

Type a command prefix → see inline ghost text → press → (Right Arrow)  to accept.

<p align="center">
  <img src="assets/demo.gif" width="800" alt="Demo">
</p>

## Features

- ⚡ Instant prefix-based suggestions
- ➡ Accept with **Right Arrow**
- ⌫ Backspace updates suggestions live
- ⬆⬇ Native Bash history untouched
- 🎨 Subtle inline ghost UI
- 🧠 Deduplicated + indexed history for performance
- 🔌 No plugins. No external dependencies

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
- **Press Right Arrow** - Accept the current suggestion
- **Press Backspace** - Remove characters and update suggestion

## How It Works

- Loads recent entries from your Bash history
- Deduplicates and indexes them by first character
- Performs fast prefix matching as you type
- Renders ghost text inline using ANSI cursor save/restore
- Never modifies history
- Never overrides Tab completion
- Leaves native Bash behavior intact

## Requirements

- Bash 4.0+
- ANSI-compatible terminal
- Readable `~/.bash_history`

## Limitations

- Prefix matching only (no fuzzy search)
- Bash only (not zsh/fish)
- Suggestions shown at end of line only
- Designed for interactive shells
