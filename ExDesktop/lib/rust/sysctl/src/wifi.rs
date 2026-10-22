// Wi-Fi through the native WLAN API.
//
// netsh and PowerShell are gone from this path: the shell asks Windows for
// the interface list and the available networks, joins with a standard
// profile document, and disconnects — all in-process. The parsers that used
// to guess at localized netsh output are replaced by typed structs, so a
// Russian Windows and an English one behave identically.

use std::ffi::c_void;
use std::ptr;
use std::thread;
use std::time::Duration;

use windows::core::{GUID, PCWSTR, PWSTR};
use windows::Win32::Foundation::{ERROR_SUCCESS, HANDLE};
use windows::Win32::NetworkManagement::WiFi::{
    dot11_BSS_type_infrastructure, wlan_connection_mode_profile, WlanCloseHandle, WlanConnect,
    WlanDisconnect, WlanEnumInterfaces, WlanFreeMemory, WlanGetAvailableNetworkList,
    WlanGetProfile, WlanOpenHandle, WlanScan, WlanSetProfile, WLAN_AVAILABLE_NETWORK,
    WLAN_AVAILABLE_NETWORK_CONNECTED, WLAN_AVAILABLE_NETWORK_LIST, WLAN_CONNECTION_PARAMETERS,
    WLAN_INTERFACE_INFO_LIST,
};

use crate::json;

struct Client {
    handle: HANDLE,
    interface: GUID,
}

impl Drop for Client {
    fn drop(&mut self) {
        unsafe {
            let _ = WlanCloseHandle(self.handle, None);
        }
    }
}

fn open_client() -> Option<Client> {
    unsafe {
        let mut negotiated = 0u32;
        let mut handle = HANDLE::default();
        let rc = WlanOpenHandle(2, None, &mut negotiated, &mut handle);
        if rc != ERROR_SUCCESS.0 {
            return None;
        }
        let mut list: *mut WLAN_INTERFACE_INFO_LIST = ptr::null_mut();
        let rc = WlanEnumInterfaces(handle, None, &mut list);
        if rc != ERROR_SUCCESS.0 || list.is_null() {
            let _ = WlanCloseHandle(handle, None);
            return None;
        }
        let count = (*list).dwNumberOfItems as usize;
        let first = if count == 0 {
            None
        } else {
            Some(*(*list).InterfaceInfo.as_ptr())
        };
        WlanFreeMemory(list as *const c_void);
        match first {
            Some(info) => Some(Client {
                handle,
                interface: info.InterfaceGuid,
            }),
            None => {
                let _ = WlanCloseHandle(handle, None);
                None
            }
        }
    }
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn profile_name(network: &WLAN_AVAILABLE_NETWORK) -> String {
    let name = &network.strProfileName;
    let end = name.iter().position(|unit| *unit == 0).unwrap_or(name.len());
    String::from_utf16_lossy(&name[..end])
}

fn ssid_of(network: &WLAN_AVAILABLE_NETWORK) -> String {
    let length = (network.dot11Ssid.uSSIDLength as usize).min(32);
    String::from_utf8_lossy(&network.dot11Ssid.ucSSID[..length]).to_string()
}

struct Net {
    ssid: String,
    signal: u32,
    secure: bool,
    known: bool,
    connected: bool,
    auto: bool,
}

/// Reads the profile's XML just far enough to report whether Windows joins
/// it automatically. The checkbox in the flyout mirrors the system setting.
unsafe fn profile_auto(client: &Client, profile: &str) -> bool {
    let name = wide(profile);
    let mut xml = PWSTR::null();
    let rc = WlanGetProfile(
        client.handle,
        &client.interface,
        PCWSTR(name.as_ptr()),
        None,
        &mut xml,
        None,
        None,
    );
    if rc != ERROR_SUCCESS.0 || xml.is_null() {
        return false;
    }
    let text = xml.to_string().unwrap_or_default();
    WlanFreeMemory(xml.0 as *const c_void);
    text.contains("<connectionMode>auto</connectionMode>")
}

fn available(client: &Client, scan: bool) -> Vec<Net> {
    unsafe {
        if scan {
            let _ = WlanScan(client.handle, &client.interface, None, None, None);
            // WlanScan kicks off an asynchronous scan; the list below is the
            // previous one until the driver has answered. Half a second is the
            // practical floor the Windows UI uses too.
            thread::sleep(Duration::from_millis(550));
        }
        let mut list: *mut WLAN_AVAILABLE_NETWORK_LIST = ptr::null_mut();
        let rc = WlanGetAvailableNetworkList(
            client.handle,
            &client.interface,
            0,
            None,
            &mut list,
        );
        if rc != ERROR_SUCCESS.0 || list.is_null() {
            return Vec::new();
        }
        let count = (*list).dwNumberOfItems as usize;
        let slice = std::slice::from_raw_parts((*list).Network.as_ptr(), count);
        let mut nets = Vec::with_capacity(count);
        for network in slice {
            let ssid = ssid_of(network);
            if ssid.is_empty() {
                continue;
            }
            let profile = profile_name(network);
            let known = !profile.is_empty();
            nets.push(Net {
                ssid,
                signal: network.wlanSignalQuality.min(100),
                secure: network.bSecurityEnabled.as_bool(),
                known,
                connected: network.dwFlags & WLAN_AVAILABLE_NETWORK_CONNECTED != 0,
                auto: known && profile_auto(client, &profile),
            });
        }
        WlanFreeMemory(list as *const c_void);
        nets
    }
}

pub fn networks_json() -> String {
    let Some(client) = open_client() else {
        return "[]".to_string();
    };
    let mut nets = available(&client, true);
    // One row per SSID, keep the strongest BSSID, connected first.
    nets.sort_by(|a, b| {
        a.ssid
            .to_lowercase()
            .cmp(&b.ssid.to_lowercase())
            .then_with(|| b.signal.cmp(&a.signal))
    });
    nets.dedup_by(|a, b| a.ssid.eq_ignore_ascii_case(&b.ssid));
    nets.sort_by(|a, b| match (a.connected, b.connected) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => b.signal.cmp(&a.signal),
    });

    let rows: Vec<String> = nets
        .iter()
        .map(|net| {
            format!(
                "{{\"ssid\":{},\"signal\":{},\"secure\":{},\"known\":{},\"connected\":{},\"auto\":{}}}",
                json::quote(&net.ssid),
                net.signal,
                net.secure,
                net.known,
                net.connected,
                net.auto
            )
        })
        .collect();
    format!("[{}]", rows.join(","))
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn profile_xml(ssid: &str, password: &str, auto: bool) -> String {
    let name = xml_escape(ssid);
    let security = if password.is_empty() {
        "<security><authEncryption><authentication>open</authentication>\
         <encryption>none</encryption><useOneX>false</useOneX></authEncryption></security>"
            .to_string()
    } else {
        format!(
            "<security><authEncryption><authentication>WPA2PSK</authentication>\
             <encryption>AES</encryption><useOneX>false</useOneX></authEncryption>\
             <sharedKey><keyType>passPhrase</keyType><protected>false</protected>\
             <keyMaterial>{}</keyMaterial></sharedKey></security>",
            xml_escape(password)
        )
    };
    format!(
        "<?xml version=\"1.0\"?><WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">\
         <name>{name}</name><SSIDConfig><SSID><name>{name}</name></SSID></SSIDConfig>\
         <connectionType>ESS</connectionType><connectionMode>{mode}</connectionMode>\
         <MSM>{security}</MSM></WLANProfile>",
        name = name,
        mode = if auto { "auto" } else { "manual" },
        security = security
    )
}

/// Joins a network. [password] may be empty for an already-known profile or
/// for an open network; [secure] tells the function which of those it is.
/// Returns the WLAN error code (0 = accepted).
pub fn connect(ssid: &str, password: &str, auto: bool, secure: bool) -> i32 {
    let Some(client) = open_client() else {
        return -1;
    };
    let name = wide(ssid);
    unsafe {
        // An open network with no profile yet needs one before WlanConnect
        // can address it by name. A locked network with an empty password
        // already has a profile somewhere or cannot be joined at all.
        if !password.is_empty() || !secure {
            let xml = wide(&profile_xml(ssid, password, auto));
            let mut reason = 0u32;
            let rc = WlanSetProfile(
                client.handle,
                &client.interface,
                0,
                PCWSTR(xml.as_ptr()),
                PCWSTR::null(),
                true,
                None,
                &mut reason,
            );
            if rc != ERROR_SUCCESS.0 {
                return rc as i32;
            }
        }
        let parameters = WLAN_CONNECTION_PARAMETERS {
            wlanConnectionMode: wlan_connection_mode_profile,
            strProfile: PCWSTR(name.as_ptr()),
            pDot11Ssid: ptr::null_mut(),
            pDesiredBssidList: ptr::null_mut(),
            dot11BssType: dot11_BSS_type_infrastructure,
            dwFlags: 0,
        };
        let rc = WlanConnect(client.handle, &client.interface, &parameters, None);
        rc as i32
    }
}

pub fn disconnect() -> i32 {
    let Some(client) = open_client() else {
        return -1;
    };
    unsafe { WlanDisconnect(client.handle, &client.interface, None) as i32 }
}

#[cfg(test)]
mod tests {
    use super::profile_xml;

    #[test]
    fn a_secure_profile_carries_the_key_and_escapes() {
        let xml = profile_xml("My \"Net\"", "pa&ss", true);
        assert!(xml.contains("WPA2PSK"));
        assert!(xml.contains("pa&amp;ss"));
        assert!(xml.contains("My &quot;Net&quot;"));
        assert!(xml.contains("<connectionMode>auto</connectionMode>"));
        assert!(!xml.contains("<authentication>open</authentication>"));
    }

    #[test]
    fn an_open_profile_has_no_key() {
        let xml = profile_xml("Cafe", "", false);
        assert!(xml.contains("<authentication>open</authentication>"));
        assert!(!xml.contains("WPA2PSK"));
        assert!(xml.contains("<connectionMode>manual</connectionMode>"));
    }
}