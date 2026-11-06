//! utt for Windows. `utt` runs the app (hold Right Ctrl to dictate, and the extensions' jobs
//! lane); `utt approve <id>` approves an extension; `utt transcribe <clip>…` prints
//! what the model hears, for checking an install.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

#[macro_use]
mod log;
mod asr;
#[cfg(windows)]
mod dictation;
mod extensions;
mod hints;
mod jobs;
mod paths;
#[cfg(windows)]
mod tray;

use std::path::Path;
use std::sync::Arc;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        None | Some("run") => run(),
        Some("approve") => command(|| approve(args.get(1))),
        Some("transcribe") => command(|| transcribe(&args[1..])),
        Some(other) => command(|| {
            Err(format!(
                "unknown command {other}: use run, approve <id> or transcribe <clip>"
            ))
        }),
    };
    std::process::exit(code);
}

fn run() -> i32 {
    if already_running() {
        log!("utt is already running");
        return 0;
    }
    let model = paths::model();
    let asr = match asr::Asr::load(&model) {
        Ok(asr) => Arc::new(asr),
        Err(error) => {
            log!("{error}");
            return 1;
        }
    };
    log!(
        "utt {} up; provider {}; model {}; extensions {}",
        env!("CARGO_PKG_VERSION"),
        asr::provider(),
        model.display(),
        paths::extensions().display()
    );
    // The first decode on CUDA sets the device up (~280 ms); pay it here, not on the first clip.
    let clock = Instant::now();
    asr.transcribe(16_000, &[0.0; 16_000]);
    log!("warmed up in {} ms", clock.elapsed().as_millis());
    let lane = asr.clone();
    let jobs = std::thread::spawn(move || jobs::run(&lane));
    #[cfg(windows)]
    dictation::run(asr);
    let _ = jobs.join();
    0
}

fn approve(id: Option<&String>) -> Result<(), String> {
    let id = id.ok_or("usage: utt approve <id>")?;
    let path = extensions::approve(&paths::extensions(), id)?;
    println!("approved {id}: {}", path.display());
    Ok(())
}

fn transcribe(clips: &[String]) -> Result<(), String> {
    if clips.is_empty() {
        return Err("usage: utt transcribe <clip>…".into());
    }
    let asr = asr::Asr::load(&paths::model())?;
    // One process for every clip, so the timings after the first are what the app sees warm.
    for clip in clips {
        let (rate, samples) = asr::read_clip(Path::new(clip))?;
        let clock = Instant::now();
        println!("{}", asr.transcribe(rate, &samples));
        eprintln!(
            "{:.1} s of audio in {} ms ({})",
            samples.len() as f64 / rate as f64,
            clock.elapsed().as_millis(),
            asr::provider()
        );
    }
    Ok(())
}

/// A subcommand prints to the console it was started from, which a GUI-subsystem exe has to ask for.
fn command(body: impl FnOnce() -> Result<(), String>) -> i32 {
    // Only when nothing was handed over: attaching replaces a pipe the caller is reading.
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::System::Console::{
            AttachConsole, GetStdHandle, ATTACH_PARENT_PROCESS, STD_ERROR_HANDLE,
        };
        if GetStdHandle(STD_ERROR_HANDLE).is_null() {
            AttachConsole(ATTACH_PARENT_PROCESS);
        }
    }
    match body() {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

/// One hook and one jobs lane per login: a second copy would answer clips twice.
#[cfg(windows)]
fn already_running() -> bool {
    use windows_sys::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS};
    use windows_sys::Win32::System::Threading::CreateMutexW;
    let name: Vec<u16> = "Local\\dev.jurrejan.utt"
        .encode_utf16()
        .chain(Some(0))
        .collect();
    unsafe {
        CreateMutexW(std::ptr::null(), 1, name.as_ptr());
        GetLastError() == ERROR_ALREADY_EXISTS
    }
}

#[cfg(not(windows))]
fn already_running() -> bool {
    false
}
