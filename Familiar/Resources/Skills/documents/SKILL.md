---
name: documents
description: Deliver verified Word, Excel, PowerPoint or PDF documents from the bundled Linux environment with a previewable File card.
version: 1.0.0
---
# Documents

Choose the lightest path that can actually produce the requested format.

1. Markdown, plain text or CSV: write the file directly with file_write. No Linux environment and no publish step are required for these formats.
2. DOCX, XLSX, PPTX or PDF: use the bundled Linux environment.
   - Call environment_status first. The bundled image already ships python-docx, openpyxl, python-pptx, fpdf2, pypdf, markdown, lxml and Pillow, so environment_prepare is normally unnecessary. Only if a genuinely missing package is required, request it by declarative name through environment_prepare; never install with pip inside shell_execute.
   - Prepare the source (UTF-8 JSON or a Python script) in Outputs with workspace_write, then run python3 through shell_execute and write the final bytes under /workspace/outputs.
   - The first content request may report "Preparing the runtime environment" while the guest boots; that is preparation, not failure.
   - Chinese PDF text: register /usr/share/fonts/noto/NotoSansSC-Regular.otf (and -Bold for bold runs) with fpdf2 `add_font` before writing text. These bundled fonts embed correctly and keep the document portable.
3. Publish every delivered document with file_publish, passing the Outputs path, the exact format and requiredText for the strings the user asked to see. DOCX, XLSX, PPTX and PDF are parsed and validated; a successful shell command alone is not delivery.
4. Report only after file_publish succeeds. The File card can be previewed and shared in the app. Never claim the file was exported merely because a share action exists.

If a validator, dependency or permission step fails, repair within the Run budget or report the concrete unfinished step. Do not fabricate success, and do not replace the requested format with a different one without asking.
