// Minimal JSON helpers for the C ABI: every backend function returns one
// string, and hand-escaping is cheaper than pulling a serializer into a
// cdylib that only ever emits flat arrays.

pub fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 8);
    for ch in value.chars() {
        match ch {
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

pub fn quote(value: &str) -> String {
    format!("\"{}\"", escape(value))
}

#[cfg(test)]
mod tests {
    use super::{escape, quote};

    #[test]
    fn escapes_quotes_and_controls() {
        assert_eq!(escape("a\"b\\c\nd"), "a\\\"b\\\\c\\nd");
    }

    #[test]
    fn quotes_a_value() {
        assert_eq!(quote("hi"), "\"hi\"");
    }
}