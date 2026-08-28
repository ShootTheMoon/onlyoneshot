-- 패링 텔레그래프(눈 별빛) + 기절 표시(머리 위 별 링)
--
-- 기획서 :
--   공격에는 시전 딜레이가 있고, 그 짧은 구간에 공격자의 눈에서 흰 별빛이 반짝인다.
--   그 타이밍에 block 을 누르면 패링. 패링당한 근접 캐릭터는 0.5초 굳고,
--   머리 위에 기절 별 링이 돈다 (때린 쪽이 뭐가 일어났는지 알아야 하니까).
--
-- ★ 화면 좌표로 그린다. Camera:WorldToViewportPoint 가 이 프로젝트에서 검증된 방법이고
--   (FriendlyHighlight 의 아군 점이 같은 방식), 지형에 가려도 보여야 하는 표시라
--   3D 파츠를 쓰지 않는다. 기획서도 "콜옵 스나이퍼 글린트처럼 멀리서도 잘 보여야 한다" 다.
--
-- ★ Rotation 을 쓰지 않는다. 이 엔진 문서에 GuiObject.Rotation 이 없다.
--   별은 십자 막대 두 개로 그린다 (크로스헤어 괄호·히트마크와 같은 방법).
--
-- ★ 카메라 뒤의 대상도 WorldToViewportPoint 는 좌표를 준다. 깊이(Z)가 음수면
--   좌우 반전된 유령이 화면에 찍힌다. onScreen 만 믿지 말고 Z 를 직접 걸러야 한다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local CFG = {
	GLINT_BAR = 30,        -- 눈 별빛 십자 막대 길이 (px)
	GLINT_THICK = 3,
	GLINT_CORE = 8,        -- 가운데 사각형
	-- ★ 높이 조정. Head 파츠의 중심이 기준이라 0 이면 얼굴 한가운데다.
	--   처음에 55 / 130 으로 뒀더니 캐릭터보다 한참 위에 떠 있었다 (2026-08-20).
	GLINT_RISE = 0,        -- 눈 별빛. Head 중심 = 대략 눈높이다
	GLINT_MIN = 0.45,      -- 멀어도 이보다 작아지진 않는다 (글린트는 멀리서 보여야 한다)

	STAR_N = 5,            -- 기절 링을 도는 별 개수
	STAR_BAR = 13,
	STAR_THICK = 2,
	STAR_RX = 38,          -- 링의 가로 반지름 (px)
	STAR_RY = 12,          -- 세로 반지름. 납작해야 머리 위를 도는 것처럼 보인다
	STAR_RISE = 55,        -- 기절 별 링. 정수리 바로 위에 얹히는 높이 (cm)
	STAR_SPEED = 3.2,      -- 도는 속도 (rad/s)

	REF_DIST = 3000,       -- 이 거리에서 크기 1배 (cm)
}

local gui = Instance.new("ScreenGui")
gui.Name = "ParryFX"
gui.Parent = playerGui

local function noBorder(f)
	pcall(function()
		f.BorderPixelSize = 0
	end)
	pcall(function()
		f.BorderSizePixel = 0
	end)
end

-- 별 하나 = 십자 막대 2개 + 가운데 사각형 3장
local function makeStar(bar, thick, core, color, zindex)
	local parts = {}
	local defs = {
		{ thick, bar },        -- 세로
		{ bar, thick },        -- 가로
		{ core, core },        -- 가운데
	}
	for i, d in ipairs(defs) do
		local f = Instance.new("Frame")
		f.Name = "Star" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.new(0, d[1], 0, d[2])
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.Visible = false
		f.ZIndex = zindex
		noBorder(f)
		f.Parent = gui
		parts[i] = { frame = f, w = d[1], h = d[2] }
	end
	return parts
end

local function hideStar(parts)
	for _, p in ipairs(parts) do
		if p.frame.Visible then
			p.frame.Visible = false
		end
	end
end

-- x, y : 화면 좌표,  s : 크기 배율,  a : 진하기 0~1
local function drawStar(parts, x, y, s, a)
	for _, p in ipairs(parts) do
		p.frame.Position = UDim2.new(0, x, 0, y)
		p.frame.Size = UDim2.new(0, math.max(1, p.w * s), 0, math.max(1, p.h * s))
		p.frame.BackgroundTransparency = 1 - a
		p.frame.Visible = true
	end
end

local WHITE = Color3.fromRGB(255, 255, 255)
local STUN_COLOR = Color3.fromRGB(255, 225, 120)

-- 눈 별빛은 한 번에 여러 명이 낼 수 있다. 대상별로 하나씩 만들어 쓰고 재사용한다.
local glints = {}      -- [player] = { parts = {...}, endAt = n }
local stuns = {}       -- [player] = { parts = { {..}, .. }, endAt = n }

local function glintOf(player)
	local g = glints[player]
	if not g then
		g = { parts = makeStar(CFG.GLINT_BAR, CFG.GLINT_THICK, CFG.GLINT_CORE, WHITE, 25), endAt = 0 }
		glints[player] = g
	end
	return g
end

local function stunOf(player)
	local s = stuns[player]
	if not s then
		s = { parts = {}, endAt = 0 }
		for i = 1, CFG.STAR_N do
			s.parts[i] = makeStar(CFG.STAR_BAR, CFG.STAR_THICK, 4, STUN_COLOR, 24)
		end
		stuns[player] = s
	end
	return s
end

local function headOf(player)
	local ch = player and player.Character
	if not ch then
		return nil
	end
	local h = ch:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h
	end
	return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position

	-- ===== 눈 별빛 =====
	for player, g in pairs(glints) do
		if now >= g.endAt then
			hideStar(g.parts)
		else
			local head = headOf(player)
			if not head then
				hideStar(g.parts)
			else
				local world = head.Position + Vector3.new(0, CFG.GLINT_RISE, 0)
				local ok, sp = pcall(function()
					return cam:WorldToViewportPoint(world)
				end)
				-- ★ Z <= 0 은 카메라 뒤다. 안 거르면 유령 별이 화면에 찍힌다
				if ok and sp and sp.Z > 0 then
					local dist = (world - camPos).Magnitude
					-- 멀수록 작아지되 바닥을 둔다. 글린트는 멀리서 보이는 게 존재 이유다
					local s = math.max(CFG.GLINT_MIN, CFG.REF_DIST / math.max(dist, 1))
					s = math.min(s, 1.6)
					-- 창의 앞뒤로 짧게 밝아졌다 어두워진다. 딱 끊기면 눈에 덜 띈다
					local left = g.endAt - now
					local a = math.min(1, left * 6)
					drawStar(g.parts, sp.X, sp.Y, s, a)
				else
					hideStar(g.parts)
				end
			end
		end
	end

	-- ===== 기절 별 링 =====
	for player, st in pairs(stuns) do
		if now >= st.endAt then
			for _, p in ipairs(st.parts) do
				hideStar(p)
			end
		else
			local head = headOf(player)
			if not head then
				for _, p in ipairs(st.parts) do
					hideStar(p)
				end
			else
				local world = head.Position + Vector3.new(0, CFG.STAR_RISE, 0)
				local ok, sp = pcall(function()
					return cam:WorldToViewportPoint(world)
				end)
				if ok and sp and sp.Z > 0 then
					local dist = (world - camPos).Magnitude
					local s = math.clamp(CFG.REF_DIST / math.max(dist, 1), 0.35, 1.4)
					local base = now * CFG.STAR_SPEED
					for i, p in ipairs(st.parts) do
						local th = base + (i / CFG.STAR_N) * math.pi * 2
						local x = sp.X + math.cos(th) * CFG.STAR_RX * s
						local y = sp.Y + math.sin(th) * CFG.STAR_RY * s
						-- 뒤로 도는 별은 살짝 흐리게. 그래야 링이 도는 것처럼 보인다
						local depth = (math.sin(th) + 1) / 2
						drawStar(p, x, y, s * (0.75 + depth * 0.35), 0.45 + depth * 0.55)
					end
				else
					for _, p in ipairs(st.parts) do
						hideStar(p)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	glints[player] = nil
	stuns[player] = nil
end)

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.phase == "telegraph" then
			local who = payload.who
			if type(who) == "userdata" then
				glintOf(who).endAt = os.clock() + (tonumber(payload.dur) or 0.35)
			end
		elseif payload.phase == "stunfx" then
			local who = payload.who
			if type(who) == "userdata" then
				stunOf(who).endAt = os.clock() + (tonumber(payload.dur) or 0.5)
			end
		end
	end)
else
	print("[ParryFX] CombatEvent 를 못 찾음 - 눈 별빛이 안 나온다")
end

print("[ParryFX] ready")
