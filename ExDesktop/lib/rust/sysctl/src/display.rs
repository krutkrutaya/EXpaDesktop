// Monitor modes: the real list Windows reports, and a real apply.
//
// The settings pane used to show a hard-coded "recommended" with no numbers.
// Here the current DEVMODE and every mode EnumDisplaySettings knows are read
// once, so the dropdowns offer exactly what the display can do. Applying goes
// through ChangeDisplaySettingsEx with the registry flag, so the choice
// survives a reboot.

use std::collections::BTreeSet;

use windows::core::PCWSTR;
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Gdi::{
    ChangeDisplaySettingsExW, EnumDisplaySettingsW, CDS_UPDATEREGISTRY, DEVMODEW,
    DEVMODE_DISPLAY_ORIENTATION, DISP_CHANGE_SUCCESSFUL, DM_DISPLAYFREQUENCY,
    DM_DISPLAYORIENTATION, DM_PELSHEIGHT, DM_PELSWIDTH, ENUM_CURRENT_SETTINGS,
    ENUM_DISPLAY_SETTINGS_MODE,
};

#[derive(Clone, Copy)]
struct Mode {
    width: u32,
    height: u32,
    hz: u32,
    orientation: u32,
    bits: u32,
}

fn read(mode: &DEVMODEW) -> Mode {
    Mode {
        width: mode.dmPelsWidth,
        height: mode.dmPelsHeight,
        hz: mode.dmDisplayFrequency,
        orientation: unsafe { mode.Anonymous1.Anonymous2.dmDisplayOrientation.0 },
        bits: mode.dmBitsPerPel,
    }
}

fn current() -> Option<(DEVMODEW, Mode)> {
    let mut mode = DEVMODEW::default();
    mode.dmSize = std::mem::size_of::<DEVMODEW>() as u16;
    let ok = unsafe { EnumDisplaySettingsW(PCWSTR::null(), ENUM_CURRENT_SETTINGS, &mut mode) };
    if !ok.as_bool() {
        return None;
    }
    Some((mode, read(&mode)))
}

pub fn state_json() -> String {
    let Some((_, now)) = current() else {
        return "{\"current\":null,\"resolutions\":[],\"refresh\":[60],\"orientations\":[0,1,2,3]}"
            .to_string();
    };

    let mut resolutions: BTreeSet<(u32, u32)> = BTreeSet::new();
    let mut refresh: BTreeSet<u32> = BTreeSet::new();
    resolutions.insert((now.width, now.height));
    if now.hz > 1 {
        refresh.insert(now.hz);
    }
    let mut index = 0u32;
    loop {
        let mut mode = DEVMODEW::default();
        mode.dmSize = std::mem::size_of::<DEVMODEW>() as u16;
        let ok = unsafe {
            EnumDisplaySettingsW(
                PCWSTR::null(),
                ENUM_DISPLAY_SETTINGS_MODE(index),
                &mut mode,
            )
        };
        if !ok.as_bool() {
            break;
        }
        index += 1;
        if mode.dmPelsWidth == 0 || mode.dmPelsHeight == 0 {
            continue;
        }
        // 8/16-bit modes still exist on old drivers; the desktop never does.
        if mode.dmBitsPerPel != 0 && mode.dmBitsPerPel < 32 {
            continue;
        }
        resolutions.insert((mode.dmPelsWidth, mode.dmPelsHeight));
        if mode.dmDisplayFrequency > 1 {
            refresh.insert(mode.dmDisplayFrequency);
        }
    }
    if refresh.is_empty() {
        refresh.insert(60);
    }

    let resolution_rows: Vec<String> = resolutions
        .iter()
        .map(|(width, height)| format!("[{},{}]", width, height))
        .collect();
    let refresh_rows: Vec<String> = refresh.iter().map(|hz| hz.to_string()).collect();

    format!(
        "{{\"current\":{{\"width\":{},\"height\":{},\"hz\":{},\"orientation\":{},\"bits\":{}}},\
         \"resolutions\":[{}],\"refresh\":[{}],\"orientations\":[0,1,2,3]}}",
        now.width,
        now.height,
        now.hz,
        now.orientation,
        now.bits,
        resolution_rows.join(","),
        refresh_rows.join(",")
    )
}

/// Applies one mode. Any of the three values may be 0 to keep the current
/// one; the Dart pane always sends the full triple, so this is only a guard.
pub fn apply(width: u32, height: u32, hz: u32, orientation: Option<u32>) -> i32 {
    let Some((mut mode, now)) = current() else {
        return 0;
    };
    mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYORIENTATION;
    mode.dmPelsWidth = if width == 0 { now.width } else { width };
    mode.dmPelsHeight = if height == 0 { now.height } else { height };
    mode.dmDisplayFrequency = if hz == 0 { now.hz } else { hz };
    mode.Anonymous1.Anonymous2.dmDisplayOrientation =
        DEVMODE_DISPLAY_ORIENTATION(orientation.unwrap_or(now.orientation));
    let result = unsafe {
        ChangeDisplaySettingsExW(
            PCWSTR::null(),
            Some(&mode),
            HWND::default(),
            CDS_UPDATEREGISTRY,
            None,
        )
    };
    i32::from(result == DISP_CHANGE_SUCCESSFUL)
}