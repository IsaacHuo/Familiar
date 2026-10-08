// Async scheduling regression only: this DOM double does not verify WebKit layout,
// Markdown parsing, SVG sanitization or real Mermaid output. No browser is launched.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../Familiar/Resources/FamiliarMarkdownRenderer/renderer.js', import.meta.url), 'utf8');

class Element {
  children = [];
  classes = new Set();
  classList = {
    add: name => this.classes.add(name),
    contains: name => this.classes.has(name),
    toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name)
  };
  events = {};
  html = '';
  clientWidth = 300;
  style = {};
  nodeType = 1;
  get childNodes() { return this.children; }
  get nodeName() { return this.tag.toUpperCase(); }
  get outerHTML() { return this.html; }
  get textContent() { return this.html; }
  set textContent(value) { this.html = value; }
  get parentNode() { return this.parent; }
  contains(target) { return this === target || this.children.some(node => node.contains(target)); }
  getBoundingClientRect() { return {height: 100}; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter(node => node !== this); }
  constructor(tag, diagramID) { this.tag = tag; this.diagramID = diagramID; }
  get firstChild() { return this.children[0]; }
  setAttribute() {}
  getAttribute(name) { return name === 'data-mermaid-id' ? String(this.diagramID) : null; }
  set innerHTML(html) {
    this.html = html;
    this.children = Array.from(html.matchAll(/data-mermaid-id="(\d+)"/g), match => new Element('div', Number(match[1])));
  }
  get innerHTML() { return this.html; }
  querySelectorAll(selector) {
    const nested = this.children.flatMap(node => node.querySelectorAll(selector));
    return selector === '[data-mermaid-id]' ? [...this.children.filter(node => node.diagramID !== undefined), ...nested] : nested;
  }
  querySelector(selector) {
    if (selector.includes('[data-mermaid-id]')) return this.querySelectorAll('[data-mermaid-id]')[0];
    if (selector === 'svg') return this.html.includes('<svg') ? { scrollWidth: 100 } : null;
    if (selector === '.mermaid-preview-button') return this.children.find(node => node.className === 'mermaid-preview-button');
    return null;
  }
  replaceChildren(...nodes) { this.children = nodes.flatMap(node => node.children && node.tag === 'fragment' ? node.children : [node]); }
  appendChild(node) { node.parent = this; this.children.push(node); }
  insertBefore(node) { this.children.unshift(node); }
  addEventListener(name, handler) { this.events[name] = handler; }
}

function harness() {
  const content = new Element('main');
  const pending = [];
  const previews = [];
  const errors = [];
  const window = {
    getSelection: () => null,
    markdownit: () => ({ render: value => value, renderer: { rules: { fence() {} } } }),
    mermaid: {
      initialize() {},
      render: (id, text) => new Promise((resolve, reject) => pending.push({ text, resolve, reject }))
    },
    webkit: { messageHandlers: {
      previewMermaid: { postMessage: value => previews.push(value) },
      renderFailed: { postMessage: value => errors.push(value) }
    } }
  };
  const document = {
    documentElement: {},
    getElementById: () => content,
    addEventListener() {},
    createElement(tag) {
      if (tag !== 'template') return new Element(tag);
      const fragment = new Element('fragment');
      return { content: fragment, set innerHTML(value) { fragment.innerHTML = value; } };
    }
  };
  vm.runInNewContext(source, { window, document, URL, requestAnimationFrame: () => 1,
    cancelAnimationFrame() {}, getComputedStyle: () => ({ getPropertyValue: () => '#000' }) });
  return { content, pending, previews, errors, render: window.FamiliarMarkdown.render };
}

const diagram = label => 'graph TD\n' + Array.from({ length: 9 }, (_, index) => `${label}${index} --> ${label}${index + 1}`).join('\n');
const fenced = text => '```mermaid\n' + text + '\n```';
const settle = () => new Promise(resolve => setImmediate(resolve));
const options = { mermaidPreviewEnabled: true, mermaidPreviewLabel: 'Preview', streaming: true };

for (const outcome of ['resolve', 'reject']) {
  test(`A stale Mermaid ${outcome} cannot decorate the newer response`, async () => {
    const h = harness();
    const oldText = diagram('Old');
    const newText = diagram('New');
    h.render(fenced(oldText), options);
    const oldNode = h.content.children[0].children[0];
    h.render(fenced(newText), options);
    const newNode = h.content.children[0].children[0];
    assert.equal(h.pending.length, 2);
    if (outcome === 'resolve') h.pending[0].resolve({ svg: '<svg>old</svg>' });
    else h.pending[0].reject(new Error('Old parse failed'));
    await settle();
    assert.equal(oldNode.innerHTML, '');
    assert.equal(newNode.innerHTML, '');
    assert.equal(newNode.querySelector('.mermaid-preview-button'), undefined);
    h.pending[1].resolve({ svg: '<svg>new</svg>' });
    await settle();
    assert.equal(newNode.innerHTML, '<svg>new</svg>');
    newNode.querySelector('.mermaid-preview-button').events.click();
    assert.deepEqual(h.previews, [newText]);
    assert.deepEqual(h.errors, []);
  });
}

test('Replacing a pending diagram stops scheduling its remaining diagrams', async () => {
  const h = harness();
  h.render(fenced(diagram('Old')) + '\n\n' + fenced(diagram('Later')), options);
  assert.equal(h.pending.length, 1);
  h.render('Current plain text', { ...options, streaming: false });
  h.pending[0].resolve({ svg: '<svg>old</svg>' });
  await settle();
  assert.equal(h.pending.length, 1);
  assert.equal(h.content.children.length, 0);
  assert.deepEqual(h.errors, []);
});

test('Appending prose reuses the same pending Mermaid job', async () => {
  const h = harness();
  const text = diagram('Same');
  h.render(fenced(text), options);
  const node = h.content.children[0].children[0];
  h.render(fenced(text) + '\\n\\nNew prose', options);
  assert.equal(h.pending.length, 1);
  h.pending[0].resolve({ svg: '<svg>same</svg>' });
  await settle();
  assert.equal(node.innerHTML, '<svg>same</svg>');
  assert.deepEqual(h.errors, []);
});
