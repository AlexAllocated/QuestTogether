-- Peer-wide transitions are explicit. Domain owners retain their own caches and
-- decide which tombstones/intents survive a departure; rendering owns no teardown.
local QT = _G.QuestTogether
local retirement = {
	"RetirePartyNavigationPeer",
	"RetirePlayerLocationPeer",
	"RetireDeveloperLocationPeer",
	"RetirePlayerPhasePeer",
	"RetirePlayerDetailsPeer",
	"ForgetPartyVisualPeer",
	"RetireNearbyStreamPeer",
	"ForgetPartyJoinPeer",
}
function QT:RetirePeerServices(name, reason)
	for _, method in ipairs(retirement) do
		if self[method] then
			self[method](self, name, reason)
		end
	end
end
