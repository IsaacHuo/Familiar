---
name: research-document
description: Research a topic using fetched sources and deliver a verified Word document with headings and source links.
version: 1.0.0
---
# Research document

1. Declare an ordered task_plan and a DOCX expectedDeliverable with a stable ID, required section headings, and minimumSources (normally 2).
2. Use web_search and web_fetch. Read at least two relevant source pages. Search snippets alone are not evidence. Prefer primary sources. Keep titles and exact fetched URLs.
3. Call environment_status. Propose python-docx through environment_prepare if missing. Do not install dependencies using shell_execute.
4. Write UTF-8 JSON to Outputs/document-input.json with title, sections (heading and paragraphs), and sources (title and url). Use workspace_write; all claims should be supported by the fetched sources. Do not invent facts to fill a document.
5. Execute `python3 /workspace/files/Skills/research-document/scripts/make_document.py --input /workspace/outputs/document-input.json --output /workspace/outputs/report.docx` with shell_execute. The script is read-only; output belongs in Outputs.
6. Call artifact_publish with the exact deliverableID and DOCX path. Read it back using artifact_read. Fix missing sections or broken files and republish, preserving an existing Artifact as the predecessor when revising it.
7. Update task_plan using actual execution evidence. Deliver the Artifact card only after publication succeeds. Say that the file can be previewed and shared; do not claim it was exported merely because a share action is available.

A successful command is not sufficient evidence of a successful document. Publication and readback must succeed. If a dependency, source, permission, or validator fails, repair within the Run budget or report the concrete unfinished step.
