-- 로비 화면 — Material 3 + 무기 랙
--
-- ★★ 2026-08-25 전면 재작성 (2차).
--   1386x640 HTML 목업으로 눈으로 맞춘 뒤 그 픽셀값을 그대로 옮겼다.
--
-- 화면
--   상단 바   1338x64  @ (24,24)     제목 / 팀·점수 / 세션 전적
--   좌측 레일  320x512  @ (24,104)    CURRENT 카드 + LOADOUT 버튼 + MATCH + 바닥 슬롯
--   무기 패널  360x320  @ (1002,296)  고른 무기 상세
--   무기 랙                            나라를 고르면 옆으로 밀린다
--
--   ★ 레일 바닥 슬롯 하나를 DEPLOY 와 BACK 이 서로 넘겨받는다. Visible 로 끊지 않고
--     투명도로 교대해야 "자리를 넘겨받는" 느낌이 난다.
--
-- ★★ 이 엔진은 GUI 에 호버 이벤트를 주지 않는다. (2026-08-25 실측)
--   InputBegan 에 MouseMovement 가 한 번도 안 온다 (로그의 "호버 입력 확인" 0건).
--   Activated 는 정상. 그래서 호버 상태 레이어는 포기하고,
--   누름 반응은 Activated 순간에 짧게 눌렀다 튕기는 것으로 만든다.
--
-- ★★ 반응형 : 1386x640 기준 픽셀 + 배수 s 하나.
--   s = min(vw/1386, vh/640). 남는 폭·높이(dW/dH)를 레터박스로 버리지 않고
--   요소별 규칙(RULE_*)에 따라 UI 가 나눠 쓴다.
--   ※ 글자는 L.TEXT_SCALE 로 따로 굴린다 — 팬텀포스 최대 불만이 "전역 배율 하나"였다.
--
-- ★★ 둥근 모서리·그림자는 전부 구운 PNG 다.
--   이 엔진엔 UICorner / UIGradient / UIStroke / ViewportFrame 이 없다.
--   PNG 는 전부 "흰색 알파 마스크" 라서 ImageColor3 로 색만 갈아 끼워 재사용한다.
--
-- ★ 9-slice 도 없다 → 높이가 변하는 모핑 행만 3조각으로 나눴다.
-- ★ Camera:WorldToViewportPoint 도 못 쓴다 (아래 metrics 주석 참고).
-- ★ 히트박스는 세 상태 이미지를 전부 물린 투명 ImageButton 이다 (아래 U.hit 주석 참고).
-- ★ RemoteEvent 를 새로 만들지 않는다. TeamEvent / CombatEvent 에 phase 를 얹어 쓴다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local DEBUG_LAYOUT = true

-- ===== 구운 PNG (2026-08-25 임포트) =====
local IMG = {
	topbar     = "ovdrassetid://42954100",   -- 1338x64  r28
	rail       = "ovdrassetid://42954200",   -- 320x512  r28
	wpanel     = "ovdrassetid://42955100",   -- 360x320  r28
	pill       = "ovdrassetid://42954300",   -- 288x56   r28
	mtop       = "ovdrassetid://42956100",   -- 288x28   위만 r28
	mbotR      = "ovdrassetid://42957100",   -- 288x28   아래 r28
	mbotM      = "ovdrassetid://42958100",   -- 288x28   아래 좌 r28 / 우 r8  (선택 상태)
	chipTeam   = "ovdrassetid://42959100",   -- 84x32    r16
	chipStat   = "ovdrassetid://42959200",   -- 84x44    r22
	bar8       = "ovdrassetid://42960100",   -- 240x8    r4
	bar6       = "ovdrassetid://42956200",   -- 200x6    r3
	square     = "ovdrassetid://42969100",   -- 16x16    모서리 없는 단색 (히트박스용)
	shTopbar   = "ovdrassetid://42954400",   -- 그림자. 사방 72px 여백 포함
	shRail     = "ovdrassetid://42960200",
	shWpanel   = "ovdrassetid://42956300",
}
local SH_MARGIN = 72

-- ★ 2026-08-25 : 네모난 UI 스위치.
--   이 엔진엔 UICorner 가 없다. 둥근 모서리가 전부 구운 PNG 라서, "각지게" 는
--   반경을 0 으로 주는 게 아니라 판 그림을 모서리 없는 단색(square) 으로 갈아끼우는 일이다.
--   PNG 가 전부 흰색 알파 마스크라 ImageColor3 는 그대로 먹는다. 9-slice 가 없어
--   늘려 쓰던 것도 단색이 되면 오히려 안전해진다 (모서리가 찌그러질 일이 없다).
--   되돌리려면 false 하나면 된다.
--   ※ 그림자(shTopbar/shRail/shWpanel)는 별도 에셋이라 그대로 남는다. 72px 블러라
--     곡률이 거의 안 보인다. 그것까지 각지게 하려면 그림자용 PNG 를 새로 구워야 한다.
local SQUARE_UI = true
if SQUARE_UI then
	for _, k in ipairs({
		"topbar", "rail", "wpanel", "pill",
		"mtop", "mbotR", "mbotM",
		"chipTeam", "chipStat", "bar8", "bar6",
	}) do
		IMG[k] = IMG.square
	end
end

-- ===== Material 3 다크. 톤은 주칠(#B2302C)에서 뽑았다 =====
local T = {
	surfCLow     = Color3.fromRGB(33, 28, 29),
	surfC        = Color3.fromRGB(38, 32, 33),
	surfCHigh    = Color3.fromRGB(49, 42, 43),
	surfCHighest = Color3.fromRGB(60, 52, 53),
	onSurf       = Color3.fromRGB(238, 232, 216),
	onSurfVar    = Color3.fromRGB(169, 159, 153),
	primary      = Color3.fromRGB(224, 138, 133),
	primCont     = Color3.fromRGB(168, 46, 41),
	onPrimCont   = Color3.fromRGB(255, 230, 227),
	blueCont     = Color3.fromRGB(46, 76, 120),
	locked       = Color3.fromRGB(101, 91, 88),
	shadow       = Color3.fromRGB(0, 0, 0),
}

-- ===== 레이아웃 : 1386x640 기준 픽셀 =====
local L = {
	REF_W = 1386, REF_H = 640,
	GUT = 24,
	TOP_X = 24, TOP_Y = 24, TOP_W = 1338, TOP_H = 64,
	RAIL_X = 24, RAIL_Y = 104, RAIL_W = 320, RAIL_H = 512,
	RAIL_PAD = 16,
	BODY_H = 408,
	ROW_W = 288, ROW_H = 56, ROW_GAP = 6, ROW_ON_H = 120,
	WP_X = 1002, WP_Y = 296, WP_W = 360, WP_H = 320, WP_PAD = 24,
	WEAPON_CX = 673,
	-- ★ 글자만 따로 굴리는 손잡이. 팬텀포스 최대 불만이 "전역 배율 하나" 였다.
	--   2026-08-25 : 진범은 TEXT_SCALE 이 아니라 TEXT_MIN 바닥이었다.
	--   에디터 플레이 창이 작아서 뷰포트가 1132x633, s=0.8167 이다. 여기에 0.7 을
	--   곱하면 배율이 0.57 이라 기준값 11~20 이 전부 12 바닥에 걸려 "같은 크기"로 뭉갰다.
	--   그러면 작은 글자가 레이아웃이 잡아 둔 박스보다 최대 90% 커져서 잘리고 겹친다.
	--   (실물 : REACH/COMBO 줄이 알약 밖으로 삐져나가고, 무기 설명이 두 줄로 접혀
	--    아래 스탯 행을 덮었다. "글자가 너무 크다" 도 원래 이 증상이었다.)
	--   -> 바닥을 8 로 내려 배율이 정직하게 먹게 하고, 배율은 0.85 로 되돌린다.
	--   s=0.8167 기준 : 기준11 -> 8px · 기준12 -> 8px · 기준15 -> 10px · 기준20 -> 14px · 기준34 -> 24px
	--   ⚠ TEXT_MIN 을 다시 올리지 마라. 글자만 바닥에 걸면 박스는 안 커져서 반드시 잘린다.
	--     작은 창에서 글자가 정 안 보이면 TEXT_SCALE 을 올려라 (박스와 같이 커진다).
	TEXT_SCALE = 0.85,
	TEXT_MIN = 8,
	RACK_GAP = 580,
}

local RULE_C = { 0.5, 0, 0, 0 }
local RULE_R = { 1, 0, 0, 0 }
local RULE_B = { 0, 1, 0, 0 }
local RULE_BR = { 1, 1, 0, 0 }
local RULE_W = { 0, 0, 1, 0 }
local RULE_H = { 0, 0, 0, 1 }

-- ===== 모션 : flutter_cloudflare_dns 값 그대로 =====
local M = {
	MOTION = 0.42, QUICK = 0.22, PRESS = 0.09, RACK = 0.55,
	OUT = 0.16, IN = 0.26, DELAY = 0.16,
}

local function bezier(x1, y1, x2, y2)
	return function(t)
		if t <= 0 then return 0 end
		if t >= 1 then return 1 end
		local u = t
		for _ = 1, 6 do
			local mt = 1 - u
			local x = 3 * mt * mt * u * x1 + 3 * mt * u * u * x2 + u * u * u
			local d = 3 * mt * mt * x1 + 6 * mt * u * (x2 - x1) + 3 * u * u * (1 - x2)
			if math.abs(d) < 1e-6 then break end
			u = u - (x - t) / d
			if u < 0 then u = 0 elseif u > 1 then u = 1 end
		end
		local mt = 1 - u
		return 3 * mt * mt * u * y1 + 3 * mt * u * u * y2 + u * u * u
	end
end
local EMPH_DEC = bezier(0.2, 0, 0, 1)
local EMPH_ACC = bezier(0.4, 0, 1, 1)

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
pcall(function()
	gui.DisplayOrder = 20
end)
gui.Parent = playerGui

-- ===== 배수 s 와 신축 =====
local V = { s = 1, ox = 0, oy = 0, dW = 0, dH = 0, reg = {}, map = {} }

local function reg(obj, x, y, w, h, rule)
	local r = { o = obj, x = x, y = y, w = w, h = h }
	if rule then
		r.ax, r.ay, r.gw, r.gh = rule[1], rule[2], rule[3], rule[4]
	end
	table.insert(V.reg, r)
	V.map[obj] = r
	return obj
end

local function place(r)
	local s = V.s
	local x = r.x + (r.ax or 0) * V.dW
	local y = r.y + (r.ay or 0) * V.dH
	local w = r.w + (r.gw or 0) * V.dW
	local h = r.h + (r.gh or 0) * V.dH
	pcall(function()
		r.o.Position = UDim2.new(0, x * s, 0, y * s)
		r.o.Size = UDim2.new(0, w * s, 0, h * s)
	end)
end

local function txtreg(obj, size)
	table.insert(V.reg, { o = obj, t = size })
	return obj
end

local function relayout()
	local cam = Workspace.CurrentCamera
	local vw, vh = 1386, 640
	pcall(function()
		vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	end)
	if vw < 1 or vh < 1 then return end
	V.s = math.min(vw / L.REF_W, vh / L.REF_H)
	V.dW = vw / V.s - L.REF_W
	V.dH = vh / V.s - L.REF_H
	V.ox, V.oy = 0, 0
	local s = V.s
	for _, r in ipairs(V.reg) do
		if r.t then
			pcall(function()
				local base = math.max(L.TEXT_MIN,
					math.floor(r.t * s * L.TEXT_SCALE + 0.5))
				r.o.TextSize = base

				-- ★ 글자가 박스보다 넓으면 들어갈 때까지 한 단계씩 줄인다.
				--   U.txt 가 TextScaled / TextWrapped 를 둘 다 꺼두기 때문에
				--   긴 글자(특히 한글)는 아무 제약 없이 박스 밖으로 삐져나온다.
				--
				-- 박스 폭은 AbsoluteSize 가 아니라 배치 기록에서 직접 계산한다.
				--   AbsoluteSize 는 Size 를 바꾼 다음 프레임에야 갱신돼서
				--   창 크기를 바꾼 첫 프레임에 옛 값으로 잘못 줄이게 된다.
				--
				-- 글자 폭을 직접 어림해서 박스에 맞춘다.
				--   TextBounds 로 재보려 했으나 이 엔진에 없어서 안 먹었다 (2026-08-26).
				--   UTF-8 이라 0xC0 이상 바이트가 한 글자의 시작이다.
				--   ASCII 1글자 = 크기의 약 0.55배, 한글 1글자 = 약 1.0배로 잡는다.
				--   어림이라 딱 맞지는 않지만 "박스 밖으로 튀어나가는" 건 확실히 막는다.
				local pr = V.map[r.o]
				if pr and pr.w then
					local lim = (pr.w + (pr.gw or 0) * V.dW) * s
					local str = r.o.Text or ""
					local units = 0
					for i = 1, #str do
						local b = string.byte(str, i)
						if b < 128 then
							units = units + 0.55
						elseif b >= 192 then
							units = units + 1.0
						end
					end
					if units > 0 and lim > 1 then
						local fit = math.floor(lim / units)
						if fit < base then
							-- TEXT_MIN 아래로는 안 내린다 (친구 주석의 경고를 지킨다)
							r.o.TextSize = math.max(L.TEXT_MIN, fit)
						end
					end
				end
			end)
		else
			place(r)
		end
	end
end

-- ===== 만들기 헬퍼 =====
local U = {}

function U.frame(parent, x, y, w, h, color, transp, z, rule)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or T.surfC
	f.BackgroundTransparency = transp or 0
	f.ZIndex = z or 10
	pcall(function() f.BorderPixelSize = 0 end)
	pcall(function() f.BorderSizePixel = 0 end)
	f.Parent = parent
	return reg(f, x, y, w, h, rule)
end

function U.img(parent, asset, x, y, w, h, color, transp, z, rule)
	local i = Instance.new("ImageLabel")
	i.Image = asset
	i.BackgroundTransparency = 1
	i.ImageColor3 = color or T.surfCLow
	i.ImageTransparency = transp or 0
	i.ZIndex = z or 10
	pcall(function() i.BorderPixelSize = 0 end)
	i.Parent = parent
	return reg(i, x, y, w, h, rule)
end

function U.txt(parent, str, x, y, w, h, size, color, bold, align, z, rule)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = str or ""
	t.TextColor3 = color or T.onSurf
	t.ZIndex = z or 12
	pcall(function() t.Bold = bold and true or false end)
	pcall(function() t.TextScaled = false end)
	pcall(function() t.TextWrapped = false end)
	pcall(function()
		t.TextXAlignment = (align == "r") and Enum.TextXAlignment.Right
			or ((align == "c") and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left)
	end)
	pcall(function() t.BorderPixelSize = 0 end)
	t.Parent = parent
	reg(t, x, y, w, h, rule)
	return txtreg(t, size)
end

-- ★★ 히트박스 : ImageButton 에 세 상태 이미지를 전부 물리고 통째로 투명하게.
--   이 엔진은 버튼 호버/누름을 Image -> HoverImage / PressImage 로 갈아끼워 그린다.
--   AutoButtonColor 는 없어서 끌 수가 없다. 이미지가 없는 TextButton 을 깔면
--   갈아낄 게 없어 엔진 기본 "사각형" 크롬이 둥근 판 위로 튀어나온다.
--   Active 한 Frame 은 입력을 아예 못 받았다 (실측 0건). 그래서 이 방식이다.
function U.hit(parent, x, y, w, h, z, rule)
	local b = Instance.new("ImageButton")
	b.BackgroundTransparency = 1
	b.ZIndex = z or 30
	pcall(function() b.Image = IMG.square end)
	pcall(function() b.HoverImage = IMG.square end)
	pcall(function() b.PressImage = IMG.square end)
	pcall(function() b.ImageTransparency = 1 end)
	pcall(function() b.BorderPixelSize = 0 end)
	b.Parent = parent
	return reg(b, x, y, w, h, rule)
end

function U.card(parent, shAsset, bodyAsset, x, y, w, h, z, rule)
	U.img(parent, shAsset, x - SH_MARGIN, y - SH_MARGIN, w + SH_MARGIN * 2, h + SH_MARGIN * 2,
		T.shadow, 0.52, (z or 10) - 1, rule)
	return U.img(parent, bodyAsset, x, y, w, h, T.surfCLow, 0.06, z or 10, rule)
end

-- ===== 트윈 =====
local function tw(obj, props, time, style, dir, delay)
	local ok, t = pcall(function()
		return TweenService:Create(obj,
			TweenInfo.new(time or M.MOTION,
				style or Enum.EasingStyle.Quint,
				dir or Enum.EasingDirection.Out,
				0, false, delay or 0),
			props)
	end)
	if ok and t then
		pcall(function() t:Play() end)
	end
end

local function mix(a, b, k)
	return Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
end

local function stateColor(base, k)
	return mix(base, T.onSurf, k)
end

-- ★ MouseMovement 는 이 엔진에서 GUI 로 안 온다 (실측). onEnter/onLeave 는 죽은 콜백이다.
--   남겨두는 이유는 엔진이 나중에 주기 시작하면 그대로 살아나기 때문. 클릭은 Activated.
local inputSeen, clickSeen = false, false

local function hover(obj, onEnter, onLeave, onDown, onUp, onClick)
	obj.InputBegan:Connect(function(input)
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseMovement then
			if not inputSeen then
				inputSeen = true
				print("[LobbyUI] 호버 입력 확인")
			end
			if onEnter then onEnter() end
		elseif ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch then
			if onDown then onDown() end
		end
	end)
	obj.InputEnded:Connect(function(input)
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseMovement then
			if onLeave then onLeave() end
		elseif ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch then
			if onUp then onUp() end
			if ty == Enum.UserInputType.Touch and onLeave then onLeave() end
		end
	end)
	if onClick then
		obj.Activated:Connect(function()
			if not clickSeen then
				clickSeen = true
				print("[LobbyUI] 클릭 확인 (Activated)")
			end
			onClick()
		end)
	end
end

-- ===== 데이터 =====
-- ★ REACH / COMBO 는 코드에 실제로 있는 값이다 (MELEE.RANGE = 380, COMBO 길이 = 3).
--   SPEED / GUARD / RANGED 는 나라별 전투 수치 테이블이 코드에 없어서 "표시용" 이다.
local ORDER = { "japan", "korea", "maxico" }
local DATA = {
	japan = {
		label = "JAPAN", weapon = "WAKIZASHI", kind = "근접", ready = true,
		desc = "짧고 빠르다. 파고들어 한 번에 끝낸다.",
		mini = 0.45, l1 = "", l2 = "",
		-- 코드에 실제로 있는 값만 남긴다 (MELEE.RANGE = 380).
		-- SPEED / GUARD / RANGED 는 근거가 없어서 뺐다.
		stats = {
			{ "REACH", 0.45, "380 cm" },
		},
		source = "Wakizashi_Viewmodel_Split",
		groups = {
			{ slot = "L", prefix = "Wakizashi_L_", size = 320, off = Vector3.new(-115, 40, 0), roll = 22 },
			{ slot = "R", prefix = "Wakizashi_R_", size = 320, off = Vector3.new(115, 40, 0), roll = -22 },
			{ slot = "K", prefix = "Kunai", size = 150, off = Vector3.new(0, -190, 0), roll = 90 },
		},
	},
	korea = {
		label = "KOREA", weapon = "GUKGUNG", kind = "원거리", ready = true,
		desc = "멀리서 한 발. 붙으면 불리하다.",
		mini = 0.95, l1 = "", l2 = "",
		-- 활 전투 로직이 아직 없어서 내놓을 수치가 없다.
		stats = {},
		source = "Gukgung_Viewmodel_Merged",
		-- ★★ 와키자시용 마커를 쓰면 안 된다 (2026-08-25 실측).
		--   그 마커는 칼 슬롯이라 (-115, 8460, 420) 에 Z 22도로 기울어 있고 320 세로다.
		--   국궁은 축이 다르다 — 활은 긴 축이 X(117.7), 화살은 긴 축이 Z(84.1).
		--   진열장 내부는 470 x 560 x 240, 중심 (0, 8450, 420).
		useMark = false,
		groups = {
			{ names = { "Gukgung_Bow", "Gukgung_String" }, size = 430,
				off = Vector3.new(0, 30, 0), rot = { 0, 0, 90 } },
			{ names = { "Arrow_Gukgung" }, size = 250,
				off = Vector3.new(170, 0, 0), rot = { 90, 0, 0 } },
		},
	},
	maxico = {
		label = "MAXICO", weapon = "MACUAHUITL", kind = "준비 중", ready = false,
		desc = "아직 에셋이 없다.",
		mini = 0, l1 = "", l2 = "",
		stats = {},
	},
}

-- ===== 상단 바 =====
local TOP = {}
do
	local y = L.TOP_Y
	U.card(gui, IMG.shTopbar, IMG.topbar, L.TOP_X, y, L.TOP_W, L.TOP_H, 10, RULE_W)

	U.txt(gui, "ONLY ONE SHOT", L.TOP_X + 28, y + 22, 300, 22, 20, T.onSurf, true, "l", 12)

	local gx = L.WEAPON_CX + 20 - 221
	TOP.chip = U.img(gui, IMG.chipTeam, gx, y + 16, 84, 32, T.surfCHigh, 0.06, 12, RULE_C)
	TOP.chipTxt = U.txt(gui, "--", gx, y + 24, 84, 16, 13, T.onSurf, true, "c", 13, RULE_C)

	U.img(gui, IMG.bar8, gx + 98, y + 28, 240, 8, T.surfCHigh, 0.1, 12, RULE_C)
	TOP.red = U.img(gui, IMG.bar8, gx + 98, y + 28, 0, 8, T.primCont, 0, 13, RULE_C)
	TOP.blue = U.img(gui, IMG.bar8, gx + 338, y + 28, 0, 8, T.blueCont, 0, 13, RULE_C)
	TOP.blueX = gx + 338
	TOP.score = U.txt(gui, "0 : 0", gx + 352, y + 24, 90, 16, 15, T.onSurf, true, "l", 13, RULE_C)

	local names = { "KILLS", "DEATHS", "K/D" }
	TOP.vals = {}
	local sx = L.TOP_X + L.TOP_W - 12 - 272
	for i = 1, 3 do
		local x = sx + (i - 1) * 94
		U.img(gui, IMG.chipStat, x, y + 10, 84, 44, T.surfC, 0.08, 12, RULE_R)
		U.txt(gui, names[i], x, y + 18, 84, 13, 11, T.onSurfVar, false, "c", 13, RULE_R)
		TOP.vals[i] = U.txt(gui, "0", x, y + 33, 84, 20, 18, T.onSurf, true, "c", 13, RULE_R)
	end
end

-- ===== 좌측 레일 =====
U.card(gui, IMG.shRail, IMG.rail, L.RAIL_X, L.RAIL_Y, L.RAIL_W, L.RAIL_H, 10, RULE_H)

local RX = L.RAIL_X + L.RAIL_PAD          -- 40
local BODY_Y = L.RAIL_Y + L.RAIL_PAD      -- 120
-- ★ 레일 바닥 슬롯. DEPLOY 와 BACK 이 이 한 자리를 서로 넘겨받는다 (사용자 요청).
local SLOT_Y = L.RAIL_Y + L.RAIL_H - L.RAIL_PAD - L.ROW_H   -- 544

local function morphRow(x, y, w, z)
	local R = { y = y, h = L.ROW_H, on = false, base = T.surfCHighest, x = x, w = w }
	R.top = U.img(gui, IMG.mtop, x, y, w, 28, R.base, 0, z)
	R.mid = U.frame(gui, x, y + 28, w, 0, R.base, 0, z)
	R.botR = U.img(gui, IMG.mbotR, x, y + L.ROW_H - 28, w, 28, R.base, 0, z)
	R.botM = U.img(gui, IMG.mbotM, x, y + L.ROW_H - 28, w, 28, R.base, 1, z)

	R.nation = U.txt(gui, "", x + 20, y + 18, 160, 22, 20, T.onSurfVar, false, "l", z + 2)
	R.wpn = U.txt(gui, "", x + w - 168 - 20, y + 21, 168, 16, 13, T.onSurfVar, false, "r", z + 2)

	-- ★ 미니 막대는 안 보여준다 (2026-08-26).
	--   d.mini 는 코드에 근거가 없는 "표시용" 비율이라 지어낸 정보였다.
	--   오브젝트 자체는 남겨둔다 — R.more / setRect / 펼침 애니메이션이 전부
	--   이 둘을 참조해서, 지우면 그 코드를 같이 뜯어야 하고 깨질 여지가 커진다.
	--   다시 보이게 하려면 여기 투명도와 아래 펼침 애니메이션 두 줄을 되돌리면 된다.
	R.miniBg = U.img(gui, IMG.bar6, x + 20, y + 58, w - 40, 6, T.onPrimCont, 1, z + 2)
	R.mini = U.img(gui, IMG.bar6, x + 20, y + 58, 0, 6, T.onPrimCont, 1, z + 3)
	R.l1 = U.txt(gui, "", x + 20, y + 72, w - 40, 16, 12, T.onPrimCont, false, "l", z + 2)
	R.l2 = U.txt(gui, "", x + 20, y + 90, w - 40, 16, 12, T.onPrimCont, false, "l", z + 2)
	R.hit = U.hit(gui, x, y, w, L.ROW_H, z + 5)

	R.more = { R.miniBg, R.mini, R.l1, R.l2 }
	return R
end

local function setRect(obj, x, y, w, h)
	local r = V.map[obj]
	if not r then return end
	if x then r.x = x end
	if y then r.y = y end
	if w then r.w = w end
	if h then r.h = h end
	place(r)
end

local function morphApply(R, h)
	R.h = h
	setRect(R.mid, nil, R.y + 28, nil, math.max(0, h - 56))
	setRect(R.botR, nil, R.y + h - 28, nil, nil)
	setRect(R.botM, nil, R.y + h - 28, nil, nil)
	setRect(R.hit, nil, nil, nil, h)
end

local RAIL = { rows = {}, anim = {} }

-- ===== 메인 페이지 =====
RAIL.menu = {}
do
	local y = BODY_Y
	RAIL.menu.head = U.txt(gui, "CURRENT", RX + 12, y + 8, 200, 17, 14, T.onSurfVar, false, "l", 12)
	RAIL.cur = morphRow(RX, y + 36, L.ROW_W, 14)

	-- ★ CURRENT 카드는 현재 장비를 "보여주는" 것이고, 로드아웃으로 가는 건 별도 버튼이다.
	--   카드를 눌러 들어가게 해놨더니 카드가 버튼인지 표시인지 헷갈렸다 (사용자 지적).
	RAIL.menu.loadBtn = U.img(gui, IMG.pill, RX, y + 162, L.ROW_W, L.ROW_H, T.surfCHigh, 0.15, 14)
	RAIL.menu.loadTxt = U.txt(gui, "LOADOUT", RX + 20, y + 181, 160, 22, 20, T.onSurf, true, "l", 16)
	RAIL.menu.loadVal = U.txt(gui, "", RX + 108, y + 184, 160, 16, 13, T.onSurfVar, false, "r", 16)
	RAIL.menu.loadHit = U.hit(gui, RX, y + 162, L.ROW_W, L.ROW_H, 20)

	RAIL.menu.head2 = U.txt(gui, "MATCH", RX + 12, y + 230, 200, 17, 14, T.onSurfVar, false, "l", 12, RULE_B)

	local rows = { { "SCORE", 0.42, "300" }, { "ULT", 0.64, "200s" }, { "PER KILL", 0.18, "+2s" } }
	RAIL.menu.match = {}
	for i, r in ipairs(rows) do
		local ry = y + 258 + (i - 1) * 34
		table.insert(RAIL.menu.match, U.txt(gui, r[1], RX + 8, ry + 9, 84, 16, 12, T.onSurfVar, false, "l", 12, RULE_B))
		table.insert(RAIL.menu.match, U.img(gui, IMG.bar6, RX + 104, ry + 14, 100, 6, T.surfCHigh, 0.1, 12, RULE_B))
		table.insert(RAIL.menu.match, U.img(gui, IMG.bar6, RX + 104, ry + 14, 100 * r[2], 6, T.primary, 0, 13, RULE_B))
		table.insert(RAIL.menu.match, U.txt(gui, r[3], RX + 212, ry + 8, 68, 18, 15, T.onSurf, true, "r", 12, RULE_B))
	end
	RAIL.menu.line = U.txt(gui, "SPACE 배치  ·  TAB 로드아웃  ·  ESC 뒤로", RX + 12, y + 370, 264, 16,
		12, T.onSurfVar, false, "l", 12, RULE_B)
	RAIL.menu.all = { RAIL.menu.head, RAIL.menu.head2, RAIL.menu.line,
		RAIL.menu.loadBtn, RAIL.menu.loadTxt, RAIL.menu.loadVal, RAIL.menu.loadHit }
end

-- ===== 로드아웃 페이지 =====
RAIL.load = {}
do
	local y = BODY_Y
	RAIL.load.head = U.txt(gui, "LOADOUT", RX + 12, y + 8, 200, 17, 14, T.onSurfVar, false, "l", 12)
	for i = 1, 3 do
		RAIL.rows[ORDER[i]] = morphRow(RX, y + 36, L.ROW_W, 14)
	end
	-- ★ DEPLOY 와 같은 자리·같은 모양. 페이지가 바뀔 때 그 자리에서 서로 교대한다.
	RAIL.back = U.img(gui, IMG.pill, RX, SLOT_Y, L.ROW_W, L.ROW_H, T.surfCHigh, 0.15, 14, RULE_B)
	RAIL.backTxt = U.txt(gui, "BACK", RX, SLOT_Y + 17, L.ROW_W, 24, 19, T.onSurf, true, "c", 16, RULE_B)
	RAIL.backHit = U.hit(gui, RX, SLOT_Y, L.ROW_W, L.ROW_H, 20, RULE_B)
end

-- ===== DEPLOY =====
local DEP = {}
do
	DEP.img = U.img(gui, IMG.pill, RX, SLOT_Y, L.ROW_W, L.ROW_H, T.primCont, 0, 14, RULE_B)
	DEP.txt = U.txt(gui, "DEPLOY", RX, SLOT_Y + 17, L.ROW_W, 24, 19, T.onPrimCont, true, "c", 16, RULE_B)
	DEP.hit = U.hit(gui, RX, SLOT_Y, L.ROW_W, L.ROW_H, 20, RULE_B)
	DEP.x, DEP.y = RX, SLOT_Y
end

-- ===== 무기 패널 =====
local WP = {}
do
	U.card(gui, IMG.shWpanel, IMG.wpanel, L.WP_X, L.WP_Y, L.WP_W, L.WP_H, 10, RULE_BR)
	local px = L.WP_X + L.WP_PAD
	local pw = L.WP_W - L.WP_PAD * 2
	-- ★ 제목(기준34)의 글리프 상자는 약 41 이라 h=38 박스를 아래로 넘친다.
	--   부제를 원래 +64 에 뒀더니 제목이 부제를 덮었다. +72 로 내려 8칸을 띄운다.
	--   (글자가 TEXT_MIN 에 눌려 작을 땐 안 보이던 문제다. 배율이 정상이 되니 드러났다.)
	WP.name = U.txt(gui, "", px, L.WP_Y + 24, pw, 38, 34, T.onSurf, true, "l", 12, RULE_BR)
	WP.sub = U.txt(gui, "", px, L.WP_Y + 72, pw, 15, 12, T.onSurfVar, false, "l", 12, RULE_BR)
	WP.desc = U.txt(gui, "", px, L.WP_Y + 92, pw, 38, 15, T.onSurfVar, false, "l", 12, RULE_BR)
	pcall(function() WP.desc.TextWrapped = true end)
	pcall(function() WP.desc.TextYAlignment = Enum.TextYAlignment.Top end)

	WP.rows = {}
	for i = 1, 4 do
		local ry = L.WP_Y + 142 + (i - 1) * 34
		local nm = U.txt(gui, "", px, ry + 9, 84, 16, 12, T.onSurfVar, false, "l", 12, RULE_BR)
		local bg = U.img(gui, IMG.bar6, px + 96, ry + 14, 152, 6, T.surfCHigh, 0.1, 12, RULE_BR)
		local fg = U.img(gui, IMG.bar6, px + 96, ry + 14, 0, 6, T.primary, 0, 13, RULE_BR)
		local vl = U.txt(gui, "", px + 252, ry + 8, 60, 18, 15, T.onSurf, true, "r", 12, RULE_BR)
		WP.rows[i] = { nm = nm, bg = bg, fg = fg, vl = vl }
	end
	-- 지어낸 지수(SPEED/GUARD/RANGED)를 걷어내서 이 안내문도 필요 없어졌다.
	WP.foot = U.txt(gui, "",
		px, L.WP_Y + 282, pw, 14, 11, Color3.fromRGB(111, 101, 98), false, "l", 12, RULE_BR)
	WP.all = { WP.name, WP.sub, WP.desc, WP.foot }
	for _, r in ipairs(WP.rows) do
		table.insert(WP.all, r.nm)
		table.insert(WP.all, r.vl)
	end
end

relayout()

-- ===== 상태 =====
local ST = {
	shown = false, page = "main", pick = "japan",
	casePos = Vector3.new(0, 8420, 420), camPos = nil, weaponMarks = nil,
	rackAt = 0, rackFrom = 0, rackTo = 0, rackT = 1,
	camShift = 0, camSolved = false,
	kills = 0, deaths = 0, team = nil,
}

local function setVisible(list, on)
	for _, o in ipairs(list) do
		pcall(function() o.Visible = on end)
	end
end

local function fillRow(R, id, isOn)
	local d = DATA[id]
	R.id = id
	R.nation.Text = d.label
	R.wpn.Text = d.ready and d.weapon or "SOON"
	R.l1.Text = d.l1
	R.l2.Text = d.l2
	R.miniW = d.mini
	R.ready = d.ready
	R.base = d.ready and T.surfCHighest or T.surfCHigh
	if isOn ~= nil then R.on = isOn end
end

local function paintRow(R, k)
	k = k or R.k or (R.on and 1 or 0)
	R.k = k
	local col = R.on and T.primCont or R.base
	if R.hoverK and R.hoverK > 0 then col = stateColor(col, R.hoverK) end
	for _, o in ipairs({ R.top, R.mid, R.botR, R.botM }) do
		pcall(function()
			if o:IsA("Frame") then o.BackgroundColor3 = col else o.ImageColor3 = col end
		end)
	end
	R.botR.ImageTransparency = k
	R.botM.ImageTransparency = 1 - k
	local nc = R.on and T.onPrimCont or (R.ready and T.onSurfVar or T.locked)
	pcall(function() R.nation.TextColor3 = nc end)
	pcall(function() R.nation.Bold = R.on and true or false end)
	pcall(function() R.wpn.TextColor3 = R.on and T.onPrimCont or (R.ready and T.onSurfVar or T.locked) end)
end

local function moreAlpha(R, a)
	R.moreA = a
	setVisible(R.more, a > 0.02)
	-- 미니 막대는 항상 숨김 (위 주석 참고). 펼쳐도 안 나온다.
	pcall(function() R.miniBg.ImageTransparency = 1 end)
	pcall(function() R.mini.ImageTransparency = 1 end)
	pcall(function() R.l1.TextTransparency = 1 - a end)
	pcall(function() R.l2.TextTransparency = 1 - a end)
	setRect(R.mini, nil, nil, (R.w - 40) * (R.miniW or 0) * a, nil)
end

local function tweenRect(obj, x, w)
	local r = V.map[obj]
	if not r then return end
	if x then r.x = x end
	if w then r.w = w end
	tw(obj, {
		Position = UDim2.new(0, (r.x + (r.ax or 0) * V.dW) * V.s,
			0, (r.y + (r.ay or 0) * V.dH) * V.s),
		Size = UDim2.new(0, (r.w + (r.gw or 0) * V.dW) * V.s,
			0, (r.h + (r.gh or 0) * V.dH) * V.s),
	}, M.MOTION)
end

local function fillPanel(id)
	local d = DATA[id]
	WP.name.Text = d.weapon
	WP.sub.Text = d.label .. "  ·  " .. d.kind
	WP.desc.Text = d.desc
	for i, r in ipairs(WP.rows) do
		local s = d.stats and d.stats[i]
		if s then
			r.nm.Text = s[1]
			r.vl.Text = s[3]
			tweenRect(r.fg, nil, 152 * s[2])
			pcall(function() r.bg.ImageTransparency = 0.1 end)
			pcall(function() r.fg.ImageTransparency = 0 end)
		else
			-- 코드에 실제 수치가 없는 항목은 아예 안 보여준다.
			r.nm.Text = ""
			r.vl.Text = ""
			tweenRect(r.fg, nil, 0)
			pcall(function() r.bg.ImageTransparency = 1 end)
			pcall(function() r.fg.ImageTransparency = 1 end)
		end
	end
end

-- 합성 전환 : 퇴장 160ms → 내용 교체 → 진입 260ms
local function swapPanel(id)
	for _, o in ipairs(WP.all) do
		tw(o, { TextTransparency = 1 }, M.OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(M.OUT, function()
		fillPanel(id)
		for _, o in ipairs(WP.all) do
			tw(o, { TextTransparency = 0 }, M.IN)
		end
	end)
end

-- ===== 무기 랙 =====
-- ★ Model:PivotTo/GetPivot 을 안 쓴다. LobbyDisplay_japan 의 WorldPivot 이
--   .ovdrjm 에 (0,0,0) 으로 저장돼 있어서 PivotTo 가 진열물을 원점으로 날린다.
local RACK = { models = {}, parts = {} }

local function isPart(d)
	if d:IsA("BasePart") then return true end
	local cn = ""
	pcall(function() cn = d.ClassName end)
	return cn == "MeshPart" or cn == "Part"
end

local function partsOf(src, g)
	local list = {}
	if g.names then
		local want = {}
		for _, n in ipairs(g.names) do want[n] = true end
		for _, d in ipairs(src:GetDescendants()) do
			if want[d.Name] and isPart(d) then table.insert(list, d) end
		end
	else
		local p = g.prefix
		for _, d in ipairs(src:GetDescendants()) do
			if isPart(d) then
				local own = string.sub(d.Name, 1, #p) == p
				local via = d.Parent and string.sub(d.Parent.Name, 1, #p) == p
				if own or via then table.insert(list, d) end
			end
		end
	end
	return list
end

local function placeGroup(list, baseCF, target, into)
	if #list == 0 then return end
	local c = Vector3.new(0, 0, 0)
	for _, d in ipairs(list) do c = c + d.Position end
	c = c / #list
	local lo, hi
	for _, d in ipairs(list) do
		local h = d.Size / 2
		local a, b = d.Position - h, d.Position + h
		lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
		hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
	end
	local span = (hi - lo).Magnitude
	local k = (span > 1) and (target / span) or 1
	for _, d in ipairs(list) do
		local cl = d:Clone()
		cl.Anchored = true
		cl.CanCollide = false
		cl.Transparency = 0
		pcall(function()
			cl.CanTouch = false
			cl.CastShadow = false
			cl.Size = d.Size * k
		end)
		cl.CFrame = baseCF * (CFrame.new((d.Position - c) * k) * (d.CFrame - d.Position))
		cl.Parent = into
	end
end

local function snapshot(id, model)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if isPart(d) then
			table.insert(list, { d, d.CFrame })
		end
	end
	RACK.models[id] = model
	RACK.parts[id] = list
	return #list
end

local function buildRack()
	local mid = ST.casePos      -- 진열장 마커가 곧 무기 자리다
	for _, id in ipairs(ORDER) do
		if not RACK.models[id] then
			local lvl = Workspace:FindFirstChild("LobbyDisplay_" .. id)
			if lvl then
				for _, d in ipairs(lvl:GetDescendants()) do
					if isPart(d) then
						pcall(function()
							d.Transparency = 0
							d.CanCollide = false
							d.CanTouch = false
							d.CastShadow = false
						end)
					end
				end
				snapshot(id, lvl)
			else
				local d = DATA[id]
				if d.source then
					local src = Workspace:FindFirstChild(d.source)
						or ReplicatedStorage:FindFirstChild(d.source)
					if src then
						local m = Instance.new("Model")
						m.Name = "LobbyRack_" .. id
						m.Parent = Workspace
						for _, g in ipairs(d.groups or {}) do
							local cf, size = nil, g.size
							local w = (d.useMark ~= false) and ST.weaponMarks
								and g.slot and ST.weaponMarks[g.slot] or nil
							if w and w.cf then
								cf = w.cf
								if w.size then size = math.max(w.size.X, w.size.Y, w.size.Z) end
							else
								local r = g.rot or { 0, 0, g.roll or 0 }
								cf = CFrame.new(mid + g.off)
									* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
							end
							placeGroup(partsOf(src, g), cf, size, m)
						end
						snapshot(id, m)
					else
						print("[LobbyUI] 무기 원본을 못 찾음: " .. tostring(d.source))
					end
				end
			end
		end
	end
end

local function rackRight()
	local cam = Workspace.CurrentCamera
	local r = Vector3.new(1, 0, 0)
	pcall(function()
		local look = cam.CFrame.LookVector
		local f = Vector3.new(look.X, 0, look.Z)
		if f.Magnitude > 0.01 then r = f.Unit:Cross(Vector3.new(0, 1, 0)) end
	end)
	return r
end

-- ★ Camera:WorldToViewportPoint 를 쓰지 않는다 — 이 엔진에서 조용히 실패한다.
--   카메라가 수평 고정이라 세로 FOV 와 거리만으로 직접 풀 수 있다.
local function metrics()
	local cam = Workspace.CurrentCamera
	local eye = ST.camPos or (ST.casePos + Vector3.new(0, 0, -620))
	local flat = Vector3.new(ST.casePos.X - eye.X, 0, ST.casePos.Z - eye.Z)
	local dist = math.max(1, flat.Magnitude)
	local fov, vw, vh = 70, 1386, 640
	pcall(function() fov = cam.FieldOfView end)
	pcall(function() vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y end)
	local perPx = (2 * dist * math.tan(math.rad(fov) / 2)) / math.max(1, vh)
	return perPx, vw, vh, eye.Y
end

local function rackSpacingCm()
	local perPx = metrics()
	return L.RACK_GAP * V.s * perPx
end

local function applyRack()
	local right = rackRight()
	local gapCm = rackSpacingCm()
	for i, id in ipairs(ORDER) do
		local list = RACK.parts[id]
		if list then
			local off = right * (((i - 1) - ST.rackAt) * gapCm)
			for _, pr in ipairs(list) do
				pcall(function() pr[1].CFrame = pr[2] + off end)
			end
		end
	end
end

local function restoreRack()
	for _, list in pairs(RACK.parts) do
		for _, pr in ipairs(list) do
			pcall(function() pr[1].CFrame = pr[2] end)
		end
	end
end

-- ===== 선택 =====
local function setPick(id, fromServer)
	if not DATA[id] then return end
	local changed = (ST.pick ~= id)
	ST.pick = id
	_G.MyPick = id            -- ViewmodelController 가 읽는다

	for key, R in pairs(RAIL.rows) do
		R.on = (key == id)
	end
	fillRow(RAIL.cur, id, true)
	RAIL.cur.miniW = DATA[id].mini
	pcall(function() RAIL.menu.loadVal.Text = DATA[id].label end)

	if changed then
		swapPanel(id)
	else
		fillPanel(id)
	end

	local idx = 0
	for i, k in ipairs(ORDER) do
		if k == id then idx = i - 1 end
	end
	ST.rackFrom = ST.rackAt
	ST.rackTo = idx
	ST.rackT = 0

	for key, R in pairs(RAIL.rows) do
		R.animFrom = R.h
		R.animTo = R.on and L.ROW_ON_H or L.ROW_H
		R.animT = 0
		R.moreFrom = R.moreA or 0     -- 지금 보이는 값에서 이어서 간다
		R.kFrom = R.k or 0            -- 모서리도 현재값에서. 안 그러면 매번 펄럭인다
	end
	RAIL.cur.animFrom = RAIL.cur.h
	RAIL.cur.animTo = L.ROW_ON_H
	RAIL.cur.animT = 0
	RAIL.cur.moreFrom = RAIL.cur.moreA or 0
	RAIL.cur.kFrom = RAIL.cur.k or 0

	if not fromServer then
		local ev = ReplicatedStorage:FindFirstChild("TeamEvent")
		if ev then
			pcall(function() ev:FireServer({ phase = "lobby_pick", character = id }) end)
		end
	end
end

-- ===== 페이지 =====
local function layoutLoadRows()
	local y = BODY_Y + 36
	for _, id in ipairs(ORDER) do
		local R = RAIL.rows[id]
		R.y = y
		setRect(R.top, nil, y, nil, nil)
		setRect(R.nation, nil, y + 18, nil, nil)
		setRect(R.wpn, nil, y + 21, nil, nil)
		setRect(R.miniBg, nil, y + 58, nil, nil)
		setRect(R.mini, nil, y + 58, nil, nil)
		setRect(R.l1, nil, y + 72, nil, nil)
		setRect(R.l2, nil, y + 90, nil, nil)
		setRect(R.hit, nil, y, nil, nil)
		morphApply(R, R.h)
		y = y + R.h + L.ROW_GAP
	end
end

local function showRow(R, on)
	setVisible({ R.top, R.mid, R.botR, R.botM, R.nation, R.wpn }, on)
	if not R.static then setVisible({ R.hit }, on) end
	if on then
		-- ★ 스냅하지 말고 접힌 상태에서 열리게 한다. 예전엔 페이지를 열 때
		--   최종 크기로 툭 나타나서 애니메이션이 통째로 없는 것처럼 보였다.
		R.h = L.ROW_H
		R.kFrom = 0
		R.moreFrom = 0
		R.animFrom = L.ROW_H
		R.animTo = R.on and L.ROW_ON_H or L.ROW_H
		R.animT = 0
		morphApply(R, L.ROW_H)
		paintRow(R, 0)
		moreAlpha(R, 0)
	else
		setVisible(R.more, false)
	end
end

-- 목록의 요소들을 a(1=보임, 0=사라짐)로 페이드한다. base 는 그 요소의 원래 투명도.
local function fadeSet(list, a, time, delay)
	for _, e in ipairs(list) do
		local obj, base = e[1], e[2] or 0
		local target = 1 - (1 - base) * a
		local isText = false
		pcall(function() isText = obj:IsA("TextLabel") end)
		if isText then
			tw(obj, { TextTransparency = target }, time, nil, nil, delay)
		else
			tw(obj, { ImageTransparency = target }, time, nil, nil, delay)
		end
	end
end

-- 바닥 슬롯의 두 얼굴. 나가는 쪽이 먼저 빠지고(160ms) 들어오는 쪽이 뒤이어 들어온다(260ms).
local BOT_DEPLOY = { { DEP.img, 0 }, { DEP.txt, 0 } }
local BOT_BACK = { { RAIL.back, 0.15 }, { RAIL.backTxt, 0 } }

local function setPage(name)
	ST.page = name
	local m = (name == "main")
	setVisible(RAIL.menu.all, m)
	showRow(RAIL.cur, m)
	for _, id in ipairs(ORDER) do showRow(RAIL.rows[id], not m) end
	setVisible({ RAIL.load.head }, not m)
	setVisible(RAIL.menu.match, m)

	-- ★ DEPLOY 와 BACK 은 같은 자리에서 교대한다. 둘 다 켜둔 채 투명도로만 넘긴다
	--   (Visible 로 딱 끊으면 자리를 넘겨받는 느낌이 안 난다).
	--   누를 수 있는 건 지금 얼굴 쪽만.
	setVisible({ DEP.img, DEP.txt, RAIL.back, RAIL.backTxt }, true)
	setVisible({ DEP.hit }, m)
	setVisible({ RAIL.backHit }, not m)
	fadeSet(m and BOT_BACK or BOT_DEPLOY, 0, M.OUT)
	fadeSet(m and BOT_DEPLOY or BOT_BACK, 1, M.IN, M.OUT)
end

-- ===== 배선 =====
local function wireRow(R, onClick)
	R.hoverK = 0
	hover(R.hit, nil, nil, nil, nil,
		function() if R.ready and onClick then onClick() end end)
end

local function wirePill(imgObj, hitObj, baseColor, onClick, x, y)
	local st = { k = 0 }
	local function paint()
		pcall(function() imgObj.ImageColor3 = stateColor(baseColor, st.k) end)
	end
	local function scale(k)
		local r = V.map[imgObj]
		local w, h = L.ROW_W * k, L.ROW_H * k
		local bx = x + (L.ROW_W - w) / 2 + ((r and r.ax or 0) * V.dW)
		local by = y + (L.ROW_H - h) / 2 + ((r and r.ay or 0) * V.dH)
		tw(imgObj, {
			Size = UDim2.new(0, w * V.s, 0, h * V.s),
			Position = UDim2.new(0, bx * V.s, 0, by * V.s),
		}, k < 1 and M.PRESS or M.MOTION,
			k < 1 and Enum.EasingStyle.Quad or Enum.EasingStyle.Back)
	end
	-- ★ 이 엔진은 GUI 에 MouseMovement 를 안 준다 (실측 0건).
	--   호버 상태 레이어와 누름 스케일이 애초에 한 번도 안 돌았다.
	--   대신 Activated 순간에 짧게 눌렀다 튕기는 반응을 만든다 — 이건 확실히 온다.
	hover(hitObj, nil, nil, nil, nil, function()
		scale(0.96)
		st.k = 0.12
		paint()
		task.delay(M.PRESS, function()
			scale(1)
			st.k = 0
			paint()
		end)
		if onClick then onClick() end
	end)
end

-- ===== 매 프레임 : 카메라 · 랙 · 모핑 =====
local function camCFrame(shift)
	local eye = ST.camPos or (ST.casePos + Vector3.new(0, 0, -620))
	local aim = Vector3.new(ST.casePos.X, eye.Y, ST.casePos.Z)
	local look = aim - eye
	if look.Magnitude > 1 and shift ~= 0 then
		local off = look.Unit:Cross(Vector3.new(0, 1, 0)) * shift
		eye = eye + off
		aim = aim + off
	end
	return CFrame.new(eye, aim)
end

local function solveCamShift()
	local perPx, vw = metrics()
	local targetX = (L.WEAPON_CX + V.dW * 0.5) * V.s
	ST.camShift = -(targetX - vw * 0.5) * perPx
	ST.camSolved = true
	print(string.format("[LobbyUI] 카메라 : 목표 x=%.0f / 화면폭 %.0f  보정 %.0fcm  (1px=%.2fcm)",
		targetX, vw, ST.camShift, perPx))
end

local ANIM = { RAIL.cur }
for _, id in ipairs(ORDER) do table.insert(ANIM, RAIL.rows[id]) end

local lastVW, lastVH = 0, 0

local function frame(dt)
	if not ST.shown then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local vw, vh = 0, 0
	pcall(function() vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y end)
	if vw ~= lastVW or vh ~= lastVH then
		lastVW, lastVH = vw, vh
		relayout()
		layoutLoadRows()
		ST.camSolved = false
		applyRack()
		if DEBUG_LAYOUT then
			print(string.format("[LobbyUI] 재배치 : 뷰포트 %dx%d  s=%.4f  여유 dW=%.0f dH=%.0f",
				vw, vh, V.s, V.dW, V.dH))
		end
	end
	if not ST.camSolved then solveCamShift() end

	pcall(function() cam.CFrame = camCFrame(ST.camShift) end)

	if ST.rackT < 1 then
		ST.rackT = math.min(1, ST.rackT + dt / M.RACK)
		local e = EMPH_DEC(ST.rackT)
		ST.rackAt = ST.rackFrom + (ST.rackTo - ST.rackFrom) * e
		applyRack()
	end

	local dirty = false
	for _, R in ipairs(ANIM) do
		if R.animT and R.animT < 1 and R.top.Visible then
			R.animT = math.min(1, R.animT + dt / M.MOTION)
			local e = EMPH_DEC(R.animT)
			morphApply(R, R.animFrom + (R.animTo - R.animFrom) * e)
			-- ★ 모서리는 "현재값에서" 목표로 간다. 예전엔 비선택 행이 매번 k=1(각짐)에서
			--   시작해서, 한 번도 각져본 적 없는 행까지 모서리가 펄럭였다.
			local kTo = R.on and 1 or 0
			local kFrom = R.kFrom or 0
			paintRow(R, kFrom + (kTo - kFrom) * e)
			local from = R.moreFrom or 0
			local to = R.on and 1 or 0
			local c
			if R.on then
				c = EMPH_DEC(math.max(0, (R.animT - 0.38) / 0.62))
			else
				c = EMPH_ACC(math.min(1, R.animT / 0.5))
			end
			moreAlpha(R, from + (to - from) * c)
			dirty = true
		end
	end
	if dirty then layoutLoadRows() end
end

RunService.RenderStepped:Connect(frame)

-- ===== 보이기 / 숨기기 =====
local logged = false

local function setShown(on)
	-- ★ 서버가 초반 12초 동안 매초 로비 상태를 다시 보낸다. 그때마다 초기화하면
	--   로드아웃에 들어가 있어도 1초 뒤 메인으로 튕긴다 (2026-08-20).
	local was = ST.shown
	ST.shown = on
	_G.InLobby = on and true or nil
	pcall(function() gui.Enabled = on end)

	local cam = Workspace.CurrentCamera
	if cam then
		pcall(function()
			cam.CameraType = on and Enum.CameraType.Scriptable or Enum.CameraType.Custom
		end)
	end

	if on and not was then
		relayout()
		buildRack()
		layoutLoadRows()
		ST.camSolved = false
		setPage("main")
		setPick(ST.pick, true)
		ST.rackT = 1
		ST.rackAt = ST.rackTo
		applyRack()
		if not logged then
			logged = true
			print(string.format("[LobbyUI] 로비 진입 : 진열장 (%.0f, %.0f, %.0f)",
				ST.casePos.X, ST.casePos.Y, ST.casePos.Z))
			for _, id in ipairs(ORDER) do
				local list = RACK.parts[id]
				print(string.format("  랙 %-7s 파츠 %d", id, list and #list or 0))
			end
		end
	elseif not on and was then
		restoreRack()
	end
end

for _, id in ipairs(ORDER) do
	local R = RAIL.rows[id]
	fillRow(R, id, id == ST.pick)
	wireRow(R, function() setPick(id) end)
end
fillRow(RAIL.cur, ST.pick, true)
RAIL.cur.hoverK = 0
RAIL.cur.ready = true
RAIL.cur.static = true          -- 표시 전용. 누르는 건 LOADOUT 버튼이다
pcall(function() RAIL.cur.hit.Visible = false end)

wirePill(RAIL.back, RAIL.backHit, T.surfCHigh, function() setPage("main") end,
	RX, SLOT_Y)
wirePill(RAIL.menu.loadBtn, RAIL.menu.loadHit, T.surfCHigh, function() setPage("loadout") end,
	RX, BODY_Y + 162)

local function deployNow()
	if not (ST.shown and ST.page == "main") then return end
	local ev = ReplicatedStorage:FindFirstChild("TeamEvent")
	if ev then
		pcall(function() ev:FireServer({ phase = "lobby_play" }) end)
	end
end

wirePill(DEP.img, DEP.hit, T.primCont, deployNow, DEP.x, DEP.y)

-- ===== 키보드 =====
-- ★ 팬텀포스는 Space 로 배치한다. 그 단축키를 없앴을 때 PC·Xbox 양쪽에서
--   "그래서 접었다" 는 반응이 나왔다 — 미관 불만보다 훨씬 큰 이탈 사유였다.
do
	local uis = game:GetService("UserInputService")
	if uis then
		uis.InputBegan:Connect(function(input, processed)
			if processed or not ST.shown then return end
			pcall(function()
				local kc = input.KeyCode
				if kc == Enum.KeyCode.Space then
					deployNow()
				elseif kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace then
					if ST.page == "loadout" then setPage("main") end
				elseif kc == Enum.KeyCode.Tab then
					setPage(ST.page == "main" and "loadout" or "main")
				end
			end)
		end)
	end
end

fillPanel(ST.pick)
setPage("main")
setShown(false)

-- ===== 무기를 직접 누르기 =====
local HIT = {}
for i, id in ipairs(ORDER) do
	HIT[i] = U.hit(gui, 0, 0, 10, 10, 8)
	HIT[i].Visible = false
	local nid = id
	hover(HIT[i], nil, nil, nil, nil, function()
		if ST.shown and DATA[nid].ready and nid ~= ST.pick then
			setPick(nid)
		end
	end)
end

RunService.RenderStepped:Connect(function()
	if not ST.shown then return end
	local perPx, vw, vh, aimY = metrics()
	local gapCm = L.RACK_GAP * V.s * perPx
	for i, id in ipairs(ORDER) do
		local b = HIT[i]
		local d = (i - 1) - ST.rackAt
		if DATA[id].ready and math.abs(d) > 0.05 and math.abs(d) < 1.6 then
			local cx = vw * 0.5 + (d * gapCm - ST.camShift) / perPx
			local list = RACK.parts[id]
			local wy = (list and list[1] and list[1][2].Position.Y) or ST.casePos.Y
			local cy = vh * 0.5 - (wy - aimY) / perPx
			local w, h = 300 * V.s, 380 * V.s
			pcall(function()
				b.Visible = true
				b.Position = UDim2.new(0, cx - w / 2, 0, cy - h / 2)
				b.Size = UDim2.new(0, w, 0, h)
			end)
		else
			pcall(function() b.Visible = false end)
		end
	end
end)

-- ===== 서버와 주고받기 =====
local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)

if teamEvent then
	teamEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end

		-- ★ phase 가 없는 건 팀 목록이다. Player.TeamColor 는 클라에서 "Grey" 로 나온다.
		if not payload.phase then
			for _, pair in ipairs(payload) do
				if pair[1] == LocalPlayer and pair[2] then
					ST.team = pair[2]
					local c = (pair[2] == "red") and T.primCont
						or ((pair[2] == "blue") and T.blueCont or T.surfCHigh)
					tw(TOP.chip, { ImageColor3 = c }, M.QUICK)
					TOP.chipTxt.Text = string.upper(pair[2])
				end
			end
			return
		end

		if payload.phase == "score" then
			local t = math.max(1, tonumber(payload.target) or 300)
			local r = math.max(0, tonumber(payload.red) or 0)
			local b = math.max(0, tonumber(payload.blue) or 0)
			local rw = math.min(120, r / t * 120)
			local bw = math.min(120, b / t * 120)
			tweenRect(TOP.red, nil, rw)
			tweenRect(TOP.blue, TOP.blueX - bw, bw)
			TOP.score.Text = string.format("%d : %d", math.floor(r), math.floor(b))
			return
		end

		if payload.phase ~= "lobby" then return end

		if payload.weaponMarks then ST.weaponMarks = payload.weaponMarks end
		if payload.camPos then ST.camPos = payload.camPos end
		if payload.casePos then ST.casePos = payload.casePos end
		if payload.pick and payload.pick ~= ST.pick then setPick(payload.pick, true) end

		setShown(payload.state == "in")
	end)
else
	print("[LobbyUI] TeamEvent 를 못 찾음 - 로비 화면이 안 뜬다")
end

-- ===== 죽으면 곧바로 로비 =====
local dying = false

do
	local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
	if combatEvent then
		combatEvent.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then return end
			if payload.phase == "state" then
				ST.kills = math.max(0, math.floor(tonumber(payload.kills) or 0))
				ST.deaths = math.max(0, math.floor(tonumber(payload.deaths) or 0))
				TOP.vals[1].Text = tostring(ST.kills)
				TOP.vals[2].Text = tostring(ST.deaths)
				TOP.vals[3].Text = string.format("%.2f",
					(ST.deaths > 0) and (ST.kills / ST.deaths) or ST.kills)
			elseif payload.phase == "kill" and payload.victim == LocalPlayer then
				dying = true
			end
		end)
	end
end

LocalPlayer.CharacterAdded:Connect(function()
	if not dying then return end
	dying = false
	setShown(true)
end)

print("[LobbyUI] ready")
