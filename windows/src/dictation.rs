//! Hold Right Ctrl, speak, release: the words are pasted at the cursor. The Windows stand-in
//! for the Mac's Control+Fn hold (there is no Fn key Windows can see). A low-level keyboard
//! hook watches the key; the microphone runs only while it is held.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use windows_sys::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData,
};
use windows_sys::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, VK_CONTROL,
    VK_RCONTROL, VK_V,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage,
    KBDLLHOOKSTRUCT, LLKHF_INJECTED, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN,
    WM_SYSKEYUP,
};

use crate::asr::Asr;

const CF_UNICODETEXT: u32 = 13;
/// The API refuses clips under 0.3 s on the Mac; a tap of the key is not dictation either.
const SHORTEST: f64 = 0.3;

enum Event {
    Start,
    Stop,
}

static EVENTS: OnceLock<Sender<Event>> = OnceLock::new();
static HELD: AtomicBool = AtomicBool::new(false);

/// Runs the hook's message loop on this thread for the life of the app.
pub fn run(asr: Arc<Asr>) {
    let (sender, receiver) = channel();
    let _ = EVENTS.set(sender);
    std::thread::spawn(move || record(asr, receiver));
    unsafe {
        let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard), std::ptr::null_mut(), 0);
        if hook.is_null() {
            crate::log!("could not install the keyboard hook; dictation is off");
        } else {
            crate::log!("hold Right Ctrl to dictate");
        }
        let mut message: MSG = std::mem::zeroed();
        while GetMessageW(&mut message, std::ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

unsafe extern "system" fn keyboard(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code >= 0 {
        let key = &*(lparam as *const KBDLLHOOKSTRUCT);
        let ours = key.flags & LLKHF_INJECTED == 0;
        if ours && key.vkCode == VK_RCONTROL as u32 {
            let message = wparam as u32;
            let event = match message {
                WM_KEYDOWN | WM_SYSKEYDOWN if !HELD.swap(true, Ordering::SeqCst) => {
                    Some(Event::Start)
                }
                WM_KEYUP | WM_SYSKEYUP if HELD.swap(false, Ordering::SeqCst) => Some(Event::Stop),
                _ => None,
            };
            if let (Some(event), Some(events)) = (event, EVENTS.get()) {
                let _ = events.send(event);
            }
        }
    }
    CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam)
}

/// Owns the microphone: a stream exists only between Start and Stop.
fn record(asr: Arc<Asr>, events: Receiver<Event>) {
    let mut open: Option<(cpal::Stream, Arc<Mutex<Vec<f32>>>, u32, usize)> = None;
    for event in events {
        match event {
            Event::Start => match listen() {
                Ok(stream) => open = Some(stream),
                Err(error) => crate::log!("microphone: {error}"),
            },
            Event::Stop => {
                let Some((stream, buffer, rate, channels)) = open.take() else {
                    continue;
                };
                drop(stream);
                let interleaved =
                    std::mem::take(&mut *buffer.lock().unwrap_or_else(|p| p.into_inner()));
                let samples = crate::asr::mono(&interleaved, channels);
                let seconds = samples.len() as f64 / rate.max(1) as f64;
                if seconds < SHORTEST {
                    continue;
                }
                let clock = Instant::now();
                let text = asr.transcribe(rate as i32, &samples);
                crate::log!(
                    "dictation: {seconds:.1} s heard in {} ms",
                    clock.elapsed().as_millis()
                );
                if !text.is_empty() {
                    paste(&text);
                }
            }
        }
    }
}

fn listen() -> Result<(cpal::Stream, Arc<Mutex<Vec<f32>>>, u32, usize), String> {
    let device = cpal::default_host()
        .default_input_device()
        .ok_or("no input device")?;
    let config = device.default_input_config().map_err(|e| e.to_string())?;
    let (rate, channels) = (config.sample_rate().0, config.channels() as usize);
    let buffer = Arc::new(Mutex::new(Vec::<f32>::new()));
    let sink = buffer.clone();
    let failed = |error: cpal::StreamError| crate::log!("microphone stream: {error}");
    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => device.build_input_stream(
            &config.config(),
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                sink.lock().unwrap().extend_from_slice(data)
            },
            failed,
            None,
        ),
        cpal::SampleFormat::I16 => device.build_input_stream(
            &config.config(),
            move |data: &[i16], _: &cpal::InputCallbackInfo| {
                sink.lock()
                    .unwrap()
                    .extend(data.iter().map(|&s| s as f32 / 32768.0))
            },
            failed,
            None,
        ),
        other => return Err(format!("unsupported sample format {other:?}")),
    }
    .map_err(|e| e.to_string())?;
    stream.play().map_err(|e| e.to_string())?;
    Ok((stream, buffer, rate, channels))
}

/// Onto the clipboard, then Ctrl+V into whatever has focus.
fn paste(text: &str) {
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        if OpenClipboard(std::ptr::null_mut()) == 0 {
            crate::log!("could not open the clipboard");
            return;
        }
        EmptyClipboard();
        let memory = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2);
        if !memory.is_null() {
            let target = GlobalLock(memory) as *mut u16;
            std::ptr::copy_nonoverlapping(wide.as_ptr(), target, wide.len());
            GlobalUnlock(memory);
            SetClipboardData(CF_UNICODETEXT, memory);
        }
        CloseClipboard();
        let key = |vk: u16, up: bool| INPUT {
            r#type: INPUT_KEYBOARD,
            Anonymous: INPUT_0 {
                ki: KEYBDINPUT {
                    wVk: vk,
                    wScan: 0,
                    dwFlags: if up { KEYEVENTF_KEYUP } else { 0 },
                    time: 0,
                    dwExtraInfo: 0,
                },
            },
        };
        let inputs = [
            key(VK_CONTROL, false),
            key(VK_V, false),
            key(VK_V, true),
            key(VK_CONTROL, true),
        ];
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        );
    }
}
