//! The tray icon: Windows' stand-in for utt's menu bar item. Its menu shows each approved
//! extension's status lines (`<id>.status.json`, cut to 60 characters as on the Mac) and Quit.
//! Extension actions are not offered: an action means whatever the extension decides, and
//! Deckhand's two (`copyToken`, `pairDevice`) only work on a Mac.

use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, WPARAM};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NOTIFYICONDATAW,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreatePopupMenu, CreateWindowExW, DefWindowProcW, DestroyMenu, GetCursorPos,
    LoadIconW, PostMessageW, PostQuitMessage, RegisterClassW, SetForegroundWindow, TrackPopupMenu,
    IDI_APPLICATION, MF_GRAYED, MF_SEPARATOR, MF_STRING, TPM_RETURNCMD, TPM_RIGHTBUTTON, WM_APP,
    WM_LBUTTONUP, WM_NULL, WM_RBUTTONUP, WNDCLASSW,
};

use crate::extensions::{self, Consent};

const CALLBACK: u32 = WM_APP + 1;
const QUIT: usize = 1;

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}

/// Adds the icon. Call on the thread that runs the message loop; the icon lives as long as it.
pub fn install() {
    unsafe {
        let instance = GetModuleHandleW(std::ptr::null());
        let class = wide("utt-tray");
        let window_class = WNDCLASSW {
            lpfnWndProc: Some(procedure),
            hInstance: instance,
            lpszClassName: class.as_ptr(),
            ..std::mem::zeroed()
        };
        RegisterClassW(&window_class);
        let title = wide("utt");
        let window = CreateWindowExW(
            0,
            class.as_ptr(),
            title.as_ptr(),
            0,
            0,
            0,
            0,
            0,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            instance,
            std::ptr::null(),
        );
        if window.is_null() {
            crate::log!("could not create the tray window");
            return;
        }
        let mut icon = notify_data(window);
        icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        icon.uCallbackMessage = CALLBACK;
        icon.hIcon = LoadIconW(std::ptr::null_mut(), IDI_APPLICATION);
        let tip = wide("utt — hold Right Ctrl to dictate");
        icon.szTip[..tip.len()].copy_from_slice(&tip);
        if Shell_NotifyIconW(NIM_ADD, &icon) == 0 {
            crate::log!("could not add the tray icon");
        }
    }
}

unsafe fn notify_data(window: HWND) -> NOTIFYICONDATAW {
    let mut data: NOTIFYICONDATAW = std::mem::zeroed();
    data.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
    data.hWnd = window;
    data.uID = 1;
    data
}

unsafe extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == CALLBACK && matches!(lparam as u32, WM_RBUTTONUP | WM_LBUTTONUP) {
        if show_menu(window) == QUIT {
            Shell_NotifyIconW(NIM_DELETE, &notify_data(window));
            PostQuitMessage(0);
            std::process::exit(0);
        }
        return 0;
    }
    DefWindowProcW(window, message, wparam, lparam)
}

/// The command chosen, or 0.
unsafe fn show_menu(window: HWND) -> usize {
    let menu = CreatePopupMenu();
    let add = |flags: u32, id: usize, text: &str| {
        let text = wide(text);
        AppendMenuW(menu, flags, id, text.as_ptr());
    };
    add(
        MF_STRING | MF_GRAYED,
        0,
        "utt for Windows — hold Right Ctrl",
    );
    for line in status_lines() {
        add(MF_STRING | MF_GRAYED, 0, &line);
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, std::ptr::null());
    add(MF_STRING, QUIT, "Quit utt");
    let mut at = POINT { x: 0, y: 0 };
    GetCursorPos(&mut at);
    // Without this the menu does not close when the person clicks elsewhere.
    SetForegroundWindow(window);
    let chosen = TrackPopupMenu(
        menu,
        TPM_RETURNCMD | TPM_RIGHTBUTTON,
        at.x,
        at.y,
        0,
        window,
        std::ptr::null(),
    );
    PostMessageW(window, WM_NULL, 0, 0);
    DestroyMenu(menu);
    chosen as usize
}

/// "deckhand · sessions: 3 live", one per key, for every approved extension that writes status.
fn status_lines() -> Vec<String> {
    let dir = crate::paths::extensions();
    let mut lines = Vec::new();
    for extension in extensions::installed(&dir) {
        if extension.consent != Consent::Approved {
            continue;
        }
        let path = dir.join(format!("{}.status.json", extension.id));
        let Ok(text) = std::fs::read_to_string(path) else {
            continue;
        };
        let Ok(serde_json::Value::Object(status)) = serde_json::from_str(&text) else {
            continue;
        };
        for (key, value) in status {
            let value: String = value
                .as_str()
                .unwrap_or_default()
                .chars()
                .take(60)
                .collect();
            lines.push(format!("{} · {key}: {value}", extension.id));
        }
    }
    lines
}
