use std::ffi::c_double;
use std::os::raw::c_int;
use std::ptr;
use windows::Win32::Foundation::{BOOL, HWND, LPARAM, RECT};
use windows::Win32::Graphics::Gdi::{
    EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO, MONITOR_DEFAULTTOPRIMARY,
};
use windows::Win32::Devices::Display::{
    GetMonitorBrightness, GetPhysicalMonitorsFromHMONITOR, SetMonitorBrightness, PHYSICAL_MONITOR,
};

// Вспомогательная функция для получения дескриптора физического монитора
unsafe fn get_primary_physical_monitor() -> Option<PHYSICAL_MONITOR> {
    // Находим главный (Primary) монитор системы
    let point = windows::Win32::Foundation::POINT { x: 0, y: 0 };
    let h_monitor = windows::Win32::Graphics::Gdi::MonitorFromPoint(point, MONITOR_DEFAULTTOPRIMARY);
    
    if h_monitor.is_invalid() {
        return None;
    }

    let mut count = 0u32;
    // Узнаем, сколько физических панелей привязано к этому HMONITOR
    if GetPhysicalMonitorsFromHMONITOR(h_monitor, &mut count, ptr::null_mut()).is_err() || count == 0 {
        return None;
    }

    let mut physical_monitors = vec![PHYSICAL_MONITOR::default(); count as usize];
    if GetPhysicalMonitorsFromHMONITOR(h_monitor, &mut count, physical_monitors.as_mut_ptr()).is_ok() {
        // Возвращаем первый попавшийся физический монитор
        return Some(physical_monitors[0]);
    }
    None
}

#[no_mangle]
pub extern "C" fn set_brightness(level: c_double) -> c_int {
    // Приводим флаттеровский 0.0 - 1.0 к процентам 0 - 100
    let brightness_pct = (level.clamp(0.0, 1.0) * 100.0) as u32;

    unsafe {
        if let Some(monitor) = get_primary_physical_monitor() {
            // Устанавливаем физическую яркость через DDC/CI драйвер
            let res = SetMonitorBrightness(monitor.hPhysicalMonitor, brightness_pct);
            if res.is_ok() {
                return 0; // Всё отлично
            }
            return -3; // Ошибка установки яркости дисплеем
        }
        -2 // Монитор не найден
    }
}

#[no_mangle]
pub extern "C" fn get_brightness() -> c_double {
    unsafe {
        if let Some(monitor) = get_primary_physical_monitor() {
            let mut min = 0u32;
            let mut current = 0u32;
            let mut max = 0u32;
            
            if GetMonitorBrightness(monitor.hPhysicalMonitor, &mut min, &mut current, &mut max).is_ok() {
                return current as f64 / 100.0;
            }
        }
        0.7 // Дефолтное значение флэтбека, если монитор заблокирован
    }
}
