-- 팀 배정 + 팀 스폰
--
-- ★ OVERDARE 에는 Teams 서비스가 없다 (docs 에 클래스만 있고 속성/메서드가 전부 비어 있음).
--   대신 Player.TeamColor(BrickColor) 와 SpawnLocation 의 Neutral/TeamColor 매칭은 정식 지원된다.
--   그래서 팀은 TeamColor 하나로 표현한다. 이 값은 클라이언트로 자동 복제되므로
--   UI 나 다른 시스템은 player.TeamColor 를 그냥 읽으면 된다. 별도 RemoteEvent 가 필요 없다.
--
-- 스폰은 SpawnLocation.Neutral = false 로 두고 TeamColor 를 맞춰두면 엔진이 알아서 갈라준다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ★ 2026-08-19 실측 : Player.TeamColor 는 클라이언트로 복제되지 않는다.
--   서버에서는 제대로 읽히는데(countTeams 가 정확히 셌다) 클라이언트에서는 "Grey" 로 나왔다.
--   그래서 팀을 명시적으로 내려준다. RemoteEvent 는 레벨에 박아둔 것을 쓴다
--   (런타임 생성은 RyunochiEvent 에서 한 번 크게 데였다 - 없으면 조용히 전부 죽는다).
local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)

local M = {}

-- 팀 색. BrickColor 이름은 레벨 파일의 스폰과 반드시 같아야 한다.
local RED_NAME = "Bright red"
local BLUE_NAME = "Bright blue"

local RED, BLUE
do
	local ok = pcall(function()
		RED = BrickColor.new(RED_NAME)
		BLUE = BrickColor.new(BLUE_NAME)
	end)
	if not ok or not RED or not BLUE then
		print("[Team] BrickColor.new 실패 - 팀 배정을 할 수 없다")
		return
	end
end

-- 스폰 이름. 레벨의 SpawnLocation 과 맞춰둔다.
local SPAWN_RED = "JSN_Spawn_Red"
local SPAWN_BLUE = "JSN_Spawn_Blue"

-- 팀별 점수. 점령/킬 시스템이 생기면 여기에 더한다.
-- 인원이 홀수일 때 "지고 있는 팀" 판정에 쓴다.
local score = { red = 0, blue = 0 }

-- ===== 승리 조건 / 궁극기 충전 =====
-- 다른 시스템이 참조할 수 있게 여기 모아둔다.
M.TARGET_SCORE = 300          -- 이 점수를 먼저 찍는 팀이 승리

-- 궁극기는 0%에서 시작해 ULT_FULL 초에 걸쳐 100% 가 된다.
-- 점수를 얻을 때마다 남은 시간이 줄어든다 (= 충전이 앞당겨진다).
M.ULT_FULL = 200              -- 기본 충전 시간(초). 150 은 너무 빨리 찼다 (2026-08-20)
M.ULT_GAIN_KILL = 2           -- 킬 1회당 앞당기는 초
M.ULT_GAIN_CAPTURE = 1        -- 점령 점수 1틱(1초)당 앞당기는 초
--   퍼센트로 환산하면 : 1초 = 100/150 = 0.667% / 킬 = 1.333% / 점령틱 = 0.667%
--   점령을 붙잡고 있으면 초당 1.333% 씩 차서 75초면 가득 찬다.

-- ★ 개인 EXP·레벨업은 폐기했다 (2026-08-19 확정).
--   킬 표시는 크로스헤어 밑의 "kill <이름>" 하나로 끝낸다. 점수는 팀 점수뿐이다.
--   EXP_KILL / EXP_CAPTURE 를 찾고 있다면 그건 없어진 것이다.

local function teamNameOf(player)
	local c = player.TeamColor
	if not c then
		return nil
	end
	if c.Name == RED_NAME then
		return "red"
	elseif c.Name == BLUE_NAME then
		return "blue"
	end
	return nil
end

local function countTeams()
	local r, b = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		local t = teamNameOf(p)
		if t == "red" then
			r = r + 1
		elseif t == "blue" then
			b = b + 1
		end
	end
	return r, b
end

local function findSpawn(name)
	local map = Workspace:FindFirstChild("JSN_Sangok")
	if map then
		local s = map:FindFirstChild(name, true)
		if s then
			return s
		end
	end
	return Workspace:FindFirstChild(name, true)
end

-- ★ 스폰을 바닥에 붙인다.
--   맵마다 지형 높이가 달라서 좌표를 손으로 맞추면 매번 뜨거나 묻힌다.
--   위에서 아래로 레이캐스트해서 실제 바닥에 얹는다. 새 맵을 넣어도 그대로 동작한다.
local function snapToGround(sp)
	if not sp then
		return
	end
	local ok, res = pcall(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		-- 스폰 자신과 캐릭터들은 바닥으로 치지 않는다
		local skip = { sp }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(skip, p.Character)
			end
		end
		rp.FilterDescendantsInstances = skip
		-- 스폰보다 30m 위에서 60m 아래로 쏜다
		local from = sp.Position + Vector3.new(0, 3000, 0)
		return Workspace:Raycast(from, Vector3.new(0, -6000, 0), rp)
	end)

	if not ok or not res then
		print("[Team] 바닥을 못 찾음 - 스폰 높이 그대로 둔다: " .. sp.Name)
		return
	end

	local half = sp.Size.Y / 2
	local before = sp.Position.Y
	pcall(function()
		sp.CFrame = CFrame.new(sp.Position.X, res.Position.Y + half, sp.Position.Z)
	end)
	print(string.format("[Team] %s 바닥에 붙임 : Y %.0f -> %.0f", sp.Name, before, sp.Position.Y))
end

-- ===== 스폰 흩뿌리기 =====
--
-- 엔진은 SpawnLocation 한 점에 그대로 떨군다. 그래서 두 명 이상이면 같은 자리에 겹쳐 나오고,
-- 서로 끼거나 한 번에 쓸려나간다. 나온 직후에 우리가 주변으로 흩어놓는다.
--
-- ★ 흩뿌린 뒤 CombatServer 에 알려야 한다.
--   그쪽은 "위치가 확 바뀌면 움직인 것" 으로 보고 스폰 무적을 8초에서 3초로 깎는데,
--   우리가 옮긴 것까지 움직인 걸로 세면 나오자마자 무적이 날아간다.
-- ★★ 확정 (2026-08-20 실측)
--   ODA 아바타의 "보이는 정면" = root 의 LookVector 그대로다. 뒤집을 필요가 없다.
--   즉 CFrame.new(위치, 목표) 만 쓰면 목표를 바라본다.
--   한동안 180도를 넣었다 뺐다 했는데, 양 팀이 동시에 반대를 보는 걸 보고 확정했다.
--   ("한쪽만 틀렸다" 면 방향 계산이 아니라 그 팀의 흩뿌리기가 실패한 것이다.)
--
--   같은 사실이 쿠나이 순간이동의 "적의 등 뒤" 계산에도 쓰인다 (ViewmodelController).
--   등 뒤 = -LookVector 쪽이다.
local SPAWN_FACE_FLIP = false

local SPAWN_SPREAD_MIN = 300     -- 스폰 지점에서 최소 이만큼 (cm)
local SPAWN_SPREAD_MAX = 1100    -- 최대 이만큼 안에 흩어놓는다 (11m)
local SPAWN_APART = 320          -- 다른 사람과 이만큼은 떨어뜨린다
local SPAWN_TRIES = 14

local function groundAt(x, z, ignore)
	local ok, res = pcall(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local skip = {}
		if ignore then
			table.insert(skip, ignore)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(skip, p.Character)
			end
		end
		rp.FilterDescendantsInstances = skip
		return Workspace:Raycast(Vector3.new(x, 9000, z), Vector3.new(0, -22000, 0), rp)
	end)
	if ok and res then
		return res.Position.Y
	end
	return nil
end

local function scatter(player, character)
	-- 로비에 있어야 하는 사람은 전장으로 흩뿌리지 않는다 (LobbyServer 가 자리를 잡는다)
	if _G.LobbyWant and _G.LobbyWant[player] then
		return
	end
	local sp = player.RespawnLocation
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("Torso", 5)
	if not (sp and root) then
		return
	end

	for _ = 1, SPAWN_TRIES do
		local th = math.random() * math.pi * 2
		local r = SPAWN_SPREAD_MIN + math.random() * (SPAWN_SPREAD_MAX - SPAWN_SPREAD_MIN)
		local x = sp.Position.X + math.cos(th) * r
		local z = sp.Position.Z + math.sin(th) * r

		-- 남과 겹치는 자리는 버린다
		local clear = true
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Character then
				local orr = other.Character:FindFirstChild("HumanoidRootPart")
					or other.Character:FindFirstChild("Torso")
				if orr then
					local dx, dz = orr.Position.X - x, orr.Position.Z - z
					if (dx * dx + dz * dz) < (SPAWN_APART * SPAWN_APART) then
						clear = false
						break
					end
				end
			end
		end

		if clear then
			local y = groundAt(x, z, character)
			if y then
				-- ★ 바라보는 방향은 상대 스폰 쪽으로 맞춘다.
				--   레드 스폰 발판이 뒤(절벽)를 향하고 있어서, 나오자마자 아무것도 안 보였다.
				--   발판 방향에 기대지 않고 여기서 직접 잡는 게 맵을 바꿔도 안전하다.
				local foe = findSpawn((teamNameOf(player) == "red") and SPAWN_BLUE or SPAWN_RED)
				local look = foe and foe.Position or Vector3.new(-60053, 0, -130)   -- 없으면 맵 중앙
				pcall(function()
					-- 수평만 본다. 위아래로 기울면 안 된다
					local cf = CFrame.new(
						Vector3.new(x, y + 120, z),
						Vector3.new(look.X, y + 120, look.Z))
					if SPAWN_FACE_FLIP then
						cf = cf * CFrame.Angles(0, math.pi, 0)
					end
					root.CFrame = cf
				end)
				pcall(function()
					local C = _G.CombatServer
					if C and C.resetSpawnTimer then
						C.resetSpawnTimer(player)
					end
				end)
				return
			end
		end
	end
end

-- 로비에서 PLAY 를 눌렀을 때 LobbyServer 가 부른다.
-- 스폰 무적 타이머까지 여기서 같이 잡아주므로 밖에서 직접 옮기지 마라.
function M.placeAtSpawn(player)
	local ch = player and player.Character
	if ch then
		scatter(player, ch)
	end
end

-- 어느 팀에 넣을지 정한다.
--   1) 인원이 적은 쪽
--   2) 같으면 지고 있는 쪽 (기획서: 홀수 인원은 지고 있는 팀에 한 명 더)
--   3) 그래도 같으면 들어온 순서대로 (레드 먼저)
local function pickTeam()
	local r, b = countTeams()
	if r < b then
		return "red"
	elseif b < r then
		return "blue"
	end
	if score.red < score.blue then
		return "red"
	elseif score.blue < score.red then
		return "blue"
	end
	return (r + b) % 2 == 0 and "red" or "blue"
end

local function assign(player, teamName)
	local col = (teamName == "red") and RED or BLUE
	local spawnName = (teamName == "red") and SPAWN_RED or SPAWN_BLUE

	pcall(function()
		player.TeamColor = col
	end)

	-- RespawnLocation 은 Workspace 안의 SpawnLocation 이어야 한다 (docs).
	local sp = findSpawn(spawnName)
	if sp then
		pcall(function()
			player.RespawnLocation = sp
		end)
	else
		print("[Team] 스폰을 못 찾음: " .. spawnName)
	end

	local r, b = countTeams()
	print(string.format("[Team] %s -> %s (레드 %d / 블루 %d)", player.Name, teamName, r, b))
end

-- 전원의 팀을 모든 클라이언트에 뿌린다.
-- Instance 키를 가진 테이블은 직렬화가 미덥지 않아 배열로 보낸다.
local function broadcastTeams()
	if not teamEvent then
		return
	end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local t = teamNameOf(p)
		if t then
			table.insert(list, { p, t })
		end
	end
	pcall(function()
		teamEvent:FireAllClients(list)
	end)
end

-- 팀 점수를 클라이언트로 보낸다 (HUD 상단 표시용).
-- ★ 팀 목록과 같은 이벤트를 쓰므로 phase 로 구분한다.
--   받는 쪽(FriendlyHighlight)은 phase 가 붙은 건 무시하게 해뒀다.
--   안 그러면 점수가 올 때마다 팀 목록을 빈 것으로 덮어써서 아군 마커가 사라진다.
local function broadcastScore()
	if not teamEvent then
		return
	end
	pcall(function()
		-- target 도 같이 보낸다. HUD 가 "120 / 300" 을 그리려면 목표 점수를 알아야 하는데
		-- 클라이언트에 숫자를 또 박아두면 여기서 바꿔도 화면은 안 바뀐다.
		teamEvent:FireAllClients({
			phase = "score",
			red = score.red,
			blue = score.blue,
			target = M.TARGET_SCORE,
		})
	end)
end

-- ===== 외부에서 쓰는 것 =====

-- 다른 시스템(점령/킬)이 점수를 올릴 때 부른다. 팀 균형 판정에 쓰인다.
function M.addScore(teamName, amount)
	if score[teamName] then
		score[teamName] = score[teamName] + amount
		broadcastScore()
	end
end

-- 새로 들어온 사람도 현재 점수를 봐야 한다.
function M.pushScore()
	broadcastScore()
end

function M.getScore()
	return score.red, score.blue
end

-- 경기가 끝나고 다음 판을 시작할 때 부른다 (CaptureServer).
function M.resetScore()
	score.red = 0
	score.blue = 0
	broadcastScore()
end

-- 같은 팀인지. 팀킬 방지에 쓴다.
function M.sameTeam(a, b)
	if not (a and b) then
		return false
	end
	local ta, tb = teamNameOf(a), teamNameOf(b)
	return ta ~= nil and ta == tb
end

M.teamNameOf = teamNameOf

_G.TeamServer = M      -- 아직 모듈 분리 전이라 전역으로 노출한다

-- ===== 배정 =====

local function hook(player)
	if not teamNameOf(player) then
		assign(player, pickTeam())
	end
	broadcastTeams()

	-- 스폰할 때마다 주변으로 흩어놓는다.
	-- 엔진이 캐릭터를 스폰 지점에 앉히는 게 먼저라 한 박자 늦춰야 우리 위치가 이긴다.
	player.CharacterAdded:Connect(function(character)
		task.delay(0.15, function()
			if player.Character == character then
				scatter(player, character)
			end
		end)
	end)
	if player.Character then
		task.delay(0.15, function()
			scatter(player, player.Character)
		end)
	end
end

Players.PlayerRemoving:Connect(function()
	task.defer(broadcastTeams)
end)

-- 클라이언트 스크립트가 RemoteEvent 연결을 마치기 전에 쏘면 놓친다.
-- 초반 10초 동안 1초마다 다시 뿌려서 늦게 붙은 클라이언트도 받게 한다.
task.spawn(function()
	for _ = 1, 10 do
		task.wait(1)
		broadcastTeams()
		broadcastScore()      -- 늦게 붙은 HUD 도 현재 점수를 받아야 한다
	end
end)

-- 스폰 발판을 안 보이게 하고 통과되게 만든다.
--
-- ★ CanTouch 는 반드시 켜둔 채로 둔다. 끄면 스폰 감지가 안 된다 (맵 최적화 때 확인).
-- ★ CanCollide 를 끄는 이유 : 발판이 딱딱하면 그 위에 나온 캐릭터가 발판 옆구리에 껴서
--   점프하지 않으면 못 빠져나오는 일이 생긴다.
local function hideSpawn(sp)
	if not sp then
		return
	end
	pcall(function()
		sp.Transparency = 1
	end)
	pcall(function()
		sp.CanCollide = false
	end)
	pcall(function()
		sp.CastShadow = false
	end)
end

-- 발판 자체도 상대 스폰 쪽을 보게 돌려둔다.
-- 흩뿌리기가 어떤 이유로 실패해도 최소한 발판 방향은 맞게 남는다.
local function faceSpawn(sp, foe)
	if not (sp and foe) then
		return
	end
	pcall(function()
		local cf = CFrame.new(
			sp.Position,
			Vector3.new(foe.Position.X, sp.Position.Y, foe.Position.Z))
		if SPAWN_FACE_FLIP then
			cf = cf * CFrame.Angles(0, math.pi, 0)
		end
		sp.CFrame = cf
	end)
end

-- 스폰을 바닥에 붙인다. 맵 지오메트리가 다 올라온 뒤에 해야 해서 한 박자 늦춘다.
task.spawn(function()
	task.wait(1)
	local red = findSpawn(SPAWN_RED)
	local blue = findSpawn(SPAWN_BLUE)
	snapToGround(red)
	snapToGround(blue)
	hideSpawn(red)
	hideSpawn(blue)
	faceSpawn(red, blue)
	faceSpawn(blue, red)
end)

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

-- 나갈 때 균형이 깨지므로 다음 입장자가 알아서 맞춰 들어간다 (countTeams 가 실시간이라 별도 처리 불필요)

print("[TeamServer] ready")
