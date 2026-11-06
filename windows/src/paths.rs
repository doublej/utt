//! Where utt keeps its files on Windows. The layout under the root is the macOS one, so an
//! extension written against utt on the Mac finds the same names here.

use std::path::PathBuf;

fn env_dir(name: &str) -> PathBuf {
    std::env::var_os(name)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

/// `%APPDATA%\dev.jurrejan.utt`, or `UTT_APPLICATION_SUPPORT` — the same override the Mac app takes.
pub fn support() -> PathBuf {
    match std::env::var_os("UTT_APPLICATION_SUPPORT") {
        Some(dir) => PathBuf::from(dir),
        None => env_dir("APPDATA").join("dev.jurrejan.utt"),
    }
}

pub fn extensions() -> PathBuf {
    support().join("extensions")
}

/// Machine-local: the model and the log are large or chatty, so they stay out of the roaming profile.
pub fn local() -> PathBuf {
    env_dir("LOCALAPPDATA").join("utt")
}

pub fn model() -> PathBuf {
    match std::env::var_os("UTT_MODEL_DIR") {
        Some(dir) => PathBuf::from(dir),
        None => local()
            .join("models")
            .join("sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"),
    }
}

pub fn log_file() -> PathBuf {
    local().join("utt.log")
}
