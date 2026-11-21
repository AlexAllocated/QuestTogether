-- SPDX-License-Identifier: GPL-3.0-only
local QuestTogether = _G.QuestTogether
local Access = QuestTogether.NativeAccess
local CanAccessForeignValue, CanAccessForeignTable = Access.Value, Access.Table
local Values = QuestTogether.NativeQuestValues
local ReadOptionalString = Values.ReadOptionalString

-- A receipt survives ordinary retry/lifecycle resets. Revalidate the exact native
-- transaction before another swap, including when its channel order looks fixed.
local nativeChatChannelRecovery, nativeChatChannelRecoveryRunning
local function CheckChatChannelOrderRecovery()
	if not nativeChatChannelRecovery then
		return true, "none"
	end
	if nativeChatChannelRecoveryRunning then
		return false, "pending", "recovery_pending"
	end
	nativeChatChannelRecoveryRunning = true
	local ok, resolved, reason, stage = pcall(nativeChatChannelRecovery)
	nativeChatChannelRecoveryRunning = nil
	if not ok then
		return false, "pending", "recovery_validation"
	end
	if resolved then
		nativeChatChannelRecovery = nil
	end
	return resolved, reason, stage
end

-- Preserve native channel identity as one guarded swap. Blizzard owns the full
-- ChatTypeInfo exchange; QT never assigns its entries or rewrites RGB colors.
local function SwapChatChannelsPreservingState(firstName, secondName)
	if nativeChatChannelRecovery then
		return false, "pending", "recovery_pending"
	end
	local dispatched = false
	local stage = "arguments"
	local function Run()
		local function Accessible(value)
			return CanAccessForeignValue(value)
		end
		local function Name(value)
			return Accessible(value)
				and type(value) == "string"
				and #value > 0
				and #value <= 256
				and not value:find("[%c|]")
		end
		if not Name(firstName) or not Name(secondName) or firstName == secondName then
			return false, "invalid"
		end
		if QuestTogether.isRunningTests then
			return false, "restricted"
		end
		stage = "secure_dispatch"
		local securityCheck, dispatch = issecurevariable, securecallfunction
		if
			not Accessible(securityCheck)
			or type(securityCheck) ~= "function"
			or not Accessible(dispatch)
			or type(dispatch) ~= "function"
		then
			return false, "unavailable"
		end
		local function Secure(owner, key)
			if not Accessible(owner) or (type(owner) == "table" and not CanAccessForeignTable(owner)) then
				return nil
			end
			local ok, secure = pcall(securityCheck, owner, key)
			return ok and Accessible(secure) and secure == true
		end
		local function Trusted(owner, key)
			if not Secure(owner, key) then
				return nil
			end
			local ok, value = pcall(function()
				return owner[key]
			end)
			return ok and Accessible(value) and type(value) == "function" and value or nil
		end
		local function DispatchTrusted()
			return Trusted(_G, "securecallfunction") == dispatch and Trusted(_G, "issecurevariable") == securityCheck
		end
		if not DispatchTrusted() then
			return false, "unavailable"
		end
		local function Call(func, ...)
			if not func then
				return false
			end
			-- Pass the actual trusted native function, never an addon closure.
			return pcall(dispatch, func, ...)
		end
		local function Restricted()
			local ok, locked = Call(Trusted(_G, "InCombatLockdown"))
			return not ok
				or not Accessible(locked)
				or (locked ~= false and locked ~= nil)
				or not QuestTogether.isEnabled
				or QuestTogether.isLoggingOut
				or QuestTogether.isRunningTests
				or QuestTogether:IsRuntimeRestricted()
				or QuestTogether:IsRuntimeRestrictionTypeActive("chat")
				or QuestTogether:IsWorkBlocked("foreign_frame_mutation")
		end
		stage = "restrictions"
		if Restricted() then
			return false, "restricted"
		end
		stage = "native_helpers"
		local getChannel = Trusted(_G, "GetChannelName")
		local swap = Trusted(_G, "ChatConfigChannelSettings_SwapChannelsByIndex")
		if
			not swap
			and Accessible(ChatConfigChannelSettings_SwapChannelsByIndex)
			and ChatConfigChannelSettings_SwapChannelsByIndex == nil
			and Secure(_G, "ChatConfigChannelSettings_SwapChannelsByIndex")
		then
			-- Loading the native addon does not open its UI. Never try to replace
			-- an existing, untrusted helper or fall back to a normal raw C swap.
			Call(Trusted(C_AddOns, "LoadAddOn") or Trusted(_G, "LoadAddOn"), "Blizzard_ChatFrame")
			swap = Trusted(_G, "ChatConfigChannelSettings_SwapChannelsByIndex")
		end
		local nativeSwap = Trusted(C_ChatInfo, "SwapChatChannelsByChannelIndex")
		if
			not getChannel
			or not swap
			or not nativeSwap
			or not CanAccessForeignTable(ChatTypeInfo)
			or not CanAccessForeignTable(CHAT_FRAMES)
		then
			return false, "unavailable"
		end
		if Restricted() then
			return false, "restricted"
		end
		local function Channel(value)
			local ok, id, name = Call(getChannel, value)
			if
				not ok
				or not Accessible(id)
				or type(id) ~= "number"
				or id < 1
				or id > 30
				or id ~= math.floor(id)
				or not Name(name)
			then
				return nil
			end
			return id, name
		end
		local function ChannelMatches(identity, expected)
			local id, canonical = Channel(identity.lookup)
			local numericID, numericName = Channel(expected)
			return id == expected
				and canonical == identity.name
				and numericID == expected
				and numericName == identity.name
		end
		local function ResolveChannel(value)
			local id, canonical = Channel(value)
			if not id then
				return nil
			end
			local numericID, numericName = Channel(id)
			if numericID ~= id or numericName ~= canonical then
				return nil
			end
			-- Display names and accepted lookup aliases differ on regional/zone
			-- channels. Prefer the canonical name, otherwise retain the verified
			-- original alias. Never pin a numeric string as a channel identity.
			local lookup = canonical
			local canonicalID, canonicalName = Channel(canonical)
			if canonicalID ~= id or canonicalName ~= canonical then
				lookup = value
			end
			if lookup:match("^%d+$") then
				return nil
			end
			local identity = { before = id, name = canonical, lookup = lookup }
			return ChannelMatches(identity, id) and identity or nil
		end
		stage = "channel_identity"
		local firstIdentity, secondIdentity = ResolveChannel(firstName), ResolveChannel(secondName)
		if not firstIdentity or not secondIdentity or firstIdentity.before == secondIdentity.before then
			return false, "invalid"
		end
		local first, second = firstIdentity.before, secondIdentity.before
		local firstKey, secondKey = "CHANNEL" .. first, "CHANNEL" .. second
		stage = "channel_metadata"
		if not Secure(ChatTypeInfo, firstKey) or not Secure(ChatTypeInfo, secondKey) then
			return false, "inaccessible"
		end
		local firstInfo, secondInfo = ChatTypeInfo[firstKey], ChatTypeInfo[secondKey]
		local function Snapshot(info)
			if not CanAccessForeignTable(info) then
				return nil
			end
			local copy, count = {}, 0
			for key, value in pairs(info) do
				if not Accessible(key) or not Accessible(value) then
					return nil
				end
				if type(key) ~= "string" and type(key) ~= "number" then
					return nil
				end
				local valueType = type(value)
				if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then
					return nil
				end
				if not Secure(info, key) then
					return nil
				end
				count = count + 1
				if count > 64 then
					return nil
				end
				copy[key] = value
			end
			return copy, count
		end
		local firstFields, firstCount = Snapshot(firstInfo)
		local secondFields, secondCount = Snapshot(secondInfo)
		if not firstFields or not secondFields or firstInfo == secondInfo then
			return false, "inaccessible"
		end
		local function SameInfo(info, fields, count, slot)
			local current, currentCount = Snapshot(info)
			if not current then
				return nil
			end
			if currentCount ~= count then
				return false
			end
			for key, value in pairs(fields) do
				if current[key] ~= value then
					-- Native chat refreshes may normalize the message type index
					-- to its new slot. Verify that value with the engine API.
					if key ~= "id" then
						return false
					end
					local ok, expected = Call(Trusted(_G, "GetChatTypeIndex"), slot)
					if not ok or not Accessible(expected) or type(expected) ~= "number" or current[key] ~= expected then
						return false
					end
				end
			end
			return true
		end
		local function InfoMatches(expectedFirst, expectedSecond)
			if
				not CanAccessForeignTable(ChatTypeInfo)
				or not Secure(ChatTypeInfo, firstKey)
				or not Secure(ChatTypeInfo, secondKey)
			then
				return nil
			end
			local currentFirst, currentSecond = ChatTypeInfo[firstKey], ChatTypeInfo[secondKey]
			if not CanAccessForeignTable(currentFirst) or not CanAccessForeignTable(currentSecond) then
				return nil
			end
			return currentFirst == expectedFirst and currentSecond == expectedSecond
		end
		local function Visible(frame)
			local ok, visible = Call(Trusted(frame, "IsVisible") or Trusted(frame, "IsShown"), frame)
			if not ok or not Accessible(visible) or type(visible) ~= "boolean" then
				return nil
			end
			return visible
		end
		local function ConfigurationReady()
			for _, frameName in ipairs({
				"ChatConfigFrame",
				"ChatConfigChannelSettingsLeft",
				"ChannelFrame",
				"ColorPickerFrame",
			}) do
				local frame = _G[frameName]
				if not Accessible(frame) then
					return false, "inaccessible"
				end
				if frame == nil then
					if frameName == "ChatConfigFrame" or frameName == "ChatConfigChannelSettingsLeft" then
						return false, "unavailable"
					end
				else
					if not QuestTogether:CanAccessForeignFrame(frame) then
						return false, "inaccessible"
					end
					local visible = Visible(frame)
					if visible == nil then
						return false, "inaccessible"
					end
					if visible and frameName ~= "ChatConfigChannelSettingsLeft" then
						return false, "busy"
					end
				end
			end
			return true
		end
		local function InputReady(box)
			if not QuestTogether:CanAccessForeignFrame(box) then
				return false, "inaccessible"
			end
			local focusedOK, focused = Call(Trusted(box, "HasFocus"), box)
			local lengthOK, length = Call(Trusted(box, "GetNumLetters"), box)
			if
				not focusedOK
				or not Accessible(focused)
				or type(focused) ~= "boolean"
				or not lengthOK
				or not Accessible(length)
				or type(length) ~= "number"
				or length < 0
				or length > 4096
				or length ~= math.floor(length)
			then
				return false, "inaccessible"
			end
			if focused then
				return false, "busy"
			end
			if length > 0 then
				local visible = Visible(box)
				if visible == nil then
					return false, "inaccessible"
				end
				if visible then
					return false, "busy"
				end
				-- An unparsed numeric slash command in a hidden draft would change
				-- meaning after a reorder. Classify transiently; never retain, log,
				-- clear or rewrite the player's text.
				local ok, draft = Call(Trusted(box, "GetText"), box)
				if not ok or not Accessible(draft) or type(draft) ~= "string" or #draft == 0 or #draft > 4096 then
					return false, "inaccessible"
				end
				if draft:find("^%s*/") then
					return false, "busy"
				end
			end
			return true
		end
		stage = "channel_configuration"
		local ready, reason = ConfigurationReady()
		if not ready then
			return false, reason
		end
		stage = "active_chat_input"
		if not Accessible(ACTIVE_CHAT_EDIT_BOX) then
			return false, "inaccessible"
		end
		local boxes, seen, frameCount = {}, {}, 0
		for _, frameName in pairs(CHAT_FRAMES) do
			stage = "chat_edit_boxes"
			frameCount = frameCount + 1
			if frameCount > 128 or not Name(frameName) then
				return false, "inaccessible"
			end
			local frame = _G[frameName]
			if not QuestTogether:CanAccessForeignFrame(frame) then
				return false, "inaccessible"
			end
			local box = frame.editBox
			if not Accessible(box) then
				return false, "inaccessible"
			end
			if box == nil then
				box = _G[frameName .. "EditBox"]
			end
			if not Accessible(box) then
				return false, "inaccessible"
			end
			if box ~= nil then
				if not QuestTogether:CanAccessForeignFrame(box) then
					return false, "inaccessible"
				end
				if not seen[box] then
					seen[box] = true
					boxes[#boxes + 1] = box
				end
			end
		end
		if frameCount == 0 then
			return false, "unavailable"
		end
		if ACTIVE_CHAT_EDIT_BOX ~= nil and not seen[ACTIVE_CHAT_EDIT_BOX] then
			seen[ACTIVE_CHAT_EDIT_BOX] = true
			boxes[#boxes + 1] = ACTIVE_CHAT_EDIT_BOX
		end
		local destinations = {}
		for _, box in ipairs(boxes) do
			stage = "chat_edit_box_state"
			ready, reason = InputReady(box)
			if not ready then
				return false, reason
			end
			stage = "chat_destination"
			local getAttribute, getTarget = Trusted(box, "GetAttribute"), Trusted(box, "GetChannelTarget")
			local ok, target = Call(getAttribute, box, "channelTarget")
			if not getTarget or not ok or not Accessible(target) then
				return false, "inaccessible"
			end
			if target ~= nil and target ~= 0 and target ~= "" then
				if type(target) ~= "number" and type(target) ~= "string" then
					return false, "inaccessible"
				end
				local id, name = Channel(target)
				local numericTarget = type(target) == "number" and target
					or (target:match("^%d+$") and tonumber(target))
				if (numericTarget == first or numericTarget == second) and id ~= numericTarget then
					return false, "inaccessible"
				end
				if id == first or id == second then
					local identity = id == first and firstIdentity or secondIdentity
					if name ~= identity.name then
						return false, "inaccessible"
					end
					local setter = Trusted(box, "SetChannelTarget")
					if not setter then
						return false, "unavailable"
					end
					destinations[#destinations + 1] = {
						box = box,
						identity = identity,
						before = id,
						after = id == first and second or first,
						getAttribute = getAttribute,
						getTarget = getTarget,
						setter = setter,
					}
				end
			end
		end
		local function DestinationMatches(destination, expected, requireName)
			local box, identity = destination.box, destination.identity
			if
				not QuestTogether:CanAccessForeignFrame(box)
				or Trusted(box, "GetAttribute") ~= destination.getAttribute
				or Trusted(box, "GetChannelTarget") ~= destination.getTarget
			then
				return nil
			end
			local ok, raw = Call(destination.getAttribute, box, "channelTarget")
			if not ok or not Accessible(raw) then
				return nil
			end
			if requireName and raw ~= identity.lookup then
				return false
			end
			local targetOK, target = Call(destination.getTarget, box)
			if not targetOK or not Accessible(target) then
				return nil
			end
			if target ~= expected then
				return false
			end
			local id, name = Channel(target)
			return id == expected and name == identity.name
		end
		stage = "destination_preparation"
		for _, destination in ipairs(destinations) do
			local ok = Call(destination.setter, destination.box, destination.identity.lookup)
			if not ok or not DestinationMatches(destination, destination.before, true) then
				return false, "prepare"
			end
		end
		if Restricted() then
			return false, "restricted"
		end
		if
			not ChannelMatches(firstIdentity, first)
			or not ChannelMatches(secondIdentity, second)
			or not InfoMatches(firstInfo, secondInfo)
			or not SameInfo(firstInfo, firstFields, firstCount, firstKey)
			or not SameInfo(secondInfo, secondFields, secondCount, secondKey)
		then
			return false, "prepare"
		end
		for _, destination in ipairs(destinations) do
			if not DestinationMatches(destination, destination.before, true) then
				return false, "prepare"
			end
		end
		local function Validate(allowCompletion)
			local validationStage = allowCompletion and "recovery_validation" or "result_validation"
			if not DispatchTrusted() or Trusted(_G, "GetChannelName") ~= getChannel then
				return false, "pending", validationStage
			end
			local before = ChannelMatches(firstIdentity, first) and ChannelMatches(secondIdentity, second)
			local after = ChannelMatches(firstIdentity, second) and ChannelMatches(secondIdentity, first)
			local metadataBefore, metadataAfter = InfoMatches(firstInfo, secondInfo), InfoMatches(secondInfo, firstInfo)
			local fieldsFirst = SameInfo(firstInfo, firstFields, firstCount, metadataAfter and secondKey or firstKey)
			local fieldsSecond =
				SameInfo(secondInfo, secondFields, secondCount, metadataAfter and firstKey or secondKey)
			if metadataBefore == nil or metadataAfter == nil or fieldsFirst == nil or fieldsSecond == nil then
				return false, "pending", validationStage
			end
			if not fieldsFirst or not fieldsSecond then
				return false, "inconsistent", validationStage
			end
			if not before and not after then
				return false, "pending", validationStage
			end
			for _, destination in ipairs(destinations) do
				local matches =
					DestinationMatches(destination, after and destination.after or destination.before, false)
				if matches == nil then
					return false, "pending", validationStage
				end
				if not matches then
					return false, "inconsistent", validationStage
				end
			end
			if after and metadataAfter then
				return true, "swapped", validationStage
			end
			if before and metadataBefore then
				return true, "no_op", validationStage
			end
			if not allowCompletion or not before or not metadataAfter then
				return false, "inconsistent", validationStage
			end
			-- The native helper exchanges records before calling C_ChatInfo. A
			-- refusal there can leave exactly this verifiable partial state. Finish
			-- only that missing phase; never rerun the helper or roll anything back.
			if Restricted() then
				return false, "pending", "recovery_restrictions"
			end
			if Trusted(C_ChatInfo, "SwapChatChannelsByChannelIndex") ~= nativeSwap then
				return false, "pending", "recovery_helpers"
			end
			local configReady = ConfigurationReady()
			if not configReady then
				return false, "pending", "recovery_configuration"
			end
			-- A temporary chat window may have appeared while recovery waited.
			-- Inspect it too and pin any newly remembered affected destination
			-- against the still-verified original channel identities.
			if not CanAccessForeignTable(CHAT_FRAMES) or not Accessible(ACTIVE_CHAT_EDIT_BOX) then
				return false, "pending", "recovery_chat_input"
			end
			local currentBoxes, count = {}, 0
			for _, frameName in pairs(CHAT_FRAMES) do
				count = count + 1
				if count > 128 or not Name(frameName) then
					return false, "pending", "recovery_chat_input"
				end
				local frame = _G[frameName]
				if not QuestTogether:CanAccessForeignFrame(frame) then
					return false, "pending", "recovery_chat_input"
				end
				local box = frame.editBox
				if not Accessible(box) then
					return false, "pending", "recovery_chat_input"
				end
				if box == nil then
					box = _G[frameName .. "EditBox"]
				end
				if not Accessible(box) then
					return false, "pending", "recovery_chat_input"
				end
				if box ~= nil then
					if not QuestTogether:CanAccessForeignFrame(box) then
						return false, "pending", "recovery_chat_input"
					end
					currentBoxes[#currentBoxes + 1] = box
				end
			end
			if count == 0 then
				return false, "pending", "recovery_chat_input"
			end
			if ACTIVE_CHAT_EDIT_BOX ~= nil then
				currentBoxes[#currentBoxes + 1] = ACTIVE_CHAT_EDIT_BOX
			end
			local destinationBoxes = {}
			for _, destination in ipairs(destinations) do
				destinationBoxes[destination.box] = true
			end
			for _, box in ipairs(currentBoxes) do
				if not seen[box] and #boxes >= 129 then
					return false, "pending", "recovery_chat_input"
				end
				if not InputReady(box) then
					return false, "pending", "recovery_chat_input"
				end
				if not destinationBoxes[box] then
					local getAttribute, getTarget = Trusted(box, "GetAttribute"), Trusted(box, "GetChannelTarget")
					local ok, target = Call(getAttribute, box, "channelTarget")
					if not getTarget or not ok or not Accessible(target) then
						return false, "pending", "recovery_chat_input"
					end
					if target ~= nil and target ~= 0 and target ~= "" then
						if type(target) ~= "number" and type(target) ~= "string" then
							return false, "pending", "recovery_chat_input"
						end
						local id, name = Channel(target)
						local numericTarget = type(target) == "number" and target
							or (target:match("^%d+$") and tonumber(target))
						if (numericTarget == first or numericTarget == second) and id ~= numericTarget then
							return false, "pending", "recovery_chat_input"
						end
						if id == first or id == second then
							local identity = id == first and firstIdentity or secondIdentity
							local setter = Trusted(box, "SetChannelTarget")
							if name ~= identity.name or not setter then
								return false, "pending", "recovery_chat_input"
							end
							local destination = {
								box = box,
								identity = identity,
								before = id,
								after = id == first and second or first,
								getAttribute = getAttribute,
								getTarget = getTarget,
								setter = setter,
							}
							local prepared = Call(setter, box, identity.lookup)
							if not prepared or not DestinationMatches(destination, id, true) then
								return false, "pending", "recovery_chat_input"
							end
							destinations[#destinations + 1] = destination
							destinationBoxes[box] = true
						end
					end
				end
				if not seen[box] then
					seen[box] = true
					boxes[#boxes + 1] = box
				end
			end
			for _, box in ipairs(boxes) do
				if not InputReady(box) then
					return false, "pending", "recovery_chat_input"
				end
			end
			for _, destination in ipairs(destinations) do
				if not DestinationMatches(destination, destination.before, true) then
					return false, "inconsistent", validationStage
				end
			end
			if
				Restricted()
				or not ChannelMatches(firstIdentity, first)
				or not ChannelMatches(secondIdentity, second)
				or not InfoMatches(secondInfo, firstInfo)
				or not SameInfo(firstInfo, firstFields, firstCount, secondKey)
				or not SameInfo(secondInfo, secondFields, secondCount, firstKey)
			then
				return false, "pending", validationStage
			end
			Call(nativeSwap, first, second)
			return Validate(false)
		end
		if
			not DispatchTrusted()
			or Trusted(_G, "ChatConfigChannelSettings_SwapChannelsByIndex") ~= swap
			or Trusted(C_ChatInfo, "SwapChatChannelsByChannelIndex") ~= nativeSwap
		then
			return false, "prepare"
		end
		nativeChatChannelRecovery = function()
			return Validate(true)
		end
		dispatched = true
		stage = "native_reorder"
		nativeChatChannelRecoveryRunning = true
		Call(swap, first, second)
		nativeChatChannelRecoveryRunning = nil
		stage = "result_validation"
		local resolved, outcome = Validate(false)
		if resolved then
			nativeChatChannelRecovery = nil
			if outcome == "swapped" then
				return true
			end
			return false, "no_op"
		end
		return false, outcome
	end
	local ok, swapped, reason = pcall(Run)
	if not ok then
		return false, dispatched and "pending" or "inaccessible", stage
	end
	return swapped, reason, not swapped and stage or nil
end

-- Social discovery only exposes character addresses. Never return Battle.net
-- account identities, friend notes, or chat contents to the network layer.
local function MeshSocialCount(value, maximum)
	if
		not CanAccessForeignValue(value)
		or type(value) ~= "number"
		or value ~= value
		or value < 0
		or value == math.huge
		or value ~= math.floor(value)
	then
		return 0
	end
	return math.min(value, maximum)
end
local function MeshSocialIndex(value)
	return CanAccessForeignValue(value)
		and type(value) == "number"
		and value >= 1
		and value <= 2048
		and value == math.floor(value)
end
local function MeshSocialName(value)
	local name = ReadOptionalString(value)
	if not name or name == "" or #name > 120 or name:find("[%c|,:]") then
		return nil
	end
	return name
end

local ordinaryWhisperObserver = { hooks = {} }
local function NotifyOrdinaryWhisperObserver(distribution, target)
	-- Never retain or forward the message text. Secure post-hooks cannot be
	-- removed. The consumer owns bounded notice receipts across disable/world
	-- transitions; clearing its callback is what makes these hooks inert.
	local callback = ordinaryWhisperObserver.callback
	if callback then
		pcall(callback, distribution, target)
	end
end

local function ObserveOrdinaryChatSend(_, distribution, language, target)
	-- SendChatMessage documents an omitted type as SAY. Unlike unreadable
	-- edit-box metadata, that native default cannot be a human whisper.
	if CanAccessForeignValue(distribution) and distribution == nil then
		distribution = "SAY"
	end
	NotifyOrdinaryWhisperObserver(distribution, target)
end

local function ObserveOrdinaryEditBox(_, editBox)
	if not ordinaryWhisperObserver.callback then
		return
	end
	local distribution, target
	if QuestTogether:CanAccessForeignFrame(editBox) then
		-- Blizzard fires this notification even after slash parsing clears the
		-- box, or Enter submits an empty sticky whisper. Zero length proves no
		-- ordinary message will be sent without reading any private chat text.
		local lengthOK, length = pcall(function()
			return editBox:GetNumLetters()
		end)
		if lengthOK and CanAccessForeignValue(length) and type(length) == "number" and length == 0 then
			return
		end
		local ok, value = pcall(function()
			return editBox:GetChatType()
		end)
		if ok then
			distribution = value
		end
		ok, value = pcall(function()
			return editBox:GetTellTarget()
		end)
		if ok then
			target = value
		end
	end
	-- Unreadable type/target is deliberately forwarded so the consumer can
	-- fail open. No chat text or extra state on Blizzard's edit box is needed.
	NotifyOrdinaryWhisperObserver(distribution, target)
end

local function SetOrdinaryWhisperObserver(callback)
	-- Private fixtures can inherit this adapter during /qt test. They must
	-- neither install real hooks nor clear the live observer between slices.
	if QuestTogether.isRunningTests then
		return false
	end
	ordinaryWhisperObserver.callback = nil
	if callback == nil then
		return true
	end
	if type(callback) ~= "function" or type(hooksecurefunc) ~= "function" then
		return false
	end
	local modern = CanAccessForeignTable(C_ChatInfo) and C_ChatInfo.SendChatMessage or nil
	local legacy = SendChatMessage
	if not CanAccessForeignValue(modern) or type(modern) ~= "function" then
		modern = nil
	end
	if not CanAccessForeignValue(legacy) or type(legacy) ~= "function" then
		legacy = nil
	end
	local found = false
	local function Install(key, owner, native)
		if not CanAccessForeignValue(native) or type(native) ~= "function" then
			return true
		end
		found = true
		if ordinaryWhisperObserver.hooks[key] == native then
			return true
		end
		local ok
		if owner then
			ok = pcall(hooksecurefunc, owner, "SendChatMessage", ObserveOrdinaryChatSend)
		else
			ok = pcall(hooksecurefunc, "SendChatMessage", ObserveOrdinaryChatSend)
		end
		if ok then
			ordinaryWhisperObserver.hooks[key] = owner and owner.SendChatMessage or SendChatMessage
		end
		return ok
	end
	if not Install("modern", C_ChatInfo, modern) then
		return false
	end
	-- Older clients expose only the global. On current clients it can be a
	-- separate forwarding wrapper; observing it also covers other replacements.
	-- A duplicate observation is harmless: consumers extend a protection window.
	local hookedModern = ordinaryWhisperObserver.hooks.modern
	if legacy and legacy == hookedModern then
		found = true
	elseif not Install("legacy", nil, legacy) then
		return false
	end
	if not found then
		return false
	end
	local registry = EventRegistry
	if
		CanAccessForeignTable(registry)
		and type(registry.RegisterCallback) == "function"
		and ordinaryWhisperObserver.registry ~= registry
	then
		-- This public event precedes the native send for typed chat. Post-hooks
		-- also cover macros/other callers, whose server replies arrive later.
		-- Do not wrap SendChatMessage merely to intercept synchronous errors.
		local ok = pcall(
			registry.RegisterCallback,
			registry,
			"ChatFrame.OnEditBoxPreSendText",
			ObserveOrdinaryEditBox,
			ordinaryWhisperObserver
		)
		if ok then
			ordinaryWhisperObserver.registry = registry
		end
	end
	ordinaryWhisperObserver.callback = callback
	return true
end

local function CallChatFilterAPI(method, legacy, eventName, filterFunc)
	if QuestTogether.isRunningTests or type(eventName) ~= "string" or type(filterFunc) ~= "function" then
		return false
	end
	local native = CanAccessForeignTable(ChatFrameUtil) and ChatFrameUtil[method] or nil
	if not CanAccessForeignValue(native) or type(native) ~= "function" then
		native = legacy
	end
	if not CanAccessForeignValue(native) or type(native) ~= "function" then
		return false
	end
	-- Blizzard's current public API owns a SecureTypes registry and wraps its
	-- callbacks securely. Call it intact rather than touching that registry.
	return pcall(native, eventName, filterFunc)
end

QuestTogether:RegisterNativeAPI("chat", {
	JoinPermanentChannel = function(name, password, chatFrameId, hasVoice)
		return JoinPermanentChannel(name, password, chatFrameId, hasVoice)
	end,
	LeaveChannelByName = function(name)
		return LeaveChannelByName(name)
	end,
	GetChannelName = function(name)
		return GetChannelName(name)
	end,
	-- Directory APIs use display-list indices, never native channel IDs.
	GetNumGuildMembers = function()
		if type(GetNumGuildMembers) ~= "function" then
			return 0
		end
		local ok, count = pcall(GetNumGuildMembers)
		return ok and CanAccessForeignValue(count) and type(count) == "number" and count or 0
	end,
	GetGuildRosterInfo = function(index)
		if type(GetGuildRosterInfo) ~= "function" then
			return nil
		end
		local ok, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, index)
		if not ok or not CanAccessForeignValue(name) or not CanAccessForeignValue(online) then
			return nil
		end
		return type(name) == "string" and name or nil, online == true
	end,
	GetMeshFriendCount = function()
		return MeshSocialCount(Access.Call(C_FriendList, "GetNumFriends"), 2048)
	end,
	GetMeshFriendName = function(index)
		if not MeshSocialIndex(index) then
			return nil
		end
		local info = Access.Call(C_FriendList, "GetFriendInfoByIndex", index)
		if not CanAccessForeignTable(info) or not CanAccessForeignValue(info.connected) or info.connected ~= true then
			return nil
		end
		return MeshSocialName(info.name)
	end,
	GetMeshBattleNetFriendCount = function()
		return MeshSocialCount(Access.Call(_G, "BNGetNumFriends"), 2048)
	end,
	GetMeshBattleNetGameAccountCount = function(friendIndex)
		if not MeshSocialIndex(friendIndex) then
			return 0
		end
		return MeshSocialCount(Access.Call(C_BattleNet, "GetFriendNumGameAccounts", friendIndex), 16)
	end,
	GetMeshBattleNetFriendName = function(friendIndex, accountIndex)
		if not MeshSocialIndex(friendIndex) or not MeshSocialIndex(accountIndex) or accountIndex > 16 then
			return nil
		end
		local info = Access.Call(C_BattleNet, "GetFriendGameAccountInfo", friendIndex, accountIndex)
		if
			not CanAccessForeignTable(info)
			or not CanAccessForeignValue(info.isOnline)
			or info.isOnline ~= true
			or not CanAccessForeignValue(info.isAppearOffline)
			or info.isAppearOffline ~= false
			or not CanAccessForeignValue(info.clientProgram)
			or info.clientProgram ~= "WoW"
			or not CanAccessForeignValue(info.isInCurrentRegion)
			or info.isInCurrentRegion ~= true
			or not CanAccessForeignValue(WOW_PROJECT_ID)
			or type(WOW_PROJECT_ID) ~= "number"
			or not CanAccessForeignValue(info.wowProjectID)
			or info.wowProjectID ~= WOW_PROJECT_ID
		then
			return nil
		end
		local name = MeshSocialName(info.characterName)
		if not name then
			return nil
		end
		if QuestTogether:UsesRegionalPlayerNames() then
			return name
		end
		local realm = MeshSocialName(info.realmName)
		if not realm then
			return nil
		end
		return QuestTogether:NormalizeMemberName(name .. "-" .. realm)
	end,
	GetMeshUnitPlayerName = function(unitToken)
		if
			not CanAccessForeignValue(unitToken)
			or type(unitToken) ~= "string"
			or #unitToken > 32
			or not unitToken:match("^[%a]+%d*$")
		then
			return nil
		end
		for _, query in ipairs({ "UnitExists", "UnitIsVisible", "UnitIsPlayer" }) do
			if Access.Call(_G, query, unitToken) ~= true then
				return nil
			end
		end
		if
			Access.Call(_G, "UnitIsFriend", "player", unitToken) ~= true
			or not CanAccessForeignValue(UnitFullName)
			or type(UnitFullName) ~= "function"
		then
			return nil
		end
		local ok, rawName, rawRealm = pcall(UnitFullName, unitToken)
		if not ok or not CanAccessForeignValue(rawRealm) then
			return nil
		end
		local name, realm = MeshSocialName(rawName), MeshSocialName(rawRealm)
		if not name or rawRealm ~= nil and rawRealm ~= "" and not realm then
			return nil
		end
		if QuestTogether:UsesRegionalPlayerNames() then
			if realm and not name:find(" ", 1, true) then
				name = name .. " " .. realm
			end
			return QuestTogether:NormalizeMemberName(name)
		end
		return QuestTogether:NormalizeMemberName(realm and name .. "-" .. realm or name)
	end,
	GetNumDisplayChannels = function()
		if type(GetNumDisplayChannels) ~= "function" then
			return 0
		end
		local ok, count = pcall(GetNumDisplayChannels)
		return ok and CanAccessForeignValue(count) and type(count) == "number" and count or 0
	end,
	GetChannelDisplayInfo = function(index)
		if type(GetChannelDisplayInfo) ~= "function" then
			return nil
		end
		local ok, name, header, collapsed, channelID, count, active = pcall(GetChannelDisplayInfo, index)
		if
			not ok
			or not CanAccessForeignValue(name)
			or not CanAccessForeignValue(header)
			or not CanAccessForeignValue(collapsed)
			or not CanAccessForeignValue(channelID)
			or not CanAccessForeignValue(count)
			or not CanAccessForeignValue(active)
		then
			return nil
		end
		return name, header, collapsed, channelID, count, active
	end,
	GetChannelRosterInfo = function(index, member)
		local getter = C_ChatInfo and C_ChatInfo.GetChannelRosterInfo or GetChannelRosterInfo
		if type(getter) ~= "function" then
			return nil
		end
		local ok, name = pcall(getter, index, member)
		return ok and CanAccessForeignValue(name) and type(name) == "string" and name or nil
	end,
	GetSelectedDisplayChannel = function()
		if type(GetSelectedDisplayChannel) ~= "function" then
			return nil
		end
		local ok, index = pcall(GetSelectedDisplayChannel)
		return ok and CanAccessForeignValue(index) and type(index) == "number" and index or nil
	end,
	SetSelectedDisplayChannel = function(index)
		if type(SetSelectedDisplayChannel) ~= "function" or (InCombatLockdown and InCombatLockdown()) then
			return false
		end
		return pcall(SetSelectedDisplayChannel, index)
	end,
	RequestChannelSelectionRestore = function(callback)
		if type(callback) ~= "function" then
			return false
		end
		local frame = QuestTogether.meshDirectoryRestoreEventFrame
		if not frame then
			frame = CreateFrame("Frame")
			QuestTogether.meshDirectoryRestoreEventFrame = frame
			frame:SetScript("OnEvent", function(owner, event)
				if event ~= "PLAYER_LOGOUT" and InCombatLockdown and InCombatLockdown() then
					return
				end
				owner:UnregisterAllEvents()
				local restore = owner.restore
				owner.restore = nil
				if restore then
					pcall(restore, event ~= "PLAYER_LOGOUT")
				end
			end)
		end
		frame.restore = callback
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		frame:RegisterEvent("PLAYER_LOGOUT")
		return true
	end,
	CancelChannelSelectionRestore = function()
		local frame = QuestTogether.meshDirectoryRestoreEventFrame
		if frame then
			frame.restore = nil
			frame:UnregisterAllEvents()
		end
	end,
	IsChannelWindowShown = function()
		local frame = ChannelFrame
		if frame == nil then
			return false
		end
		if not QuestTogether:CanAccessForeignFrame(frame) then
			return true
		end
		local ok, shown = pcall(frame.IsShown, frame)
		return not ok or not CanAccessForeignValue(shown) or shown == true
	end,
	GetChatChannelList = function()
		if type(GetChannelList) ~= "function" then
			return nil
		end
		return { GetChannelList() }
	end,
	SwapChatChannelsPreservingState = SwapChatChannelsPreservingState,
	CheckChatChannelOrderRecovery = CheckChatChannelOrderRecovery,
	GetNumChatWindows = function()
		return NUM_CHAT_WINDOWS or 0
	end,
	GetChatWindowInfo = function(chatFrameID)
		return FCF_GetChatWindowInfo(chatFrameID)
	end,
	GetChatFrameByID = function(chatFrameID)
		local chatFrame = FCF_GetChatFrameByID(chatFrameID)
		if
			QuestTogether
			and QuestTogether.CanAccessForeignFrame
			and not QuestTogether:CanAccessForeignFrame(chatFrame)
		then
			return nil
		end
		return chatFrame
	end,
	RemoveChatWindowChannel = function(chatFrame, channelName)
		if
			QuestTogether
			and QuestTogether.CanAccessForeignFrame
			and not QuestTogether:CanAccessForeignFrame(chatFrame)
		then
			return nil
		end
		if chatFrame and chatFrame.RemoveChannel then
			return chatFrame:RemoveChannel(channelName)
		end
		if type(ChatFrame_RemoveChannel) == "function" and chatFrame then
			return ChatFrame_RemoveChannel(chatFrame, channelName)
		end
		return nil
	end,
	AddMessageEventFilter = function(eventName, filterFunc)
		return CallChatFilterAPI("AddMessageEventFilter", ChatFrame_AddMessageEventFilter, eventName, filterFunc)
	end,
	RemoveMessageEventFilter = function(eventName, filterFunc)
		return CallChatFilterAPI("RemoveMessageEventFilter", ChatFrame_RemoveMessageEventFilter, eventName, filterFunc)
	end,
	SetOrdinaryWhisperObserver = SetOrdinaryWhisperObserver,
	GetPlayerNotFoundMessageFormat = function()
		local value = ERR_CHAT_PLAYER_NOT_FOUND_S
		if CanAccessForeignValue(value) and type(value) == "string" and #value > 0 and #value <= 1024 then
			return value
		end
		return nil
	end,
	OpenChatWindow = function(name, noDefaultChannels)
		return FCF_OpenNewWindow(name, noDefaultChannels)
	end,
	CloseChatWindow = function(chatFrame)
		if
			QuestTogether
			and QuestTogether.CanAccessForeignFrame
			and not QuestTogether:CanAccessForeignFrame(chatFrame)
		then
			return nil
		end
		return FCF_Close(chatFrame)
	end,
	SetChatWindowFontSize = function(chatFrame, fontSize)
		if
			QuestTogether
			and QuestTogether.CanAccessForeignFrame
			and not QuestTogether:CanAccessForeignFrame(chatFrame)
		then
			return nil
		end
		return FCF_SetChatWindowFontSize(nil, chatFrame, fontSize)
	end,
	RegisterAddonPrefix = function(prefix)
		local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
		return ok and result or nil
	end,
	SendAddonMessage = function(prefix, message, channel, target)
		-- Transport owns the error boundary and records native exceptions.
		return C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
	end,
	ReportLuaError = function(message)
		if type(geterrorhandler) == "function" then
			local handler = geterrorhandler()
			if type(handler) == "function" then
				handler(message)
			end
		end
	end,
	SendLocalChatMessage = function(message, distribution)
		if distribution ~= "SAY" and distribution ~= "YELL" then
			return false
		end
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if type(send) ~= "function" then
			return false
		end
		local ok, result = pcall(send, message, distribution)
		return ok and result ~= false
	end,
	SendPartyChatMessage = function(message, distribution)
		if distribution ~= "PARTY" and distribution ~= "INSTANCE_CHAT" then
			return false
		end
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if type(send) ~= "function" then
			return false
		end
		local ok = pcall(send, message, distribution)
		return ok
	end,
	OpenQTChatComposer = function()
		if QuestTogether:IsRuntimeRestricted() then
			return false
		end
		local openChat
		if CanAccessForeignTable(ChatFrameUtil) then
			openChat = ChatFrameUtil.OpenChat
		end
		if not CanAccessForeignValue(openChat) then
			return false
		end
		if type(openChat) ~= "function" then
			openChat = ChatFrame_OpenChat
		end
		if not CanAccessForeignValue(openChat) or type(openChat) ~= "function" then
			return false
		end
		-- Let Blizzard choose its edit box; pass only text, never the minimap
		-- button as a chat frame. Opening a draft does not send a message.
		local ok, result = pcall(openChat, "/qt ")
		return ok and CanAccessForeignValue(result) and result ~= false
	end,
	SendTell = function(name, chatFrame)
		-- Menus can be anchored to map dots or UIParent. Only a readable
		-- chat frame with an edit box is a native preferred chat destination;
		-- nil lets Blizzard choose its active/default window.
		local editBox = QuestTogether:GetAccessibleFrameMember(chatFrame, "editBox")
		if not QuestTogether:CanAccessForeignFrame(editBox) then
			chatFrame = nil
		end
		if ChatFrameUtil and ChatFrameUtil.SendTell then
			local ok, result = pcall(ChatFrameUtil.SendTell, name, chatFrame)
			return ok and QuestTogether:CanAccessValue(result) and result ~= false
		end
		if type(ChatFrame_SendTell) == "function" then
			local ok, result = pcall(ChatFrame_SendTell, name, chatFrame)
			return ok and QuestTogether:CanAccessValue(result) and result ~= false
		end
		return false
	end,
	AddFriend = function(name)
		if C_FriendList and C_FriendList.AddFriend then
			local ok, result = pcall(C_FriendList.AddFriend, name)
			return ok and result or nil
		end
		return nil
	end,
	AddOrDelIgnore = function(name)
		if C_FriendList and C_FriendList.AddOrDelIgnore then
			-- Ignore-list APIs can throw for invalid names; keep menu actions non-fatal.
			local ok, result = pcall(C_FriendList.AddOrDelIgnore, name)
			return ok and result or nil
		end
		return nil
	end,
	IsOnIgnoredList = function(name)
		if C_FriendList and C_FriendList.IsOnIgnoredList then
			-- Ignore-list lookups can throw on malformed names; treat as "not ignored".
			local ok, result = pcall(C_FriendList.IsOnIgnoredList, name)
			return ok and result or false
		end
		return false
	end,
})
