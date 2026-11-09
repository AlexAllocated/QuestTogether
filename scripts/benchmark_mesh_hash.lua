-- Offline CPU benchmark. Uses the bundled hash implementation and production
-- 16-step coroutine slices; host timing is not a live-client frame guarantee.
QuestTogether = {}
dofile("Libs/Ed25519/Ed25519.lua")
print(_VERSION .. " nativeBit=" .. tostring(bit32 ~= nil or bit ~= nil))
for _, size in ipairs({ 256, 1024, 8192 }) do
	local wall, maxSlice, totalFrames, bytes = 0, 0, 0, 0
	local repetitions = 5
	collectgarbage("collect")
	local startMemory = collectgarbage("count")
	local started = os.clock()
	for _ = 1, repetitions do
		local co = coroutine.create(function()
			return QuestTogether.Ed25519.Hash(string.rep("q", size), coroutine.yield)
		end)
		local frames = 0
		while coroutine.status(co) ~= "dead" do
			local sliceStarted = os.clock()
			for _ = 1, 16 do
				local ok, value = coroutine.resume(co)
				assert(ok, value)
				if coroutine.status(co) == "dead" then
					assert(#value == 64)
					break
				end
			end
			maxSlice = math.max(maxSlice, (os.clock() - sliceStarted) * 1000)
			frames = frames + 1
		end
		totalFrames = totalFrames + frames
	end
	local elapsed = (os.clock() - started) * 1000 / repetitions
	print(
		string.format(
			"bytes=%d repetitions=%d averageCPUms=%.3f max16stepSliceMs=%.3f averageSlices=%.1f heapDeltaKiB=%.1f",
			size,
			repetitions,
			elapsed,
			maxSlice,
			totalFrames / repetitions,
			collectgarbage("count") - startMemory
		)
	)
end
