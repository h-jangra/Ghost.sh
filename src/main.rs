use crossterm::{
    cursor::MoveToColumn,
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    style::{Color, Print, ResetColor, SetForegroundColor},
    terminal::{self, Clear, ClearType},
};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{self, BufRead, BufReader, Write};
use std::process::{exit, Command};

const HISTORY_SIZE: usize = 1000;
const GHOST_COLOR: Color = Color::Rgb {
    r: 80,
    g: 80,
    b: 80,
};

struct GhostCompletion {
    history: VecDeque<String>,
    current_input: String,
    cursor_position: usize,
    ghost_text: Option<String>,
}

impl GhostCompletion {
    fn new() -> Self {
        Self {
            history: VecDeque::with_capacity(HISTORY_SIZE),
            current_input: String::new(),
            cursor_position: 0,
            ghost_text: None,
        }
    }

    fn load_bash_history(&mut self) -> io::Result<()> {
        let home_dir = dirs::home_dir().expect("Could not find home directory");
        let history_path = home_dir.join(".bash_history");

        if let Ok(file) = File::open(&history_path) {
            let reader = BufReader::new(file);
            for line in reader.lines() {
                if let Ok(command) = line {
                    let command = command.trim().to_string();
                    if !command.is_empty() {
                        if self.history.len() >= HISTORY_SIZE {
                            self.history.pop_front();
                        }
                        self.history.push_back(command);
                    }
                }
            }
        }
        Ok(())
    }

    fn find_best_match(&self, input: &str) -> Option<String> {
        if input.is_empty() {
            return None;
        }

        // prefix match only
        for command in self.history.iter().rev() {
            if command.starts_with(input) && command.len() > input.len() {
                return Some(command.clone());
            }
        }

        None
    }

    fn update_ghost_text(&mut self) {
        self.ghost_text = if self.current_input.is_empty() {
            None
        } else {
            self.find_best_match(&self.current_input)
        };
    }

    fn insert_char(&mut self, c: char) {
        self.current_input.insert(self.cursor_position, c);
        self.cursor_position += 1;
        self.update_ghost_text();
    }

    fn move_cursor_left(&mut self) {
        if self.cursor_position > 0 {
            self.cursor_position -= 1;
        }
    }

    fn delete_char(&mut self) {
        if self.cursor_position > 0 && !self.current_input.is_empty() {
            self.current_input.remove(self.cursor_position - 1);
            self.cursor_position -= 1;
            self.update_ghost_text();
        }
    }

    fn accept_ghost_text(&mut self) {
        if let Some(ghost) = &self.ghost_text {
            let remaining = &ghost[self.current_input.len()..];
            self.current_input.push_str(remaining);
            self.cursor_position = self.current_input.len();
            self.ghost_text = None;
        }
    }

    fn move_cursor_right(&mut self) {
        if self.cursor_position < self.current_input.len() {
            self.cursor_position += 1;
        }
    }

    fn clear_input(&mut self) {
        self.current_input.clear();
        self.cursor_position = 0;
        self.ghost_text = None;
    }

    fn draw_prompt(&self) -> io::Result<()> {
        let mut stdout = io::stdout();

        execute!(stdout, MoveToColumn(0), Clear(ClearType::UntilNewLine))?;
        execute!(stdout, Print("> "), Print(&self.current_input))?;

        if let Some(ghost) = &self.ghost_text {
            if ghost.len() > self.current_input.len() {
                let ghost_part = &ghost[self.current_input.len()..];
                execute!(
                    stdout,
                    SetForegroundColor(GHOST_COLOR),
                    Print(ghost_part),
                    ResetColor
                )?;
            }
        }

        let cursor_display_pos = 2 + self.cursor_position as u16;
        execute!(stdout, MoveToColumn(cursor_display_pos))?;

        stdout.flush()?;
        Ok(())
    }

    fn execute_command(&self, command: &str) -> io::Result<()> {
        if command.trim().is_empty() {
            return Ok(());
        }

        // For shell builtins or complex commands, use system shell
        if command.contains('|')
            || command.contains('>')
            || command.contains('&')
            || command.contains('$')
        {
            let status = Command::new("sh").arg("-c").arg(command).status()?;

            if !status.success() {
                eprintln!("Command failed with exit code: {}", status);
            }
        } else {
            // Parse simple commands
            let parts: Vec<&str> = command.split_whitespace().collect();
            if parts.is_empty() {
                return Ok(());
            }

            let status = Command::new(parts[0]).args(&parts[1..]).status()?;

            if !status.success() {
                eprintln!("Command failed with exit code: {}", status);
            }
        }

        Ok(())
    }

    fn add_to_history(&mut self, command: String) {
        if !command.trim().is_empty() {
            if self.history.back().map(|s| s.as_str()) != Some(command.as_str()) {
                if self.history.len() >= HISTORY_SIZE {
                    self.history.pop_front();
                }
                self.history.push_back(command);
            }
        }
    }

    fn run_shell(&mut self) -> io::Result<()> {
        // Load actual bash history
        if let Err(e) = self.load_bash_history() {
            eprintln!("Warning: Could not load bash history: {}", e);
        }

        println!("Ghost Completion Shell");
        println!("Type 'exit' or press Ctrl+D to quit");
        println!();

        loop {
            terminal::enable_raw_mode()?;

            self.clear_input();
            println!(); // Separate from previous output

            let mut should_exit = false;

            loop {
                self.draw_prompt()?;

                if let Event::Key(KeyEvent {
                    code, modifiers, ..
                }) = event::read()?
                {
                    match code {
                        KeyCode::Char('c') if modifiers == KeyModifiers::CONTROL => {
                            self.clear_input();
                            println!();
                            break;
                        }
                        KeyCode::Char('d') if modifiers == KeyModifiers::CONTROL => {
                            if self.current_input.is_empty() {
                                should_exit = true;
                                println!();
                                break;
                            }
                        }
                        KeyCode::Enter => {
                            println!();
                            if !self.current_input.trim().is_empty() {
                                let command = self.current_input.clone();

                                // Check for exit command
                                if command.trim() == "exit" || command.trim() == "quit" {
                                    should_exit = true;
                                    break;
                                }

                                // Add to history and execute
                                self.add_to_history(command.clone());

                                terminal::disable_raw_mode()?;
                                if let Err(e) = self.execute_command(&command) {
                                    eprintln!("Error executing command: {}", e);
                                }
                                terminal::enable_raw_mode()?;
                            }
                            break;
                        }
                        KeyCode::Right => {
                            // Right arrow accepts ghost text if available, otherwise moves cursor
                            if self.ghost_text.is_some() {
                                self.accept_ghost_text();
                            } else {
                                self.move_cursor_right();
                            }
                        }
                        KeyCode::Tab => {
                            if self.ghost_text.is_some() {
                                self.accept_ghost_text();
                            }
                        }
                        KeyCode::Backspace => {
                            self.delete_char();
                        }
                        KeyCode::Left => {
                            self.move_cursor_left();
                        }
                        KeyCode::Char(c) => {
                            self.insert_char(c);
                        }
                        KeyCode::Esc => {
                            self.ghost_text = None;
                        }
                        _ => {}
                    }
                }
            }

            terminal::disable_raw_mode()?;

            if should_exit {
                break;
            }
        }

        Ok(())
    }
}

fn main() -> io::Result<()> {
    let mut ghost_completion = GhostCompletion::new();

    if let Err(e) = ghost_completion.run_shell() {
        eprintln!("Error: {}", e);
        exit(1);
    }

    println!("Goodbye!");
    Ok(())
}
