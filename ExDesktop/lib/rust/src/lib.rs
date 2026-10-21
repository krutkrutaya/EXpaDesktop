use std::ffi::c_double;
use std::os::raw::c_int;
use windows::Win32::Foundation::POINT;
use windows::Win32::Graphics::Gdi::{
    MONITOR_DEFAULTTOPRIMARY, MonitorFromPoint, GetDC, ReleaseDC,
};
use windows::Win32::Devices::Display::{
    GetMonitorBrightness, GetPhysicalMonitorsFromHMONITOR, SetMonitorBrightness,
    SetMonitorContrast, PHYSICAL_MONITOR,
};

unsafe fn get_primary_physical_monitor() -> Option<PHYSICAL_MONITOR> {
    let point = POINT { x: 0, y: 0 };
    let h_monitor = MonitorFromPoint(point, MONITOR_DEFAULTTOPRIMARY);
    
    if h_monitor.is_invalid() {
        return None;
    }

    let mut physical_monitors = [PHYSICAL_MONITOR::default(); 1];
    if GetPhysicalMonitorsFromHMONITOR(h_monitor, &mut physical_monitors).is_ok() {
        return Some(physical_monitors[0]);
    }
    None
}

#[no_mangle]
pub extern "C" fn set_brightness(level: c_double) -> c_int {
    let brightness_pct = (level.clamp(0.0, 1.0) * 100.0) as u32;

    unsafe {
        if let Some(monitor) = get_primary_physical_monitor() {
            let res = SetMonitorBrightness(monitor.hPhysicalMonitor, brightness_pct);
            if res == 0 {
                return 0;
            }
            return -3;
        }
        -2
    }
}

#[no_mangle]
pub extern "C" fn get_brightness() -> c_double {
    unsafe {
        if let Some(monitor) = get_primary_physical_monitor() {
            let mut min = 0u32;
            let mut current = 0u32;
            let mut max = 0u32;
            
            if GetMonitorBrightness(monitor.hPhysicalMonitor, &mut min, &mut current, &mut max) == 0 {
                return current as f64 / 100.0;
            }
        }
        0.7
    }
}

#[no_mangle]
pub extern "C" fn set_contrast(level: c_double) -> c_int {
    let contrast_pct = (level.clamp(0.0, 1.0) * 100.0) as u32;

    unsafe {
        if let Some(monitor) = get_primary_physical_monitor() {
            let res = SetMonitorContrast(monitor.hPhysicalMonitor, contrast_pct);
            if res == 0 {
                return 0;
            }
            return -3;
        }
        -2
    }
}

#[no_mangle]
pub extern "C" fn set_warmth(level: c_double) -> c_int {
    unsafe {
        let hdc = GetDC(None);
        if hdc.is_invalid() {
            return -2;
        }

        let warmth = level.clamp(0.0, 1.0);
        let red_factor = 1.0 - (warmth * 0.3);
        let blue_factor = 1.0 - (warmth * 0.3);
        let green_factor = 1.0;

        let mut ramp = [0u16; 768];
        for i in 0..256 {
            ramp[i] = (i as f64 * red_factor) as u16 * 256;
            ramp[256 + i] = (i as f64 * green_factor) as u16 * 256;
            ramp[512 + i] = (i as f64 * blue_factor) as u16 * 256;
        }

        let hdc_handle = hdc.0 as isize;
        let res = SetDeviceGammaRamp(hdc_handle, ramp.as_ptr());
        ReleaseDC(None, hdc);
        
        if res != 0 {
            0
        } else {
            -3
        }
    }
}

#[no_mangle]
pub extern "C" fn reset_gamma() -> c_int {
    unsafe {
        let hdc = GetDC(None);
        if hdc.is_invalid() {
            return -2;
        }

        let mut ramp = [0u16; 768];
        for i in 0..256 {
            ramp[i] = i as u16 * 256;
            ramp[256 + i] = i as u16 * 256;
            ramp[512 + i] = i as u16 * 256;
        }

        let hdc_handle = hdc.0 as isize;
        let res = SetDeviceGammaRamp(hdc_handle, ramp.as_ptr());
        ReleaseDC(None, hdc);
        
        if res != 0 {
            0
        } else {
            -3
        }
    }
}

#[no_mangle]
pub extern "C" fn set_brightness_boost(level: c_double) -> c_int {
    unsafe {
        let hdc = GetDC(None);
        if hdc.is_invalid() {
            return -2;
        }

        let boost = level.clamp(0.0, 1.0);
        let factor = 1.0 + (boost * 0.5);

        let mut ramp = [0u16; 768];
        for i in 0..256 {
            let val = (i as f64 * factor).min(255.0) as u16 * 256;
            ramp[i] = val;
            ramp[256 + i] = val;
            ramp[512 + i] = val;
        }

        let hdc_handle = hdc.0 as isize;
        let res = SetDeviceGammaRamp(hdc_handle, ramp.as_ptr());
        ReleaseDC(None, hdc);
        
        if res != 0 {
            0
        } else {
            -3
        }
    }
}

extern "system" {
    fn SetDeviceGammaRamp(hdc: isize, lpRamp: *const u16) -> i32;
}