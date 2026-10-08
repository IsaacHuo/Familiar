#!/usr/bin/env python3
"""Vendor pinned MIT terminal assets; never run package lifecycle scripts."""
import base64, hashlib, io, json, tarfile, urllib.request
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'Familiar/Resources/FamiliarTerminalRenderer'
packages = [
 ('@xterm/xterm', '6.0.0', 'sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg==', {'lib/xterm.js':'xterm.js', 'css/xterm.css':'xterm.css'}),
 ('@xterm/addon-fit', '0.11.0', 'sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g==', {'lib/addon-fit.js':'addon-fit.js'}),
 ('@xterm/addon-unicode11', '0.9.0', 'sha512-FxDnYcyuXhNl+XSqGZL/t0U9eiNb/q3EWT5rYkQT/zuig8Gz/VagnQANKHdDWFM2lTMk9ly0EFQxxxtZUoRetw==', {'lib/addon-unicode11.js':'addon-unicode11.js'}),
]
root.mkdir(parents=True, exist_ok=True)
manifest = []
for name, version, integrity, files in packages:
 with urllib.request.urlopen('https://registry.npmjs.org/' + name + '/' + version, timeout=20) as response:
  metadata = json.load(response)
 assert metadata['version'] == version and metadata['license'] == 'MIT'
 assert metadata['dist']['integrity'] == integrity
 with urllib.request.urlopen(metadata['dist']['tarball'], timeout=30) as response: archive = response.read()
 assert 'sha512-' + base64.b64encode(hashlib.sha512(archive).digest()).decode() == integrity
 with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as package:
  hashes = {}
  for source, destination in {**files, 'LICENSE': name.split('/')[-1] + '-LICENSE.txt'}.items():
   member = package.getmember('package/' + source)
   assert member.isfile()
   data = package.extractfile(member).read()
   (root / destination).write_bytes(data)
   hashes[destination] = hashlib.sha256(data).hexdigest()
 manifest.append({'name':name,'version':version,'license':'MIT','url':metadata['dist']['tarball'],'integrity':integrity,'sha256':hashes})
(root / 'vendor-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Verified pinned terminal packages:', ', '.join(name + '@' + version for name, version, *_ in packages))
