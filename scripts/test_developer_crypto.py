#!/usr/bin/env python3
"""Cross-check the Lua Ed25519/SHA-512 port against OpenSSL, using test-only keys.

Usage: python3 scripts/test_developer_crypto.py /path/to/lua
Requires openssl on PATH. Never reads the developer's real key.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qt-crypto-tests-') as directory:
    temp = Path(directory)
    cases = []
    for length in (1, 32, 64, 111, 112, 127, 128, 129, 255, 256, 1024):
        seed = hashlib.sha256(('QT TEST ONLY ' + str(length)).encode()).digest()
        key = temp / 'test.der'
        key.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + seed)
        public = subprocess.check_output(['openssl', 'pkey', '-inform', 'DER', '-in', str(key), '-pubout', '-outform', 'DER'])[-32:]
        message = bytes(i % 256 for i in range(length))
        (temp / 'message').write_bytes(message)
        signature = subprocess.check_output(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(key), '-in', str(temp / 'message')])
        cases.append([seed.hex(), public.hex(), message.hex(), signature.hex(), hashlib.sha512(message).hexdigest()])
    lua = '''QuestTogether={}
dofile(%s)
local E=QuestTogether.Ed25519
local function unhex(s) return (s:gsub("..",function(v)return string.char(tonumber(v,16))end)) end
local cases=%s
for index,c in ipairs(cases) do
    local seed,key,message,sig,hash=unhex(c[1]),unhex(c[2]),unhex(c[3]),unhex(c[4]),unhex(c[5])
    assert(E.Hash(message)==hash,"SHA-512 case "..index)
    assert(E.PublicKey(seed)==key,"public key case "..index)
    assert(E.Sign(seed,message)==sig,"sign case "..index)
    assert(E.Verify(key,message,sig),"verify case "..index)
    assert(not E.Verify(key,message.."x",sig),"tamper case "..index)
    for _,candidate in ipairs({message,message.."x"}) do
        local verifier,steps=E.NewVerification(key,candidate,sig),0
        while coroutine.status(verifier)~="dead" do
            local ok,value=coroutine.resume(verifier)
            assert(ok,value);steps=steps+1
            if coroutine.status(verifier)=="dead" then assert(value==(candidate==message),"incremental case "..index) end
        end
        assert(steps>100,"missing incremental checkpoints "..index)
    end
end
print("OpenSSL interoperability: "..#cases.." cases passed")
''' % (json.dumps(str(root / 'Libs/Ed25519/Ed25519.lua')), '{' + ','.join('{' + ','.join(json.dumps(s) for s in row) + '}' for row in cases) + '}')
    (temp / 'check.lua').write_text(lua)
    subprocess.run([sys.argv[1], str(temp / 'check.lua')], check=True)
