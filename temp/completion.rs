use crate::history::HistoryManager;
use std::env;
use std::fs;
use std::path::Path;

pub enum CompletionType {
    Command(usize, String),   // token_start, token
    Directory(usize, String), // token_start, token
    File(usize, String),      // token_start, token
    None,
}

pub struct Completion {
    path_commands: Vec<String>,
}

impl Completion {
    pub fn new() -> Self {
        Self {
            path_commands: Self::load_path_commands(),
        }
    }

    fn load_path_commands() -> Vec<String> {
        let mut cmds = Vec::new();
        if let Ok(path_var) = env::var("PATH") {
            for dir in path_var.split(if cfg!(windows) { ';' } else { ':' }) {
                let p = Path::new(dir);
                if let Ok(entries) = fs::read_dir(p) {
                    for e in entries.flatten() {
                        if let Ok(ft) = e.file_type() {
                            if ft.is_file() {
                                if let Some(name) = e.file_name().to_str() {
                                    cmds.push(name.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
        cmds.sort();
        cmds.dedup();
        cmds
    }

    pub fn get_completion_type(&self, input: &str, cursor_pos: usize) -> CompletionType {
        let before_cursor = &input[..cursor_pos];
        let tokens: Vec<&str> = before_cursor.split_whitespace().collect();

        if tokens.is_empty() || before_cursor.ends_with(char::is_whitespace) {
            return CompletionType::None;
        }

        let start = before_cursor
            .rfind(char::is_whitespace)
            .map(|i| i + 1)
            .unwrap_or(0);

        let token = input[start..cursor_pos].to_string();

        if start == 0 {
            // First token - complete as command
            CompletionType::Command(start, token)
        } else {
            // Determine based on first command
            let first_cmd = tokens[0];
            if first_cmd == "cd" || first_cmd == "rmdir" || first_cmd == "pushd" {
                CompletionType::Directory(start, token)
            } else {
                CompletionType::File(start, token)
            }
        }
    }

    pub fn complete_command(
        &self,
        input: &str,
        token_start: usize,
        cursor_pos: usize,
        token: &str,
        history: &HistoryManager,
    ) -> Option<String> {
        if token.is_empty() {
            return None;
        }

        let mut candidates: Vec<String> = Vec::new();

        // Add PATH commands
        candidates.extend(self.path_commands.clone());

        // Add history first words
        for h in history.iter() {
            if let Some(first) = h.split_whitespace().next() {
                candidates.push(first.to_string());
            }
        }

        // Add built-ins
        candidates.extend(vec![
            "cd".to_string(),
            "history".to_string(),
            "clear".to_string(),
            "exit".to_string(),
            "z".to_string(),
        ]);

        candidates.sort();
        candidates.dedup();

        let best = Self::best_candidate(token, &candidates)?;
        let mut line = String::new();
        line.push_str(&input[..token_start]);
        line.push_str(&best);
        line.push_str(&input[cursor_pos..]);
        Some(line)
    }

    pub fn complete_directory(
        &self,
        input: &str,
        token_start: usize,
        cursor_pos: usize,
        token: &str,
    ) -> Option<String> {
        let cwd = env::current_dir().ok()?;
        let candidates = Self::list_entries(&cwd, true);

        if candidates.is_empty() {
            return None;
        }

        let best = Self::best_candidate(token, &candidates)?;
        let mut line = String::new();
        line.push_str(&input[..token_start]);
        line.push_str(&best);
        line.push_str(&input[cursor_pos..]);
        Some(line)
    }

    pub fn complete_file(
        &self,
        input: &str,
        token_start: usize,
        cursor_pos: usize,
        token: &str,
    ) -> Option<String> {
        let cwd = env::current_dir().ok()?;
        let candidates = Self::list_entries(&cwd, false);

        if candidates.is_empty() {
            return None;
        }

        let best = Self::best_candidate(token, &candidates)?;
        let mut line = String::new();
        line.push_str(&input[..token_start]);
        line.push_str(&best);
        line.push_str(&input[cursor_pos..]);
        Some(line)
    }

    fn list_entries(cwd: &Path, dirs_only: bool) -> Vec<String> {
        let mut out = Vec::new();
        if let Ok(entries) = fs::read_dir(cwd) {
            for e in entries.flatten() {
                let path = e.path();
                let file_name = match path.file_name().and_then(|s| s.to_str()) {
                    Some(n) => n.to_string(),
                    None => continue,
                };

                // Skip hidden files unless specifically typed
                if file_name.starts_with('.') {
                    continue;
                }

                match e.file_type() {
                    Ok(ft) => {
                        if dirs_only {
                            if ft.is_dir() {
                                out.push(file_name + "/");
                            }
                        } else {
                            if ft.is_dir() {
                                out.push(file_name + "/");
                            } else if ft.is_file() {
                                out.push(file_name);
                            }
                        }
                    }
                    Err(_) => continue,
                }
            }
        }
        out.sort();
        out
    }

    fn best_candidate(pattern: &str, candidates: &[String]) -> Option<String> {
        let mut best: Option<(usize, usize, &String)> = None;

        for c in candidates {
            let score = if c.starts_with(pattern) {
                0
            } else if Self::fuzzy_match(pattern, c) {
                1
            } else {
                continue;
            };

            let len = c.len();
            match &mut best {
                None => best = Some((score, len, c)),
                Some((b_score, b_len, _)) => {
                    if score < *b_score || (score == *b_score && len < *b_len) {
                        *b_score = score;
                        *b_len = len;
                        best.as_mut().unwrap().2 = c;
                    }
                }
            }
        }

        best.map(|(_, _, v)| v.clone())
    }

    fn fuzzy_match(pattern: &str, text: &str) -> bool {
        if pattern.is_empty() {
            return false;
        }
        let mut it = text.chars();
        for c in pattern.chars() {
            match it.position(|x| x == c) {
                Some(_) => continue,
                None => return false,
            }
        }
        true
    }
}

impl Default for Completion {
    fn default() -> Self {
        Self::new()
    }
}
