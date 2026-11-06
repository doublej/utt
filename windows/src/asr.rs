//! Parakeet TDT 0.6b v3 — the model utt uses by default on the Mac — through sherpa-onnx.
//! One recognizer for the whole app, behind a mutex: the hotkey and the jobs lane take turns,
//! as they do on the Mac, where a clip in progress is never interrupted.

use std::path::Path;
use std::sync::Mutex;

use sherpa_onnx::{OfflineRecognizer, OfflineRecognizerConfig};

pub struct Asr {
    recognizer: Mutex<OfflineRecognizer>,
}

impl Asr {
    pub fn load(dir: &Path) -> Result<Self, String> {
        prefer_bundled_runtime();
        // The fp32 export names its files `encoder.onnx`, the int8 one `encoder.int8.onnx`.
        let file = |name: &str| {
            let quantized = name.replace(".onnx", ".int8.onnx");
            [name, quantized.as_str()]
                .iter()
                .map(|n| dir.join(n))
                .find(|path| path.is_file())
                .map(|path| Some(path.to_string_lossy().into_owned()))
                .ok_or_else(|| format!("model file missing: {}", dir.join(name).display()))
        };
        let mut config = OfflineRecognizerConfig::default();
        config.model_config.transducer.encoder = file("encoder.onnx")?;
        config.model_config.transducer.decoder = file("decoder.onnx")?;
        config.model_config.transducer.joiner = file("joiner.onnx")?;
        config.model_config.tokens = file("tokens.txt")?;
        config.model_config.model_type = Some("nemo_transducer".into());
        config.model_config.num_threads = threads();
        config.model_config.provider = Some(provider());
        config.decoding_method = Some("greedy_search".into());
        let recognizer = OfflineRecognizer::create(&config)
            .ok_or_else(|| format!("sherpa-onnx could not load the model in {}", dir.display()))?;
        Ok(Self {
            recognizer: Mutex::new(recognizer),
        })
    }

    /// Mono samples at `rate` in, the words heard out (trimmed, unprocessed).
    pub fn transcribe(&self, rate: i32, samples: &[f32]) -> String {
        let recognizer = self
            .recognizer
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let stream = recognizer.create_stream();
        stream.accept_waveform(rate, samples);
        recognizer.decode(&stream);
        stream
            .get_result()
            .map(|result| result.text.trim().to_string())
            .unwrap_or_default()
    }
}

/// `cuda` unless `UTT_PROVIDER` says otherwise. On a build linked against the CPU-only
/// sherpa-onnx, or with no CUDA 12 and cuDNN 9 on PATH, onnxruntime falls back to the CPU itself.
pub fn provider() -> String {
    std::env::var("UTT_PROVIDER").unwrap_or_else(|_| "cuda".into())
}

fn threads() -> i32 {
    let available = std::thread::available_parallelism().map_or(4, |n| n.get());
    available.clamp(1, 8) as i32
}

/// Any clip utt on the Mac opens (wav, m4a, mp3, aiff, flac, caf) as mono f32 samples and its rate.
pub fn read_clip(path: &Path) -> Result<(i32, Vec<f32>), String> {
    use symphonia::core::audio::SampleBuffer;
    use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
    use symphonia::core::errors::Error;
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let unreadable = |e: Error| format!("could not read the clip: {e}");
    let file = std::fs::File::open(path).map_err(|e| format!("could not open the clip: {e}"))?;
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let source = MediaSourceStream::new(Box::new(file), Default::default());
    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            source,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(unreadable)?;
    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or("the clip has no audio track")?;
    let (track_id, mut rate) = (track.id, track.codec_params.sample_rate.unwrap_or(0));
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(unreadable)?;
    let mut samples = Vec::new();
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(Error::ResetRequired) => break,
            Err(e) => return Err(unreadable(e)),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(Error::DecodeError(_)) => continue, // one bad packet is not a lost clip
            Err(e) => return Err(unreadable(e)),
        };
        let spec = *decoded.spec();
        rate = spec.rate;
        let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buffer.copy_interleaved_ref(decoded);
        samples.extend(mono(buffer.samples(), spec.channels.count()));
    }
    if rate == 0 {
        return Err("the clip has no sample rate".into());
    }
    Ok((rate as i32, samples))
}

pub fn mono(interleaved: &[f32], channels: usize) -> Vec<f32> {
    if channels <= 1 {
        return interleaved.to_vec();
    }
    interleaved
        .chunks(channels)
        .map(|frame| frame.iter().sum::<f32>() / channels as f32)
        .collect()
}

/// Windows 11 ships an older `onnxruntime.dll` (1.17) in System32, and sherpa-onnx ends up
/// with that one ("API version [28] is not available"). Loading the copy beside utt.exe by
/// full path first means every later load by name gets it instead.
#[cfg(windows)]
fn prefer_bundled_runtime() {
    use windows_sys::Win32::System::LibraryLoader::LoadLibraryW;
    let Some(dir) = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(Path::to_path_buf))
    else {
        return;
    };
    let path: Vec<u16> = dir
        .join("onnxruntime.dll")
        .to_string_lossy()
        .encode_utf16()
        .chain(Some(0))
        .collect();
    if unsafe { LoadLibraryW(path.as_ptr()) }.is_null() {
        crate::log!("could not load {}", dir.join("onnxruntime.dll").display());
    }
}

#[cfg(not(windows))]
fn prefer_bundled_runtime() {}
