use std::collections::VecDeque;
use std::io;
use std::path::PathBuf;

struct History {
    entries: VecDeque<String>,
    _file_path: PathBuf,
    _max_size: usize,
}

impl History {
    fn new(max_size: usize) -> io::Result<Self> {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let file_path = PathBuf::from(home).join(".bash_history");

        let mut entries = VecDeque::new();

        if let Ok(content) = std::fs::read_to_string(&file_path) {
            for line in content.lines().rev().take(max_size) {
                if !line.trim().is_empty() {
                    entries.push_front(line.to_string());
                }
            }
        }

        Ok(History {
            entries,
            _file_path: file_path,
            _max_size: max_size,
        })
    }

    fn find_suggestion(&self, prefix: &str) -> Option<String> {
        if prefix.is_empty() {
            return None;
        }

        self.entries
            .iter()
            .rev()
            .find(|entry| entry.starts_with(prefix) && entry.len() > prefix.len())
            .map(|s| s[prefix.len()..].to_string())
    }
}

struct GhostEditor {
    history: History,
}

impl GhostEditor {
    fn new() -> io::Result<Self> {
        Ok(GhostEditor {
            history: History::new(10000)?,
        })
    }

    pub fn ghost_widget(&mut self) -> io::Result<()> {
        if let Ok(line) = std::env::var("READLINE_LINE") {
            if let Some(suggestion) = self.history.find_suggestion(&line) {
                eprint!("\x1b[90m{}\x1b[0m", suggestion);
            }
        }
        Ok(())
    }

    pub fn accept_ghost(&mut self) -> io::Result<()> {
        if let Ok(line) = std::env::var("READLINE_LINE") {
            if let Some(suggestion) = self.history.find_suggestion(&line) {
                println!("{}{}", line, suggestion);
            }
        }
        Ok(())
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        println!("Ghost Editor - Testing Mode");
        println!("Commands: ghost-widget, accept-ghost");
        return Ok(());
    }

    let mut editor = GhostEditor::new()?;

    match args[1].as_str() {
        "ghost-widget" => editor.ghost_widget(),
        "accept-ghost" => editor.accept_ghost(),
        _ => {
            eprintln!("Unknown command: {}", args[1]);
            std::process::exit(1);
        }
    }
}
