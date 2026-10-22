// The Windows clipboard, for the in-shell Clipboard app.
//
// Text only for now (CF_UNICODETEXT): it is what a clipboard history actually
// needs, and it keeps the ABI a single UTF-8 string. The sequence number lets
// the app poll cheaply and only read when something changed.

use std::ptr;
use std::thread;
use std::time::Duration;

use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL, HWND};
use windows::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, GetClipboardData, GetClipboardSequenceNumber, OpenClipboard,
    SetClipboardData,
};
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};

const CF_UNICODETEXT: u32 = 13;
const MAX_CHARS: usize = 1_000_000;

pub fn sequence() -> u32 {
    unsafe { GetClipboardSequenceNumber() }
}

fn open() -> bool {
    // Another process can hold the clipboard for a few milliseconds.
    for _ in 0..8 {
        if unsafe { OpenClipboard(HWND::default()) }.is_ok() {
            return true;
        }
        thread::sleep(Duration::from_millis(6));
    }
    false
}

pub fn read_text() -> String {
    if !open() {
        return String::new();
    }
    let text = unsafe {
        let result = (|| {
            let handle = GetClipboardData(CF_UNICODETEXT).ok()?;
            let global = HGLOBAL(handle.0);
            let raw = GlobalLock(global) as *const u16;
            if raw.is_null() {
                return None;
            }
            let mut length = 0usize;
            while length < MAX_CHARS && *raw.add(length) != 0 {
                length += 1;
            }
            let units = std::slice::from_raw_parts(raw, length);
            let value = String::from_utf16_lossy(units);
            let _ = GlobalUnlock(global);
            Some(value)
        })();
        let _ = CloseClipboard();
        result
    };
    text.unwrap_or_default().replace('\0', "")
}

pub fn write_text(value: &str) -> bool {
    let units = to_units(value);
    let bytes = units.len() * std::mem::size_of::<u16>();
    if !open() {
        return false;
    }
    let written = unsafe {
        let result = (|| {
            EmptyClipboard().ok()?;
            let global = GlobalAlloc(GMEM_MOVEABLE, bytes).ok()?;
            let target = GlobalLock(global) as *mut u16;
            if target.is_null() {
                let _ = GlobalFree(global);
                return None;
            }
            ptr::copy_nonoverlapping(units.as_ptr(), target, units.len());
            let _ = GlobalUnlock(global);
            if SetClipboardData(CF_UNICODETEXT, HANDLE(global.0)).is_err() {
                let _ = GlobalFree(global);
                return None;
            }
            // On success Windows owns the HGLOBAL; do not free it.
            Some(())
        })();
        let _ = CloseClipboard();
        result
    };
    written.is_some()
}

pub fn clear() -> bool {
    if !open() {
        return false;
    }
    let ok = unsafe {
        let cleared = EmptyClipboard().is_ok();
        let _ = CloseClipboard();
        cleared
    };
    ok
}

/// UTF-16 with the trailing NUL the clipboard format requires.
fn to_units(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

#[cfg(test)]
mod tests {
    use super::to_units;

    #[test]
    fn the_clipboard_string_is_nul_terminated() {
        let units = to_units("hi");
        assert_eq!(units, vec![b'h' as u16, b'i' as u16, 0]);
    }

    #[test]
    fn an_empty_string_is_just_the_terminator() {
        assert_eq!(to_units(""), vec![0]);
    }

    #[test]
    fn unicode_survives() {
        let units = to_units("привет 🚀");
        let text = String::from_utf16(&units[..units.len() - 1]).unwrap();
        assert_eq!(text, "привет 🚀");
    }
}