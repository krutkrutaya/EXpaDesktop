// Windows' own time-zone table, with the offset that is actually in effect
// today (DST included). The shell's clock ticks in UTC and adds this offset,
// so picking "Pacific Standard Time" moves the desktop clock without touching
// the machine's clock.

use std::time::{SystemTime, UNIX_EPOCH};

use windows::Win32::Foundation::SYSTEMTIME;
use windows::Win32::System::Time::{
    EnumDynamicTimeZoneInformation, SystemTimeToTzSpecificLocalTimeEx,
    DYNAMIC_TIME_ZONE_INFORMATION,
};

use crate::json;

fn wide_string(value: &[u16]) -> String {
    let end = value.iter().position(|unit| *unit == 0).unwrap_or(value.len());
    String::from_utf16_lossy(&value[..end])
        .trim()
        .to_string()
}

fn utc_now() -> SYSTEMTIME {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0);
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    SYSTEMTIME {
        wYear: year as u16,
        wMonth: month as u16,
        wDayOfWeek: 0,
        wDay: day as u16,
        wHour: (rest / 3600) as u16,
        wMinute: ((rest % 3600) / 60) as u16,
        wSecond: (rest % 60) as u16,
        wMilliseconds: 0,
    }
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if month <= 2 { year + 1 } else { year }, month, day)
}

fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = (year - era * 400) as u64;
    let mp = if month > 2 { month - 3 } else { month + 9 } as u64;
    let doy = (153 * mp + 2) / 5 + day as u64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe as i64 - 719_468
}

fn minutes(stamp: &SYSTEMTIME) -> i64 {
    days_from_civil(stamp.wYear as i64, stamp.wMonth as u32, stamp.wDay as u32) * 1_440
        + stamp.wHour as i64 * 60
        + stamp.wMinute as i64
}

pub fn list_json() -> String {
    let utc = utc_now();
    let mut rows: Vec<String> = Vec::new();
    let mut index = 0u32;
    loop {
        let mut info = DYNAMIC_TIME_ZONE_INFORMATION::default();
        let rc = unsafe { EnumDynamicTimeZoneInformation(index, &mut info) };
        // ERROR_SUCCESS, then ERROR_NO_MORE_ITEMS.
        if rc != 0 {
            break;
        }
        index += 1;
        let id = wide_string(&info.TimeZoneKeyName);
        if id.is_empty() {
            continue;
        }
        let name = wide_string(&info.StandardName);
        let mut local = SYSTEMTIME::default();
        let offset = unsafe {
            SystemTimeToTzSpecificLocalTimeEx(Some(&info), &utc, &mut local)
                .ok()
                .map(|_| minutes(&local) - minutes(&utc))
                .unwrap_or(0)
        };
        rows.push(format!(
            "{{\"id\":{},\"name\":{},\"offset\":{}}}",
            json::quote(&id),
            json::quote(if name.is_empty() { &id } else { &name }),
            offset
        ));
    }
    rows.sort_by(|a, b| a.to_lowercase().cmp(&b.to_lowercase()));
    format!("[{}]", rows.join(","))
}

/// Current offset of one zone, in minutes east of UTC. -9999 when the id is
/// not on this machine.
pub fn offset_minutes(id: &str) -> i32 {
    let utc = utc_now();
    let mut index = 0u32;
    loop {
        let mut info = DYNAMIC_TIME_ZONE_INFORMATION::default();
        let rc = unsafe { EnumDynamicTimeZoneInformation(index, &mut info) };
        if rc != 0 {
            break;
        }
        index += 1;
        if wide_string(&info.TimeZoneKeyName) != id {
            continue;
        }
        let mut local = SYSTEMTIME::default();
        return unsafe {
            SystemTimeToTzSpecificLocalTimeEx(Some(&info), &utc, &mut local)
                .ok()
                .map(|_| (minutes(&local) - minutes(&utc)) as i32)
                .unwrap_or(-9999)
        };
    }
    -9999
}

#[cfg(test)]
mod tests {
    use super::{civil_from_days, days_from_civil};

    #[test]
    fn the_epoch_is_the_epoch() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(days_from_civil(1970, 1, 1), 0);
    }

    #[test]
    fn civil_dates_round_trip() {
        for date in [(2026, 10, 22), (2000, 2, 29), (1999, 12, 31), (1970, 3, 1)] {
            let days = days_from_civil(date.0, date.1, date.2);
            assert_eq!(civil_from_days(days), date);
        }
    }
}