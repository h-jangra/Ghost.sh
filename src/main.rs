use crossterm::{
    cursor::MoveToColumn,
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    style::{Color, Print, ResetColor, SetForegroundColor},
    terminal::{self, Clear, ClearType},
};
use std::collections::VecDeque;
use std::env;
use std::fs::File;
use std::io::{self, BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::exit;
use std::process::Command;

const HISTORY_SIZE: usize = 1000;
const GHOST_COLOR: Color = Color::Rgb {
    r: 80,
    g: 80,
    b: 80,
};

const ANSI_COLOR_BLUE: &str = "\x1b[34m";
const ANSI_COLOR_RESET: &str = "\x1b[0m";

const PROMPT_ARROW: &str = "❱";

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

    fn visible_length(s: &str) -> usize {
        let mut count = 0;
        let mut in_ansi = false;

        for c in s.chars() {
            if c == '\x1b' {
                in_ansi = true;
                continue;
            }

            if in_ansi {
                if c.is_alphabetic() || c.is_ascii_control() {
                    if c.is_alphabetic() {
                        in_ansi = false;
                    } else if c.is_ascii_control() && c != '[' && c != ';' {
                        in_ansi = false;
                    }
                }
                continue;
            }

            if !c.is_control() {
                count += 1;
            }
        }
        count
    }

    fn get_prompt(&self) -> String {
        let current_dir = env::current_dir().unwrap_or_default();
        let dir_name = current_dir
            .file_name()
            .unwrap_or_else(|| current_dir.as_os_str())
            .to_string_lossy();

        let mut prompt = format!(
            "{blue}{}{reset} ",
            dir_name,
            blue = ANSI_COLOR_BLUE,
            reset = ANSI_COLOR_RESET,
        );

        prompt.push_str(&format!("{prompt_arrow} ", prompt_arrow = PROMPT_ARROW));

        prompt
    }

    fn find_best_match(&self, input: &str) -> Option<String> {
        if input.is_empty() {
            return None;
        }

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
        if let Some(ghost) = self.ghost_text.clone() {
            self.current_input = ghost;
            self.cursor_position = self.current_input.len();
            self.ghost_text = None;
        }
    }

    fn clear_input(&mut self) {
        self.current_input.clear();
        self.cursor_position = 0;
        self.ghost_text = None;
    }

    fn draw_prompt(&mut self) -> io::Result<()> {
        let mut stdout = io::stdout();

        let current_prompt = self.get_prompt();

        execute!(stdout, MoveToColumn(0), Clear(ClearType::UntilNewLine))?;
        execute!(stdout, Print(&current_prompt), Print(&self.current_input))?;

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

        let prompt_visible_len = Self::visible_length(&current_prompt);
        let cursor_display_pos = prompt_visible_len as u16 + self.cursor_position as u16;
        execute!(stdout, MoveToColumn(cursor_display_pos))?;

        stdout.flush()?;
        Ok(())
    }

    fn execute_command(&mut self, command: &str) -> io::Result<()> {
        let command_trimmed = command.trim();
        if command_trimmed.is_empty() {
            return Ok(());
        }

        let parts: Vec<&str> = command_trimmed.split_whitespace().collect();
        if parts.is_empty() {
            return Ok(());
        }

        if parts[0] == "history" {
            for (i, cmd) in self.history.iter().enumerate() {
                println!(" {:4}  {}", i + 1, cmd);
            }
            return Ok(());
        }

        if parts[0] == "cd" {
            let target_arg = parts.get(1).map(|s| s.to_string());

            let target_dir = match target_arg {
                None => dirs::home_dir().expect("Home directory not found"),
                Some(p) => {
                    if p == "~" || p.starts_with("~/") {
                        let home = dirs::home_dir().expect("Home directory not found");
                        if p.len() > 1 {
                            home.join(&p[2..])
                        } else {
                            home
                        }
                    } else {
                        PathBuf::from(p)
                    }
                }
            };

            if let Err(e) = env::set_current_dir(&target_dir) {
                eprintln!("cd: {}: {}", target_dir.display(), e);
            }
            return Ok(());
        }

        if parts[0] == "z" {
            let z_args = parts.get(1..).unwrap_or(&[]);

            let zoxide_result = Command::new("zoxide").arg("query").args(z_args).output();

            match zoxide_result {
                Ok(output) => {
                    if output.status.success() {
                        let target_path =
                            String::from_utf8_lossy(&output.stdout).trim().to_string();

                        if let Err(e) = env::set_current_dir(&target_path) {
                            eprintln!(
                                "zoxide: failed to change directory to {}: {}",
                                target_path, e
                            );
                        }
                    } else {
                        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
                        eprintln!("z: command failed. {}", stderr);
                    }
                }
                Err(e) => eprintln!("Failed to execute zoxide: {}", e),
            }
            return Ok(());
        }

        let status = Command::new("bash")
            .arg("-ic")
            .arg(command_trimmed)
            .status()?;

        if !status.success() {
            eprintln!("Command failed with exit code: {}", status);
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
        if let Err(e) = self.load_bash_history() {
            eprintln!("Warning: Could not load bash history: {}", e);
        }

        println!("Fish-like Ghost Completion Shell");
        println!("Type 'exit' or press Ctrl+D to quit. Use Ctrl+L to clear screen.");

        loop {
            terminal::enable_raw_mode()?;

            self.clear_input();

            execute!(io::stdout(), Print("\n"))?;

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
                        KeyCode::Char('l') if modifiers == KeyModifiers::CONTROL => {
                            execute!(io::stdout(), Clear(ClearType::All), MoveToColumn(1))?;
                        }
                        KeyCode::Enter => {
                            let command = self.current_input.clone();

                            terminal::disable_raw_mode()?;

                            if command.trim() == "exit" || command.trim() == "quit" {
                                should_exit = true;
                                break;
                            }

                            self.add_to_history(command.clone());

                            execute!(io::stdout(), Print("\r\n"))?;

                            if let Err(e) = self.execute_command(&command) {
                                eprintln!("Error executing command: {}", e);
                            }

                            break;
                        }
                        KeyCode::Tab | KeyCode::Right => {
                            self.accept_ghost_text();
                        }
                        KeyCode::Backspace => {
                            self.delete_char();
                        }
                        KeyCode::Left => {
                            self.move_cursor_left();
                        }
                        KeyCode::Delete => {
                            if self.cursor_position < self.current_input.len() {
                                self.current_input.remove(self.cursor_position);
                                self.update_ghost_text();
                            }
                        }
                        KeyCode::Home => {
                            self.cursor_position = 0;
                        }
                        KeyCode::End => {
                            self.cursor_position = self.current_input.len();
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
        let _ = terminal::disable_raw_mode();
        eprintln!("Error: {}", e);
        exit(1);
    }

    Ok(())
}
