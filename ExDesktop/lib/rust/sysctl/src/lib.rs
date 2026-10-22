// sysctl.dll — the shell's native backend.
//
// One library owns the Windows calls that were previously a mix of netsh,
// PowerShell and hand-written COM vtable code in Dart:
//   * master volume and per-app audio sessions (WASAPI),
//   * Wi-Fi scan/connect/disconnect (WLAN API),
//   * monitor modes and display changes (GDI),
//   * the Windows time-zone table (DST-aware offsets).
//
// Everything is exposed through a tiny C ABI: numbers for setters/getters and
// one JSON string for lists. The Dart side (lib/native/sysctl.dart) wraps
// this, and every function fails soft when the DLL is absent.

mod audio;
mod display;
mod json;
mod timezones;
mod wifi;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

fn to_c(value: String) -> *mut c_char {
    CString::new(value)
        .map(|text| text.into_raw())
        .unwrap_or(ptr::null_mut())
}

fn read(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(value) }
            .to_string_lossy()
            .to_string(),
    )
}

/// Frees every string returned by this library.
#[no_mangle]
pub extern "C" fn free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

// ---- master volume ----------------------------------------------------------

#[no_mangle]
pub extern "C" fn master_volume_get() -> f64 {
    audio::master_volume_get() as f64
}

#[no_mangle]
pub extern "C" fn master_volume_set(level: f64) -> i32 {
    audio::master_volume_set(level as f32)
}

/// 1 = muted, 0 = audible, -1 = the audio service did not answer.
#[no_mangle]
pub extern "C" fn master_mute_get() -> i32 {
    audio::master_mute_get()
}

#[no_mangle]
pub extern "C" fn master_mute_set(muted: i32) -> i32 {
    audio::master_mute_set(muted != 0)
}

// ---- per-app sessions -------------------------------------------------------

#[no_mangle]
pub extern "C" fn audio_sessions_json() -> *mut c_char {
    to_c(audio::sessions_json())
}

#[no_mangle]
pub extern "C" fn audio_session_set_volume(pid: u32, level: f64) -> i32 {
    audio::session_set_volume(pid, level as f32)
}

#[no_mangle]
pub extern "C" fn audio_session_set_mute(pid: u32, muted: i32) -> i32 {
    audio::session_set_mute(pid, muted != 0)
}

// ---- wi-fi ------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn wifi_networks_json() -> *mut c_char {
    to_c(wifi::networks_json())
}

/// Returns 0 when Windows accepted the profile + connect call.
#[no_mangle]
pub extern "C" fn wifi_connect(
    ssid: *const c_char,
    password: *const c_char,
    auto_connect: i32,
    secure: i32,
) -> i32 {
    let Some(ssid) = read(ssid) else {
        return -1;
    };
    let password = read(password).unwrap_or_default();
    wifi::connect(&ssid, &password, auto_connect != 0, secure != 0)
}

#[no_mangle]
pub extern "C" fn wifi_disconnect() -> i32 {
    wifi::disconnect()
}

// ---- display ----------------------------------------------------------------

#[no_mangle]
pub extern "C" fn display_state_json() -> *mut c_char {
    to_c(display::state_json())
}

/// `orientation` is 0..3, or -1 to keep the current one.
#[no_mangle]
pub extern "C" fn display_apply(width: u32, height: u32, hz: u32, orientation: i32) -> i32 {
    let orientation = if (0..=3).contains(&orientation) {
        Some(orientation as u32)
    } else {
        None
    };
    display::apply(width, height, hz, orientation)
}

// ---- time zones -------------------------------------------------------------

#[no_mangle]
pub extern "C" fn timezones_json() -> *mut c_char {
    to_c(timezones::list_json())
}

#[no_mangle]
pub extern "C" fn timezone_offset(id: *const c_char) -> i32 {
    let Some(id) = read(id) else {
        return -9999;
    };
    timezones::offset_minutes(&id)
}