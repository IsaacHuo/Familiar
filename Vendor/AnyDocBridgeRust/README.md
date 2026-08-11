# Familiar AnyDoc bridge

This crate exposes a narrow C ABI around [`anydoc` 0.1.8](https://github.com/firecrawl/anydoc) for the Familiar iOS app.

- All structured document conversion is local and uses `anydoc::to_markdown_bytes`.
- PDF conversion uses AnyDoc's `pdf-inspector` path.
- TXT and Markdown are validated and passed through because upstream AnyDoc does not define those as input formats.
- The generated static XCFramework contains arm64 slices for iPhone devices and Apple Silicon iPhone simulators. Intel Mac simulators are intentionally excluded.

Rebuild with:

```sh
./Scripts/build-anydoc-xcframework.sh
```

AnyDoc is MIT licensed. See `LICENSE.anydoc`.
