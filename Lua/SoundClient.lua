-- 클라이언트 사운드 재생기 (2026-08-25)
--
-- 하는 일
--   1) SoundDB 카탈로그를 읽어 이름으로 소리를 튼다        _G.Sfx("sword_hit", pos)
--   2) 이미 날아오고 있는 CombatEvent 를 듣고 phase 를 소리로 옮긴다
--      → 전투·HUD 스크립트를 한 줄도 안 고친다
--   3) Sound 인스턴스를 풀로 돌려쓰고, 보이스 예산을 넘지 않게 자른다
--
-- ★ 왜 예산을 자르는가
--   엔진 오디오 믹서의 동시 보이스 상한이 32 다 (Studio 로그에서 확인).
--   10인 PvP 에서 발소리·칼질이 겹치면 금방 닿는데, 상한을 넘으면 엔진이
--   무엇을 버릴지 우리가 못 고른다. 우리가 먼저 잘라야 "중요한 소리가 사라지는" 일이 없다.
--   그래서 24 로 잡고, 예산이 없으면 새 소리를 조용히 버린다.
--
-- ★ 3D 인가 2D 인가는 카탈로그의 max 로 정한다.
--   max == 0 이면 거리 감쇠 없는 2D (내 화면 피드백 : 킬·점수·UI).
--   max > 0 이면 그 자리에서 나는 3D. 3D 는 보이지 않는 Part 를 그 자리로 옮겨 거기 물린다.
--   (이 엔진에는 SoundService 가 없다. Sound 는 부모가 Part 여야 위치를 갖는다.)
--
-- ★ id 가 비어 있으면 그냥 넘어간다. 소리 없이도 게임은 그대로 돈다.
--   무엇이 비었는지는 10초 뒤에 한 번 모아 찍는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local okDB, DB = pcall(function()
	return require(ReplicatedStorage:WaitForChild("SoundDB", 10))
end)
if not okDB or type(DB) ~= "table" then
	warn("[Sound] SoundDB 를 못 읽었다. 사운드 없이 계속한다.")
	return
end

local BUDGET      = DB.VOICE_BUDGET or 24
local EMITTERS    = 12      -- 3D 자리표 Part 개수. 동시에 다른 자리에서 날 수 있는 소리 수다
local MAX_LEN     = 12      -- Ended 를 못 받았을 때 강제로 회수하는 시간(초)

---------------------------------------------------------------- 그룹
local groups = {}
for gname, gvol in pairs(DB.GROUPS or {}) do
	local existing = ReplicatedStorage:FindFirstChild("SG_" .. gname)
	if existing and existing:IsA("SoundGroup") then
		groups[gname] = existing
	else
		-- 레벨에 없으면 클라에서 만들어 쓴다 (없어도 소리는 나야 한다)
		local sg = Instance.new("SoundGroup")
		sg.Name = "SG_" .. gname
		sg.Volume = gvol
		sg.Parent = ReplicatedStorage
		groups[gname] = sg
	end
end

---------------------------------------------------------------- 풀
local poolRoot = Instance.new("Model")
poolRoot.Name = "SoundPool_Local"
poolRoot.Parent = Workspace

local emitters, emitterAt = {}, 1
for i = 1, EMITTERS do
	local p = Instance.new("Part")
	p.Name = "SndEmit_" .. i
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Transparency = 1
	p.CastShadow = false
	p.Size = Vector3.new(20, 20, 20)
	p.Parent = poolRoot
	emitters[i] = p
end

local twoD = Instance.new("Model")
twoD.Name = "SoundPool_2D"
twoD.Parent = poolRoot

local free, live = {}, 0

local function acquire()
	local s = table.remove(free)
	if s then return s end
	local ok, made = pcall(function() return Instance.new("Sound") end)
	if not ok then return nil end
	return made
end

local function release(s)
	if not s then return end
	pcall(function()
		s:Stop()
		s.SoundId = ""
		s.Parent = nil
	end)
	live = math.max(0, live - 1)
	if #free < 40 then free[#free + 1] = s end
end

---------------------------------------------------------------- 재생
local lastAt = {}      -- 이름별 마지막 재생 시각 (쿨다운)
local missing = {}     -- id 가 빈 채로 요청된 이름들
local dropped = 0      -- 예산이 없어 버린 횟수

local function camPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.new()
end

local function play(name, at)
	local d = DB.SOUNDS[name]
	if not d then
		missing["?" .. tostring(name)] = true
		return
	end
	if d.id == nil or d.id == "" then
		missing[name] = true
		return
	end

	local now = os.clock()
	local cd = d.cd or 0
	if cd > 0 and lastAt[name] and (now - lastAt[name]) < cd then return end

	local is3D = (d.max or 0) > 0

	-- 거리 컷 : 어차피 안 들릴 소리에 보이스를 쓰지 않는다
	local pos
	if is3D and at then
		if typeof(at) == "Vector3" then
			pos = at
		elseif typeof(at) == "Instance" then
			local ok, v = pcall(function()
				if at:IsA("BasePart") then return at.Position end
				if at:IsA("Model") then return at:GetPivot().Position end
				return nil
			end)
			pos = ok and v or nil
		end
		if pos and (pos - camPos()).Magnitude > d.max then return end
	end
	if is3D and not pos then is3D = false end     -- 자리를 모르면 2D 로 낸다

	if live >= BUDGET then
		dropped = dropped + 1
		return
	end

	local s = acquire()
	if not s then return end

	local okSet = pcall(function()
		s.SoundId = d.id
		s.Volume = d.vol or 1
		s.Looped = d.loop == true
		s.PlaybackSpeed = 1 + ((d.pitch or 0) > 0 and (math.random() * 2 - 1) * d.pitch or 0)
		if is3D then
			s.RollOffMinDistance = d.min or 100
			s.RollOffMaxDistance = d.max
		end
		local g = groups[d.group or "SFX"]
		if g then s.SoundGroup = g end
	end)
	if not okSet then release(s); return end

	if is3D then
		local em = emitters[emitterAt]
		emitterAt = emitterAt % EMITTERS + 1
		pcall(function() em.CFrame = CFrame.new(pos) end)
		s.Parent = em
	else
		s.Parent = twoD
	end

	lastAt[name] = now
	live = live + 1

	local done = false
	local conn
	conn = s.Ended:Connect(function()
		if done then return end
		done = true
		if conn then conn:Disconnect() end
		release(s)
	end)

	-- Ended 를 못 받는 경우(로드 실패 등)가 있어 반드시 보험을 둔다.
	-- 이게 없으면 풀이 마르고 그때부터 아무 소리도 안 난다.
	if not s.Looped then
		task.delay(MAX_LEN, function()
			if done then return end
			done = true
			if conn then conn:Disconnect() end
			release(s)
		end)
	end

	pcall(function() s:Play() end)
	return s
end

---------------------------------------------------------------- 배경음 (풀 밖에서 따로 산다)
local bgm, bgmName
local function setBgm(name)
	if bgmName == name then return end
	bgmName = name
	if bgm then pcall(function() bgm:Stop(); bgm:Destroy() end); bgm = nil end
	local d = name and DB.SOUNDS[name]
	if not d or d.id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = d.id
	s.Volume = d.vol or 0.3
	s.Looped = true
	local g = groups[d.group or "Music"]
	if g then s.SoundGroup = g end
	s.Parent = twoD
	pcall(function() s:Play() end)
	bgm = s
end

---------------------------------------------------------------- 바깥에서 부르는 문
_G.Sfx = play
_G.SfxBgm = setBgm

---------------------------------------------------------------- 이미 있는 이벤트에 얹기
local combatEvent = ReplicatedStorage:FindFirstChild("CombatEvent")
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		local name = DB.PHASE_TO_SOUND[payload.phase]
		if not name then return end

		-- 자리 정하기 : 누가 관련됐는지 알면 그 사람 자리에서 낸다
		local who = payload.who or payload.victim or payload.target
		local at
		if typeof(who) == "Instance" and who:IsA("Player") then
			local ch = who.Character
			at = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
		elseif typeof(who) == "Instance" then
			at = who
		elseif typeof(payload.pos) == "Vector3" then
			at = payload.pos
		end
		play(name, at)
	end)
end

-- 서버가 직접 부르는 문 (SoundServer 의 SfxAll / SfxTo / SfxNear)
local soundEvent = ReplicatedStorage:FindFirstChild("SoundEvent")
if soundEvent then
	soundEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or not payload.name then return end
		play(payload.name, payload.pos)
	end)
end

---------------------------------------------------------------- 비어 있는 슬롯 보고
task.delay(10, function()
	local filled, total = 0, 0
	for _, d in pairs(DB.SOUNDS) do
		total = total + 1
		if d.id and d.id ~= "" then filled = filled + 1 end
	end
	local names = {}
	for k in pairs(missing) do names[#names + 1] = k end
	table.sort(names)
	print(string.format("[Sound] 카탈로그 %d칸 중 %d칸 채워짐. 보이스예산 %d", total, filled, BUDGET))
	if #names > 0 then
		print("[Sound] 이번에 불렸는데 비어 있던 슬롯 : " .. table.concat(names, ", "))
	end
	if filled == 0 then
		print("[Sound] 아직 id 가 하나도 없다. Lua/SoundDB.lua 의 id 를 ovdrassetid://<contentId> 로 채워라.")
	end
end)

print("[Sound] SoundClient ready")
