"""Real issuer -> Lua activation -> signed peer proof, with disposable keys only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from issuer import Issuer

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.environ.get("QT_TEST_LUA"), "set QT_TEST_LUA for Lua interoperability")
class AddonInteropTests(unittest.TestCase):
    def test_issuer_activation_and_sender_bound_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            issuer = Issuer(Path(directory) / "issuer", "111111111111111111", initialize=True)
            issuer.grant("111111111111111111", "222222222222222222")
            claim = "QTCLAIM1." + "a" * 32
            activation = issuer.claim("222222222222222222", claim)
            # Written only inside the disposable test directory, never printed.
            values = "\n".join("local " + k + "=" + json.dumps(v) for k, v in {
                "root": str(ROOT), "issuerPublic": issuer.public_hex, "claim": claim, "activation": activation,
            }.items())
            script = values + r'''
QuestTogether={Translate=function(s)return s end}
local QT=QuestTogether
dofile(root.."/Libs/Ed25519/Ed25519.lua")
dofile(root.."/PeerState.lua")
dofile(root.."/VIPIdentity.lua")
local function Peer(name)
    local a=setmetatable({name=name,now=100,isEnabled=true,vipStore={claim=claim},
        vipIssuerPublicKeyHex=issuerPublic,sent={}}, {__index=QT})
    a.API={GetTime=function()return a.now end}
    function a:SafeToNumber(v)return tonumber(v)end
    function a:NormalizeMemberName(n)return n end
    function a:IsIgnoredPlayerName(n)return self.ignored==n end
    function a:IsSelfSender(n)return n==self.name end
    function a:InitializeCommunications()
        self.communicationState=self.communicationState or {session="session-"..name}
        return self.communicationState
    end
    function a:GetPlayerFullName()return self.name end
    function a:GetAnnouncementServerTime()return 1800000000+math.floor(self.now)end
    function a:CancelCommunicationOwner()end
    function a:Emit(op,data,routes,options)
        assert(op=="VIP")
        assert(data.seed==nil and data.claim==nil)
        self.sent[#self.sent+1]=data
        self.lastOptions=options
        return true
    end
    return a
end
local function Pump(a,done)
    for i=1,2000 do
        a:UpdateVIPIdentity()
        if done()then return i end
    end
    error("incremental crypto did not complete")
end
local source=Peer("VIP-Realm")
assert(source:ImportVIPActivation(activation))
assert(not source:IsVerifiedVIP(source.name),"import is asynchronous")
local steps=Pump(source,function()return #source.sent>0 end)
assert(steps>10,"crypto must yield across frames")
assert(source:IsVerifiedVIP(source.name))
assert(source.vipStore.seed and source.vipStore.certificate)
local proof=source.sent[1]
local savedSeed=source.vipStore.seed
assert(not source:ImportVIPActivation(activation:gsub("a", "b", 1)))
assert(source.vipStore.seed==savedSeed,"bad claims must preserve installed identity")
-- Correct certificate but wrong private seed must fail.
local wrongSeed=activation:sub(1,43)..string.rep("0",64)..activation:sub(108)
assert(source:ImportVIPActivation(wrongSeed))
Pump(source,function()return not source.vipState.localJob end)
assert(source.vipStore.seed==savedSeed)
local function Receive(a,data,sender,stamp)
    return a:HandleVIPIdentity(data,sender or source.name,{session=data.session,stamp=stamp or data.issuedAt})
end
local receiver=Peer("Observer-Realm")
assert(Receive(receiver,proof,nil,999999999999))
assert(not receiver:IsVerifiedVIP(source.name))
Pump(receiver,function()return #receiver.vipState.jobs==0 end)
assert(receiver:IsVerifiedVIP(source.name))
assert(receiver.peerSnapshotState.peers[source.name].epoch.stamp==proof.issuedAt,
    "unsigned envelope timestamp must not establish epoch ordering")
assert(not Receive(receiver,proof),"duplicates rejected")
for _,altered in ipairs({"sender","session","active","certificate","signature"})do
    local a=Peer("Observer-Realm")
    local data={}
    for k,v in pairs(proof)do data[k]=v end
    local sender=source.name
    if altered=="sender"then sender="Impostor-Realm"
    elseif altered=="session"then data.session="another-session"
    elseif altered=="active"then data.active=false
    elseif altered=="certificate"then data.certificate=data.certificate:sub(1,-2)..(data.certificate:sub(-1)=="0"and"1"or"0")
    else data.signature=string.rep("0",128)end
    assert(Receive(a,data,sender))
    Pump(a,function()return #a.vipState.jobs==0 end)
    assert(not a:IsVerifiedVIP(sender),altered.." must fail real crypto")
end
for _,boundary in ipairs({"retire","ignore","disable","reset","epoch","expire"})do
    local a=Peer("Observer-Realm")
    assert(Receive(a,proof))
    if boundary=="retire"then a:RetireVIPPeer(source.name)
    elseif boundary=="ignore"then a.ignored=source.name
    elseif boundary=="disable"then a.isEnabled=false
    elseif boundary=="reset"then a:ResetVIPIdentity()
    elseif boundary=="epoch"then a:RecordPeerEpoch(source.name,"replacement",proof.issuedAt+1)
    else a.now=a.now+300 end
    for _=1,700 do a:UpdateVIPIdentity()end
    assert(not a:IsVerifiedVIP(source.name),boundary.." must not revive an old badge")
end
-- A new character reads the same account-wide activation, not a profile copy.
local alt=Peer("Alt-Realm")
alt.vipStore=source.vipStore
Pump(alt,function()return alt:IsVerifiedVIP(alt.name)end)
source.now=source.now+13
receiver.now=receiver.now+13
source:SetVIPDisplayEnabled(false)
Pump(source,function()return #source.sent==2 end)
assert(not source:IsVerifiedVIP(source.name))
assert(Receive(receiver,source.sent[2]))
Pump(receiver,function()return #receiver.vipState.jobs==0 end)
assert(not receiver:IsVerifiedVIP(source.name),"signed withdrawal hides cosmetic")
assert(not Receive(receiver,proof),"older proof cannot undo withdrawal")
assert(source.lastOptions.isCurrent())
source:ResetVIPIdentity()
assert(not source.lastOptions.isCurrent(),"queued proof cannot outlive reset")
print("VIP issuer-to-addon activation, signatures, lifecycle and withdrawal passed")
'''
            path = Path(directory) / "check.lua"
            path.write_text(script)
            result = subprocess.run([os.environ["QT_TEST_LUA"], str(path)], text=True, capture_output=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            issuer.close()
