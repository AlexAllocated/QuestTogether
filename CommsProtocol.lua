-- Protocol generation 2. Only schemas declared here cross the native boundary.
-- This is a bounded record codec, not an arbitrary Lua table serializer.
local QT = _G.QuestTogether
local MAX_OBJECT, MAX_FIELDS, MAX_PARTS = 131072, 64, 1024
local catalog = {}
local function Field(name, kind, limit, required)
	return { name = name, kind = kind or "string", limit = limit, required = required }
end
local function Add(op, semantic, priority, fields, options)
	local spec = options or {}
	spec.operation, spec.semantic, spec.priority, spec.fields = op, semantic, priority, fields
	spec.maxBytes = spec.maxBytes or (semantic == "response" and MAX_OBJECT or 4096)
	spec.lifetime = spec.lifetime or (semantic == "event" and 15 or 30)
	catalog[op] = spec
end
local function Extend(fields, more)
	for _, field in ipairs(more) do
		fields[#fields + 1] = field
	end
	return fields
end
local S, N, B = "string", "number", "boolean"
local function F(name, kind, limit, required)
	return Field(name, kind, limit, required)
end

Add(
	"ANN",
	"event",
	"event",
	Extend({
		F("eventType", S, 1024),
		F("senderGUID", S, 1024),
		F("classFile", S, 1024),
		F("senderName", S, 120),
		F("text", S, 1024),
		F("questId", S, 1024),
		F("iconAsset", S, 1024),
		F("iconKind", S, 1024),
		F("zoneName", S, 1024),
		F("coordX", S, 1024),
		F("coordY", S, 1024),
		F("warMode", S, 1024),
		F("emoteToken", S, 1024),
		F("eventFacts", S, 1024),
		F("mapID", S, 1024),
		F("eventId", S, 1024),
	}, { F("occurredAt", N) })
)
Add("LVL", "event", "event", catalog.ANN.fields)
Add("HELLO", "event", "background", { F("version", S, 40) }, { globalOnly = true, maxBytes = 128 })
Add("DEVANN", "event", "control", {
	F("requestId", S, 64, true),
	F("issuedAt", N, nil, true),
	F("targetName", S, 120),
	F("active", B, nil, true),
	F("subscriptionSession", S, 64, true),
	F("signature", S, 128, true),
}, { globalOnly = true, authenticatedEvent = true, maxBytes = 512, lifetime = 30 })
Add("QTPR", "state", "active", { F("active", B, nil, true) })
Add("QTVR", "state", "active", { F("version", S, 40, true), F("count", N), F("partySize", N) })
Add("QTLF", "state", "active", { F("session", S, 64), F("sequence", N), F("looking", B, nil, true) })
Add("QTLQ", "state", "active", { F("session", S, 64), F("sequence", N), F("questID", N), F("title", S, 1024) })
Add(
	"QTPG",
	"state",
	"active",
	{ F("size", N, nil, true), F("leader", S, 120), F("leaderClass", S, 20), F("revision", S, 64) }
)
Add("QJST", "state", "active", { F("session", S, 64), F("sequence", N), F("grouped", S, 1), F("invite", B) })
Add("LOC", "state", "active", {
	F("session", S, 64),
	F("sequence", N),
	F("mask", N, nil, true),
	F("mapID", N),
	F("x", N),
	F("y", N),
	F("classFile", S, 20),
	F("className", S, 96),
	F("race", S, 96),
	F("faction", S, 16),
	F("level", N),
	F("warMode", B),
})
-- Private diagnostic coordinates have a dedicated route and cannot be folded
-- into ordinary presence, detail or departure snapshots.
Add("DLOC", "state", "background", {
	F("subscriptionSession", S, 64, true),
	F("subscriptionId", S, 64, true),
	F("locationShared", B, nil, true),
	F("location", "LOC", nil, true),
}, { privateOnly = true, maxBytes = 1024, lifetime = 30 })
Add("QTCI", "state", "active", { F("streams", B), F("raceID", N), F("direct", B) })
Add(
	"QTHI",
	"state",
	"active",
	{ F("race", S, 96), F("className", S, 96), F("classFile", S, 20), F("level", N), F("faction", S, 16) }
)
Add("QTN2", "state", "control", {
	F("session", S, 64),
	F("sequence", N),
	F("questID", N),
	F("mapID", N),
	F("x", N),
	F("y", N),
	F("hello", B),
	F("following", S, 120),
	F("title", S, 1024),
}, { groupOnly = true })
Add("STATE", "state", "active", { F("records", "topics", 16, true) }, { maxBytes = 8192 })
Add("QTDQ", "event", "control", { F("zone", N, nil, true) }, { regionalOnly = true, maxBytes = 64 })
Add("BYE", "state", "control", { F("reason", S, 24), F("records", "topics", 16) }, { maxBytes = 1024 })

local requestFields = {
	F("requestId", S, 80, true),
	F("targetName", S, 120),
	F("objectiveQuestId", N),
	F("knownRevision", S, 64),
	F("partyOnly", B),
	F("historyQuestIds", "QCID[]", 32),
}
Add("QCMP", "request", "control", requestFields, { responses = { QCRS = true }, lifetime = 180 })
Add("QCID", "record", "bulk", { F("questId", N, nil, true) })
Add("QCHS", "record", "bulk", { F("questId", N, nil, true), F("status", S, 16, true), F("sampledAt", N) })
Add("QCENTRY", "record", "bulk", {
	F("questId", N, nil, true),
	F("questTitle", S, 1024),
	F("isComplete", B),
	F("isPushable", B),
	F("objectiveCount", N),
	F("classFile", S, 20),
	F("objectives", "QCOB[]", 20),
})
Add("QCOB", "record", "bulk", {
	F("questId", N),
	F("objectiveIndex", N),
	F("text", S, 2048),
	F("kind", S, 32),
	F("finished", B),
	F("current", N),
	F("required", N),
})
Add("QCRS", "response", "bulk", {
	F("requestId", S, 80, true),
	F("snapshotId", S, 64, true),
	F("revision", S, 64),
	F("unchanged", B),
	F("classFile", S, 20),
	F("entries", "QCENTRY[]", 100),
	F("objectiveQuestId", N),
	F("count", N),
	F("supportsQuestHistory", B),
	F("historyStates", "QCHS[]", 32),
}, {})
Add(
	"QPGR",
	"request",
	"control",
	{ F("requestId", S, 80, true), F("targetName", S, 120), F("revision", S, 64) },
	{ responses = { QPGM = true } }
)
Add("MEMBER", "record", "bulk", { F("name", S, 120, true), F("classFile", S, 20) })
Add("QPGM", "response", "bulk", { F("requestId", S, 80, true), F("revision", S, 64), F("members", "MEMBER[]", 40) })
Add("QTHQ", "request", "control", { F("requestId", S, 80) }, { responses = { QTHD = true }, lifetime = 15 })
Add("QTHD", "response", "control", { F("requestId", S, 80), F("records", "topics", 16) }, { maxBytes = 16384 })
Add("ERROR", "response", "control", {
	F("requestId", S, 80, true),
	F("operation", S, 16, true),
	F("code", S, 32, true),
	F("detail", S, 128),
}, { maxBytes = 512 })
Add("PHGUID", "record", "background", { F("guid", S, 48, true) })
Add("QTPH", "request", "control", {
	F("requestId", S, 80, true),
	F("kind", S, 16),
	F("mapID", N),
	F("routingKey", S, 32),
	F("guid", S, 48),
	F("players", "PHGUID[]", 8),
}, { responses = { QTPH = true } })
Add(
	"QJON",
	"request",
	"control",
	{ F("requestId", S, 80, true), F("targetName", S, 120), F("status", S, 24), F("leader", S, 120) },
	{ responses = { QJON = true } }
)
Add(
	"QSHR",
	"request",
	"control",
	{ F("requestId", S, 80, true), F("targetName", S, 120), F("questID", N), F("status", S, 32), F("reasonCode", S, 24) },
	{ groupOnly = true, responses = { QSHR = true } }
)
Add("QTSR", "stream", "control", { F("token", S, 80, true) }, { lifetime = 12 })
Add(
	"QTSP",
	"stream",
	"active",
	{ F("token", S, 80, true), F("sequence", N), F("stamp", N), F("mapID", N), F("x", N), F("y", N), F("duration", N) },
	{ maxBytes = 256, lifetime = 2 }
)
Add("QTSX", "stream", "control", { F("token", S, 80, true) }, { maxBytes = 128 })
Add("PING", "request", "control", {
	F("requestId", S, 80, true),
	F("targetName", S, 120),
	F("issuedAt", N),
	F("debugRequest", B),
	F("developerRequest", B),
	F("signature", S, 128),
}, { responses = { PONG = true, DREPORT = true }, lifetime = 300, maxBytes = 1024 })
Add(
	"PONG",
	"response",
	"control",
	Extend({
		F("requestId", S, 80, true),
		F("senderName", S, 120),
		F("realmName", S, 256),
		F("raceName", S, 256),
		F("classFile", S, 256),
		F("className", S, 256),
		F("level", S, 256),
		F("zoneName", S, 256),
		F("coordX", S, 256),
		F("coordY", S, 256),
		F("warMode", S, 256),
		F("mapID", S, 256),
		F("addonVersion", S, 256),
		F("faction", S, 256),
	}, {
		F("developer", B),
		F("locationShared", B),
		F("lookingForQuestPartners", B),
		F("sampledAt", N),
		F("party", "QTPG"),
	}),
	{ maxBytes = 16384 }
)
Add(
	"DREPORT",
	"response",
	"bulk",
	{ F("requestId", S, 80, true), F("diagnosticText", S, 98304, true) },
	{ maxBytes = MAX_OBJECT }
)
for _, op in ipairs({ "FXEND", "FXACK", "FXSTAT", "FXMISS" }) do
	Add(
		op,
		"transfer",
		"control",
		{ F("session", S, 64, true), F("messageId", S, 64, true), F("parts", S, 4096), F("status", S, 16) },
		{ maxBytes = 8192 }
	)
end

local function Accessible(a, value)
	return not a.CanAccessValue or a:CanAccessValue(value)
end
local function Cell(text)
	return #text .. ":" .. text
end
local function ReadCell(text, at, limit)
	local colon = text:find(":", at, true)
	if not colon or colon - at > 6 then
		return nil
	end
	local token = text:sub(at, colon - 1)
	if token == "" or token:find("[^0-9]") then
		return nil
	end
	local length = tonumber(token)
	if length > limit or colon + length > #text then
		return nil
	end
	return text:sub(colon + 1, colon + length), colon + length + 1
end
local Encode, Decode
local function ValueEncode(a, field, value, depth)
	if not Accessible(a, value) then
		return nil
	end
	local kind = field.kind
	if kind == S then
		if type(value) ~= "string" and type(value) ~= "number" then
			return nil
		end
		local text = tostring(value)
		if #text > (field.limit or 256) or text:find("\0", 1, true) then
			return nil
		end
		return text
	elseif kind == N then
		local n = type(value) == "number" and value or (type(value) == "string" and tonumber(value))
		if not n or n ~= n or math.abs(n) > 1e12 then
			return nil
		end
		return string.format("%.12g", n)
	elseif kind == B then
		if type(value) ~= "boolean" then
			return nil
		end
		return value and "1" or "0"
	end
	if type(value) ~= "table" or (a.CanAccessTable and not a:CanAccessTable(value)) or depth >= 4 then
		return nil
	end
	local child = kind:match("^(%w+)%[%]$")
	if child or kind == "topics" then
		if #value > (field.limit or 100) then
			return nil
		end
		local chunks, topics = {}, {}
		for i, row in ipairs(value) do
			local body
			if kind == "topics" then
				if
					type(row) ~= "table"
					or not Accessible(a, row)
					or (a.CanAccessTable and not a:CanAccessTable(row))
					or not Accessible(a, row.topic)
					or type(row.topic) ~= "string"
					or not catalog[row.topic]
					or catalog[row.topic].semantic ~= "state"
					or catalog[row.topic].privateOnly
					or row.topic == "STATE"
					or row.topic == "BYE"
					or topics[row.topic]
				then
					return nil
				end
				topics[row.topic] = true
				local stamp, revision = row.sampledAt or 0, row.revision
				if
					not Accessible(a, stamp)
					or type(stamp) ~= "number"
					or stamp ~= stamp
					or stamp < 0
					or stamp > 1e12
					or (
						revision ~= nil
						and (
							not Accessible(a, revision)
							or type(revision) ~= "number"
							or revision < 1
							or revision > 1e12
							or revision % 1 ~= 0
						)
					)
				then
					return nil
				end
				local data = Encode(a, row.topic, row.data, depth + 1)
				if not data then
					return nil
				end
				body = Cell(row.topic)
					.. Cell(tostring(stamp))
					.. Cell(revision and tostring(revision) or "")
					.. Cell(data)
			else
				body = Encode(a, child, row, depth + 1)
			end
			if not body then
				return nil
			end
			chunks[i] = Cell(body)
		end
		return table.concat(chunks)
	end
	return Encode(a, kind, value, depth + 1)
end
local function ValueDecode(a, field, text, depth)
	if field.kind == S then
		if #text > (field.limit or 256) then
			return nil
		end
		return text
	end
	if field.kind == N then
		local n = tonumber(text)
		if not n or n ~= n or math.abs(n) > 1e12 then
			return nil
		end
		return n
	end
	if field.kind == B then
		if text == "1" then
			return true
		elseif text == "0" then
			return false
		end
		return nil
	end
	if depth >= 4 then
		return nil
	end
	local child = field.kind:match("^(%w+)%[%]$")
	if child or field.kind == "topics" then
		local rows, topics, at = {}, {}, 1
		while at <= #text do
			if #rows >= (field.limit or 100) then
				return nil
			end
			local body, nextAt = ReadCell(text, at, MAX_OBJECT)
			if not body then
				return nil
			end
			local row
			if field.kind == "topics" then
				local topic, p = ReadCell(body, 1, 16)
				if
					not topic
					or not catalog[topic]
					or catalog[topic].semantic ~= "state"
					or catalog[topic].privateOnly
					or topic == "STATE"
					or topic == "BYE"
					or topics[topic]
				then
					return nil
				end
				local stamp, q = ReadCell(body, p, 16)
				topics[topic] = true
				local revision, r
				if q then
					revision, r = ReadCell(body, q, 16)
				end
				local revisionNumber = revision ~= "" and tonumber(revision) or nil
				if
					revision == nil
					or (
						revision ~= ""
						and (
							not revisionNumber
							or revisionNumber < 1
							or revisionNumber > 1e12
							or revisionNumber % 1 ~= 0
						)
					)
				then
					return nil
				end
				local payload, finish
				if r then
					payload, finish = ReadCell(body, r, 8192)
				end
				local numeric = stamp and tonumber(stamp)
				if
					not numeric
					or numeric ~= numeric
					or numeric < 0
					or numeric > 1e12
					or not payload
					or finish ~= #body + 1
				then
					return nil
				end
				local data = Decode(a, topic, payload, depth + 1)
				if not data then
					return nil
				end
				row = { topic = topic, data = data, sampledAt = numeric, revision = revisionNumber }
			else
				row = Decode(a, child, body, depth + 1)
			end
			if not row then
				return nil
			end
			rows[#rows + 1], at = row, nextAt
		end
		return rows
	end
	return Decode(a, field.kind, text, depth + 1)
end
Encode = function(a, operation, record, depth)
	local spec = catalog[operation]
	if
		not spec
		or not Accessible(a, record)
		or type(record) ~= "table"
		or (a.CanAccessTable and not a:CanAccessTable(record))
	then
		return nil, "invalid"
	end
	local parts, total = {}, 0
	for id, field in ipairs(spec.fields) do
		local value = record[field.name]
		if value ~= nil then
			local encoded = ValueEncode(a, field, value, depth or 0)
			if encoded == nil then
				return nil, "invalid:" .. field.name
			end
			local part = id .. "=" .. Cell(encoded)
			total = total + #part
			if total > spec.maxBytes then
				return nil, "oversize"
			end
			parts[#parts + 1] = part
		elseif field.required then
			return nil, "missing:" .. field.name
		end
	end
	return table.concat(parts)
end
Decode = function(a, operation, payload, depth)
	local spec = catalog[operation]
	if
		not spec
		or not Accessible(a, payload)
		or type(payload) ~= "string"
		or #payload > spec.maxBytes
		or payload:find("\0", 1, true)
	then
		return nil
	end
	local result, seen, at, count = {}, {}, 1, 0
	while at <= #payload do
		count = count + 1
		if count > MAX_FIELDS then
			return nil
		end
		local equals = payload:find("=", at, true)
		if not equals or equals - at > 3 then
			return nil
		end
		local token = payload:sub(at, equals - 1)
		local id = not token:find("[^0-9]") and tonumber(token)
		if not id or id < 1 or id > 255 or seen[id] then
			return nil
		end
		seen[id] = true
		local text, nextAt = ReadCell(payload, equals + 1, spec.maxBytes)
		if not text then
			return nil
		end
		local field = spec.fields[id]
		if field then
			local value = ValueDecode(a, field, text, depth or 0)
			if value == nil then
				return nil
			end
			result[field.name] = value
		end
		at = nextAt
	end
	for _, field in ipairs(spec.fields) do
		if field.required and result[field.name] == nil then
			return nil
		end
	end
	return result
end
function QT:GetCommOperation(operation)
	return catalog[operation]
end
function QT:IsCommResponseRecord(operation, record)
	local spec = catalog[operation]
	return spec
			and (spec.semantic == "response" or ((operation == "QJON" or operation == "QSHR") and record.status ~= nil and record.status ~= "request") or (operation == "QTPH" and record.kind == "R"))
		or false
end
function QT:EncodeCommRecord(operation, record)
	return Encode(self, operation, record, 0)
end
function QT:DecodeCommRecord(operation, payload)
	return Decode(self, operation, payload, 0)
end
function QT:CopyCommRecord(operation, record)
	local payload, reason = Encode(self, operation, record, 0)
	return payload and Decode(self, operation, payload, 0) or nil, reason, payload
end

function QT:EncodeCommFrame(frame, body)
	local header = table.concat({
		"2",
		frame.operation,
		frame.session,
		frame.messageId,
		frame.requestId or "",
		frame.part or 1,
		frame.total or 1,
		frame.stamp or 0,
	}, "|") .. "|"
	local wire = header .. (body or "")
	if #wire > 255 or wire:find("\0", 1, true) then
		return nil, "oversize"
	end
	return wire
end
function QT:DecodeCommFrame(wire)
	if not Accessible(self, wire) or type(wire) ~= "string" or #wire > 255 or wire:find("\0", 1, true) then
		return nil
	end
	local version, op, session, id, request, part, total, stamp, body =
		wire:match("^(%d+)|(%w+)|([^|]+)|([^|]+)|([^|]*)|(%d+)|(%d+)|(%d+)|(.*)$")
	if
		version ~= "2"
		or not catalog[op]
		or catalog[op].semantic == "record"
		or #session > 64
		or #id > 64
		or #request > 80
		or session:find("[^%w%-]")
		or id:find("[^%w%-]")
		or request:find("[^%w%-]")
	then
		return nil
	end
	part, total, stamp = tonumber(part), tonumber(total), tonumber(stamp)
	if part < 1 or total < part or total > MAX_PARTS or stamp > 1e12 then
		return nil
	end
	return {
		operation = op,
		session = session,
		messageId = id,
		requestId = request ~= "" and request or nil,
		part = part,
		total = total,
		stamp = stamp,
	},
		body
end
function QT:BuildCommFrames(operation, record, context)
	local payload, reason = self:EncodeCommRecord(operation, record)
	if not payload then
		return nil, reason
	end
	local frame = {
		operation = operation,
		session = context.session,
		messageId = context.messageId,
		requestId = context.requestId,
		stamp = context.stamp,
		total = MAX_PARTS,
		part = MAX_PARTS,
	}
	local header = self:EncodeCommFrame(frame, "")
	if not header then
		return nil, "oversize"
	end
	local capacity = 255 - #header
	if capacity < 1 then
		return nil, "oversize"
	end
	local total = math.max(1, math.ceil(#payload / capacity))
	if total > MAX_PARTS then
		return nil, "oversize"
	end
	local frames = {}
	frame.total = total
	for part = 1, total do
		frame.part = part
		frames[part] = self:EncodeCommFrame(frame, payload:sub((part - 1) * capacity + 1, part * capacity))
	end
	return frames, nil, payload
end
