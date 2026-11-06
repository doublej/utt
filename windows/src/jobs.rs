//! The jobs lane: an extension declaring `sendsAudio` drops a finished clip into
//! `<id>.jobs\`, utt answers with `<stem>.json` beside it and deletes the audio and its
//! `<stem>.hints.json`. The answer file is the extension's to remove. Same files, same keys
//! and same order as utt 2.5.0 on the Mac (`Utt/Clients/Extensions/Jobs/ExtensionJobs.swift`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime};

use serde_json::{json, Value};

use crate::asr::{self, Asr};
use crate::extensions::{self, Consent, Extension};
use crate::hints;

/// The Mac polls every 300 ms behind a kqueue wake; a plain poll this short costs a few
/// directory listings and keeps the hand-off well under the Mac's worst case.
const POLL: Duration = Duration::from_millis(100);
/// `ApiConfiguration.maximumBodyBytes` on the Mac.
const MAXIMUM_BYTES: u64 = 25 * 1024 * 1024;
const AUDIO: &[&str] = &["wav", "m4a", "mp3", "aiff", "flac", "caf"];
const AWAITING_APPROVAL: &str =
    "This extension is waiting for approval in utt. Approve it with `utt approve <id>` on Windows.";

pub fn run(asr: &Asr) -> ! {
    loop {
        match next_job() {
            Some((extension, clip)) => answer(asr, &extension, &clip),
            None => std::thread::sleep(POLL),
        }
    }
}

/// The oldest clip in the highest band, across every extension that may send audio.
fn next_job() -> Option<(Extension, PathBuf)> {
    let dir = crate::paths::extensions();
    let mut found: Vec<(i32, SystemTime, Extension, PathBuf)> = Vec::new();
    for extension in extensions::installed(&dir) {
        if !extension.sends_audio || extension.consent == Consent::Disabled {
            continue;
        }
        let jobs = dir.join(format!("{}.jobs", extension.id));
        if std::fs::create_dir_all(&jobs).is_err() {
            continue;
        }
        let band = extensions::consent(&dir, &extension.id).1;
        for clip in clips(&jobs) {
            let born = std::fs::metadata(&clip).and_then(|m| m.created().or_else(|_| m.modified()));
            found.push((
                band,
                born.unwrap_or(SystemTime::now()),
                extension.clone(),
                clip,
            ));
        }
    }
    found.sort_by_key(|job| (job.0, job.1));
    found
        .into_iter()
        .next()
        .map(|(_, _, extension, clip)| (extension, clip))
}

fn clips(jobs: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(jobs) else {
        return Vec::new();
    };
    entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_file())
        .filter(|p| {
            let ext = p
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_ascii_lowercase();
            AUDIO.contains(&ext.as_str())
        })
        .collect()
}

fn answer(asr: &Asr, extension: &Extension, clip: &Path) {
    let started = SystemTime::now();
    let hints_path = clip.with_extension("hints.json");
    let result = if extension.consent == Consent::Pending {
        Err(AWAITING_APPROVAL.replace("<id>", &extension.id))
    } else {
        heard(asr, clip, &hints_path)
    };
    let finished = SystemTime::now();
    let mut body: BTreeMap<&str, Value> = BTreeMap::new();
    body.insert("startedAt", json!(iso(started)));
    body.insert("finishedAt", json!(iso(finished)));
    body.insert("startedAtMs", json!(millis(started)));
    body.insert("finishedAtMs", json!(millis(finished)));
    match result {
        Ok(heard) => {
            log!(
                "[{}] {} → {} chars in {} ms",
                extension.id,
                name(clip),
                heard.text.len(),
                heard.decode_ms
            );
            body.insert("text", json!(heard.text));
            body.insert("raw", json!(heard.raw));
            body.insert("stages", json!(heard.stages));
            body.insert("duration", json!(heard.duration));
            body.insert("timings", json!(heard.timings));
        }
        Err(error) => {
            log!("[{}] {} failed: {error}", extension.id, name(clip));
            body.insert("error", json!(error));
        }
    }
    let _ = std::fs::remove_file(clip);
    let _ = std::fs::remove_file(&hints_path);
    let bytes = serde_json::to_vec_pretty(&body).unwrap_or_default();
    if let Err(error) = extensions::write_atomically(&clip.with_extension("json"), &bytes) {
        log!("[{}] could not write the answer: {error}", extension.id);
    }
}

struct Heard {
    text: String,
    raw: String,
    stages: Vec<&'static str>,
    duration: f64,
    timings: BTreeMap<&'static str, u64>,
    decode_ms: u64,
}

fn heard(asr: &Asr, clip: &Path, hints_path: &Path) -> Result<Heard, String> {
    let size = std::fs::metadata(clip).map_err(|e| e.to_string())?.len();
    if size > MAXIMUM_BYTES {
        return Err(format!(
            "the clip is {} MB; utt takes at most 25 MB",
            size / 1_048_576
        ));
    }
    let (rate, samples) = asr::read_clip(clip)?;
    let duration = samples.len() as f64 / rate.max(1) as f64;
    let clock = Instant::now();
    let raw = asr.transcribe(rate, &samples);
    let decode_ms = clock.elapsed().as_millis() as u64;
    let mut timings = BTreeMap::from([("decode", decode_ms)]);
    let mut stages = Vec::new();
    let mut text = raw.clone();
    // Read at transcription time: written before the clip's rename, so it is whole by now.
    let wanted: Vec<String> = std::fs::read_to_string(hints_path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default();
    if !wanted.is_empty() {
        let clock = Instant::now();
        let hinted = hints::apply(&text, &wanted);
        timings.insert("hints", clock.elapsed().as_millis() as u64);
        if hinted != text {
            stages.push("hints");
            text = hinted;
        }
    }
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err("No speech was heard in the clip.".into());
    }
    Ok(Heard {
        text,
        raw,
        stages,
        duration,
        timings,
        decode_ms,
    })
}

fn iso(at: SystemTime) -> String {
    chrono::DateTime::<chrono::Utc>::from(at)
        .format("%Y-%m-%dT%H:%M:%SZ")
        .to_string()
}

fn millis(at: SystemTime) -> u64 {
    at.duration_since(SystemTime::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

fn name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}
