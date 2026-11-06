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

/// The fp32 export when it is installed, else the int8 one. On the GPU fp32 is the fast one
/// (measured 2026-11-06 on an RTX 4080 SUPER: 60–86 ms warm for 3–5 s clips against 230–300 ms
/// for int8, whose quantized ops leave the GPU); on the CPU the two are about even.
pub fn model() -> PathBuf {
    if let Some(dir) = std::env::var_os("UTT_MODEL_DIR") {
        return PathBuf::from(dir);
    }
    let models = local().join("models");
    let full = models.join("sherpa-onnx-nemo-parakeet-tdt-0.6b-v3");
    if full.join("encoder.onnx").is_file() {
        return full;
    }
    models.join("sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
}

pub fn log_file() -> PathBuf {
    local().join("utt.log")
}
