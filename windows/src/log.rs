//! One appended line per event in `%LOCALAPPDATA%\utt\utt.log`. The app has no console.

use std::io::Write;

pub fn line(message: &str) {
    let stamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
    let path = crate::paths::log_file();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        let _ = writeln!(file, "{stamp}  {message}");
    }
}

#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => { $crate::log::line(&format!($($arg)*)) };
}
