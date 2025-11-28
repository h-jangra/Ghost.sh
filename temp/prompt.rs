use std::env;
use std::process::Command;

const ANSI_COLOR_RESET: &str = "\x1b[0m";

pub struct Prompt {
    ps1_template: String,
}

impl Prompt {
    pub fn new() -> Self {
        let ps1 = Self::get_bash_ps1().unwrap_or_else(|| "\\W \\$ ".to_string());
        Self { ps1_template: ps1 }
    }

    fn get_bash_ps1() -> Option<String> {
        // Try environment variable first
        if let Ok(ps1) = env::var("PS1") {
            return Some(ps1);
        }

        // Try getting from bash
        let output = Command::new("bash")
            .arg("-i")
            .arg("-c")
            .arg("echo \"$PS1\"")
            .output()
            .ok()?;

        if output.status.success() {
            let ps1 = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !ps1.is_empty() && ps1 != "$PS1" {
                return Some(ps1);
            }
        }

        None
    }

    pub fn render(&mut self) -> String {
        self.expand_ps1()
    }

    fn expand_ps1(&self) -> String {
        let mut result = String::new();
        let mut chars = self.ps1_template.chars().peekable();

        while let Some(ch) = chars.next() {
            if ch == '\\' {
                if let Some(&next) = chars.peek() {
                    chars.next();
                    match next {
                        'w' => {
                            // Full path with ~
                            if let Ok(cwd) = env::current_dir() {
                                if let Some(home) = dirs::home_dir() {
                                    if cwd.starts_with(&home) {
                                        let relative = cwd.strip_prefix(&home).unwrap();
                                        result.push('~');
                                        if !relative.as_os_str().is_empty() {
                                            result.push('/');
                                            result.push_str(&relative.to_string_lossy());
                                        }
                                    } else {
                                        result.push_str(&cwd.to_string_lossy());
                                    }
                                } else {
                                    result.push_str(&cwd.to_string_lossy());
                                }
                            }
                        }
                        'W' => {
                            // Basename
                            if let Ok(cwd) = env::current_dir() {
                                if let Some(home) = dirs::home_dir() {
                                    if cwd == home {
                                        result.push('~');
                                    } else {
                                        let name = cwd
                                            .file_name()
                                            .unwrap_or_else(|| cwd.as_os_str())
                                            .to_string_lossy();
                                        result.push_str(&name);
                                    }
                                } else {
                                    let name = cwd
                                        .file_name()
                                        .unwrap_or_else(|| cwd.as_os_str())
                                        .to_string_lossy();
                                    result.push_str(&name);
                                }
                            }
                        }
                        'u' => {
                            if let Ok(user) = env::var("USER") {
                                result.push_str(&user);
                            }
                        }
                        'h' => {
                            if let Ok(hostname) = hostname::get() {
                                let h = hostname.to_string_lossy();
                                if let Some(short) = h.split('.').next() {
                                    result.push_str(short);
                                } else {
                                    result.push_str(&h);
                                }
                            }
                        }
                        'H' => {
                            if let Ok(hostname) = hostname::get() {
                                result.push_str(&hostname.to_string_lossy());
                            }
                        }
                        '$' => {
                            let uid = unsafe { libc::getuid() };
                            if uid == 0 {
                                result.push('#');
                            } else {
                                result.push('$');
                            }
                        }
                        '\\' => result.push('\\'),
                        'n' => result.push('\n'),
                        'r' => result.push('\r'),
                        'e' => result.push('\x1b'),
                        '[' | ']' => {
                            // Skip bracket characters used in bash color codes
                        }
                        _ => {
                            // Unknown escape sequence, just print both characters
                            result.push('\\');
                            result.push(next);
                        }
                    }
                } else {
                    result.push(ch);
                }
            } else {
                result.push(ch);
            }
        }

        result
    }
}

impl Default for Prompt {
    fn default() -> Self {
        Self::new()
    }
}
