-- 샷건 크로스헤어:  ( . )
--   양옆에 곡선 괄호, 가운데에 점. 위아래는 뚫려 있다.
--   글자로 찍는 게 아니라 프레임 조각으로 곡선을 그린다.
--
-- 괄호 곡선은 포물선으로 만든다. 세로 위치 t(-1~1) 에 대해
--   바깥으로 밀리는 양 = CURVE * (1 - t^2)
-- 이면 양끝은 0, 가운데가 가장 볼록해져서 ( 모양이 된다.
--
-- 숫자만 고치면 모양이 바뀐다:
--   GAP     중심에서 괄호까지 거리. 키우면 산탄 퍼진 느낌
--   HEIGHT  괄호 세로 길이
--   CURVE   괄호가 휘는 정도. 0 이면 직선 | |
--   THICK   선 두께,  DOT 가운데 점 크기
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local GAP = 13
local HEIGHT = 24
local CURVE = 5
local SEGMENTS = 9
local THICK = 2
local DOT = 3
local COLOR = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(0, 0, 0)
local OUTLINE_TRANSPARENCY = 0.35

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.Parent = playerGui

-- Frame 의 테두리 속성 이름이 BorderPixelSize 다 (BorderSizePixel 아님).
-- 버전에 따라 다를 수 있어 둘 다 시도한다.
local function noBorder(f)
	pcall(function()
		f.BorderPixelSize = 0
	end)
	pcall(function()
		f.BorderSizePixel = 0
	end)
end

-- 검은 테두리 한 겹 + 흰 본체 한 겹. OVERDARE 엔 UIStroke 가 없다.
local function makePiece(name, w, h, xOff, yOff)
	local shadow = Instance.new("Frame")
	shadow.Name = name .. "_Outline"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, xOff, 0.5, yOff)
	shadow.Size = UDim2.new(0, w + 2, 0, h + 2)
	shadow.BackgroundColor3 = OUTLINE
	shadow.BackgroundTransparency = OUTLINE_TRANSPARENCY
	shadow.ZIndex = 20
	noBorder(shadow)
	shadow.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = name
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.5, xOff, 0.5, yOff)
	bar.Size = UDim2.new(0, w, 0, h)
	bar.BackgroundColor3 = COLOR
	bar.ZIndex = 21
	noBorder(bar)
	bar.Parent = gui
	return bar
end

-- side: -1 이면 왼쪽 "(" , 1 이면 오른쪽 ")"
local function makeBracket(side, label)
	-- 조각을 살짝 겹쳐 쌓아야 계단처럼 끊겨 보이지 않는다
	local segH = HEIGHT / SEGMENTS + 1
	for i = 0, SEGMENTS - 1 do
		local t = (i / (SEGMENTS - 1)) * 2 - 1      -- -1 .. 1
		local y = t * HEIGHT / 2
		local bulge = CURVE * (1 - t * t)           -- 양끝 0, 가운데 최대
		makePiece(label .. i, THICK, segH, side * (GAP + bulge), y)
	end
end

makeBracket(-1, "Left")
makeBracket(1, "Right")

-- 가운데 점. 괄호와 같은 세로 중심(yOff = 0)에 놓아 정확히 정렬된다.
makePiece("Dot", DOT, DOT, 0, 0)

-- ===== 처치 표시 =====
-- 적을 잡으면 크로스헤어 바로 밑에 "kill <이름>" 을 잠깐 띄운다.
-- 서버가 죽인 사람에게만 보낸다 (CombatServer 의 killfeed).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KILL_HOLD = 2.2        -- 떠 있는 시간 (초)
local KILL_OFFSET = 34       -- 크로스헤어 중심에서 아래로 (px)

local killLabel = Instance.new("TextLabel")
killLabel.Name = "KillFeed"
killLabel.AnchorPoint = Vector2.new(0.5, 0)
killLabel.Position = UDim2.new(0.5, 0, 0.5, KILL_OFFSET)
killLabel.Size = UDim2.new(0, 320, 0, 24)
killLabel.BackgroundTransparency = 1
killLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
killLabel.TextSize = 20
killLabel.Text = ""
killLabel.Visible = false
killLabel.ZIndex = 8
-- OVERDARE 에는 Font enum 이 없다. Bold(boolean) 만 있다.
pcall(function()
	killLabel.Bold = true
end)
killLabel.Parent = gui

-- ===== 히트마크 =====
-- 공격이 맞으면 크로스헤어 주변에 작은 X 가 번쩍인다. FPS 의 그 표시다.
-- GuiObject 의 Rotation 을 못 믿어서(문서에 없다) 작은 정사각형을 계단식으로 쌓아 대각선을 만든다.
-- 크로스헤어 괄호를 프레임 조각으로 그린 것과 같은 방식이다.
local HIT_HOLD = 0.18        -- 번쩍이는 시간 (초)
local HIT_INNER = 9          -- 중심에서 팔이 시작하는 거리 (px)
local HIT_LEN = 6            -- 팔 하나의 조각 수
local HIT_PIX = 2            -- 조각 한 변 (px)
local HIT_COLOR = Color3.fromRGB(255, 255, 255)
local HIT_KILL_COLOR = Color3.fromRGB(255, 90, 90)   -- 처치했을 때는 빨갛게

local hitParts = {}
for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
	for i = 0, HIT_LEN - 1 do
		local f = Instance.new("Frame")
		f.Name = "Hit"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.new(0, HIT_PIX + 1, 0, HIT_PIX + 1)
		f.BackgroundColor3 = HIT_COLOR
		f.BorderPixelSize = 0
		f.Visible = false
		f.ZIndex = 9
		f.Position = UDim2.new(
			0.5, d[1] * (HIT_INNER + i * HIT_PIX),
			0.5, d[2] * (HIT_INNER + i * HIT_PIX))
		f.Parent = gui
		table.insert(hitParts, f)
	end
end

local hitSeq = 0
local function flashHit(killed)
	local c = killed and HIT_KILL_COLOR or HIT_COLOR
	for _, f in ipairs(hitParts) do
		f.BackgroundColor3 = c
		f.Visible = true
	end
	hitSeq = hitSeq + 1
	local mine = hitSeq
	task.delay(HIT_HOLD, function()
		if hitSeq == mine then
			for _, f in ipairs(hitParts) do
				f.Visible = false
			end
		end
	end)
end

-- ===== 피격 방향 표시 =====
--
-- 맞으면 크로스헤어 둘레에 빨간 호가 떠서 "어느 쪽에서 맞았는지" 를 알려준다.
-- 위쪽이 정면이다. 몸을 돌리면 호도 같이 돌아간다 (월드 좌표를 들고 매 프레임 다시 계산한다).
-- 그래야 호를 보고 그쪽으로 돌면 호가 위로 올라오는, FPS 에서 익숙한 그 동작이 된다.
--
-- ★ 회전 속성을 안 쓴다. GuiObject 의 Rotation 은 이 엔진 문서에 없어서 못 믿는다.
--   크로스헤어 괄호·히트마크와 같은 방법으로, 링 위에 조각을 미리 깔아두고
--   방향에 해당하는 구간만 켠다.
local HIT_DIR = {
	HOLD = 1.1,        -- 떠 있는 시간 (초)
	RADIUS = 96,       -- 중심에서 호까지 거리 (px)
	DOTS = 48,         -- 링을 이루는 조각 수. 많을수록 매끄럽고 그만큼 비싸다
	PIX = 4,           -- 조각 한 변 (px)
	ARC = 26,          -- 호의 반각 (도). 26이면 52도짜리 부채꼴
	COLOR = Color3.fromRGB(255, 70, 70),
}

local dirDots = {}
for i = 0, HIT_DIR.DOTS - 1 do
	local th = (i / HIT_DIR.DOTS) * math.pi * 2       -- 0 = 정면(위), 시계방향
	local f = Instance.new("Frame")
	f.Name = "HitDir"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.new(0, HIT_DIR.PIX, 0, HIT_DIR.PIX)
	f.Position = UDim2.new(
		0.5, math.sin(th) * HIT_DIR.RADIUS,
		0.5, -math.cos(th) * HIT_DIR.RADIUS)
	f.BackgroundColor3 = HIT_DIR.COLOR
	f.BackgroundTransparency = 1
	f.Visible = false
	f.ZIndex = 7
	noBorder(f)
	f.Parent = gui
	dirDots[i] = { frame = f, angle = th, on = false }
end

local hits = {}          -- { { pos = Vector3, endAt = number, angle = number }, ... }
local arcRad = math.rad(HIT_DIR.ARC)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

RunService.RenderStepped:Connect(function()
	-- 로비에서는 크로스헤어도 감춘다
	-- ★ nil 과 false 를 비교하면 영영 안 켜진다 (HUD 에서 같은 실수를 했다). 불리언으로 맞춘다.
	local wantCross = not _G.InLobby
	if gui.Enabled ~= wantCross then
		pcall(function()
			gui.Enabled = wantCross
		end)
	end

	local now = os.clock()
	for i = #hits, 1, -1 do
		if now >= hits[i].endAt then
			table.remove(hits, i)
		end
	end

	if #hits == 0 then
		-- 켜져 있던 것만 끈다. 매 프레임 48개를 다 만지면 낭비다
		for _, d in pairs(dirDots) do
			if d.on then
				d.on = false
				d.frame.Visible = false
			end
		end
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camCF = cam.CFrame

	-- 맞은 지점의 화면상 방향을 매 프레임 다시 잰다.
	--   카메라 기준 좌표로 바꾸면 X 가 오른쪽, -Z 가 정면이다.
	for _, h in ipairs(hits) do
		local ok, a = pcall(function()
			local lv = camCF:VectorToObjectSpace(h.pos - camCF.Position)
			return math.atan2(lv.X, -lv.Z)
		end)
		h.angle = ok and a or 0
	end

	for i = 0, HIT_DIR.DOTS - 1 do
		local d = dirDots[i]
		local best = 0
		for _, h in ipairs(hits) do
			-- 두 각의 차이를 -pi ~ pi 로 접는다. 안 접으면 링의 이음매에서 호가 끊긴다
			local diff = math.abs(((d.angle - h.angle + math.pi) % (math.pi * 2)) - math.pi)
			if diff <= arcRad then
				local edge = 1 - (diff / arcRad)                -- 가운데가 제일 진하다
				local life = (h.endAt - now) / HIT_DIR.HOLD
				local a = edge * math.min(1, life * 1.6)        -- 끝날 때 서서히 사라진다
				if a > best then
					best = a
				end
			end
		end
		if best > 0.02 then
			d.on = true
			d.frame.Visible = true
			d.frame.BackgroundTransparency = 1 - best
		elseif d.on then
			d.on = false
			d.frame.Visible = false
		end
	end
end)

local killSeq = 0
local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.phase == "killfeed" then
			killLabel.Text = "kill  " .. tostring(payload.name)
			killLabel.Visible = true
			killSeq = killSeq + 1
			local mine = killSeq
			task.delay(KILL_HOLD, function()
				if killSeq == mine then      -- 그 사이 또 죽였으면 새 것이 이긴다
					killLabel.Visible = false
				end
			end)
		elseif payload.phase == "hitmark" then
			flashHit(payload.killed)
		elseif payload.phase == "autodefence" or payload.phase == "blocked" then
			-- 오토디펜스가 막았거나(파란 배리어) 방어로 막았거나(주황 배리어).
			-- 둘 다 "어디서 맞았는지" 는 알려줘야 한다.
			if payload.from then
				table.insert(hits, {
					pos = payload.from,
					endAt = os.clock() + HIT_DIR.HOLD,
					angle = 0,
				})
			end
		end
	end)
else
	print("[Crosshair] CombatEvent 를 못 찾음 - 처치 표시가 안 나온다")
end

print("[Crosshair] ready")
