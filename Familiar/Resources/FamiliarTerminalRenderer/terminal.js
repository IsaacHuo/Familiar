'use strict';
const terminal = new Terminal({cursorBlink:true,screenReaderMode:true,fontSize:14,scrollback:2500,theme:{background:'#101114',foreground:'#e7e8eb'},allowProposedApi:true});
const fit = new FitAddon.FitAddon();
terminal.loadAddon(fit); terminal.loadAddon(new Unicode11Addon.Unicode11Addon()); terminal.unicode.activeVersion='11';
terminal.open(document.getElementById('terminal'));
function post(kind,value){ window.webkit.messageHandlers.terminal.postMessage({kind,value}); }
function encode(bytes){ let binary=''; for (const byte of bytes) binary+=String.fromCharCode(byte); return btoa(binary); }
terminal.onData(text=>post('input',encode(new TextEncoder().encode(text))));
terminal.onBinary(text=>post('input',btoa(text)));
terminal.onResize(size=>post('resize',size));
window.familiarTerminalWrite=base64=>terminal.write(Uint8Array.from(atob(base64),c=>c.charCodeAt(0)));
new ResizeObserver(()=>fit.fit()).observe(document.getElementById('terminal'));
fit.fit(); post('ready',true);
