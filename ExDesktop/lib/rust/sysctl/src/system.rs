// Windows input settings through SystemParametersInfo: pointer speed, button
// swap, wheel lines, keyboard repeat delay/rate. These are the same knobs the
// old Settings page linked to; the shell now owns them itself.

use std::ffi::c_void;

use windows::Win32::UI::WindowsAndMessaging::{
    SystemParametersInfoW, SPI_GETKEYBOARDDELAY, SPI_GETKEYBOARDSPEED, SPI_GETMOUSESPEED, SPI_GETWHEELSCROLLLINES, SPI_SETKEYBOARDDELAY, SPI_SETKEYBOARDSPEED,
    SPI_SETMOUSEBUTTONSWAP, SPI_SETMOUSESPEED, SPI_SETWHEELSCROLLLINES,
    SYSTEM_PARAMETERS_INFO_ACTION, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
};

const SPI_GET_MOUSE_SWAP: SYSTEM_PARAMETERS_INFO_ACTION = SYSTEM_PARAMETERS_INFO_ACTION(32);

fn update() -> SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS {
    SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0)
}

fn get_u32(action: SYSTEM_PARAMETERS_INFO_ACTION) -> Option<u32> {
    unsafe {
        let mut value = 0u32;
        SystemParametersInfoW(
            action,
            0,
            Some(&mut value as *mut u32 as *mut c_void),
            update(),
        )
        .ok()?;
        Some(value)
    }
}

fn set_u32(action: SYSTEM_PARAMETERS_INFO_ACTION, value: u32) -> bool {
    unsafe { SystemParametersInfoW(action, value, None, update()).is_ok() }
}

pub fn mouse_speed_get() -> i32 {
    get_u32(SPI_GETMOUSESPEED).map(|value| value as i32).unwrap_or(-1)
}

pub fn mouse_speed_set(value: i32) -> i32 {
    i32::from(set_u32(SPI_SETMOUSESPEED, value.clamp(1, 20) as u32))
}

pub fn mouse_swap_get() -> i32 {
    get_u32(SPI_GET_MOUSE_SWAP)
        .map(|value| i32::from(value != 0))
        .unwrap_or(-1)
}

pub fn mouse_swap_set(value: bool) -> i32 {
    i32::from(set_u32(SPI_SETMOUSEBUTTONSWAP, u32::from(value)))
}

pub fn wheel_lines_get() -> i32 {
    get_u32(SPI_GETWHEELSCROLLLINES)
        .map(|value| value as i32)
        .unwrap_or(-1)
}

pub fn wheel_lines_set(value: i32) -> i32 {
    i32::from(set_u32(SPI_SETWHEELSCROLLLINES, value.clamp(1, 100) as u32))
}

pub fn keyboard_delay_get() -> i32 {
    get_u32(SPI_GETKEYBOARDDELAY)
        .map(|value| value as i32)
        .unwrap_or(-1)
}

pub fn keyboard_delay_set(value: i32) -> i32 {
    i32::from(set_u32(SPI_SETKEYBOARDDELAY, value.clamp(0, 3) as u32))
}

pub fn keyboard_speed_get() -> i32 {
    get_u32(SPI_GETKEYBOARDSPEED)
        .map(|value| value as i32)
        .unwrap_or(-1)
}

pub fn keyboard_speed_set(value: i32) -> i32 {
    i32::from(set_u32(SPI_SETKEYBOARDSPEED, value.clamp(0, 31) as u32))
}