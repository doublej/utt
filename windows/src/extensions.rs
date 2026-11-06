//! The extensions folder, read the way utt 2.5.0 reads it on the Mac: a manifest is
//! `<id>.json` whose `id` matches its file name, consent lives in `<id>.consent.json`, and
//! nothing an extension writes is trusted beyond the keys used here. `skipsTextStages` is not
//! read: this build runs none of the text stages it can name (replacements, cleanup, formatting).

use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::{json, Value};

/// File suffixes that belong to an extension but are not its manifest.
const RESERVED: &[&str] = &[
    "values.json",
    "status.json",
    "action.json",
    "transcript.json",
    "partial.json",
    "level.json",
    "consent.json",
];

#[derive(Debug, Clone)]
pub struct Extension {
    pub id: String,
    pub sends_audio: bool,
    pub consent: Consent,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Consent {
    Pending,
    Approved,
    Disabled,
}

#[derive(Deserialize)]
struct Manifest {
    id: String,
    #[allow(dead_code)]
    name: String,
    #[serde(default, rename = "sendsAudio")]
    sends_audio: Option<Value>,
}

#[derive(Deserialize)]
struct ConsentFile {
    decision: String,
    #[serde(default)]
    priority: Option<String>,
}

pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && !id.starts_with('.')
        && id
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "._-".contains(c))
}

/// Every installed extension, in id order. A manifest that does not parse is skipped.
pub fn installed(dir: &Path) -> Vec<Extension> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| {
            name.ends_with(".json") && !RESERVED.iter().any(|r| name.ends_with(&format!(".{r}")))
        })
        .collect();
    names.sort();
    names.iter().filter_map(|name| read(dir, name)).collect()
}

fn read(dir: &Path, name: &str) -> Option<Extension> {
    let stem = name.strip_suffix(".json")?;
    let text = std::fs::read_to_string(dir.join(name)).ok()?;
    let manifest: Manifest = serde_json::from_str(&text).ok()?;
    if manifest.id != stem || !valid_id(&manifest.id) {
        return None;
    }
    Some(Extension {
        consent: consent(dir, &manifest.id).0,
        id: manifest.id,
        sends_audio: manifest
            .sends_audio
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
    })
}

fn consent_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.consent.json"))
}

/// The decision and the priority band (next = -10, normal = 0, last = 10). No file is pending.
pub fn consent(dir: &Path, id: &str) -> (Consent, i32) {
    let Ok(text) = std::fs::read_to_string(consent_path(dir, id)) else {
        return (Consent::Pending, 0);
    };
    let Ok(file) = serde_json::from_str::<ConsentFile>(&text) else {
        return (Consent::Pending, 0);
    };
    let decision = match file.decision.as_str() {
        "approved" => Consent::Approved,
        "disabled" => Consent::Disabled,
        _ => Consent::Pending,
    };
    let band = match file.priority.as_deref() {
        Some("next") => -10,
        Some("last") => 10,
        _ => 0,
    };
    (decision, band)
}

/// What the Mac's consent sheet writes when the person approves an extension.
pub fn approve(dir: &Path, id: &str) -> Result<PathBuf, String> {
    if !valid_id(id) {
        return Err(format!("not an extension id: {id}"));
    }
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let stamp = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let body = json!({ "decision": "approved", "decidedAt": stamp, "priority": "normal" });
    let path = consent_path(dir, id);
    write_atomically(&path, &serde_json::to_vec_pretty(&body).unwrap_or_default())?;
    Ok(path)
}

/// Temp file then rename, so a reader never sees half a file.
pub fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    std::fs::write(&tmp, bytes).map_err(|e| format!("write {}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("rename to {}: {e}", path.display()))
}
