-- 경기구역 (아웃 오브 바운드)
--
-- 경계는 레벨에 박아둔 빨간 벽 4개가 정한다.
--   Arena_Bound_North / South / East / West
-- 스크립트에 좌표를 적어두지 않는다. 스튜디오에서 벽을 옮기면 그게 그대로 경기구역이 된다.
-- 벽 4개 중 하나라도 없으면 이 시스템은 조용히 쉰다 (맵을 바꿔 끼울 때를 위해서다).
--
-- 판정은 서버가 한다. 사람을 죽이는 일이라 클라이언트에 맡길 수 없다.
-- 화면 연출(빨간 울타리·검어짐·카운트다운)은 BoundaryFX 가 그린다.
--
-- ★ 빨간 벽은 편집기에서 눈으로 잡으라고 놓은 것이지 플레이어에게 보여줄 물건이 아니다.
--   그런데 이 엔진은 Transparency = 1 로도, 클라이언트 쪽 Destroy 로도 안 지워졌다
--   (2026-08-21 실측). 그래서 서버가 아예 ServerStorage 로 치워버린다.
--   복제가 안 되는 곳이라 클라이언트에는 존재 자체가 없다. 확실하다.
--   레벨 파일은 안 건드리므로 편집기에서는 그대로 빨갛게 보인다.
--
-- ★ 치워버린 뒤에는 클라이언트가 Workspace 에서 경계를 못 읽는다.
--   그래서 서버가 사각형을 직접 내려보낸다 (phase = "boundary", state = "rect").
--
-- ★ 로비에 있는 사람은 제외한다. 로비는 (0, 8000, 0) 이라 경기구역 밖이고,
--   빼지 않으면 죽자마자 로비에서 또 죽는다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== 조절값 =====
local CFG = {
	GRACE = 10,        -- 밖에서 버틸 수 있는 시간 (초)
	TICK = 0.25,       -- 검사 주기 (초)
	SLACK = 0,         -- 벽에서 이만큼 더 나가야 밖으로 친다 (cm). 0 이면 벽이 곧 경계
	RECHECK = 2,       -- 벽 위치를 다시 읽는 주기 (초). 스튜디오에서 옮기면 바로 반영된다
	RESEND = 3,        -- 사각형을 클라이언트에 다시 보내는 주기 (초). 늦게 들어온 사람용
	LABEL = "THE BOUNDARY",   -- 킬로그·킬캠에 뜨는 이름. 인게임 표시는 전부 영어
}

local NAMES = { "Arena_Bound_North", "Arena_Bound_South", "Arena_Bound_East", "Arena_Bound_West" }

-- 새 RemoteEvent 를 만들면 안 된다. 레벨에 박아둔 것을 쓴다.
local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)

-- ===== 벽 찾아서 치우기 =====
local marks = nil      -- 벽 4개의 참조. 치운 뒤에도 여기서 위치를 계속 읽는다

local function grabMarks()
	local got = {}
	for _, n in ipairs(NAMES) do
		local part = Workspace:FindFirstChild(n, true) or ServerStorage:FindFirstChild(n, true)
		if not part then
			return nil
		end
		got[#got + 1] = part
	end

	-- 클라이언트에서 안 보이게 복제 밖으로 치운다. 위치는 그대로 남는다.
	local holder = ServerStorage:FindFirstChild("ArenaBounds")
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = "ArenaBounds"
		holder.Parent = ServerStorage
	end
	for _, p in ipairs(got) do
		if p.Parent ~= holder then
			pcall(function()
				p.Parent = holder
			end)
		end
	end
	return got
end

-- 벽의 얇은 축을 보고 동/서인지 남/북인지 가른다. 이름 순서에 의존하지 않는다.
local function readRect()
	if not marks then
		marks = grabMarks()
		if not marks then
			return nil
		end
	end

	local minX, maxX, minZ, maxZ
	for _, part in ipairs(marks) do
		local pos, size
		local ok = pcall(function()
			pos = part.Position
			size = part.Size
		end)
		if not (ok and pos and size) then
			marks = nil       -- 누가 지웠다. 다음 번에 다시 찾는다
			return nil
		end
		if size.X < size.Z then
			-- X 로 얇다 = 동/서 벽. 이 벽의 X 가 경계다
			if not minX or pos.X < minX then minX = pos.X end
			if not maxX or pos.X > maxX then maxX = pos.X end
		else
			if not minZ or pos.Z < minZ then minZ = pos.Z end
			if not maxZ or pos.Z > maxZ then maxZ = pos.Z end
		end
	end
	if not (minX and maxX and minZ and maxZ) then
		return nil
	end
	if maxX - minX < 100 or maxZ - minZ < 100 then
		return nil      -- 네 벽이 한쪽으로 몰려 있다. 잘못 놓인 것이다
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local rect = nil
local out = {}      -- [player] = 죽는 시각 (os.clock)

local function rootOf(player)
	local ch = player.Character
	if not ch then
		return nil
	end
	return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function tell(player, state, left)
	if not combatEvent then
		return
	end
	pcall(function()
		combatEvent:FireClient(player, { phase = "boundary", state = state, left = left })
	end)
end

-- 경계 사각형을 전원에게 알린다. 클라이언트는 이걸 받아야 울타리를 그린다.
local function broadcastRect()
	if not (combatEvent and rect) then
		return
	end
	pcall(function()
		combatEvent:FireAllClients({
			phase = "boundary",
			state = "rect",
			minX = rect.minX,
			maxX = rect.maxX,
			minZ = rect.minZ,
			maxZ = rect.maxZ,
		})
	end)
end

local function clear(player)
	if out[player] then
		out[player] = nil
		tell(player, "in")
	end
end

Players.PlayerRemoving:Connect(function(player)
	out[player] = nil
end)

task.spawn(function()
	local nextRead, nextSend = 0, 0
	local warned = false
	while true do
		task.wait(CFG.TICK)
		local now = os.clock()

		if now >= nextRead then
			nextRead = now + CFG.RECHECK
			local r = readRect()
			if r then
				local changed = (not rect)
					or r.minX ~= rect.minX or r.maxX ~= rect.maxX
					or r.minZ ~= rect.minZ or r.maxZ ~= rect.maxZ
				rect = r
				warned = false
				if changed then
					broadcastRect()
					print(string.format("[Boundary] 경기구역 X[%.0f..%.0f] Z[%.0f..%.0f]",
						r.minX, r.maxX, r.minZ, r.maxZ))
				end
			elseif not warned then
				warned = true
				print("[Boundary] Arena_Bound 벽 4개를 못 찾음 - 경기구역 판정을 쉰다")
			end
		end

		-- 늦게 들어온 사람도 받아야 한다. 작은 신호라 계속 보내도 부담이 없다.
		if rect and now >= nextSend then
			nextSend = now + CFG.RESEND
			broadcastRect()
		end

		local C = _G.CombatServer
		if rect and C then
			for _, player in ipairs(Players:GetPlayers()) do
				local inLobby = _G.LobbyWant and _G.LobbyWant[player]
				local alive = C.isAlive and C.isAlive(player)
				local root = (not inLobby) and alive and rootOf(player) or nil

				if not root then
					clear(player)
				else
					local p = root.Position
					local outside =
						p.X < rect.minX - CFG.SLACK or p.X > rect.maxX + CFG.SLACK or
						p.Z < rect.minZ - CFG.SLACK or p.Z > rect.maxZ + CFG.SLACK

					if not outside then
						clear(player)
					else
						local deadline = out[player]
						if not deadline then
							deadline = now + CFG.GRACE
							out[player] = deadline
						end
						local left = deadline - now
						if left <= 0 then
							out[player] = nil
							tell(player, "in")
							pcall(function()
								C.killByWorld(player, CFG.LABEL)
							end)
						else
							tell(player, "out", left)
						end
					end
				end
			end
		end
	end
end)

print("[Boundary] ready")
