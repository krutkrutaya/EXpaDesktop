// A fast music-folder scanner for the shell.
//
// Dart can walk a directory and parse ID3 tags, but doing that for a whole
// library on startup means reading every file on the UI isolate's doorstep.
// This library walks the folder, pulls the ID3 title/artist/TLEN/APIC frames
// (and the WAV duration) in one native pass, writes the cover art to a cache
// folder and returns one JSON array. Dart runs it inside an isolate; if the
// DLL is missing, the shell falls back to the pure-Dart scanner.
//
// No external crates: the JSON is four fields per track and is escaped here.

use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::Read;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};

const AUDIO_EXTENSIONS: [&str; 11] = [
    "mp3", "wav", "flac", "ogg", "oga", "m4a", "aac", "wma", "opus", "aiff", "aif",
];

/// Entry point: scan `dir`, write covers to `cache`, return a JSON string.
/// The caller owns the string and must free it with `free_music_string`.
#[no_mangle]
pub extern "C" fn scan_music(dir: *const c_char, cache: *const c_char) -> *mut c_char {
    if dir.is_null() || cache.is_null() {
        return std::ptr::null_mut();
    }
    let dir = unsafe { CStr::from_ptr(dir) }
        .to_string_lossy()
        .to_string();
    let cache = unsafe { CStr::from_ptr(cache) }
        .to_string_lossy()
        .to_string();
    let json = scan_impl(&dir, &cache);
    CString::new(json)
        .map(|value| value.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn free_music_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

fn scan_impl(dir: &str, cache: &str) -> String {
    let root = Path::new(dir);
    if !root.is_dir() {
        return "[]".to_string();
    }
    // Covers from a previous scan are replaced wholesale: the folder is a
    // cache, and stale files for deleted tracks would grow forever.
    let _ = fs::remove_dir_all(cache);
    let _ = fs::create_dir_all(cache);

    let mut files: Vec<PathBuf> = Vec::new();
    walk(root, &mut files);
    files.sort_by_key(|path| path.to_string_lossy().to_lowercase());

    let mut items: Vec<String> = Vec::new();
    for (index, path) in files.iter().enumerate() {
        let mut tags = read_tags(path, cache, index);
        let relative = relative_key(path, root);
        let extension = extension_of(path);
        if extension == "wav" {
            if tags.duration.is_none() {
                tags.duration = wav_duration(path);
            }
        }
        let title = tags
            .title
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| title_from_file(path));
        let artist = tags
            .artist
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "Unknown artist".to_string());
        let cover = tags.cover.unwrap_or_default();
        let duration = tags.duration.unwrap_or_else(|| String::new());
        items.push(format!(
            "{{\"path\":\"{}\",\"file\":\"{}\",\"title\":\"{}\",\"artist\":\"{}\",\"duration\":\"{}\",\"cover\":\"{}\"}}",
            escape(&path.to_string_lossy()),
            escape(&relative),
            escape(&title),
            escape(&artist),
            escape(&duration),
            escape(&cover),
        ));
    }

    format!("[{}]", items.join(","))
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        // Symlinks are skipped: a linked folder can be a loop, and a music
        // library has no reason to follow ones.
        if file_type.is_symlink() {
            continue;
        }
        let path = entry.path();
        if file_type.is_dir() {
            walk(&path, out);
        } else if file_type.is_file() && is_audio(&path) {
            out.push(path);
        }
    }
}

fn is_audio(path: &Path) -> bool {
    AUDIO_EXTENSIONS.contains(&extension_of(path).as_str())
}

fn extension_of(path: &Path) -> String {
    path.extension()
        .map(|value| value.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

fn relative_key(path: &Path, root: &Path) -> String {
    let relative = path.strip_prefix(root).unwrap_or(path);
    relative
        .to_string_lossy()
        .replace('\\', "/")
        .trim_start_matches('/')
        .to_string()
}

fn title_from_file(path: &Path) -> String {
    let stem = path
        .file_stem()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "Unknown".to_string());
    let cleaned = stem.replace(['_', '-'], " ");
    let mut result = String::with_capacity(cleaned.len());
    let mut capitalize = true;
    for character in cleaned.chars() {
        if character.is_whitespace() {
            capitalize = true;
            result.push(' ');
        } else if capitalize {
            result.extend(character.to_uppercase());
            capitalize = false;
        } else {
            result.push(character);
        }
    }
    if result.trim().is_empty() {
        "Unknown".to_string()
    } else {
        result
    }
}

// ---- tags -------------------------------------------------------------------

#[derive(Default)]
struct Tags {
    title: Option<String>,
    artist: Option<String>,
    duration: Option<String>,
    cover: Option<String>,
}

fn read_tags(path: &Path, cache: &str, index: usize) -> Tags {
    if extension_of(path) != "mp3" {
        return Tags::default();
    }
    let Some(bytes) = read_id3(path) else {
        return Tags::default();
    };
    parse_id3(&bytes, cache, index)
}

fn read_id3(path: &Path) -> Option<Vec<u8>> {
    let mut file = File::open(path).ok()?;
    let mut header = [0u8; 10];
    file.read_exact(&mut header).ok()?;
    if &header[0..3] != b"ID3" {
        return None;
    }
    let size = ((header[6] & 0x7f) as usize) << 21
        | ((header[7] & 0x7f) as usize) << 14
        | ((header[8] & 0x7f) as usize) << 7
        | (header[9] & 0x7f) as usize;
    let total = (10 + size).min(8 * 1024 * 1024);
    let mut bytes = vec![0u8; total];
    file = File::open(path).ok()?;
    file.read_exact(&mut bytes).ok()?;
    Some(bytes)
}

fn parse_id3(data: &[u8], cache: &str, index: usize) -> Tags {
    let mut tags = Tags::default();
    if data.len() < 10 {
        return tags;
    }
    let version = data[3];
    let end = data.len();
    let mut pos = 10usize;
    while pos + 10 <= end {
        let id = &data[pos..pos + 4];
        if id[0] == 0 {
            break;
        }
        let frame_size = if version >= 4 {
            syncsafe(&data[pos + 4..pos + 8]) as usize
        } else {
            big_endian_u32(&data[pos + 4..pos + 8]) as usize
        };
        if frame_size == 0 || pos + 10 + frame_size > end {
            break;
        }
        let body = &data[pos + 10..pos + 10 + frame_size];
        match id {
            b"TIT2" => tags.title = decode_text(body),
            b"TPE1" => tags.artist = decode_text(body),
            b"TLEN" => tags.duration = decode_text(body).and_then(|value| {
                let millis: u64 = value.trim().parse().ok()?;
                Some(format_time(millis / 1000))
            }),
            b"APIC" => tags.cover = write_cover(body, cache, index),
            _ => {}
        }
        pos += 10 + frame_size;
    }
    tags
}

fn syncsafe(bytes: &[u8]) -> u32 {
    ((bytes[0] & 0x7f) as u32) << 21
        | ((bytes[1] & 0x7f) as u32) << 14
        | ((bytes[2] & 0x7f) as u32) << 7
        | (bytes[3] & 0x7f) as u32
}

fn big_endian_u32(bytes: &[u8]) -> u32 {
    (bytes[0] as u32) << 24 | (bytes[1] as u32) << 16 | (bytes[2] as u32) << 8 | bytes[3] as u32
}

fn decode_text(body: &[u8]) -> Option<String> {
    let (&encoding, rest) = body.split_first()?;
    let value = match encoding {
        0 => rest.iter().map(|byte| *byte as char).collect::<String>(),
        1 => {
            let mut units: Vec<u16> = Vec::with_capacity(rest.len() / 2);
            let mut index = 0;
            let big = rest.len() >= 2 && rest[0] == 0xFE && rest[1] == 0xFF;
            if rest.len() >= 2 && rest[0] == 0xFF && rest[1] == 0xFE {
                index = 2;
            } else if big {
                index = 2;
            }
            while index + 1 < rest.len() {
                let unit = if big {
                    u16::from_be_bytes([rest[index], rest[index + 1]])
                } else {
                    u16::from_le_bytes([rest[index], rest[index + 1]])
                };
                units.push(unit);
                index += 2;
            }
            String::from_utf16_lossy(&units)
        }
        2 => {
            let mut units: Vec<u16> = Vec::with_capacity(rest.len() / 2);
            let mut index = 0;
            while index + 1 < rest.len() {
                units.push(u16::from_be_bytes([rest[index], rest[index + 1]]));
                index += 2;
            }
            String::from_utf16_lossy(&units)
        }
        _ => String::from_utf8_lossy(rest).to_string(),
    };
    let trimmed = value.trim_end_matches('\0').trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn write_cover(body: &[u8], cache: &str, index: usize) -> Option<String> {
    let (&encoding, rest) = body.split_first()?;
    let mime_end = rest.iter().position(|byte| *byte == 0)?;
    let mime = String::from_utf8_lossy(&rest[..mime_end]).to_lowercase();
    let mut cursor = mime_end + 1;
    if cursor >= rest.len() {
        return None;
    }
    cursor += 1; // picture type
    // The description is null-terminated; UTF-16 descriptions have two zero
    // bytes, so step over them by the encoding.
    if encoding == 1 || encoding == 2 {
        while cursor + 1 < rest.len() {
            if rest[cursor] == 0 && rest[cursor + 1] == 0 {
                cursor += 2;
                break;
            }
            cursor += 2;
        }
    } else {
        while cursor < rest.len() {
            if rest[cursor] == 0 {
                cursor += 1;
                break;
            }
            cursor += 1;
        }
    }
    let image = &rest[cursor..];
    if image.len() < 32 {
        return None;
    }
    let extension = if mime.contains("png") || image.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        "png"
    } else if mime.contains("webp") {
        "webp"
    } else {
        "jpg"
    };
    let name = format!("cover-{}-{}.{}", fnv1a(image), index, extension);
    let path = Path::new(cache).join(name);
    if fs::write(&path, image).is_err() {
        return None;
    }
    Some(path.to_string_lossy().to_string())
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

// ---- wav --------------------------------------------------------------------

fn wav_duration(path: &Path) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let mut bytes = vec![0u8; 64 * 1024];
    let read = file.read(&mut bytes).ok()?;
    bytes.truncate(read);
    if bytes.len() < 44 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return None;
    }
    let mut byte_rate: u32 = 0;
    let mut data_size: u32 = 0;
    let mut offset = 12usize;
    while offset + 8 <= bytes.len() {
        let id = &bytes[offset..offset + 4];
        let size = u32::from_le_bytes([
            bytes[offset + 4],
            bytes[offset + 5],
            bytes[offset + 6],
            bytes[offset + 7],
        ]);
        if id == b"fmt " && offset + 20 <= bytes.len() {
            byte_rate = u32::from_le_bytes([
                bytes[offset + 16],
                bytes[offset + 17],
                bytes[offset + 18],
                bytes[offset + 19],
            ]);
        } else if id == b"data" {
            data_size = size;
            break;
        }
        offset += 8 + size as usize + (size as usize % 2);
    }
    if byte_rate == 0 || data_size == 0 {
        return None;
    }
    let seconds = data_size as u64 / byte_rate as u64;
    Some(format_time(seconds))
}

fn format_time(seconds: u64) -> String {
    format!("{}:{:02}", seconds / 60, seconds % 60)
}

fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 8);
    for character in value.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}