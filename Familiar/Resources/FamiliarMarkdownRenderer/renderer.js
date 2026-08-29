(function () {
  "use strict";

  const content = document.getElementById("content");
  let pendingHeightFrame = null;
  let pendingSelectionFrame = null;
  let lastReportedHeight = 0;
  let lastReportedSelection = "";
  let selectionEnabled = false;

  function post(name, payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(payload);
    }
  }

  function reportHeight() {
    if (pendingHeightFrame !== null) return;
    pendingHeightFrame = requestAnimationFrame(function () {
      pendingHeightFrame = null;
      const height = Math.ceil(Math.max(content.scrollHeight, content.getBoundingClientRect().height));
      if (Math.abs(height - lastReportedHeight) < 1) return;
      lastReportedHeight = height;
      post("heightChanged", height);
    });
  }

  function selectedPlainText() {
    if (!selectionEnabled) return "";
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return "";
    const text = selection.toString().trim();
    return Array.from(text).slice(0, 4000).join("");
  }

  function reportSelection() {
    if (pendingSelectionFrame !== null) cancelAnimationFrame(pendingSelectionFrame);
    pendingSelectionFrame = requestAnimationFrame(function () {
      pendingSelectionFrame = null;
      const text = selectedPlainText();
      if (text === lastReportedSelection) return;
      lastReportedSelection = text;
      post("selectionChanged", text);
    });
  }

  function setSelectionEnabled(enabled) {
    selectionEnabled = enabled;
    content.classList.toggle("selection-disabled", !enabled);
    if (!enabled) {
      const selection = window.getSelection();
      if (selection) selection.removeAllRanges();
    }
    reportSelection();
  }

  function escapeHTML(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function preprocessTaskLists(markdown) {
    return markdown.replace(
      /^(\s*[-*+]\s+)\[( |x|X)\]\s+/gm,
      function (_, prefix, checked) {
        const className = checked.trim().length > 0 ? "task-marker checked" : "task-marker";
        return prefix + '<span class="' + className + '" aria-label="task item"></span> ';
      }
    );
  }

  function extractCitations(markdown, sources) {
    const sourceMap = new Map();
    (sources || []).forEach(function (source, index) {
      if (source && typeof source.id === "string") {
        sourceMap.set(source.id, { source: source, number: index + 1 });
      }
    });

    return markdown.replace(/\[\[([^\]\n]+)\]\]/g, function (match, sourceID) {
      const entry = sourceMap.get(sourceID.trim());
      if (!entry) return match;
      const source = entry.source;
      const label = source.title || source.siteName || source.url;
      return '<a class="citation-chip" href="' + escapeHTML(source.url) + '" title="' + escapeHTML(label) + '" aria-label="' + escapeHTML("Source " + entry.number + ": " + label) + '">' + entry.number + "</a>";
    });
  }

  function extractFootnotes(markdown) {
    const notes = [];
    const withoutDefinitions = markdown
      .split(/\r?\n/)
      .filter(function (line) {
        const match = line.match(/^\[\^([^\]]+)\]:\s*(.*)$/);
        if (!match) {
          return true;
        }
        notes.push({ id: match[1], text: match[2] });
        return false;
      })
      .join("\n");

    const withReferences = withoutDefinitions.replace(/\[\^([^\]]+)\]/g, function (_, id) {
      const index = notes.findIndex(function (note) { return note.id === id; });
      if (index < 0) {
        return "[^" + id + "]";
      }
      const number = index + 1;
      return '<sup id="fnref-' + escapeHTML(id) + '"><a href="#fn-' + escapeHTML(id) + '">' + number + "</a></sup>";
    });

    return { markdown: withReferences, notes: notes };
  }

  function protectFencedCode(markdown) {
    const fences = [];
    const protectedMarkdown = markdown.replace(
      /(^|\n)(`{3,}|~{3,})[\s\S]*?\n\2[^\n]*(?=\n|$)/g,
      function (match, prefix) {
        const token = "@@FAMILIAR_FENCE_" + fences.length + "@@";
        fences.push(match.slice(prefix.length));
        return prefix + token;
      }
    );
    return { markdown: protectedMarkdown, fences: fences };
  }

  function restoreFencedCode(markdown, fences) {
    return markdown.replace(/@@FAMILIAR_FENCE_(\d+)@@/g, function (_, index) {
      return fences[Number(index)] || "";
    });
  }

  function extractMath(markdown) {
    const protectedCode = protectFencedCode(markdown);
    const math = [];
    let text = protectedCode.markdown;

    function placeholder(expression, display) {
      const index = math.push({ expression: expression, display: display }) - 1;
      const tag = display ? "div" : "span";
      const className = display ? "math-block" : "math-inline";
      return "<" + tag + ' class="' + className + '" data-math-id="' + index + '"></' + tag + ">";
    }

    text = text.replace(/\$\$([\s\S]+?)\$\$/g, function (_, expression) {
      return placeholder(expression, true);
    });
    text = text.replace(/\\\[([\s\S]+?)\\\]/g, function (_, expression) {
      return placeholder(expression, true);
    });
    text = text.replace(/\\\(([\s\S]+?)\\\)/g, function (_, expression) {
      return placeholder(expression, false);
    });
    text = text.replace(/(^|[^\\$])\$([^\n$]+?)\$/g, function (_, prefix, expression) {
      return prefix + placeholder(expression, false);
    });

    return {
      markdown: restoreFencedCode(text, protectedCode.fences),
      math: math
    };
  }

  function extractMermaid(markdown) {
    const diagrams = [];
    const text = markdown.replace(
      /(^|\n)(`{3,}|~{3,})[ \t]*(mermaid)\s*\n([\s\S]*?)\n\2[^\n]*(?=\n|$)/gi,
      function (_, prefix, fence, language, source) {
        const index = diagrams.push(source) - 1;
        return prefix + '<div class="mermaid-diagram" data-mermaid-id="' + index + '"></div>';
      }
    );
    return { markdown: text, diagrams: diagrams };
  }

  function createMarkdownIt() {
    if (!window.markdownit) {
      return null;
    }
    return window.markdownit({
      html: true,
      linkify: true,
      typographer: false,
      breaks: false,
      highlight: function (source, language) {
        if (!window.hljs) {
          return escapeHTML(source);
        }
        try {
          if (language && window.hljs.getLanguage(language)) {
            return window.hljs.highlight(source, { language: language, ignoreIllegals: true }).value;
          }
          return window.hljs.highlightAuto(source).value;
        } catch (_) {
          return escapeHTML(source);
        }
      }
    });
  }

  function renderFootnotes(notes, md) {
    if (!notes.length) {
      return "";
    }
    const items = notes.map(function (note, index) {
      return '<li id="fn-' + escapeHTML(note.id) + '">' + md.renderInline(note.text) + "</li>";
    });
    return '<section class="footnotes"><ol>' + items.join("") + "</ol></section>";
  }

  function sanitize(html) {
    if (!window.DOMPurify) {
      return html;
    }
    return window.DOMPurify.sanitize(html, {
      ADD_TAGS: ["details", "summary"],
      ADD_ATTR: [
        "aria-label",
        "class",
        "data-mermaid-id",
        "data-math-id",
        "href",
        "id",
        "rel",
        "src",
        "target",
        "title",
        "alt"
      ],
      FORBID_TAGS: ["script", "style", "iframe", "form", "input", "object", "embed", "textarea", "select"],
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
    });
  }

  function sanitizeMermaidSVG(svg) {
    if (!window.DOMPurify) {
      return svg;
    }
    return window.DOMPurify.sanitize(svg, {
      USE_PROFILES: { svg: true, svgFilters: true },
      ADD_TAGS: ["style"],
      ADD_ATTR: [
        "aria-hidden",
        "aria-label",
        "class",
        "clip-path",
        "d",
        "dominant-baseline",
        "fill",
        "font-family",
        "font-size",
        "font-style",
        "font-weight",
        "height",
        "id",
        "marker-end",
        "marker-start",
        "points",
        "rx",
        "ry",
        "stroke",
        "stroke-dasharray",
        "stroke-linecap",
        "stroke-width",
        "style",
        "text-anchor",
        "transform",
        "viewBox",
        "width",
        "x",
        "x1",
        "x2",
        "y",
        "y1",
        "y2"
      ]
    });
  }

  function hardenLinksAndImages(root) {
    root.querySelectorAll("img").forEach(function (image) {
      const source = image.getAttribute("src") || "";
      let url;
      try {
        url = new URL(source);
      } catch (_) {
        image.remove();
        return;
      }

      if (url.protocol !== "https:") {
        image.remove();
        return;
      }

      const link = document.createElement("a");
      const description = (image.getAttribute("alt") || "").trim();
      const label = document.createElement("span");
      const host = document.createElement("span");

      link.className = "remote-image-link";
      link.href = url.href;
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
      link.setAttribute("aria-label", description ? description + " (" + url.hostname + ")" : url.hostname);

      label.className = "remote-image-label";
      label.textContent = description || url.hostname;
      link.appendChild(label);

      if (description && description !== url.hostname) {
        host.className = "remote-image-host";
        host.textContent = url.hostname;
        link.appendChild(host);
      }

      image.replaceWith(link);
    });

    root.querySelectorAll("a").forEach(function (link) {
      const href = link.getAttribute("href") || "";
      if (/^(https?:|mailto:)/i.test(href)) {
        link.setAttribute("target", "_blank");
        link.setAttribute("rel", "noopener noreferrer");
      } else if (!href.startsWith("#")) {
        link.removeAttribute("href");
      }
    });

  }

  function renderMath(root, math) {
    if (!window.katex) {
      return;
    }
    root.querySelectorAll("[data-math-id]").forEach(function (node) {
      const item = math[Number(node.getAttribute("data-math-id"))];
      if (!item) {
        return;
      }
      try {
        window.katex.render(item.expression, node, {
          displayMode: item.display,
          throwOnError: false,
          output: "html"
        });
      } catch (_) {
        node.textContent = item.expression;
      }
    });
  }

  function fallbackMermaid(node, source) {
    const pre = document.createElement("pre");
    const code = document.createElement("code");
    code.className = "language-mermaid";
    code.textContent = source;
    pre.appendChild(code);
    node.replaceChildren(pre);
  }

  async function renderMermaid(root, diagrams) {
    if (!diagrams.length) {
      return;
    }
    if (!window.mermaid || typeof window.mermaid.render !== "function") {
      root.querySelectorAll("[data-mermaid-id]").forEach(function (node) {
        fallbackMermaid(node, diagrams[Number(node.getAttribute("data-mermaid-id"))] || "");
      });
      return;
    }

    try {
      window.mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        themeVariables: {
          background: "transparent",
          mainBkg: "#f7f9ff",
          primaryColor: "#edf4ff",
          primaryTextColor: "#172033",
          primaryBorderColor: "#bfd2f2",
          lineColor: "#536985",
          textColor: "#172033",
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
        }
      });
    } catch (_) {}

    const nodes = Array.from(root.querySelectorAll("[data-mermaid-id]"));
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const source = diagrams[Number(node.getAttribute("data-mermaid-id"))] || "";
      if (!source.trim()) {
        fallbackMermaid(node, source);
        continue;
      }
      try {
        const id = "familiar-mermaid-" + Date.now() + "-" + index;
        const result = await window.mermaid.render(id, source);
        node.innerHTML = sanitizeMermaidSVG(result.svg || "");
        node.classList.add("rendered");
      } catch (_) {
        fallbackMermaid(node, source);
      }
    }
  }

  function decorateMermaidPreviews(root, diagrams, options) {
    if (!(options && options.mermaidPreviewEnabled)) return;
    root.querySelectorAll("[data-mermaid-id]").forEach(function (node) {
      const source = diagrams[Number(node.getAttribute("data-mermaid-id"))] || "";
      const svg = node.querySelector("svg");
      const isLong = source.length > 320 || source.split(/\r?\n/).length > 8 || (svg && svg.scrollWidth > node.clientWidth);
      if (!isLong || node.querySelector(".mermaid-preview-button")) return;

      const button = document.createElement("button");
      button.className = "mermaid-preview-button";
      button.type = "button";
      button.textContent = options.mermaidPreviewLabel || "Open diagram";
      button.addEventListener("click", function () {
        post("previewMermaid", source);
      });
      node.insertBefore(button, node.firstChild);
    });
  }

  function decorateCodeBlocks(root) {
    root.querySelectorAll("pre > code").forEach(function (code) {
      const pre = code.parentElement;
      if (!pre || pre.parentElement.classList.contains("code-block")) {
        return;
      }

      const languageClass = Array.from(code.classList).find(function (className) {
        return className.indexOf("language-") === 0;
      });
      const language = languageClass ? languageClass.replace("language-", "") : "";
      const wrapper = document.createElement("div");
      wrapper.className = "code-block";
      const header = document.createElement("div");
      header.className = "code-header";
      const label = document.createElement("span");
      label.className = "code-language";
      label.textContent = language || "text";
      const button = document.createElement("button");
      button.className = "copy-code";
      button.type = "button";
      button.textContent = "\u590d\u5236";
      button.addEventListener("click", function () {
        post("copyCode", code.textContent || "");
        button.textContent = "\u5df2\u590d\u5236";
        window.setTimeout(function () {
          button.textContent = "\u590d\u5236";
        }, 1200);
      });
      header.appendChild(label);
      header.appendChild(button);
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(header);
      wrapper.appendChild(pre);
    });
  }

  function decorateTables(root) {
    root.querySelectorAll("table").forEach(function (table) {
      if (table.parentElement && table.parentElement.classList.contains("table-scroll")) {
        return;
      }
      const wrapper = document.createElement("div");
      wrapper.className = "table-scroll";
      table.parentNode.insertBefore(wrapper, table);
      wrapper.appendChild(table);
    });
  }

  function render(markdown, options) {
    try {
      setSelectionEnabled(!(options && options.streaming));
      content.classList.toggle("streaming", Boolean(options && options.streaming));
      const md = createMarkdownIt();
      if (!md) {
        content.innerHTML = "<p>" + escapeHTML(markdown).replace(/\n/g, "<br>") + "</p>";
        reportHeight();
        return;
      }

      const citedMarkdown = extractCitations(markdown || "", options && options.sources);
      const footnoteResult = extractFootnotes(preprocessTaskLists(citedMarkdown));
      const mathResult = extractMath(footnoteResult.markdown);
      const mermaidResult = extractMermaid(mathResult.markdown);
      const rawHTML = md.render(mermaidResult.markdown) + renderFootnotes(footnoteResult.notes, md);
      const template = document.createElement("template");
      template.innerHTML = sanitize(rawHTML);
      hardenLinksAndImages(template.content);
      content.replaceChildren(template.content);
      renderMath(content, mathResult.math);
      renderMermaid(content, mermaidResult.diagrams)
        .catch(function () {
          content.querySelectorAll("[data-mermaid-id]").forEach(function (node) {
            fallbackMermaid(node, mermaidResult.diagrams[Number(node.getAttribute("data-mermaid-id"))] || "");
          });
        })
        .then(function () {
          decorateMermaidPreviews(content, mermaidResult.diagrams, options);
          decorateCodeBlocks(content);
          decorateTables(content);
          reportHeight();
        });
    } catch (error) {
      content.innerHTML = "<p>" + escapeHTML(markdown || "").replace(/\n/g, "<br>") + "</p>";
      post("renderFailed", String(error && error.message ? error.message : error));
      reportHeight();
    }
  }

  if (window.ResizeObserver) {
    new ResizeObserver(reportHeight).observe(content);
  }
  document.addEventListener("selectionchange", reportSelection);

  window.FamiliarMarkdown = {
    render: render
  };
  post("rendererReady", true);
})();
