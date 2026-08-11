use anydoc::{ConvertError, Format};
use encoding_rs::{UTF_16BE, UTF_16LE, WINDOWS_1252};
use std::ffi::{CStr, CString, c_char};
use std::ptr;
use std::slice;

const VERSION: &[u8] = b"anydoc-0.1.8\0";

#[repr(C)]
pub struct FamiliarAnyDocResult {
    markdown: Vec<u8>,
    format: CString,
    error_code: CString,
    error_message: CString,
}

impl FamiliarAnyDocResult {
    fn success(markdown: String, format: &str) -> Self {
        Self {
            markdown: markdown.into_bytes(),
            format: safe_c_string(format),
            error_code: safe_c_string(""),
            error_message: safe_c_string(""),
        }
    }

    fn failure(code: &str, message: impl AsRef<str>, format: &str) -> Self {
        Self {
            markdown: Vec::new(),
            format: safe_c_string(format),
            error_code: safe_c_string(code),
            error_message: safe_c_string(message.as_ref()),
        }
    }
}

fn safe_c_string(value: &str) -> CString {
    CString::new(value.replace('\0', "�")).unwrap_or_default()
}

fn extension_from_pointer(extension: *const c_char) -> String {
    if extension.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(extension) }
        .to_string_lossy()
        .trim_start_matches('.')
        .to_ascii_lowercase()
}

fn format_name(format: Format) -> &'static str {
    match format {
        Format::Doc => "doc",
        Format::Docx => "docx",
        Format::Odt => "odt",
        Format::Pdf => "pdf",
        Format::Ppt => "ppt",
        Format::Pptx => "pptx",
        Format::Rtf => "rtf",
        Format::Epub => "epub",
        Format::Excel => "excel",
        Format::Ods => "ods",
        Format::Odp => "odp",
        Format::Csv => "csv",
    }
}

fn error_result(error: ConvertError, format: &str) -> FamiliarAnyDocResult {
    FamiliarAnyDocResult::failure(error.code(), error.to_string(), format)
}

fn decode_plain_text(bytes: &[u8]) -> Result<String, &'static str> {
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return String::from_utf8(bytes[3..].to_vec()).map_err(|_| "invalid UTF-8 text");
    }
    if bytes.starts_with(&[0xFF, 0xFE]) {
        let (text, _, malformed) = UTF_16LE.decode(&bytes[2..]);
        return (!malformed).then(|| text.into_owned()).ok_or("invalid UTF-16 text");
    }
    if bytes.starts_with(&[0xFE, 0xFF]) {
        let (text, _, malformed) = UTF_16BE.decode(&bytes[2..]);
        return (!malformed).then(|| text.into_owned()).ok_or("invalid UTF-16 text");
    }
    if let Ok(text) = String::from_utf8(bytes.to_vec()) {
        return Ok(text);
    }
    let (text, _, malformed) = WINDOWS_1252.decode(bytes);
    (!malformed).then(|| text.into_owned()).ok_or("unsupported text encoding")
}

fn convert(bytes: &[u8], extension: &str) -> FamiliarAnyDocResult {
    if matches!(extension, "txt" | "md" | "markdown") {
        return match decode_plain_text(bytes) {
            Ok(text) if !text.trim().is_empty() => {
                FamiliarAnyDocResult::success(text.replace("\r\n", "\n"), extension)
            }
            Ok(_) => FamiliarAnyDocResult::failure("malformed", "document is empty", extension),
            Err(message) => FamiliarAnyDocResult::failure("malformed", message, extension),
        };
    }

    let format = Format::from_bytes(bytes).or_else(|| Format::from_extension(extension));
    let Some(format) = format else {
        return FamiliarAnyDocResult::failure(
            "unsupported",
            "unrecognized file content and extension",
            extension,
        );
    };
    let name = format_name(format);
    match anydoc::to_markdown_bytes(bytes, format) {
        Ok(markdown) if !markdown.trim().is_empty() => FamiliarAnyDocResult::success(markdown, name),
        Ok(_) => FamiliarAnyDocResult::failure("malformed", "document is empty", name),
        Err(error) => error_result(error, name),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_convert(
    bytes: *const u8,
    length: usize,
    extension: *const c_char,
) -> *mut FamiliarAnyDocResult {
    if bytes.is_null() || length == 0 {
        return Box::into_raw(Box::new(FamiliarAnyDocResult::failure(
            "malformed",
            "document is empty",
            "",
        )));
    }
    let input = unsafe { slice::from_raw_parts(bytes, length) };
    let extension = extension_from_pointer(extension);
    let result = std::panic::catch_unwind(|| convert(input, &extension)).unwrap_or_else(|_| {
        FamiliarAnyDocResult::failure(
            "bridge",
            "AnyDoc conversion terminated unexpectedly",
            &extension,
        )
    });
    Box::into_raw(Box::new(result))
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_markdown_bytes(
    result: *const FamiliarAnyDocResult,
) -> *const u8 {
    if result.is_null() {
        return ptr::null();
    }
    unsafe { (*result).markdown.as_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_markdown_length(
    result: *const FamiliarAnyDocResult,
) -> usize {
    if result.is_null() {
        return 0;
    }
    unsafe { (*result).markdown.len() }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_format(
    result: *const FamiliarAnyDocResult,
) -> *const c_char {
    if result.is_null() {
        return ptr::null();
    }
    unsafe { (*result).format.as_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_error_code(
    result: *const FamiliarAnyDocResult,
) -> *const c_char {
    if result.is_null() {
        return ptr::null();
    }
    unsafe { (*result).error_code.as_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_error_message(
    result: *const FamiliarAnyDocResult,
) -> *const c_char {
    if result.is_null() {
        return ptr::null();
    }
    unsafe { (*result).error_message.as_ptr() }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_result_free(result: *mut FamiliarAnyDocResult) {
    if !result.is_null() {
        unsafe { drop(Box::from_raw(result)) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn familiar_anydoc_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn successful_markdown(bytes: &[u8], extension: &str) -> String {
        let result = convert(bytes, extension);
        assert_eq!(result.error_code.to_str().unwrap(), "");
        String::from_utf8(result.markdown).unwrap()
    }

    #[test]
    fn passes_markdown_through() {
        let markdown = successful_markdown(b"# Familiar\n\nLocal document.", "md");
        assert!(markdown.contains("# Familiar"));
    }

    #[test]
    fn converts_csv_to_markdown() {
        let markdown = successful_markdown(include_bytes!("../tests/fixtures/sample.csv"), "csv");
        assert!(markdown.contains("Familiar"));
        assert!(markdown.contains('|'));
    }

    #[test]
    fn converts_docx_to_markdown() {
        let markdown = successful_markdown(include_bytes!("../tests/fixtures/sample.docx"), "docx");
        assert!(markdown.contains("AnyDoc Heading"));
        assert!(markdown.contains("Familiar local document conversion"));
    }

    #[test]
    fn converts_pdf_to_markdown() {
        let markdown = successful_markdown(include_bytes!("../tests/fixtures/sample.pdf"), "pdf");
        assert!(markdown.contains("Hello AnyDoc PDF"));
    }

    #[test]
    fn rejects_unknown_binary_data() {
        let result = convert(&[0, 1, 2, 3], "bin");
        assert_eq!(result.error_code.to_str().unwrap(), "unsupported");
    }

    #[test]
    fn c_abi_owns_and_releases_results() {
        let bytes = b"# Familiar FFI";
        let extension = CString::new("md").unwrap();
        let result = familiar_anydoc_convert(bytes.as_ptr(), bytes.len(), extension.as_ptr());
        assert!(!result.is_null());
        assert_eq!(familiar_anydoc_markdown_length(result), bytes.len());
        assert_eq!(unsafe { CStr::from_ptr(familiar_anydoc_error_code(result)) }.to_bytes(), b"");
        familiar_anydoc_result_free(result);
    }
}
