---
name: research-document
description: Research a topic using fetched sources and deliver a verified Word document with headings and source links.
version: 1.0.0
---
# Research document

1. Use the user's requested headings and source requirements. Show a task_plan only when a checklist helps the user; it is not required to execute the task.
2. Use web_search and web_fetch. Read at least two relevant source pages. Search snippets alone are not evidence. Prefer primary sources. Keep titles and exact fetched URLs.
3. The bundled runtime already ships python-docx, openpyxl, python-pptx, fpdf2, pypdf, markdown, lxml and Pillow; python-docx needs no installation. Only use environment_prepare for a genuinely missing package, and never install dependencies with pip inside shell_execute.
4. Write UTF-8 JSON to Outputs/document-input.json with title, sections (heading and paragraphs), and sources (title and url). Use workspace_write; all claims should be supported by the fetched sources. Do not invent facts to fill a document.
5. Execute `python3 /workspace/files/Skills/research-document/scripts/make_document.py --input /workspace/outputs/document-input.json --output /workspace/outputs/report.docx` with shell_execute. The script is read-only; output belongs in Outputs.
6. Call file_publish with the DOCX path, requiredText for requested headings, and minimumSources (normally 2). Read it back using file_read when needed. Fix missing sections or broken files and republish, preserving an existing File as the predecessor when revising it.
7. Deliver the File card only after publication succeeds. Say that the file can be previewed and shared; do not claim it was exported merely because a share action is available. If you showed a checklist, update it to reflect actual outcomes.

A successful command is not sufficient evidence of a successful document. Publication and readback must succeed. If a dependency, source, permission, or validator fails, repair within the Run budget or report the concrete unfinished step.
