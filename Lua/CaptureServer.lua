-- 점령 구역 (Take the Point)
--
-- 게임이 처음으로 "끝나는" 상태가 되는 지점이다. 여기가 없으면 킬을 아무리 해도 판이 안 끝난다.
--
-- 흐름 :
--   경기 시작 -> OPEN_DELAY 초 카운트다운 -> 첫 구역이 맵 정중앙에 열림
--   -> MOVE_INTERVAL 초마다 맵 안 무작위 위치로 옮겨감
--   -> 어느 팀이든 TARGET_SCORE 를 먼저 찍으면 경기 종료 -> 재정비 후 다시 시작
--
-- 점수 (기획서) :
--   구역 안 인원의 "차이" 만큼 점수가 오른다. 많은 쪽만 먹는다.
--   블루 4 / 레드 0  -> 블루에 초당 2.0점   (4 * 0.5)
--   블루 4 / 레드 2  -> 블루에 초당 1.0점   ((4-2) * 0.5)
--   블루 2 / 레드 2  -> 아무도 못 먹는다 (난전)
--
-- ★ RemoteEvent 를 새로 만들지 않는다.
--   런타임에 만든 RemoteEvent 는 클라이언트가 못 찾는다 (RyunochiEvent 로 크게 당했다).
--   그래서 이미 레벨에 박혀 있는 TeamEvent 에 phase 를 붙여 같이 실어 보낸다.
--
-- ★ 원은 파츠 조각을 둥글게 세워 그린다.
--   Cylinder 모양이 이 엔진에 있는지 확인된 적이 없어서 확실한 방법을 쓴다.
--   조각은 한 번만 만들고 자리를 옮길 때 위치만 다시 잡는다 (인스턴스를 늘리지 않는다).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = {
	OPEN_DELAY = 20,          -- 경기 시작 후 첫 구역이 열리기까지 (초)
	MOVE_INTERVAL = 90,       -- 구역이 옮겨가는 주기 (초) = 1분 30초
	RADIUS = 1400,            -- 구역 반지름 (cm) = 14m
	HEIGHT = 1000,            -- 판정 높이. 이 안의 높이차만 구역 안으로 친다
	TICK = 1,                 -- 점수 계산 주기 (초)
	SCORE_PER_NET = 0.5,      -- 인원차 1명당 1초에 주는 점수
	SEGMENTS = 32,            -- 원을 이루는 조각 수
	SEG_W = 70,               -- 조각의 접선 방향 폭
	SEG_T = 45,               -- 두께
	SEG_H = 300,              -- 높이. 멀리서도 원이 보여야 한다
	RISE = 40,                -- 지면에서 띄우는 높이
	MIN_SPAWN_DIST = 6500,    -- 팀 스폰에서 이만큼은 떨어진 곳에 연다
	RESTART_DELAY = 20,       -- 경기 종료 후 재정비 (초)

	-- ★ 제한시간. 이 시간이 지나면 점수가 목표에 못 미쳐도 경기가 끝나고
	--   그 시점에 점수가 더 높은 팀이 이긴다. 같으면 무승부.
	--   시간은 첫 구역이 열리는 순간부터 센다 (앞의 20초 카운트다운은 안 센다).
	MATCH_TIME = 360,         -- 6분

	-- ★ 전장에 이만큼은 나와 있어야 경기가 시작된다.
	--   로비에서 아무도 PLAY 를 안 눌렀는데 카운트다운이 돌고 시간이 흐르면 안 된다.
	--   혼자 테스트할 일이 많아 1로 뒀다. 실제로 붙일 땐 2로 올리는 게 맞다.
	MIN_PLAYERS = 1,
}

-- 맵 범위 (SeamFiller 와 같은 실측값)
local MAP_NAME = "JSN_Sangok"
local X_MIN, X_MAX = -73053, -47053
local Z_MIN, Z_MAX = -13130, 12870
local CENTER_X, CENTER_Z = -60053, -130      -- 첫 구역 자리 (맵 정중앙)
local EDGE_MARGIN = 4000                      -- 가장자리에는 열지 않는다

-- ★ 경기구역(Arena_Bound_* 빨간 벽 4개)이 있으면 그 안에서만 연다.
--   구역 밖에 점령지가 열리면 점령하러 나갔다가 이탈 판정으로 죽는다.
--   판정 규칙은 BoundaryServer 와 똑같이 맞춰둔다. 벽이 없으면 위의 맵 전체값을 그대로 쓴다.
local BOUND_NAMES = { "Arena_Bound_North", "Arena_Bound_South", "Arena_Bound_East", "Arena_Bound_West" }

local function useArenaBounds()
	local minX, maxX, minZ, maxZ
	for _, n in ipairs(BOUND_NAMES) do
		-- BoundaryServer 가 벽을 ServerStorage 로 치워버리므로 거기도 봐야 한다
		local part = Workspace:FindFirstChild(n, true)
			or game:GetService("ServerStorage"):FindFirstChild(n, true)
		if not part then
			return false
		end
		local pos, size
		local ok = pcall(function()
			pos = part.Position
			size = part.Size
		end)
		if not (ok and pos and size) then
			return false
		end
		if size.X < size.Z then
			if not minX or pos.X < minX then minX = pos.X end
			if not maxX or pos.X > maxX then maxX = pos.X end
		else
			if not minZ or pos.Z < minZ then minZ = pos.Z end
			if not maxZ or pos.Z > maxZ then maxZ = pos.Z end
		end
	end
	if not (minX and maxX and minZ and maxZ) then
		return false
	end
	if maxX - minX < 100 or maxZ - minZ < 100 then
		return false
	end
	X_MIN, X_MAX, Z_MIN, Z_MAX = minX, maxX, minZ, maxZ
	CENTER_X, CENTER_Z = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
	return true
end

local WHITE = Color3.fromRGB(235, 235, 235)
local RED = Color3.fromRGB(255, 70, 70)
local BLUE = Color3.fromRGB(70, 150, 255)

local map = Workspace:WaitForChild(MAP_NAME, 20)
local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)

local function team()
	return _G.TeamServer
end
local function combat()
	return _G.CombatServer
end

local function send(payload)
	if not teamEvent then
		return
	end
	pcall(function()
		teamEvent:FireAllClients(payload)
	end)
end

-- ===== 원 만들기 =====
local ring = { parts = {}, folder = nil, center = nil }

local function buildRing()
	local folder = Instance.new("Model")
	folder.Name = "CaptureZone"
	folder.Parent = Workspace
	ring.folder = folder

	for i = 1, CFG.SEGMENTS do
		local p = Instance.new("Part")
		p.Name = "ZoneSeg"
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(CFG.SEG_T, CFG.SEG_H, CFG.SEG_W)
		p.Color = WHITE
		p.Transparency = 0.35
		pcall(function()
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
		end)
		p.Parent = folder
		ring.parts[i] = p
	end
	-- 열리기 전에는 숨겨둔다
	for _, p in ipairs(ring.parts) do
		p.Transparency = 1
	end
end

local rayParams
local function groundY(x, z)
	local ok, res = pcall(function()
		if not rayParams then
			rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { ring.folder }
		end
		return Workspace:Raycast(Vector3.new(x, 9000, z), Vector3.new(0, -22000, 0), rayParams)
	end)
	if ok and res then
		return res.Position.Y
	end
	return nil
end

-- 원을 이 자리로 옮긴다. 조각마다 지면 높이를 다시 재서 경사에도 붙게 한다.
local function placeRing(cx, cz, cy)
	ring.center = Vector3.new(cx, cy, cz)
	for i = 1, CFG.SEGMENTS do
		local th = (i / CFG.SEGMENTS) * math.pi * 2
		local x = cx + math.cos(th) * CFG.RADIUS
		local z = cz + math.sin(th) * CFG.RADIUS
		local y = groundY(x, z) or cy
		local p = ring.parts[i]
		pcall(function()
			-- 접선 방향으로 세운다. 안 돌리면 조각이 다 같은 방향을 봐서 원이 각져 보인다
			p.CFrame = CFrame.new(Vector3.new(x, y + CFG.RISE + CFG.SEG_H / 2, z))
				* CFrame.Angles(0, -th, 0)
		end)
	end
end

local function setRingColor(color, transparency)
	for _, p in ipairs(ring.parts) do
		pcall(function()
			p.Color = color
			p.Transparency = transparency
		end)
	end
end

-- 난전일 때. 조각을 인원 비율대로 두 색으로 나눠 칠한다.
-- 점수를 먹는 쪽이 더 진하게 보이도록 투명도를 다르게 준다.
local function setRingSplit(redCount, blueCount, owner)
	local total = redCount + blueCount
	if total <= 0 then
		return
	end
	local redSegs = math.floor(CFG.SEGMENTS * (redCount / total) + 0.5)
	for i, p in ipairs(ring.parts) do
		local isRed = i <= redSegs
		local strong = (owner == "red" and isRed) or (owner == "blue" and not isRed)
		pcall(function()
			p.Color = isRed and RED or BLUE
			p.Transparency = strong and 0.15 or 0.6
		end)
	end
end

-- ===== 다음 구역 자리 고르기 =====
local function spawnPositions()
	local out = {}
	if not map then
		return out
	end
	for _, name in ipairs({ "JSN_Spawn_Red", "JSN_Spawn_Blue" }) do
		local sp = map:FindFirstChild(name, true)
		if sp then
			table.insert(out, sp.Position)
		end
	end
	return out
end

local function pickSpot(first)
	useArenaBounds()      -- 스튜디오에서 벽을 옮겼으면 여기서 바로 따라간다
	if first then
		local y = groundY(CENTER_X, CENTER_Z)
		if y then
			return CENTER_X, CENTER_Z, y
		end
	end

	local spawns = spawnPositions()
	-- 20번까지 시도한다. 다 실패하면 그냥 중앙으로 간다.
	for _ = 1, 20 do
		-- 구역이 좁으면 4000 을 그대로 빼면 남는 데가 없다. 변 길이의 1/4 로 묶는다
		local mx = math.min(EDGE_MARGIN, (X_MAX - X_MIN) * 0.25)
		local mz = math.min(EDGE_MARGIN, (Z_MAX - Z_MIN) * 0.25)
		local x = (X_MIN + mx) + math.random() * ((X_MAX - mx) - (X_MIN + mx))
		local z = (Z_MIN + mz) + math.random() * ((Z_MAX - mz) - (Z_MIN + mz))
		local y = groundY(x, z)
		if y then
			local okDist = true
			for _, sp in ipairs(spawns) do
				local dx, dz = x - sp.X, z - sp.Z
				if math.sqrt(dx * dx + dz * dz) < CFG.MIN_SPAWN_DIST then
					okDist = false
					break
				end
			end
			if okDist then
				return x, z, y
			end
		end
	end

	local y = groundY(CENTER_X, CENTER_Z) or 854
	return CENTER_X, CENTER_Z, y
end

-- ===== 구역 안 인원 세기 =====
local function countInside()
	local red, blue = 0, 0
	local inside = {}
	if not ring.center then
		return red, blue, inside
	end
	local C = combat()
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
		-- 죽은 사람은 안 센다. 시체가 구역을 먹고 있으면 안 된다
		local alive = (C == nil) or C.isAlive(p)
		if root and alive then
			local dx = root.Position.X - ring.center.X
			local dz = root.Position.Z - ring.center.Z
			local dy = math.abs(root.Position.Y - ring.center.Y)
			if dy <= CFG.HEIGHT and (dx * dx + dz * dz) <= (CFG.RADIUS * CFG.RADIUS) then
				local T = team()
				local tn = T and T.teamNameOf(p)
				if tn == "red" then
					red = red + 1
					table.insert(inside, { p, "red" })
				elseif tn == "blue" then
					blue = blue + 1
					table.insert(inside, { p, "blue" })
				end
			end
		end
	end
	return red, blue, inside
end

-- ===== 경기 진행 =====
local running = false

local function announce(state, extra)
	local payload = { phase = "capture", state = state }
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	send(payload)
end

-- 전장에 나와 있는 인원. 로비에 있는 사람은 안 센다.
local function deployedCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if not (_G.LobbyWant and _G.LobbyWant[p]) then
			n = n + 1
		end
	end
	return n
end

local function moveZone(first)
	local x, z, y = pickSpot(first)
	placeRing(x, z, y)
	setRingColor(WHITE, 0.35)
	announce("moved", { first = first and true or false })
end

local function checkWin()
	local T = team()
	if not T then
		return nil
	end
	local r, b = T.getScore()
	if r >= T.TARGET_SCORE then
		return "red"
	end
	if b >= T.TARGET_SCORE then
		return "blue"
	end
	return nil
end

local function matchLoop()
	while true do
		running = false
		setRingColor(WHITE, 1)

		-- ===== 전장에 사람이 나올 때까지 기다린다 =====
		-- 로비에 있는 사람은 안 센다. PLAY 를 눌러 나온 사람만 경기 인원이다.
		while deployedCount() < CFG.MIN_PLAYERS do
			announce("waiting", { need = CFG.MIN_PLAYERS })
			task.wait(1)
		end

		-- 새 판이니 점수부터 0으로
		local T0 = team()
		if T0 and T0.resetScore then
			T0.resetScore()
		end

		-- ===== 시작 전 카운트다운 =====
		for left = CFG.OPEN_DELAY, 1, -1 do
			announce("countdown", { left = left })
			task.wait(1)
		end

		moveZone(true)
		running = true

		local sinceMove = 0
		local elapsed = 0
		local aborted = false      -- 사람이 다 빠져서 접은 건지, 승부가 나서 끝난 건지
		while running do
			task.wait(CFG.TICK)
			sinceMove = sinceMove + CFG.TICK
			elapsed = elapsed + CFG.TICK

			-- 전장이 비면 판을 접고 대기로 돌아간다.
			-- 아무도 없는데 시간만 흐르고 점수가 쌓이면 안 된다.
			if deployedCount() < CFG.MIN_PLAYERS then
				running = false
				aborted = true
				setRingColor(WHITE, 1)
				announce("waiting", { need = CFG.MIN_PLAYERS })
				break
			end

			local red, blue, inside = countInside()
			local net = math.abs(red - blue)
			local owner = nil
			if net > 0 then
				owner = (red > blue) and "red" or "blue"
			end

			-- 색 갱신
			if red == 0 and blue == 0 then
				setRingColor(WHITE, 0.35)
			elseif red > 0 and blue > 0 then
				setRingSplit(red, blue, owner)
			else
				setRingColor(red > 0 and RED or BLUE, 0.2)
			end

			-- 점수
			local gain = 0
			if owner then
				gain = net * CFG.SCORE_PER_NET * CFG.TICK
				local T = team()
				if T then
					T.addScore(owner, gain)
				end
				-- 점령 중인 팀원은 궁극기가 앞당겨진다
				local C = combat()
				if C and T then
					for _, e in ipairs(inside) do
						if e[2] == owner then
							C.addUlt(e[1], T.ULT_GAIN_CAPTURE)
						end
					end
				end
			end

			announce("tick", {
				red = red,
				blue = blue,
				owner = owner,
				gain = gain,
				timeLeft = math.max(0, CFG.MATCH_TIME - elapsed),
			})

			-- 승리 판정 : 목표 점수를 먼저 찍거나, 제한시간이 끝나면 점수가 높은 쪽
			local winner = checkWin()
			if not winner and elapsed >= CFG.MATCH_TIME then
				local T = team()
				local r, b = T and T.getScore()
				r, b = r or 0, b or 0
				if r > b then
					winner = "red"
				elseif b > r then
					winner = "blue"
				else
					winner = "draw"
				end
			end

			if winner then
				running = false
				if winner == "draw" then
					setRingColor(WHITE, 0.1)
				else
					setRingColor(winner == "red" and RED or BLUE, 0.1)
				end
				announce("over", { winner = winner })
				break
			end

			-- 구역 이동
			if sinceMove >= CFG.MOVE_INTERVAL then
				sinceMove = 0
				moveZone(false)
			end
		end

		-- ===== 경기 종료 -> 재정비 =====
		-- 사람이 다 빠져서 접은 경우엔 재정비 없이 바로 대기로 돌아간다.
		if not aborted then
			for left = CFG.RESTART_DELAY, 1, -1 do
				announce("restart", { left = left })
				task.wait(1)
			end
		end
		local T = team()
		if T and T.resetScore then
			T.resetScore()
		end
	end
end

buildRing()

task.spawn(function()
	task.wait(6)      -- 맵과 스폰 스냅이 끝난 뒤에 시작한다
	matchLoop()
end)

print("[Capture] ready")
