use std::collections::VecDeque;
use std::fs::File;
use std::io::{self, BufRead, BufReader, Write};
use std::path::PathBuf;

pub struct HistoryManager {
    history: VecDeque<String>,
    max_size: usize,
    history_file: PathBuf,
}

impl HistoryManager {
    pub fn new(max_size: usize) -> Self {
        let home_dir = dirs::home_dir().expect("Could not find home directory");
        let history_file = home_dir.join(".ghost_history");

        Self {
            history: VecDeque::with_capacity(max_size),
            max_size,
            history_file,
        }
    }

    pub fn load_from_bash_history(&mut self) -> io::Result<()> {
        // First load bash history
        let home_dir = dirs::home_dir().expect("Could not find home directory");
        let bash_history = home_dir.join(".bash_history");

        if let Ok(file) = File::open(&bash_history) {
            let reader = BufReader::new(file);
            for line in reader.lines() {
                if let Ok(command) = line {
                    let command = command.trim().to_string();
                    if !command.is_empty() && !command.starts_with('#') {
                        self.add_internal(command);
                    }
                }
            }
        }

        // Then load ghost history (which takes precedence)
        if let Ok(file) = File::open(&self.history_file) {
            let reader = BufReader::new(file);
            for line in reader.lines() {
                if let Ok(command) = line {
                    let command = command.trim().to_string();
                    if !command.is_empty() && !command.starts_with('#') {
                        self.add_internal(command);
                    }
                }
            }
        }

        Ok(())
    }

    pub fn save_to_file(&self) -> io::Result<()> {
        let mut file = File::create(&self.history_file)?;
        for cmd in &self.history {
            writeln!(file, "{}", cmd)?;
        }
        Ok(())
    }

    fn add_internal(&mut self, command: String) {
        if self.history.len() >= self.max_size {
            self.history.pop_front();
        }
        // Don't add if it's the same as the last command
        if self.history.back().map(|s| s.as_str()) != Some(&command) {
            self.history.push_back(command);
        }
    }

    pub fn add(&mut self, command: String) {
        let trimmed = command.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            return;
        }
        self.add_internal(trimmed.to_string());
    }

    pub fn get(&self, index: usize) -> Option<&String> {
        self.history.get(index)
    }

    pub fn last(&self) -> Option<&String> {
        self.history.back()
    }

    pub fn len(&self) -> usize {
        self.history.len()
    }

    pub fn is_empty(&self) -> bool {
        self.history.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = &String> {
        self.history.iter()
    }

    pub fn find_completion(&self, prefix: &str) -> Option<String> {
        for cmd in self.history.iter().rev() {
            if cmd.starts_with(prefix) && cmd.len() > prefix.len() {
                return Some(cmd.clone());
            }
        }
        None
    }

    pub fn search(&self, query: &str) -> Option<String> {
        if query.is_empty() {
            return self.last().cloned();
        }

        for cmd in self.history.iter().rev() {
            if cmd.contains(query) {
                return Some(cmd.clone());
            }
        }
        None
    }

    pub fn display(&self) {
        for (i, cmd) in self.history.iter().enumerate() {
            println!(" {:4}  {}", i + 1, cmd);
        }
    }

    /// Expand bash-style history references
    pub fn expand_history(&self, command: &str) -> String {
        let trimmed = command.trim();

        // Handle !! - repeat last command
        if trimmed == "!!" {
            return self.last().cloned().unwrap_or_default();
        }

        // Handle !$ - last argument of previous command
        if trimmed.contains("!$") {
            if let Some(last_cmd) = self.last() {
                if let Some(last_arg) = last_cmd.split_whitespace().last() {
                    return trimmed.replace("!$", last_arg);
                }
            }
        }

        // Handle !^ - first argument of previous command
        if trimmed.contains("!^") {
            if let Some(last_cmd) = self.last() {
                let mut parts = last_cmd.split_whitespace();
                parts.next(); // skip command
                if let Some(first_arg) = parts.next() {
                    return trimmed.replace("!^", first_arg);
                }
            }
        }

        // Handle !* - all arguments of previous command
        if trimmed.contains("!*") {
            if let Some(last_cmd) = self.last() {
                let mut parts = last_cmd.split_whitespace();
                parts.next(); // skip command
                let args: Vec<&str> = parts.collect();
                if !args.is_empty() {
                    return trimmed.replace("!*", &args.join(" "));
                }
            }
        }

        // Handle !n - command number n
        if trimmed.starts_with('!') && trimmed.len() > 1 {
            let rest = &trimmed[1..];

            // Try to parse as number
            if let Ok(n) = rest.parse::<usize>() {
                if n > 0 && n <= self.history.len() {
                    return self.history[n - 1].clone();
                }
            } else if rest.starts_with('-') {
                // !-n means n commands ago
                if let Ok(n) = rest[1..].parse::<usize>() {
                    if n > 0 && n <= self.history.len() {
                        return self.history[self.history.len() - n].clone();
                    }
                }
            } else {
                // !pattern - find last command starting with pattern
                for cmd in self.history.iter().rev() {
                    if cmd.starts_with(rest) {
                        return cmd.clone();
                    }
                }
            }
        }

        // Handle !?pattern? - find last command containing pattern
        if trimmed.starts_with("!?") && trimmed.len() > 2 {
            let pattern = &trimmed[2..];
            let pattern = pattern.trim_end_matches('?');

            for cmd in self.history.iter().rev() {
                if cmd.contains(pattern) {
                    return cmd.clone();
                }
            }
        }

        command.to_string()
    }
}
