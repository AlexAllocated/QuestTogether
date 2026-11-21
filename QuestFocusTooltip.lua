-- Native quest tooltips remain Blizzard-owned. Only POT is repositioned;
-- optional suppression is limited to the exact currently hovered quest owner.
local QT = _G.QuestTogether

local function Read(a, frame, method)
	local getter = a:GetAccessibleFrameMember(frame, method)
	if type(getter) ~= "function" then return end
	local ok, value = pcall(getter, frame)
	if ok and a:CanAccessValue(value) then return value, true end
end

local function Number(a, frame, method)
	local n = a:SafeToNumber(Read(a, frame, method))
	if n and n == n and math.abs(n) ~= math.huge then return n end
end

local function Rect(a, frame)
	if not a:CanAccessForeignFrame(frame, true) then return end
	local l, t = Number(a, frame, "GetLeft"), Number(a, frame, "GetTop")
	local w, h = Number(a, frame, "GetWidth"), Number(a, frame, "GetHeight")
	local s = Number(a, frame, "GetEffectiveScale")
	if not l or not t or not w or not h or not s or w <= 0 or h <= 0 or s <= 0 then return end
	return { left = l * s, right = (l + w) * s, top = t * s, bottom = (t - h) * s, scale = s }
end

function QT:GetQuestFocusNativeTooltip()
	return GameTooltip
end

function QT:GetQuestFocusHoverEventRegistry()
	return EventRegistry
end

function QT:InstallQuestFocusHoverEvents()
	if rawget(self, "questFocusHoverEvents") or self:IsWorkBlocked("foreign_frame_mutation") then return end
	local registry = self:GetQuestFocusHoverEventRegistry()
	local register = self:GetAccessibleFrameMember(registry, "RegisterCallback")
	if type(register) ~= "function" then return end
	local function Changed()
		if not self.isEnabled or self.isLoggingOut then return end
		-- The native event fires after its tooltip is populated. Read the actual
		-- mouse owner again next frame: pooled blocks can change before we run.
		self:ScheduleRuntimeWork("quest_focus_presentation", "quest_focus_render", function()
			if self.isEnabled and not self.isLoggingOut then self:UpdateQuestFocusWindow() end
		end, { mode = "nextFrame", coalesce = true, reason = "quest tooltip hover" })
	end
	self.questFocusHoverEvents = true
	register(registry, "OnQuestBlockHeader.OnEnter", Changed, self)
	-- Native headers emit no leave event; the existing runtime observer handles
	-- leaving without installing global tooltip or protected header hooks.
end

local function MatchingHover(self, state)
	if not self.isEnabled or self.isLoggingOut or not state or state ~= rawget(self, "questFocusState")
		or not self.db or state.profile ~= self.db.profile or state.mode ~= self:GetQuestTrackerMode()
		or state.mode == "hidden" or self:IsQuestTrackerHiddenWhileSolo()
		or state.editing or not state.hoverBlock
		or not state.hoverID or state.hoverID ~= state.id
		or self:IsWorkBlocked("foreign_frame_mutation") then return end
	local block = state.hoverBlock
	if not self:CanAccessForeignFrame(block, true) or Read(self, block, "IsVisible") ~= true
		or self:NormalizeQuestID(self:GetAccessibleFrameMember(block, "id")) ~= state.hoverID then return end
	return block
end

function QT:GetQuestFocusMatchingTooltip(state)
	local block, tooltip = MatchingHover(self, state), self:GetQuestFocusNativeTooltip()
	if block and self:CanAccessForeignFrame(tooltip, true) and Read(self, tooltip, "IsVisible") == true
		and Read(self, tooltip, "GetOwner") == block then return tooltip end
end

local function HiddenTooltipRect(a, state)
	local block = MatchingHover(a, state)
	local saved = state and state.nativeTooltipAnchor
	if not block or not state.hoverNative or not saved or saved.block ~= block or saved.id ~= state.hoverID
		or a:GetOption("questTrackerHideBlizzardTooltip") ~= true then return end
	local tooltip = a:GetQuestFocusNativeTooltip()
	if tooltip ~= saved.tooltip or not a:CanAccessForeignFrame(tooltip)
		or Read(a, tooltip, "IsShown") ~= false then return end
	local owner, readable = Read(a, tooltip, "GetOwner")
	if not readable or owner ~= nil and owner ~= block then return end
	local current = Rect(a, block)
	if not current then return end
	-- Follow the source row if the tracker moves or UI scale changes. Native
	-- Hide may clear both owner and geometry; only our snapshot is retained.
	local result = {}
	for _, edge in ipairs({ "left", "right", "top", "bottom" }) do
		local axis = (edge == "left" or edge == "right") and "left" or "top"
		result[edge] = current[axis] + (saved.tip[edge] - saved.source[axis]) * current.scale / saved.source.scale
	end
	return result
end

-- Rectangles are in physical screen coordinates, so mixed UI scales do not
-- produce overlap. Try the preferred edge and its opposite before other edges;
-- only shrink when no edge fits the visible panel at its normal scale.
function QT:PlaceQuestTrackerAtTooltip(screen, tip, width, height, gap, obstacle, placement)
	local side = placement == "side"
	local verticalGap = side and gap or 0
	local boxes = {
		replace = { left = screen.left, right = screen.right, bottom = screen.bottom, top = screen.top, side = "replace" },
		left = { left = screen.left, right = math.min(screen.right, tip.left - gap), bottom = screen.bottom, top = screen.top, side = "left" },
		right = { left = math.max(screen.left, tip.right + gap), right = screen.right, bottom = screen.bottom, top = screen.top, side = "right" },
		above = { left = screen.left, right = screen.right, bottom = math.max(screen.bottom, tip.top + verticalGap), top = screen.top, side = "above" },
		below = { left = screen.left, right = screen.right, bottom = screen.bottom, top = math.min(screen.top, tip.bottom - verticalGap), side = "below" },
	}
	local order = placement == "replace" and { "replace", "left", "right", "above", "below" } or side and { "left", "right", "above", "below" }
		or placement == "bottom" and { "below", "above", "left", "right" }
		or { "above", "below", "left", "right" }
	local bestX, bestY, factor = nil, nil, 0
	for _, edge in ipairs(order) do
		local box = boxes[edge]
		local fit = math.min(1, (box.right - box.left) / width, (box.top - box.bottom) / height)
		if fit > factor then
			local w, h = width * fit, height * fit
			local x = box.side == "left" and tip.left - gap - w or tip.right + gap
			local y = tip.top
			if box.side == "replace" then
				x = tip.right - w
			elseif box.side == "above" or box.side == "below" then
				x = side and tip.left or tip.right - w
				y = box.side == "above" and tip.top + verticalGap + h or tip.bottom - verticalGap
			end
			x = math.max(box.left, math.min(box.right - w, x))
			y = math.max(box.bottom + h, math.min(box.top, y))
			local clear = true
			if obstacle and x < obstacle.right and x + w > obstacle.left
				and y > obstacle.bottom and y - h < obstacle.top then
				-- Don't cover the source row/cursor and cause a hover-leave loop.
				if obstacle.bottom - gap - h >= box.bottom then y = obstacle.bottom - gap
				elseif obstacle.top + gap + h <= box.top then y = obstacle.top + gap + h
				else clear = false end
			end
			if clear then bestX, bestY, factor = x, y, fit end
			if clear and fit >= 1 then break end
		end
	end
	-- There may be no readable adjacent area (e.g. a full-screen tooltip).
	if not bestX or factor < 0.6 then return end
	return bestX, bestY, factor
end

function QT:ClearQuestTrackerTooltipAnchor(frame)
	if not frame or not frame.questTooltipDocked or self:IsWorkBlocked("foreign_frame_mutation")
		or not self:CanMutateOwnedUI(frame) then return end
	frame.questTooltipDocked = nil
	-- Restore saved scale and position, never persist transient tooltip docking.
	self:ApplyWindowLayout(frame, true)
	self:ApplyQuestTrackerDefaultAnchor(frame)
end

function QT:UpdateQuestTrackerTooltipAnchor(frame, state)
	if not frame or self:IsWorkBlocked("foreign_frame_mutation") or not self:CanMutateOwnedUI(frame) then return end
	-- IsShown ignores hidden parents. Only suppress native information when
	-- the matching POT content is actually visible, not merely configured on.
	local visible = Read(self, frame, "IsVisible") == true and Read(self, frame.panel, "IsVisible") == true
	local tooltip = visible and self:GetQuestFocusMatchingTooltip(state)
	local hiddenTip = visible and HiddenTooltipRect(self, state)
	if state and not hiddenTip then state.nativeTooltipAnchor = nil end
	if tooltip and state.hoverNative and self:GetOption("questTrackerHideBlizzardTooltip") == true then
		-- Hide runs native cleanup. Never change alpha, replace native scripts,
		-- or force Show on a reused tooltip when POT goes away.
		if not self:IsProtectedFrame(tooltip) then
			local hide = self:GetAccessibleFrameMember(tooltip, "Hide")
			if type(hide) == "function" then
				local tip, source = Rect(self, tooltip), Rect(self, state.hoverBlock)
				local ok = pcall(hide, tooltip)
				if ok and Read(self, tooltip, "IsShown") == false then
					if tip and source then
						state.nativeTooltipAnchor = { tip = tip, source = source, tooltip = tooltip,
							block = state.hoverBlock, id = state.hoverID }
						hiddenTip = HiddenTooltipRect(self, state)
					end
					tooltip = nil
				end
			end
		end
	end
	if (tooltip or hiddenTip) and self:IsQuestTrackerSnapped() and not frame.dragging and not frame.resizing then
		local root = self:GetOwnedUIParent()
		local screen, tip = Rect(self, root), hiddenTip or Rect(self, tooltip)
		local fs, scale = Number(self, frame, "GetEffectiveScale"), Number(self, frame, "GetScale")
		if screen and tip and fs and scale and fs > 0 and scale > 0 then
			local dock = frame.questTooltipDocked
			-- A display/scale change may have reapplied the managed layout.
			local base = dock and scale == dock.appliedScale and dock.baseScale or scale
			local effective = fs * base / scale
			local x, y, factor = self:PlaceQuestTrackerAtTooltip(screen, tip,
				frame.panel:GetWidth() * effective, frame.panel:GetHeight() * effective, 4 * screen.scale,
				Rect(self, state.hoverBlock), hiddenTip and "replace" or self:GetQuestTrackerTooltipPlacement())
			if x then
				local wanted = base * factor
				frame.questTooltipDocked = { baseScale = base, appliedScale = wanted }
				if scale ~= wanted then frame:SetScale(wanted) end
				-- The invisible managed frame retains the configured max height.
				-- Clamp the visible panel above instead of clamping that empty area.
				frame:SetClampedToScreen(false)
				local newScale = effective * factor
				x, y = (x - screen.left) / newScale, (y - screen.bottom) / newScale
				local p, relative, rp, oldX, oldY = frame:GetPoint(1)
				if p ~= "TOPLEFT" or relative ~= root or rp ~= "BOTTOMLEFT" or oldX ~= x or oldY ~= y then
					frame:ClearAllPoints()
					frame:SetPoint("TOPLEFT", root, "BOTTOMLEFT", x, y)
				end
				return
			end
		end
	end
	self:ClearQuestTrackerTooltipAnchor(frame)
	self:ApplyQuestTrackerDefaultAnchor(frame)
end
