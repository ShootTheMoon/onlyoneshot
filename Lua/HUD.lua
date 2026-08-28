-- 인게임 HUD
--
-- ★ 서버는 이미 다 보내고 있었다. 받는 쪽이 없었을 뿐이다.
--   CombatServer 가 phase = "state" 로 오토디펜스·궁극기·킬·데스를 계속 쏘는데
--   클라이언트에서 아무도 안 듣고 있었다 (2026-08-19 확인). 그래서 이 스크립트가 듣는다.
--
-- 여기 있는 것:
--   상단 중앙  : 팀 점수 (레드 / 블루)
--   크로스헤어 밑 : 오토디펜스 2칸
--   우하단     : 궁극기 게이지
--   화면 테두리 : 상황별로 물드는 경고 (오토디펜스 = 파랑)
--
-- ★ 테두리 물듦은 다른 시스템도 쓸 것이라 _G.HUD.flash 로 열어둔다.
--     패링당함 = 검붉은색 / 원거리 패링 = 검정 / 쿠나이 박힘 = 살짝 검정 / 경계선 이탈 = 주황
--   나중에 그 시스템들이 색만 바꿔 부르면 된다. 테두리를 또 만들지 마라.
--
-- ★ 이 엔진 UI 에서 확인된 제약 (Crosshair 에서 겪은 것들)
--   - UIStroke 없음. 외곽선은 검은 프레임을 한 겹 깔아 흉내낸다
--   - Font enum 없음. Bold(boolean) 만 있다
--   - 테두리 속성 이름이 BorderPixelSize 다. 버전에 따라 다를 수 있어 둘 다 시도한다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ===== 조정 숫자 =====
local UI = {
	RED = Color3.fromRGB(255, 95, 95),
	BLUE = Color3.fromRGB(95, 165, 255),
	DIM = Color3.fromRGB(65, 65, 72),        -- 비어 있는 칸 / 게이지 바닥
	TEXT = Color3.fromRGB(240, 240, 240),

	AD_Y = 64,        -- 크로스헤어 중심에서 오토디펜스 칸까지 (px)
	AD_W = 46,        -- 칸 하나의 가로 (px)
	AD_H = 6,         -- 칸 하나의 세로
	AD_GAP = 8,       -- 칸 사이 간격

	ULT_W = 190,      -- 궁극기 게이지 가로
	ULT_H = 10,
	ULT_MARGIN = 28,  -- 화면 오른쪽·아래에서 띄우는 거리

	SCORE_Y = 16,     -- 화면 위에서 팀 점수까지
	EDGE = 90,        -- 화면 테두리 경고의 두께 (px)
	EDGE_PEAK = 0.45, -- 제일 진할 때의 불투명도 (1 이면 안 보임)
}

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.Parent = playerGui

local function noBorder(f)
	pcall(function()
		f.BorderPixelSize = 0
	end)
	pcall(function()
		f.BorderSizePixel = 0
	end)
end

local function newFrame(name, parent)
	local f = Instance.new("Frame")
	f.Name = name
	noBorder(f)
	f.Parent = parent or gui
	return f
end

local function newText(name, size, color)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.TextColor3 = color or UI.TEXT
	t.TextSize = size
	t.Text = ""
	t.ZIndex = 12
	noBorder(t)
	pcall(function()
		t.Bold = true
	end)
	t.Parent = gui
	return t
end

-- ===== 상단 스코어 바 (에이펙스 컨트롤 모드 배치를 옮겨온 것) =====
--
--   [ 120 / 300 ▓▓▓░░ ]  [2]  [ POINT ]  [1]  [ ░░▓▓▓ 95 / 300 ]
--        레드 점수바      레드  점령구역  블루      블루 점수바
--                        인원   현재상태  인원
--
-- 에이펙스는 여기에 무기·팀원 상태도 붙지만 이 게임엔 필요 없어서 뺐다.
-- 가운데 상자가 "지금 열려 있는 점령 구역" 이고, 양옆 작은 상자가 그 안의 팀별 인원이다.
--
-- ★ 사선으로 깎인 에이펙스 특유의 모서리는 못 만든다. GuiObject 의 Rotation 이
--   이 엔진 문서에 없어서 못 믿는다. 직사각형으로 간다.
local SB = {
	BAR_W = 250, BAR_H = 26,       -- 점수 바
	CNT_W = 34,                    -- 인원 상자 폭
	ZONE_W = 130, ZONE_H = 30,     -- 점령 구역 상자
	GAP = 8,
	Y = 14,
}

local scoreTarget = 300           -- 서버가 보내주면 덮어쓴다

local function makeBar(side)      -- side : -1 이면 왼쪽(레드), 1 이면 오른쪽(블루)
	local color = (side < 0) and UI.RED or UI.BLUE
	local edge = SB.ZONE_W / 2 + SB.GAP + SB.CNT_W + SB.GAP

	local back = newFrame("Bar" .. tostring(side))
	back.AnchorPoint = Vector2.new((side < 0) and 1 or 0, 0)
	back.Position = UDim2.new(0.5, side * edge, 0, SB.Y)
	back.Size = UDim2.new(0, SB.BAR_W, 0, SB.BAR_H)
	back.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	back.BackgroundTransparency = 0.55
	back.ZIndex = 10

	-- 채움은 가운데(점령 구역) 쪽에서 바깥으로 자란다. 양쪽이 거울처럼 보인다.
	local fill = newFrame("Fill", back)
	fill.AnchorPoint = Vector2.new((side < 0) and 1 or 0, 0.5)
	fill.Position = UDim2.new((side < 0) and 1 or 0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.35
	fill.ZIndex = 11

	local text = newText("BarText" .. tostring(side), 19, color)
	text.AnchorPoint = back.AnchorPoint
	text.Position = back.Position
	text.Size = UDim2.new(0, SB.BAR_W, 0, SB.BAR_H)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.Text = "0 / 300"
	text.ZIndex = 13

	return { back = back, fill = fill, text = text }
end

local redBar = makeBar(-1)
local blueBar = makeBar(1)

local function makeCount(side)
	local color = (side < 0) and UI.RED or UI.BLUE
	local box = newFrame("Cnt" .. tostring(side))
	box.AnchorPoint = Vector2.new((side < 0) and 1 or 0, 0)
	box.Position = UDim2.new(0.5, side * (SB.ZONE_W / 2 + SB.GAP), 0, SB.Y)
	box.Size = UDim2.new(0, SB.CNT_W, 0, SB.BAR_H)
	box.BackgroundColor3 = color
	box.BackgroundTransparency = 0.7
	box.ZIndex = 10

	local t = newText("CntText" .. tostring(side), 18, color)
	t.AnchorPoint = box.AnchorPoint
	t.Position = box.Position
	t.Size = UDim2.new(0, SB.CNT_W, 0, SB.BAR_H)
	t.Text = "0"
	t.ZIndex = 13
	return t
end

local redCount = makeCount(-1)
local blueCount = makeCount(1)

-- 점령 구역 상자 (가운데)
local zoneBox = newFrame("Zone")
zoneBox.AnchorPoint = Vector2.new(0.5, 0)
zoneBox.Position = UDim2.new(0.5, 0, 0, SB.Y - 2)
zoneBox.Size = UDim2.new(0, SB.ZONE_W, 0, SB.ZONE_H)
zoneBox.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
zoneBox.BackgroundTransparency = 0.45
zoneBox.ZIndex = 10

local zoneText = newText("ZoneText", 17)
zoneText.AnchorPoint = Vector2.new(0.5, 0)
zoneText.Position = UDim2.new(0.5, 0, 0, SB.Y - 1)
zoneText.Size = UDim2.new(0, SB.ZONE_W, 0, SB.ZONE_H)
zoneText.Text = "CLOSED"
zoneText.TextColor3 = UI.DIM
zoneText.ZIndex = 13

local function setScore(red, blue, target)
	scoreTarget = target or scoreTarget
	local t = math.max(1, scoreTarget)
	redBar.text.Text = string.format("%d / %d", math.floor(red or 0), scoreTarget)
	blueBar.text.Text = string.format("%d / %d", math.floor(blue or 0), scoreTarget)
	redBar.fill.Size = UDim2.new(math.clamp((red or 0) / t, 0, 1), 0, 1, 0)
	blueBar.fill.Size = UDim2.new(math.clamp((blue or 0) / t, 0, 1), 0, 1, 0)
end

local function setZone(text, color, red, blue)
	zoneText.Text = text
	zoneText.TextColor3 = color or UI.TEXT
	zoneBox.BackgroundColor3 = (color and color ~= UI.TEXT and color ~= UI.DIM)
		and color or Color3.fromRGB(0, 0, 0)
	zoneBox.BackgroundTransparency = (color == UI.RED or color == UI.BLUE) and 0.6 or 0.45
	redCount.Text = tostring(red or 0)
	blueCount.Text = tostring(blue or 0)
end

setScore(0, 0, 300)

-- ===== 남은 시간 (우상단) =====
-- 에이펙스도 같은 자리에 둔다. 6분이 지나면 점수가 높은 팀이 이긴다 (CaptureServer).
local clock = newText("MatchClock", 22, UI.TEXT)
clock.AnchorPoint = Vector2.new(1, 0)
clock.Position = UDim2.new(1, -UI.ULT_MARGIN, 0, SB.Y)
clock.Size = UDim2.new(0, 120, 0, 28)
clock.TextXAlignment = Enum.TextXAlignment.Right
clock.Text = ""
clock.Visible = false

local function setClock(seconds)
	if not seconds then
		clock.Visible = false
		return
	end
	local s = math.max(0, math.floor(seconds))
	clock.Text = string.format("%d:%02d", math.floor(s / 60), s % 60)
	-- 마지막 30초는 빨갛게. 판이 끝나간다는 걸 놓치면 안 된다
	clock.TextColor3 = (s <= 30) and UI.RED or UI.TEXT
	clock.Visible = true
end

-- ===== 오토디펜스 2칸 (크로스헤어 밑) =====
-- 한 대 = 즉사인 게임이라 "내가 몇 번 더 버티나" 가 제일 중요한 정보다.
-- 그래서 좌하단이 아니라 시선이 머무는 크로스헤어 바로 밑에 둔다.
local adCells = {}
local AD_MAX = 2
for i = 1, AD_MAX do
	-- 가운데 정렬 : 칸 2개면 -(총폭)/2 부터 시작한다
	local total = AD_MAX * UI.AD_W + (AD_MAX - 1) * UI.AD_GAP
	local x = -total / 2 + (i - 1) * (UI.AD_W + UI.AD_GAP)

	local back = newFrame("ADBack" .. i)
	back.AnchorPoint = Vector2.new(0, 0.5)
	back.Position = UDim2.new(0.5, x - 1, 0.5, UI.AD_Y)
	back.Size = UDim2.new(0, UI.AD_W + 2, 0, UI.AD_H + 2)
	back.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	back.BackgroundTransparency = 0.45
	back.ZIndex = 10

	local cell = newFrame("ADCell" .. i)
	cell.AnchorPoint = Vector2.new(0, 0.5)
	cell.Position = UDim2.new(0.5, x, 0.5, UI.AD_Y)
	cell.Size = UDim2.new(0, UI.AD_W, 0, UI.AD_H)
	cell.BackgroundColor3 = UI.BLUE
	cell.ZIndex = 11
	adCells[i] = cell
end

local function setAutoDefence(left)
	for i = 1, AD_MAX do
		adCells[i].BackgroundColor3 = (i <= (left or 0)) and UI.BLUE or UI.DIM
	end
end
setAutoDefence(AD_MAX)

-- ===== 궁극기 게이지 (우하단) =====
local ultBack = newFrame("UltBack")
ultBack.AnchorPoint = Vector2.new(1, 1)
ultBack.Position = UDim2.new(1, -UI.ULT_MARGIN, 1, -UI.ULT_MARGIN)
ultBack.Size = UDim2.new(0, UI.ULT_W, 0, UI.ULT_H)
ultBack.BackgroundColor3 = UI.DIM
ultBack.BackgroundTransparency = 0.25
ultBack.ZIndex = 10

local ultFill = newFrame("UltFill", ultBack)
ultFill.AnchorPoint = Vector2.new(0, 0.5)
ultFill.Position = UDim2.new(0, 0, 0.5, 0)
ultFill.Size = UDim2.new(0, 0, 1, 0)
ultFill.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
ultFill.ZIndex = 11

local ultText = newText("UltText", 18)
ultText.AnchorPoint = Vector2.new(1, 1)
ultText.Position = UDim2.new(1, -UI.ULT_MARGIN, 1, -UI.ULT_MARGIN - UI.ULT_H - 4)
ultText.Size = UDim2.new(0, UI.ULT_W, 0, 22)
ultText.TextXAlignment = Enum.TextXAlignment.Right
ultText.Text = "ULT 0%"

local function setUlt(pct)
	pct = math.clamp(pct or 0, 0, 1)
	ultFill.Size = UDim2.new(pct, 0, 1, 0)
	ultText.Text = string.format("ULT %d%%", math.floor(pct * 100 + 0.5))
	-- 다 차면 눈에 띄게. 궁극기가 준비됐다는 건 놓치면 안 되는 정보다
	ultText.TextColor3 = (pct >= 1) and Color3.fromRGB(255, 210, 90) or UI.TEXT
end

-- ===== 화면 테두리 경고 =====
-- 상/하/좌/우 네 장으로 테두리를 만든다. 이 엔진엔 그라데이션이 없어서
-- 두께와 투명도로만 표현한다.
local edges = {}
do
	local defs = {
		{ UDim2.new(1, 0, 0, UI.EDGE), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0) },
		{ UDim2.new(1, 0, 0, UI.EDGE), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1) },
		{ UDim2.new(0, UI.EDGE, 1, 0), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5) },
		{ UDim2.new(0, UI.EDGE, 1, 0), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5) },
	}
	for i, d in ipairs(defs) do
		local f = newFrame("Edge" .. i)
		f.Size = d[1]
		f.Position = d[2]
		f.AnchorPoint = d[3]
		f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		f.BackgroundTransparency = 1
		f.Visible = false
		f.ZIndex = 5
		edges[i] = f
	end
end

-- ===== 화면 전체 어둡게 (지속형 경고) =====
-- 테두리 물듦은 잠깐 번쩍이는 것이고, 이건 상황이 끝날 때까지 계속 깔려 있는 것이다.
-- 지금은 쿠나이가 몸에 박혀 있는 동안 쓴다. 경계선 밖으로 나갔을 때도 이걸 쓰면 된다.
local dim = newFrame("Dim")
dim.AnchorPoint = Vector2.new(0.5, 0.5)
dim.Position = UDim2.new(0.5, 0, 0.5, 0)
dim.Size = UDim2.new(1, 0, 1, 0)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 1
dim.Visible = false
dim.ZIndex = 4

local function setDim(on, strength)
	if on then
		dim.BackgroundTransparency = 1 - (strength or 0.25)
		dim.Visible = true
	else
		dim.Visible = false
		dim.BackgroundTransparency = 1
	end
end

local flashState = { until_ = 0, hold = 0, peak = 0 }

-- color : 물드는 색,  strength : 0~1 (1이면 UI.EDGE_PEAK 만큼 진하게),  hold : 지속 시간(초)
-- 다른 시스템도 쓴다. 패링·쿠나이·경계선이 색만 바꿔 부르면 된다.
local function flash(color, strength, hold)
	hold = hold or 0.5
	flashState.until_ = os.clock() + hold
	flashState.hold = hold
	flashState.peak = (1 - UI.EDGE_PEAK) * math.clamp(strength or 1, 0, 1)
	for _, f in ipairs(edges) do
		f.BackgroundColor3 = color or Color3.fromRGB(0, 0, 0)
		f.Visible = true
	end
end

_G.HUD = {
	flash = flash,
	setDim = setDim,
	setAutoDefence = setAutoDefence,
	setUlt = setUlt,
}

RunService.RenderStepped:Connect(function()
	if flashState.until_ <= 0 then
		return
	end
	local left = flashState.until_ - os.clock()
	if left <= 0 then
		flashState.until_ = 0
		for _, f in ipairs(edges) do
			f.Visible = false
			f.BackgroundTransparency = 1
		end
		return
	end
	-- 처음이 제일 진하고 선형으로 옅어진다
	local k = left / math.max(flashState.hold, 0.001)
	local alpha = 1 - (flashState.peak * k)
	for _, f in ipairs(edges) do
		f.BackgroundTransparency = alpha
	end
end)

-- ===== 중앙 공지 배너 =====
-- 점령 카운트다운, 점령 중, 경기 결과가 전부 여기로 나온다.
-- 화면 한가운데는 크로스헤어 자리라 살짝 위에 둔다.
local banner = newText("Banner", 34)
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.22, 0)
banner.Size = UDim2.new(0, 700, 0, 44)
banner.Visible = false

local sub = newText("BannerSub", 20, UI.DIM)
sub.AnchorPoint = Vector2.new(0.5, 0.5)
sub.Position = UDim2.new(0.5, 0, 0.22, 30)
sub.Size = UDim2.new(0, 700, 0, 26)
sub.Visible = false

local bannerUntil = 0
local function setBanner(text, color, subText, hold)
	if not text then
		banner.Visible = false
		sub.Visible = false
		bannerUntil = 0
		return
	end
	banner.Text = text
	banner.TextColor3 = color or UI.TEXT
	banner.Visible = true
	sub.Text = subText or ""
	sub.Visible = subText ~= nil
	bannerUntil = hold and (os.clock() + hold) or 0      -- 0 이면 지울 때까지 유지
end

-- ===== 킬 로그 (우상단) =====
-- 누가 누구를 죽였는지 전원이 본다. 판이 어떻게 돌아가는지 읽으려면 필요하다.
local KILLLOG = { MAX = 4, HOLD = 6, H = 22 }
local killRows = {}
for i = 1, KILLLOG.MAX do
	local t = newText("KillRow" .. i, 17)
	t.AnchorPoint = Vector2.new(1, 0)
	t.Position = UDim2.new(1, -UI.ULT_MARGIN, 0, UI.SCORE_Y + 44 + (i - 1) * KILLLOG.H)
	t.Size = UDim2.new(0, 420, 0, KILLLOG.H)
	t.TextXAlignment = Enum.TextXAlignment.Right
	t.Visible = false
	killRows[i] = t
end

local killLog = {}      -- { {text, color, until}, ... } 최신이 1번
local function pushKillLog(killerName, victimName, killerTeam)
	table.insert(killLog, 1, {
		text = tostring(killerName) .. "   >   " .. tostring(victimName),
		color = (killerTeam == "red") and UI.RED or ((killerTeam == "blue") and UI.BLUE or UI.TEXT),
		endAt = os.clock() + KILLLOG.HOLD,
	})
	while #killLog > KILLLOG.MAX do
		table.remove(killLog)
	end
end

-- ===== 서버에서 오는 것 =====
local ultWasReady = false

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.phase == "state" then
			setAutoDefence(payload.autoDefence)
			setUlt(payload.ult)

			-- ★ 궁극기는 쿨타임이 아니라 이 충전량으로 열린다.
			--   ViewmodelController 가 _G.UltCharge 를 보고 발동 여부를 정한다.
			--   (지역변수 한도가 196/200 이라 거기에 변수를 더 못 넣어서 전역으로 넘긴다)
			_G.UltCharge = payload.ult or 0

			local ready = (payload.ult or 0) >= 1
			if ready and not ultWasReady then
				setBanner("ULTIMATE READY", Color3.fromRGB(255, 210, 90), nil, 2.5)
			end
			ultWasReady = ready
		elseif payload.phase == "autodefence" then
			-- 기획서 : 오토디펜스가 막으면 화면 테두리가 파랗게 잠깐 빛난다
			flash(UI.BLUE, 1, 0.45)
		elseif payload.phase == "parried" then
			-- 패링당했다. 기획서 : 화면 테두리가 검붉게 물든다
			local dur = tonumber(payload.dur) or 0.5
			flash(Color3.fromRGB(120, 20, 20), 1, dur + 0.35)
			setBanner("PARRIED", Color3.fromRGB(220, 70, 70), nil, 1.2)

			-- ★ 기절 동안은 아무 조작도 못 한다.
			--   걷기는 서버가 WalkSpeed 로 막지만, 공격·방어·스킬·궁극기·점프는
			--   클라이언트 입력이라 서버가 막을 수 없다. 그래서 여기서 알려준다.
			--   ViewmodelController 와 MobileControls 가 이 값을 보고 입력을 씹는다.
			_G.StunUntil = os.clock() + dur
		elseif payload.phase == "parry" then
			-- 내가 패링에 성공했다
			flash(Color3.fromRGB(235, 235, 235), 0.7, 0.3)
			setBanner("PARRY", Color3.fromRGB(255, 255, 255), nil, 1.2)
		elseif payload.phase == "kunai_stuck" then
			-- 내 몸에 쿠나이가 박혔다. 기획서 : 화면이 살짝 검어지는 경고
			-- (상대가 이 쿠나이로 내 뒤에 순간이동해 올 수 있다는 뜻이다)
			if payload.who == LocalPlayer then
				setDim(payload.on, 0.28)
				if payload.on then
					setBanner("MARKED", Color3.fromRGB(200, 200, 200), nil, 1.4)
				end
			end
		elseif payload.phase == "kill" then
			local kt = nil
			pcall(function()
				kt = payload.killerTeam
			end)
			pushKillLog(
				payload.killer and payload.killer.Name or payload.killerName or "?",
				payload.victim and payload.victim.Name or "?",
				kt)
		end
	end)
else
	print("[HUD] CombatEvent 를 못 찾음 - 오토디펜스·궁극기 표시가 안 된다")
end

local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)
if teamEvent then
	teamEvent.OnClientEvent:Connect(function(payload)
		-- 팀 목록·점수·점령이 전부 같은 이벤트로 온다 (RemoteEvent 를 새로 만들면 안 된다).
		-- phase 로 갈라 본다.
		if type(payload) ~= "table" then
			return
		end

		if payload.phase == "score" then
			setScore(payload.red, payload.blue, payload.target)

		elseif payload.phase == "capture" then
			local st = payload.state
			if st == "waiting" then
				-- 아무도 전장에 안 나와 있다. 경기는 아직 시작 안 했다.
				setZone("WAITING", UI.DIM, 0, 0)
				setClock(nil)
			elseif st == "countdown" then
				setZone(string.format("OPENS  %d", payload.left or 0), UI.DIM, 0, 0)
				-- 마지막 5초만 화면 가운데에 크게 띄운다. 20초 내내 띄우면 시야만 가린다
				if (payload.left or 0) <= 5 then
					setBanner(string.format("POINT OPENS IN  %d", payload.left), UI.TEXT, nil, 1.1)
				end
			elseif st == "moved" then
				setZone("POINT", UI.TEXT, 0, 0)
				setBanner(payload.first and "POINT IS OPEN" or "POINT MOVED", UI.TEXT, nil, 3)
			elseif st == "tick" then
				setClock(payload.timeLeft)
				local r, b = payload.red or 0, payload.blue or 0
				if payload.owner then
					local c = (payload.owner == "red") and UI.RED or UI.BLUE
					setZone(string.format("+%.1f", payload.gain or 0), c, r, b)
				elseif r > 0 and b > 0 then
					setZone("CONTESTED", UI.TEXT, r, b)
				else
					setZone("POINT", UI.TEXT, r, b)
				end
			elseif st == "over" then
				local w = payload.winner
				setZone("CLOSED", UI.DIM, 0, 0)
				setClock(0)
				if w == "draw" then
					setBanner("DRAW", UI.TEXT)
				else
					setBanner(
						string.format("%s WINS", string.upper(tostring(w))),
						(w == "red") and UI.RED or UI.BLUE)
				end
			elseif st == "restart" then
				setZone("CLOSED", UI.DIM, 0, 0)
				setClock(nil)
				setBanner(string.format("NEXT MATCH IN  %d", payload.left or 0), UI.TEXT)
			end
		end
	end)
else
	print("[HUD] TeamEvent 를 못 찾음 - 팀 점수 표시가 안 된다")
end

-- ===== 배너·킬로그 시간 처리 =====
RunService.Heartbeat:Connect(function()
	-- 로비에서는 인게임 HUD 를 통째로 감춘다. 메뉴 위에 점수·게이지가 겹치면 안 된다.
	-- ★ 예전엔 gui.Enabled == _G.InLobby 로 비교했는데, 로비를 나가면 InLobby 가 nil 이라
	--   false == nil 이 거짓이 되어 HUD 가 영영 안 켜졌다 (2026-08-20). 불리언으로 맞춰 비교한다.
	local wantHud = not _G.InLobby
	if gui.Enabled ~= wantHud then
		pcall(function()
			gui.Enabled = wantHud
		end)
	end

	local now = os.clock()

	if bannerUntil > 0 and now >= bannerUntil then
		bannerUntil = 0
		banner.Visible = false
		sub.Visible = false
	end

	for i = #killLog, 1, -1 do
		if now >= killLog[i].endAt then
			table.remove(killLog, i)
		end
	end
	for i = 1, KILLLOG.MAX do
		local e = killLog[i]
		local row = killRows[i]
		if e then
			if row.Text ~= e.text then
				row.Text = e.text
			end
			row.TextColor3 = e.color
			row.Visible = true
		elseif row.Visible then
			row.Visible = false
		end
	end
end)

-- 죽고 새 몸으로 나오면 지속형 경고는 무조건 푼다.
-- 쿠나이가 박힌 채로 죽으면 던진 쪽의 "빠졌다" 신호를 못 받을 수 있다.
LocalPlayer.CharacterAdded:Connect(function()
	setDim(false)
	_G.StunUntil = nil
end)

print("[HUD] ready")
