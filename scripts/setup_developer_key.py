#!/usr/bin/env python3
"""Provision the private QT companion once; never print or package its seed."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
private = ROOT / '.local/addons/QuestTogetherDev'
private.mkdir(parents=True, exist_ok=True)
key = private / 'developer-ed25519.pem'
if not key.exists():
    previous = os.umask(0o077)
    try:
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(key)], check=True)
    finally:
        os.umask(previous)
der = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-outform', 'DER'])
public = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'])
assert der.startswith(bytes.fromhex('302e020100300506032b657004220420')) and len(der) == 48
assert public.startswith(bytes.fromhex('302a300506032b6570032100')) and len(public) == 44
seed = ''.join('\\%03d' % b for b in der[-32:])
script = private / 'DeveloperKey.lua'
script.write_text('''-- PRIVATE. Never package this file or its seed.
local QT = _G.QuestTogether
local seed = "%s"
function QT:SignDeveloperRequest(message)
    return self.Ed25519.Sign(seed, message)
end
''' % seed)
script.chmod(0o600)
toc = private / 'QuestTogetherDev.toc'
if 'DeveloperKey.lua' not in toc.read_text():
    toc.write_text(toc.read_text().rstrip() + '\nDeveloperKey.lua\n')
(ROOT / 'DeveloperPublicKey.lua').write_text('-- Public verification key only. Private seed lives in the unshipped QuestTogetherDev companion.\n'
    '_G.QuestTogether.developerPublicKeyHex = "' + public[-32:].hex() + '"\n')
print('Developer key provisioned. Only DeveloperPublicKey.lua belongs in the release.')
