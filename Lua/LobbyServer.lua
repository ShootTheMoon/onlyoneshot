-- 로비
--
-- 접속하면 전장이 아니라 로비 공간에서 시작한다. PLAY 를 눌러야 전장으로 나간다.
-- 죽으면 킬캠 5초 뒤 다시 로비로 돌아온다 (기획서). 전적은 그대로 보존된다.
--
-- ★ 로비 공간은 맵에서 아주 멀리 떨어진 허공에 만든다.
--   맵 안에 두면 궁극기 광역이나 점령 판정이 로비까지 닿는다.
--   맵 범위가 X -73k~-47k / Z -14k~12k 라, 원점 위 8000 은 어디와도 안 겹친다.
--
-- ★ RemoteEvent 를 새로 만들지 않는다.
--   런타임 생성 RemoteEvent 를 클라이언트가 못 찾아 이펙트가 통째로 죽은 사고가 있었다.
--   레벨에 박혀 있는 TeamEvent 에 phase 를 붙여 같이 쓴다.
--     서버 -> 클라 : { phase = "lobby", state = "in"/"out", pick = "japan" }
--     클라 -> 서버 : { phase = "lobby_play" } / { phase = "lobby_pick", character = "korea" }

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOBBY = {
	POS = Vector3.new(0, 8000, 0),
	ROOM = Vector3.new(2600, 950, 3000),   -- 격납고 안쪽 크기 (가로, 높이, 세로)
	WALL_T = 40,
	CASE_AT = Vector3.new(0, 0, 420),      -- 원점 기준 진열장 자리
	STAND_AT = Vector3.new(0, 0, -620),    -- 플레이어가 서는 자리 (카메라 뒤라 안 보인다)
	STAND_UP = 140,          -- 바닥 위로 캐릭터를 얼마나 띄워 세울지 (cm)
	ENTER_DELAY = 0.28,      -- CharacterAdded 후 이만큼 뒤에 옮긴다
}

-- 격납고 색. 어두운 금속 + 나무 + 놋쇠. 옛날 무기를 두는 창고 느낌으로 잡았다.
local MAT = {
	-- ★ 전체적으로 어둡게 잡는다. 창고가 밝으면 진열장이 안 산다.
	FLOOR = Color3.fromRGB(38, 37, 35),
	WALL = Color3.fromRGB(46, 45, 43),
	TRIM = Color3.fromRGB(30, 29, 28),
	DARK = Color3.fromRGB(20, 19, 18),      -- 진열장 뒤판. 무기 뒤가 어두워야 형태가 보인다
	WOOD = Color3.fromRGB(64, 45, 30),
	BRASS = Color3.fromRGB(120, 96, 48),
	LIGHT = Color3.fromRGB(255, 226, 170),  -- 따뜻한 등불색. 흰색이면 너무 쨍하다
	GLASS = Color3.fromRGB(120, 140, 155),
}

-- 고를 수 있는 캐릭터. 지금 실제로 되는 건 japan 뿐이다.
local CHARACTERS = { "japan", "korea", "maxico" }
local DEFAULT_PICK = "japan"

-- ★ 다른 스크립트가 보는 상태.
--   true = 이 사람은 로비에 있어야 한다.
--   TeamServer 는 이게 켜져 있으면 전장 스폰으로 흩뿌리지 않고,
--   CombatServer 는 피격 판정에서 통째로 제외한다.
_G.LobbyWant = _G.LobbyWant or {}
_G.LobbyPick = _G.LobbyPick or {}

local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)

-- ===== 격납고 =====
--
-- 무기 창고처럼 꾸민다. 가운데에 진열장이 하나 있고, 카메라가 그 앞에 고정된다.
-- 진열장 안의 무기는 클라이언트가 채운다 (사람마다 고른 나라가 다르니 서버가 하면 겹친다).
--
-- ★ 파츠 수를 아끼려고 벽·바닥만 큼직하게 두고 장식은 최소로 했다.
--   맵 최적화로 인스턴스를 줄여놨는데 로비로 도로 늘리면 의미가 없다.
-- ★★ 직접 만든 격납고를 쓰는 법
--
--   Workspace 에 "LobbySpace" 라는 이름의 Model 을 만들어 그 안에 방을 지어라.
--   그게 있으면 이 스크립트는 방을 만들지 않고 네 것을 그대로 쓴다.
--
--   그 안에 아래 이름의 Part 를 놓아두면 자리를 잡아준다. 안 놓으면 기본값으로 간다.
--     Lobby_Stand    플레이어가 서는 자리 (아바타는 안 보이니 아무 데나 카메라 뒤로)
--     Lobby_Camera   카메라가 놓이는 자리
--     Lobby_Weapon   진열될 무기가 뜨는 자리
--
--   마커는 크기·색 아무래도 상관없다. 서버가 알아서 안 보이게 하고 통과되게 만든다.
--   방을 통째로 옮겨도 마커만 같이 옮기면 코드는 안 건드려도 된다.
--     Lobby_Weapon_L      왼쪽 칼이 놓일 자리
--     Lobby_Weapon_R      오른쪽 칼
--     Lobby_Weapon_Kunai  쿠나이
--
--   ★ 무기 마커는 위치뿐 아니라 "회전" 과 "크기" 까지 그대로 쓴다.
--     Studio 에서 마커를 돌려놓으면 칼도 그렇게 눕고, 마커를 늘이면 칼도 그만큼 길어진다.
--     원본(Wakizashi_Viewmodel_Split)을 건드리면 1인칭 뷰모델과 3인칭 손의 칼까지
--     같이 바뀌니, 진열 자세는 반드시 이 마커로 잡아라.
local MARKER_NAMES = { "Lobby_Stand", "Lobby_Camera", "Lobby_Weapon" }
local WEAPON_MARKS = { L = "Lobby_Weapon_L", R = "Lobby_Weapon_R", K = "Lobby_Weapon_Kunai" }

local marks = {}          -- [이름] = Vector3
local wmarks = {}         -- [L/R/K] = { cf = CFrame, size = Vector3 }


-- 직접 만든 격납고가 있으면 그걸 쓴다. 마커도 여기서 읽는다.
local function adoptLobby()
	-- LobbySpace 모델이 있으면 그 안에서, 없으면 Workspace 전체에서 마커를 찾는다.
	-- 모델로 묶지 않고 파츠만 놓아도 되게 해두는 게 편집하기 쉽다.
	local space = Workspace:FindFirstChild("LobbySpace") or Workspace

	local found = 0
	for _, name in ipairs(MARKER_NAMES) do
		local m = space:FindFirstChild(name, true)
		if m and m:IsA("BasePart") then
			found = found + 1
			marks[name] = m.Position
			-- 마커는 보이면 안 되고 몸에 걸려도 안 된다
			pcall(function()
				m.Transparency = 1
				m.CanCollide = false
				m.CanTouch = false
				m.CastShadow = false
			end)
		end
	end

	-- 무기 마커는 위치·회전·크기를 통째로 쓴다
	for key, name in pairs(WEAPON_MARKS) do
		local m = space:FindFirstChild(name, true)
		if m and m:IsA("BasePart") then
			found = found + 1
			wmarks[key] = { cf = m.CFrame, size = m.Size }
			pcall(function()
				m.Transparency = 1
				m.CanCollide = false
				m.CanTouch = false
				m.CastShadow = false
			end)
		end
	end

	if found == 0 then
		return false      -- 마커가 하나도 없다. 임시 방을 만들어 쓴다
	end

	print(string.format("[Lobby] 레벨의 격납고 사용 : stand=%s camera=%s weapon=%s",
		tostring(marks.Lobby_Stand ~= nil),
		tostring(marks.Lobby_Camera ~= nil),
		tostring(marks.Lobby_Weapon ~= nil)))
	return true
end

-- ★★ 격납고는 이제 레벨에 실제 파츠로 지어져 있다 (2026-08-20).
--   예전엔 이 스크립트가 실행할 때 방을 만들었는데, 그러면 Studio 편집 화면에 아무것도 안 보여서
--   무기 배치를 눈으로 보면서 못 잡았다. 그래서 Workspace 에 직접 박았다.
--
--   Workspace 의 Lobby_* 파츠들이 그 방이다. 자유롭게 옮기고 고치고 지워도 된다.
--   이 스크립트가 하는 일은 마커(Lobby_Stand / Lobby_Camera / Lobby_Weapon 과
--   Lobby_Weapon_L / _R / _Kunai)의 자리를 읽어 카메라와 진열 위치를 잡는 것뿐이다.
local function buildLobby()
	adoptLobby()
	return nil
end

local function tell(player, state)
	if not teamEvent then
		return
	end
	pcall(function()
		teamEvent:FireClient(player, {
			phase = "lobby",
			state = state,
			pick = _G.LobbyPick[player] or DEFAULT_PICK,
			characters = CHARACTERS,
			-- 카메라와 진열 위치의 기준점. 클라이언트에 좌표를 또 박아두면
			-- 여기서 방을 옮겼을 때 화면만 딴 데를 본다.
			origin = LOBBY.POS,
			-- 직접 만든 방의 마커가 있으면 그걸, 없으면 자동 생성 방의 기본 자리를 보낸다
			casePos = marks.Lobby_Weapon or (LOBBY.POS + LOBBY.CASE_AT),
			camPos = marks.Lobby_Camera,
			weaponMarks = wmarks,      -- 있으면 클라이언트가 이 자세 그대로 진열한다
		})
	end)
end

local function freeze(player, on)
	_G.MovementFreeze = _G.MovementFreeze or {}
	_G.MovementFreeze[player] = on and true or nil
end

-- 로비로 보낸다.
local function toLobby(player)
	_G.LobbyWant[player] = true

	local ch = player.Character
	local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
	if root then
		pcall(function()
			-- 카메라 뒤쪽에 세운다. 아바타는 화면에 안 나온다 (진열장만 보여준다).
			local at = marks.Lobby_Stand
				or (LOBBY.POS + LOBBY.STAND_AT + Vector3.new(0, LOBBY.STAND_UP, 0))
			root.CFrame = CFrame.new(at, at + Vector3.new(0, 0, 1000))
		end)
	end

	-- 로비에서는 걸어다니지 않는다. 발판 밖으로 떨어지면 곤란하다.
	freeze(player, true)
	tell(player, "in")
end

-- 전장으로 내보낸다.
local function toBattle(player)
	_G.LobbyWant[player] = nil
	freeze(player, false)

	-- 팀 스폰 주변으로 흩뿌리는 건 TeamServer 가 한다 (스폰 무적 타이머까지 같이 잡아준다)
	local ok = false
	pcall(function()
		local T = _G.TeamServer
		if T and T.placeAtSpawn then
			T.placeAtSpawn(player)
			ok = true
		end
	end)
	if not ok then
		print("[Lobby] TeamServer.placeAtSpawn 을 못 찾음 - 전장 스폰 위치를 못 잡는다")
	end

	tell(player, "out")
end

-- ===== 외부에서 쓰는 것 =====
_G.LobbyServer = {
	-- CombatServer 가 죽은 사람을 되살릴 때 부른다.
	-- 다음 CharacterAdded 에서 전장이 아니라 로비로 가게 표시해둔다.
	onDeath = function(player)
		_G.LobbyWant[player] = true
	end,
	toLobby = toLobby,
	toBattle = toBattle,
}

-- ===== 플레이어 수명 =====
local function hook(player)
	if _G.LobbyPick[player] == nil then
		_G.LobbyPick[player] = DEFAULT_PICK
	end
	_G.LobbyWant[player] = true      -- 접속하면 무조건 로비부터

	player.CharacterAdded:Connect(function(character)
		if not _G.LobbyWant[player] then
			return
		end
		-- ★ 새 몸이 전장 스폰에 서 있는 순간을 한 프레임도 보여주면 안 된다.
		--   예전엔 0.28초 뒤에 옮겼는데, 죽고 되살아날 때 그 사이가 그대로 보여서
		--   "맵에 이미 부활했는데 로비 UI 만 덮어놓은" 것처럼 됐다 (2026-08-21).
		--   TeamServer.scatter 는 이미 로비 대기자를 건너뛰므로 늦출 이유가 전혀 없었다.
		freeze(player, true)

		-- HumanoidRootPart 는 CharacterAdded 시점에 아직 없을 수 있다. 붙는 즉시 옮긴다.
		for _ = 1, 60 do
			if player.Character ~= character or not _G.LobbyWant[player] then
				return
			end
			if character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") then
				break
			end
			task.wait()
		end
		if player.Character ~= character or not _G.LobbyWant[player] then
			return
		end
		toLobby(player)

		-- 엔진이나 다른 스크립트가 뒤늦게 스폰 자리로 되돌리는 경우가 있어 몇 번 더 잡는다
		for _, d in ipairs({ 0.1, 0.3, 0.6 }) do
			task.delay(d, function()
				if player.Character == character and _G.LobbyWant[player] then
					toLobby(player)
				end
			end)
		end
	end)

	if player.Character then
		task.delay(LOBBY.ENTER_DELAY, function()
			if _G.LobbyWant[player] then
				toLobby(player)
			end
		end)
	end
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

Players.PlayerRemoving:Connect(function(player)
	_G.LobbyWant[player] = nil
	_G.LobbyPick[player] = nil
	if _G.MovementFreeze then
		_G.MovementFreeze[player] = nil
	end
end)

-- ===== 클라이언트 요청 =====
if teamEvent then
	teamEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" then
			return
		end

		if payload.phase == "lobby_play" then
			if _G.LobbyWant[player] then
				toBattle(player)
			end

		elseif payload.phase == "lobby_pick" then
			local pick = payload.character
			for _, name in ipairs(CHARACTERS) do
				if pick == name then
					_G.LobbyPick[player] = pick
					tell(player, _G.LobbyWant[player] and "in" or "out")
					return
				end
			end
		end
	end)
else
	print("[Lobby] TeamEvent 를 못 찾음 - 로비가 동작하지 않는다")
end

buildLobby()

-- ★ 클라이언트 스크립트가 TeamEvent 연결을 마치기 전에 쏘면 그 신호를 놓친다.
--   놓치면 로비 화면도 안 뜨고 카메라 고정도 안 걸려서, 1인칭 그대로 격납고 안에 서 있게 된다.
--   초반 12초 동안 1초마다 다시 보내고 자리도 다시 잡아준다.
--   (TeamServer 가 팀 목록을 다시 뿌리는 것과 같은 수법)
task.spawn(function()
	for _ = 1, 12 do
		task.wait(1)
		for _, p in ipairs(Players:GetPlayers()) do
			if _G.LobbyWant[p] then
				toLobby(p)
			end
		end
	end
end)

print("[Lobby] ready")
