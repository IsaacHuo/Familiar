(function () {
  "use strict";

  const content = document.getElementById("content");
  let pendingHeightFrame = null;
  let pendingSelectionFrame = null;
  let lastReportedHeight = 0;
  let lastReportedSelection = "";
  let selectionEnabled = false;
  let renderVersion = 0;
  let markdownParser = null;
  let readingAnchor = null;
  function setReadingTop(y) {
    readingAnchor = null;
    if (!Number.isFinite(y)) return;
    const nodes = content.querySelectorAll("p, li, h1, h2, h3, h4, pre, table, [data-mermaid-id]");
    for (const node of nodes) {
      const rect = node.getBoundingClientRect();
      if (rect.bottom > y) { readingAnchor = { node: node, top: rect.top }; break; }
    }
  }

  function post(name, payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(payload);
    }
  }

  function reportHeight() {
    if (pendingHeightFrame !== null) return;
    pendingHeightFrame = requestAnimationFrame(function () {
      pendingHeightFrame = null;
      if (readingAnchor && content.contains(readingAnchor.node)) {
        const top = readingAnchor.node.getBoundingClientRect().top;
        const shift = top - readingAnchor.top;
        if (Math.abs(shift) > 0.5) post("readingShift", shift);
        readingAnchor.top = top;
      }
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
    if (markdownParser) return markdownParser;
    markdownParser = window.markdownit({
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
    const fence = markdownParser.renderer.rules.fence;
    markdownParser.renderer.rules.fence = function (tokens, index, options, env, self) {
      const token = tokens[index];
      const last = env && env.lines && token.map ? env.lines[token.map[1] - 1] || "" : "";
      const closed = last.trim().startsWith(token.markup) && last.trim().slice(token.markup.length).trim() === "";
      if (env && env.streaming && !closed) {
        const language = (token.info || "").trim().split(/\s+/)[0];
        return '<pre data-familiar-open-code="true"><code class="language-' + escapeHTML(language) + '">' + escapeHTML(token.content) + '</code></pre>';
      }
      return fence(tokens, index, options, env, self);
    };
    return markdownParser;
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
      if (!item) { return; }
      const signature = JSON.stringify(item);
      if (node._familiarMath === signature) return;
      node._familiarMath = signature;
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

  async function renderMermaid(root, diagrams, version, options) {
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
          mainBkg: getComputedStyle(document.documentElement).getPropertyValue("--familiar-inset").trim(),
          primaryColor: getComputedStyle(document.documentElement).getPropertyValue("--familiar-accent-tint").trim(),
          primaryTextColor: getComputedStyle(document.documentElement).getPropertyValue("--familiar-ink").trim(),
          primaryBorderColor: getComputedStyle(document.documentElement).getPropertyValue("--familiar-line-strong").trim(),
          lineColor: getComputedStyle(document.documentElement).getPropertyValue("--familiar-secondary").trim(),
          textColor: getComputedStyle(document.documentElement).getPropertyValue("--familiar-ink").trim(),
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif"
        }
      });
    } catch (_) {}

    const nodes = Array.from(root.querySelectorAll("[data-mermaid-id]"));
    for (let index = 0; index < nodes.length; index += 1) {
      if (version !== renderVersion) return;
      const node = nodes[index];
      const source = diagrams[Number(node.getAttribute("data-mermaid-id"))] || "";
      const style = document.documentElement.getAttribute ? document.documentElement.getAttribute("style") || "" : "";
      const signature = source + style;
      if (node._familiarMermaid === signature || node._familiarMermaidPending === signature) continue;
      node._familiarMermaidPending = signature;
      if (!source.trim()) {
        fallbackMermaid(node, source);
        continue;
      }
      try {
        const id = "familiar-mermaid-" + Date.now() + "-" + index;
        const result = await window.mermaid.render(id, source);
        if (!content.contains(node) || node._familiarMermaidPending !== signature) continue;
        node.innerHTML = sanitizeMermaidSVG(result.svg || "");
        node.classList.add("rendered");
        node._familiarMermaid = signature;
        node._familiarMermaidPending = null;
        decorateMermaidPreviews(root, diagrams, options);
        reportHeight();
      } catch (_) {
        if (!content.contains(node) || node._familiarMermaidPending !== signature) continue;
        node._familiarMermaidPending = null;
        fallbackMermaid(node, source);
        reportHeight();
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

  function decorateCodeBlocks(root, options) {
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
      button.disabled = pre.hasAttribute("data-familiar-open-code");
      button.textContent = options.copyLabel;
      button.addEventListener("click", function () {
        post("copyCode", code.textContent || "");
        button.textContent = options.copiedLabel;
        window.setTimeout(function () {
          button.textContent = options.copyLabel;
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

  // The block wrapper owns identity; content changes never replace the whole document.
  function appendChunk(parent, value, animate) {
    if (!value) return;
    if (!animate) { parent.appendChild(document.createTextNode(value)); return; }
    const span = document.createElement("span");
    span.className = "familiar-chunk";
    span.textContent = value;
    span.addEventListener("animationend", function () {
      span.replaceWith(document.createTextNode(span.textContent));
      parent.normalize();
    }, { once: true });
    parent.appendChild(span);
  }

  function patchNode(current, next, animate) {
    if (current.nodeType !== next.nodeType || current.nodeName !== next.nodeName) {
      current.replaceWith(next);
      return;
    }
    if (current.nodeType === 3) { current.data = next.data; return; }
    if (current.nodeType !== 1) return;
    Array.from(current.attributes).forEach(function (attr) {
      if (!next.hasAttribute(attr.name)) current.removeAttribute(attr.name);
    });
    Array.from(next.attributes).forEach(function (attr) { current.setAttribute(attr.name, attr.value); });
    // Preserve already appearing text chunks across subsequent pacing ticks.
    const nextText = next.childNodes.length === 1 && next.firstChild.nodeType === 3;
    const currentText = Array.from(current.childNodes).every(function (node) {
      return node.nodeType === 3 || (node.nodeType === 1 && node.classList.contains("familiar-chunk"));
    });
    if (nextText && currentText) {
      const before = current.textContent;
      const after = next.textContent;
      if (after.startsWith(before)) appendChunk(current, after.slice(before.length), animate);
      else current.textContent = after;
      return;
    }
    const children = Array.from(next.childNodes);
    children.forEach(function (child, index) {
      if (current.childNodes[index]) patchNode(current.childNodes[index], child, animate);
      else current.appendChild(child);
    });
    while (current.childNodes.length > children.length) current.lastChild.remove();
  }

  function reconcileBlocks(fragment, options) {
    const animate = Boolean(options && options.streaming && !options.reduceMotion);
    const nodes = Array.from(fragment.childNodes).filter(function (node) {
      return node.nodeType !== 3 || node.textContent.trim();
    });
    const old = Array.from(content.children);
    nodes.forEach(function (node, index) {
      const html = node.outerHTML || node.textContent;
      let block = old[index];
      if (!block) {
        block = document.createElement("div");
        block.className = "markdown-block";
        block.setAttribute("data-familiar-block", String(index));
        block.appendChild(node);
        block._familiarHTML = html;
        content.appendChild(block);
        if (animate) block.classList.add("familiar-appear");
      } else if (block._familiarHTML !== html) {
        // Code/table/diagram decoration changes structure; retain their measured wrapper.
        const complex = block.querySelector("pre, table, [data-mermaid-id], .code-block, .table-scroll");
        if (complex) {
          block.style.minHeight = options && options.streaming ? block.getBoundingClientRect().height + "px" : "";
          const pre = block.querySelector("pre");
          const table = block.querySelector("table");
          if (pre && node.nodeName === "PRE" && pre.querySelector("code") && node.querySelector("code")) {
            patchNode(pre.querySelector("code"), node.querySelector("code"), false);
            pre.toggleAttribute("data-familiar-open-code", node.hasAttribute("data-familiar-open-code"));
            const copy = block.querySelector(".copy-code");
            if (copy) copy.disabled = node.hasAttribute("data-familiar-open-code");
          } else if (table && node.nodeName === "TABLE") patchNode(table, node, false);
          else block.replaceChildren(node);
        } else if (block.firstChild) patchNode(block.firstChild, node, animate);
        else block.appendChild(node);
        block._familiarHTML = html;
      }
    });
    old.slice(nodes.length).forEach(function (node) { node.remove(); });
  }

  function render(markdown, options) {
    const version = ++renderVersion;
    try {
      const style = options && options.style;
      if (style) Object.keys(style).forEach(function (key) {
        if (key.indexOf("--familiar-") === 0) document.documentElement.style.setProperty(key, String(style[key]));
      });
      setSelectionEnabled(!(options && options.streaming));
      content.classList.toggle("reduce-motion", Boolean(options && options.reduceMotion));
      content.classList.toggle("streaming", Boolean(options && options.streaming));
      if (!(options && options.streaming)) {
        Array.from(content.children).forEach(function (block) { if (block.style) block.style.minHeight = ""; });
      }
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
      const rawHTML = md.render(mermaidResult.markdown, {
        streaming: Boolean(options && options.streaming), lines: mermaidResult.markdown.split("\n")
      }) + renderFootnotes(footnoteResult.notes, md);
      const template = document.createElement("template");
      template.innerHTML = sanitize(rawHTML);
      hardenLinksAndImages(template.content);
      reconcileBlocks(template.content, options);
      renderMath(content, mathResult.math);
      renderMermaid(content, mermaidResult.diagrams, version, options)
        .catch(function () {
          if (version !== renderVersion) return;
          content.querySelectorAll("[data-mermaid-id]").forEach(function (node) {
            fallbackMermaid(node, mermaidResult.diagrams[Number(node.getAttribute("data-mermaid-id"))] || "");
          });
        })
        .then(function () {
          if (version !== renderVersion) return;
          decorateMermaidPreviews(content, mermaidResult.diagrams, options);
          decorateCodeBlocks(content, options);
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
    render: render,
    setReadingTop: setReadingTop
  };
  post("rendererReady", true);
})();
