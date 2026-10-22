// Master volume and per-application audio sessions through WASAPI.
//
// This replaces the hand-rolled COM vtable code the Dart shell used to carry:
// windows-rs generates the interfaces, so a wrong vtable index is a compile
// error instead of a crash. Every call is fail-soft and returns a sentinel;
// the UI keeps working on a machine where the audio service is missing.

use std::ffi::c_void;
use std::ptr;

use windows::core::{Interface, GUID, HRESULT, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, BOOL, HANDLE, S_OK};
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{
    eMultimedia, eRender, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator,
    ISimpleAudioVolume, MMDeviceEnumerator,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_MULTITHREADED,
};
use windows::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};

use crate::json;

/// COM is per-thread. The Dart side calls these on one isolate; initialize
/// for the duration of a call and unwind it afterwards when this thread did
/// the initialization. RPC_E_CHANGED_MODE means Flutter already set an
/// apartment mode — in that case leave it alone.
fn with_com<T>(body: impl FnOnce() -> T) -> T {
    let result = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    let owned = result != HRESULT(0x8001_0106u32 as i32); // RPC_E_CHANGED_MODE
    let value = body();
    if owned {
        unsafe { CoUninitialize() };
    }
    value
}

fn endpoint() -> Option<IAudioEndpointVolume> {
    with_com(|| unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
        let device = enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia).ok()?;
        device.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None).ok()
    })
}

pub fn master_volume_get() -> f32 {
    endpoint()
        .and_then(|volume| unsafe { volume.GetMasterVolumeLevelScalar().ok() })
        .unwrap_or(-1.0)
}

pub fn master_mute_get() -> i32 {
    match endpoint().and_then(|volume| unsafe { volume.GetMute().ok() }) {
        Some(muted) => i32::from(muted.as_bool()),
        None => -1,
    }
}

pub fn master_volume_set(level: f32) -> i32 {
    let level = level.clamp(0.0, 1.0);
    match endpoint() {
        Some(volume) => unsafe {
            match volume.SetMasterVolumeLevelScalar(level, ptr::null()) {
                Ok(()) => 1,
                Err(_) => 0,
            }
        },
        None => 0,
    }
}

pub fn master_mute_set(muted: bool) -> i32 {
    match endpoint() {
        Some(volume) => unsafe {
            match volume.SetMute(BOOL::from(muted), ptr::null()) {
                Ok(()) => 1,
                Err(_) => 0,
            }
        },
        None => 0,
    }
}

/// Walks this machine's sessions. `visit` receives the pid, the exe stem and
/// the two controls so the caller can read or write without opening the
/// enumerator twice.
unsafe fn visit_sessions(
    mut visit: impl FnMut(u32, &str, &IAudioSessionControl2, &ISimpleAudioVolume),
) {
    let Ok(enumerator) =
        CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL)
    else {
        return;
    };
    let Ok(device) = enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia) else {
        return;
    };
    let Ok(manager) = device.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else {
        return;
    };
    let Ok(list) = manager.GetSessionEnumerator() else {
        return;
    };
    let Ok(count) = list.GetCount() else {
        return;
    };
    let own_pid = std::process::id();
    for index in 0..count {
        let Ok(control) = list.GetSession(index) else {
            continue;
        };
        let Ok(control2) = control.cast::<IAudioSessionControl2>() else {
            continue;
        };
        // The "system sounds" session is Windows' own beeps, not an app.
        if control2.IsSystemSoundsSession() == S_OK {
            continue;
        }
        let Ok(pid) = control2.GetProcessId() else {
            continue;
        };
        if pid == 0 || pid == own_pid {
            continue;
        }
        let Ok(simple) = control2.cast::<ISimpleAudioVolume>() else {
            continue;
        };
        let name = process_name(pid);
        visit(pid, &name, &control2, &simple);
    }
}

/// `C:\Program Files\...\chrome.exe` -> `chrome`. Empty when the process is
/// protected or already gone.
unsafe fn process_name(pid: u32) -> String {
    let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
        return String::new();
    };
    let mut buffer = [0u16; 1024];
    let mut length = buffer.len() as u32;
    let result = QueryFullProcessImageNameW(
        handle,
        PROCESS_NAME_WIN32,
        PWSTR(buffer.as_mut_ptr()),
        &mut length,
    );
    let _ = CloseHandle(handle);
    if result.is_err() {
        return String::new();
    }
    let path = String::from_utf16_lossy(&buffer[..length as usize]);
    let base = path.rsplit(['\\', '/']).next().unwrap_or(&path);
    base.strip_suffix(".exe")
        .or_else(|| base.strip_suffix(".EXE"))
        .unwrap_or(base)
        .to_lowercase()
}

pub fn sessions_json() -> String {
    with_com(|| {
        let mut rows: Vec<String> = Vec::new();
        unsafe {
            visit_sessions(|pid, exe, _control, simple| {
                let volume = simple.GetMasterVolume().unwrap_or(0.0);
                let muted = simple
                    .GetMute()
                    .map(|value| value.as_bool())
                    .unwrap_or(false);
                rows.push(format!(
                    "{{\"pid\":{},\"exe\":{},\"volume\":{:.4},\"muted\":{}}}",
                    pid,
                    json::quote(exe),
                    volume.clamp(0.0, 1.0),
                    muted
                ));
            });
        }
        format!("[{}]", rows.join(","))
    })
}

pub fn session_set_volume(pid: u32, level: f32) -> i32 {
    let level = level.clamp(0.0, 1.0);
    with_com(|| {
        let mut done = false;
        unsafe {
            visit_sessions(|candidate, _exe, _control, simple| {
                if candidate == pid && !done {
                    if simple.SetMasterVolume(level, ptr::null()).is_ok() {
                        done = true;
                    }
                }
            });
        }
        i32::from(done)
    })
}

pub fn session_set_mute(pid: u32, muted: bool) -> i32 {
    with_com(|| {
        let mut done = false;
        unsafe {
            visit_sessions(|candidate, _exe, _control, simple| {
                if candidate == pid && !done {
                    if simple.SetMute(BOOL::from(muted), ptr::null()).is_ok() {
                        done = true;
                    }
                }
            });
        }
        i32::from(done)
    })
}

/// Unused import guard: PCWSTR/GUID/HANDLE/c_void are referenced through the
/// generated signatures above; keep the module honest for the compiler.
#[allow(dead_code)]
fn _types(_: GUID, _: PCWSTR, _: HANDLE, _: *const c_void) {}