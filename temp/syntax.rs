use crossterm::style::Color;
use std::path::Path;

pub struct TextSegment {
    pub text: String,
    pub color: Color,
}

pub struct SyntaxHighlighter {
    commands: Vec<String>,
}

impl SyntaxHighlighter {
    pub fn new() -> Self {
        Self {
            commands: Self::load_common_commands(),
        }
    }

    fn load_common_commands() -> Vec<String> {
        vec![
            // Built-ins
            "cd", "exit", "quit", "history", "clear", "z", // Common commands
            "ls", "cat", "grep", "sed", "awk", "find", "xargs", "git", "cargo", "npm", "python",
            "node", "rustc", "mkdir", "rm", "cp", "mv", "touch", "chmod", "chown", "echo",
            "printf", "read", "export", "source", "ps", "top", "kill", "killall", "pkill", "curl",
            "wget", "ssh", "scp", "rsync", "tar", "gzip", "gunzip", "zip", "unzip", "vim", "nano",
            "emacs", "code", "sudo", "su", "passwd", "man", "help", "which", "whereis", "type",
            "head", "tail", "less", "more", "wc", "sort", "uniq", "docker", "kubectl", "helm",
        ]
        .into_iter()
        .map(String::from)
        .collect()
    }

    pub fn highlight(&self, input: &str) -> Vec<TextSegment> {
        if input.is_empty() {
            return vec![];
        }

        let mut segments = Vec::new();
        let mut current_pos = 0;
        let tokens = self.tokenize(input);

        for (i, token) in tokens.iter().enumerate() {
            let start = current_pos;
            let end = start + token.len();

            // Skip if out of bounds
            if end > input.len() {
                break;
            }

            let text = token.to_string();
            let color = if i == 0 {
                // First token - command
                if self.is_valid_command(&text) {
                    Color::Green
                } else if text.starts_with('#') {
                    Color::DarkGrey
                } else {
                    Color::Red
                }
            } else if token.starts_with('-') {
                // Flags
                Color::Cyan
            } else if token.starts_with('$') {
                // Variables
                Color::Yellow
            } else if token.starts_with('"') || token.starts_with('\'') {
                // Strings
                Color::Magenta
            } else if token.starts_with('~') || token.starts_with('/') || token.starts_with('.') {
                // Paths
                if self.path_exists(token) {
                    Color::Blue
                } else {
                    Color::DarkBlue
                }
            } else if token.parse::<i64>().is_ok() || token.parse::<f64>().is_ok() {
                // Numbers
                Color::Magenta
            } else if self.is_operator(token) {
                // Operators
                Color::Yellow
            } else {
                // Default
                Color::White
            };

            segments.push(TextSegment { text, color });

            // Add whitespace if not at end
            current_pos = end;
            if current_pos < input.len() {
                let next_token_start = input[current_pos..]
                    .find(|c: char| !c.is_whitespace())
                    .map(|i| current_pos + i)
                    .unwrap_or(input.len());

                if next_token_start > current_pos {
                    let whitespace = input[current_pos..next_token_start].to_string();
                    segments.push(TextSegment {
                        text: whitespace,
                        color: Color::White,
                    });
                    current_pos = next_token_start;
                }
            }
        }

        // Add any remaining text
        if current_pos < input.len() {
            segments.push(TextSegment {
                text: input[current_pos..].to_string(),
                color: Color::White,
            });
        }

        segments
    }

    fn tokenize<'a>(&self, input: &'a str) -> Vec<&'a str> {
        let mut tokens = Vec::new();
        let mut in_quotes = false;
        let mut quote_char = ' ';
        let mut start = 0;

        for (i, c) in input.char_indices() {
            if c == '"' || c == '\'' {
                if !in_quotes {
                    if i > start {
                        let token = &input[start..i];
                        if !token.trim().is_empty() {
                            tokens.push(token);
                        }
                    }
                    in_quotes = true;
                    quote_char = c;
                    start = i;
                } else if c == quote_char {
                    tokens.push(&input[start..=i]);
                    in_quotes = false;
                    start = i + 1;
                }
            } else if c.is_whitespace() && !in_quotes {
                if i > start {
                    let token = &input[start..i];
                    if !token.trim().is_empty() {
                        tokens.push(token);
                    }
                }
                start = i + 1;
            }
        }

        // Add remaining
        if start < input.len() {
            let token = &input[start..];
            if !token.trim().is_empty() {
                tokens.push(token);
            }
        }

        tokens
    }

    fn is_valid_command(&self, cmd: &str) -> bool {
        // Check built-in commands first
        if self.commands.contains(&cmd.to_string()) {
            return true;
        }

        // Check if command exists in PATH using std library
        if let Ok(path_var) = std::env::var("PATH") {
            for dir in path_var.split(if cfg!(windows) { ';' } else { ':' }) {
                let mut cmd_path = std::path::PathBuf::from(dir);
                cmd_path.push(cmd);

                if cmd_path.exists() {
                    return true;
                }

                // On Unix-like systems, also check without extension
                #[cfg(unix)]
                if cmd_path.is_file() {
                    use std::os::unix::fs::PermissionsExt;
                    if let Ok(metadata) = std::fs::metadata(&cmd_path) {
                        let permissions = metadata.permissions();
                        if permissions.mode() & 0o111 != 0 {
                            return true;
                        }
                    }
                }
            }
        }

        false
    }

    fn path_exists(&self, path: &str) -> bool {
        // Expand ~ if needed
        let expanded = if path.starts_with('~') {
            if let Some(home) = dirs::home_dir() {
                home.join(&path[1..]).to_string_lossy().to_string()
            } else {
                path.to_string()
            }
        } else {
            path.to_string()
        };

        Path::new(&expanded).exists()
    }

    fn is_operator(&self, token: &str) -> bool {
        matches!(
            token,
            "|" | "||" | "&&" | ">" | ">>" | "<" | "<<" | "&" | ";" | "(" | ")" | "{" | "}" | "="
        )
    }
}

impl Default for SyntaxHighlighter {
    fn default() -> Self {
        Self::new()
    }
}
