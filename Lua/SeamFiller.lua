-- 지형 타일 이음매의 단차 메우기 + 보이지 않는 벽 진단
--
-- 맵이 6500x6500cm 타일 4x4 격자로 조립돼 있다 (STA_TER_00 ~ 33).
-- X/Z 로는 딱 맞물리는데 타일마다 높이가 달라서 경계에서 턱이 생긴다.
--
-- ★ 메시 표면 높이는 레벨 파일로 알 수 없다 (에셋 안에 있다).
--   그래서 런타임에 이음매를 따라 레이캐스트로 훑어 실제 지면 높이를 재고,
--   턱이 있는 자리에만 경사 블록을 깐다. 추측으로 미리 깔지 않는다.
--
-- ★★ 2026-08-19 실측으로 드러난 것 (표본 198곳 중 120곳에 블록을 깔았다)
--   1) "높이차 >= 45cm" 만 보면 자연 경사면이 전부 걸린다.
--      480cm 를 건너 재는데 5.4도만 기울어도 45cm 가 나온다. 산비탈이 통째로 잡힌다.
--      -> 이음매 양옆 바깥(PROBE_FAR)의 지면 기울기를 같이 재서, 주변 경사만큼은 빼고
--         "순수한 턱" 만 본다. 비탈 한가운데면 턱이 0 에 가깝게 나온다.
--   2) STEP_MAX 700 은 너무 높았다. 480cm 를 건너 700cm 를 오르면 55도다.
--      MaxSlopeAngle 이 45도라 못 걷는다. 즉 안 보이는 벽을 깐 셈이 된다.
--      -> SLOPE_MAX_DY 로 자른다. 못 걸을 경사면 아예 안 깐다.
--         메우지 못한 턱은 눈에 보이는 절벽으로 남는 게 낫다. 안 보이는 벽보다 낫다.
--
-- 절벽은 건드리지 않는다. STEP_MAX 를 넘는 높이차는 의도된 지형으로 본다.

local Workspace = game:GetService("Workspace")

local MAP_NAME = "JSN_Sangok"

-- ★ 확인용 스위치 두 개. 다 확인했으면 둘 다 false 로 되돌려라.
--   DEBUG_SHOW : 안 보이는 충돌 박스를 눈에 보이게 만든다.
--                JSN_COL(맵 원본 충돌) = 빨강,  SeamPatch(이 스크립트가 깐 것) = 초록.
--                맵의 모든 충돌은 JSN_COL 이 담당한다 (STA_TER 는 CanCollide = 0).
--   DIAGNOSE   : 맵 전체를 훑어 "눈으로는 뚫려 있는데 막힌 자리" 를 찾아 로그로 보고한다.
local DEBUG_SHOW = false
local DIAGNOSE = false

-- 타일 격자 (실측)
local TILE = 6500
local X_BOUNDS = { -66553, -60053, -53553 }
local Z_BOUNDS = { -6630, -130, 6370 }
local X_MIN, X_MAX = -73053, -47053
local Z_MIN, Z_MAX = -13130, 12870

-- ★ 패치도 인스턴스다. 최적화로 줄여놓은 걸 도로 늘리면 안 된다.
--   간격을 넓히고 블록을 크게 만들어 같은 이음매를 더 적은 개수로 덮는다.
local SAMPLE_STEP = 800        -- 이음매를 따라 훑는 간격 (cm)
local PROBE_OFFSET = 240       -- 경계 양옆으로 이만큼 떨어져 지면을 잰다
local STEP_MIN = 45            -- 이보다 낮은 턱은 그냥 넘어간다 (걸어서 넘는다)
local STEP_MAX = 700           -- 이보다 높으면 절벽. 메우지 않는다
local PATCH_W = 900            -- 경사 블록의 이음매 방향 폭. 간격보다 커야 틈이 없다
local PATCH_T = 50             -- 두께
local RAY_UP = 9000
local RAY_DOWN = 22000
local MAX_PATCH = 250          -- 안전장치. 이보다 많이 깔리면 기준이 잘못된 것

-- ★ 위 2026-08-19 실측으로 추가한 것
local PROBE_FAR = 720          -- 주변 경사를 재는 바깥쪽 지점 (PROBE_OFFSET 의 3배)
local SLOPE_MAX_DY = 430       -- 480cm 를 건너 이보다 더 오르면 45도를 넘어 못 걷는다

local map = Workspace:WaitForChild(MAP_NAME, 15)
if not map then
	print("[SeamFiller] 맵을 못 찾음: " .. MAP_NAME)
	return
end

local folder = Instance.new("Model")
folder.Name = "SeamPatches"
folder.Parent = map

local rayParams      -- 이음매를 잴 때 쓴다. 이미 깐 패치는 제외한다
local diagParams     -- 진단할 때 쓴다. 패치도 장애물이 될 수 있으니 아무것도 제외하지 않는다
local function refreshParams()
	local ok, rp = pcall(function()
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { folder }    -- 이미 깐 패치 위에 또 얹지 않는다
		return p
	end)
	rayParams = ok and rp or nil

	-- ★ 진단은 패치를 포함해서 봐야 한다. 우리가 깐 패치가 범인일 수 있는데
	--   같은 필터를 쓰면 그것만 쏙 빠져서 영영 안 잡힌다.
	local ok2, dp = pcall(function()
		return RaycastParams.new()
	end)
	diagParams = ok2 and dp or nil
end

local function groundY(x, z, params)
	params = params or rayParams
	if not params then
		return nil
	end
	local ok, res = pcall(function()
		return Workspace:Raycast(Vector3.new(x, RAY_UP, z), Vector3.new(0, -RAY_DOWN, 0), params)
	end)
	if ok and res then
		return res.Position.Y
	end
	return nil
end

local made = 0
local skippedSlope = 0     -- 턱은 맞는데 너무 가팔라서 포기한 곳
local skippedAmbient = 0   -- 그냥 비탈이라 턱이 아니었던 곳

-- a, b : 경계 양옆의 지면 지점. 두 점을 잇는 경사면을 깐다.
local function patch(a, b)
	if made >= MAX_PATCH then
		return
	end
	local mid = (a + b) / 2
	local d = b - a
	local len = d.Magnitude
	if len < 1 then
		return
	end

	local p = Instance.new("Part")
	p.Name = "SeamPatch"
	p.Anchored = true
	p.CanCollide = true
	p.Size = Vector3.new(PATCH_W, PATCH_T, len + 120)
	p.Transparency = DEBUG_SHOW and 0.35 or 1   -- 평소엔 안 보이게. 지형 위에 얹는 보정용이다
	if DEBUG_SHOW then
		pcall(function()
			p.Color = Color3.fromRGB(90, 230, 120)
		end)
	end
	-- ★ CanQuery 는 건드리지 않는다.
	--   CanCollide = true 인데 CanQuery = false 면 엔진이 유효하지 않은 조합으로 보고
	--   매번 CanQuery 를 true 로 되돌리며 경고를 뱉는다 (패치 수만큼 로그가 터진다).
	--   충돌하는 파츠는 레이캐스트에도 잡혀야 정상이다.
	pcall(function()
		p.CanTouch = false
		p.CastShadow = false
	end)

	-- 두 점을 잇는 방향으로 눕힌다 (로컬 +Z 가 a->b 를 보게)
	local ok = pcall(function()
		p.CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -PATCH_T / 2, 0)
	end)
	if not ok then
		pcall(function()
			p.CFrame = CFrame.new(mid)
		end)
	end

	p.Parent = folder
	made = made + 1
end

-- 이음매 한 지점을 판정한다.
--   n1/n2 : 경계 바로 양옆 (PROBE_OFFSET)
--   f1/f2 : 그 바깥 (PROBE_FAR). 주변 경사를 재기 위한 것이다.
-- 반환 : 턱을 메웠으면 true
local function consider(n1x, n1z, n2x, n2z, f1x, f1z, f2x, f2z)
	local h1 = groundY(n1x, n1z)
	local h2 = groundY(n2x, n2z)
	if not (h1 and h2) then
		return false
	end

	local dy = math.abs(h1 - h2)
	if dy < STEP_MIN or dy > STEP_MAX then
		return false
	end

	-- 주변 경사만큼을 뺀다. 비탈 한가운데면 여기서 걸러진다.
	local g1 = groundY(f1x, f1z)
	local g2 = groundY(f2x, f2z)
	if g1 and g2 then
		local ambient = math.abs(g1 - g2) * (PROBE_OFFSET / PROBE_FAR)
		if dy - ambient < STEP_MIN then
			skippedAmbient = skippedAmbient + 1
			return false
		end
	end

	-- 못 걸을 경사면 안 깐다. 깔면 그게 안 보이는 벽이다.
	if dy > SLOPE_MAX_DY then
		skippedSlope = skippedSlope + 1
		return false
	end

	patch(Vector3.new(n1x, h1, n1z), Vector3.new(n2x, h2, n2z))
	return true
end

-- ===== 진단 : 눈으로는 뚫려 있는데 막힌 자리 찾기 =====
--
-- 맵의 충돌은 전부 안 보이는 파츠가 담당한다 (JSN_COL 1,669개 + 우리 SeamPatch).
-- 그래서 "안 보이는데 막힌다" 는 것만으로는 절벽인지 버그인지 구분이 안 된다.
--
-- 판정 기준:
--   앞쪽 260cm 지점의 지면 높이가 지금 자리와 비슷하면 (= 걸어갈 수 있는 땅)
--   그런데 무릎 높이 레이가 막히면  ->  그게 "뚫려 있는데 막힌 자리" 다.
local DIAG = {
	STEP = 1300,      -- 훑는 간격 (cm). 맵이 260m 라 약 20x20 = 400 지점
	KNEE = 70,        -- 무릎 높이 (cm)
	REACH = 260,      -- 이만큼 앞으로 갈 수 있어야 한다
	FLAT = 110,       -- 앞 지면과의 높이차가 이 안이면 걸어갈 수 있는 땅으로 본다
	MAX_REPORT = 12,  -- 좌표를 몇 개까지 찍을지
}

local function diagnose()
	local dirs = {
		{ DIAG.REACH, 0 }, { -DIAG.REACH, 0 }, { 0, DIAG.REACH }, { 0, -DIAG.REACH },
	}
	local byName = {}
	local samples = {}
	local spots, points = 0, 0

	local x = X_MIN
	while x <= X_MAX do
		local z = Z_MIN
		while z <= Z_MAX do
			-- ★ 진단은 diagParams 로 쏜다. rayParams 는 SeamPatch 를 빼버려서
			--   정작 우리가 깐 것이 범인일 때 그것만 쏙 빠진다 (1차 진단이 이래서 틀렸다).
			local g0 = groundY(x, z, diagParams)
			if g0 then
				points = points + 1
				local origin = Vector3.new(x, g0 + DIAG.KNEE, z)
				local blocked = nil
				for _, d in ipairs(dirs) do
					local g1 = groundY(x + d[1], z + d[2], diagParams)
					-- 앞이 절벽이면 막혀도 정상이다. 평평할 때만 따진다.
					if g1 and math.abs(g1 - g0) <= DIAG.FLAT then
						local ok, res = pcall(function()
							return Workspace:Raycast(origin, Vector3.new(d[1], 0, d[2]), diagParams)
						end)
						if ok and res and res.Instance then
							-- ★★ 레이는 CanCollide 와 무관하게 맞는다.
							--   소나무(JSN_Pine)와 지형(STA_TER)은 CanCollide = 0 이라
							--   레이는 맞아도 몸은 그냥 통과한다. 1차 진단에서 소나무 44곳이
							--   1위로 나온 게 이것 때문이었다. 실제로 막는 것만 세야 한다.
							local solid = false
							pcall(function()
								solid = res.Instance.CanCollide == true
							end)
							if solid then
								blocked = res.Instance.Name
								break
							end
						end
					end
				end
				if blocked then
					spots = spots + 1
					-- 이름 뒤 번호를 떼고 묶는다 (JSN_COL_0123 -> JSN_COL)
					local key = string.gsub(blocked, "_%d+$", "")
					byName[key] = (byName[key] or 0) + 1
					if #samples < DIAG.MAX_REPORT then
						table.insert(samples, string.format("%s (%d, %d)", blocked, x, z))
					end
				end
			end
			z = z + DIAG.STEP
		end
		task.wait()      -- 프레임을 양보한다. 한 번에 다 돌면 서버가 멈춘다
		x = x + DIAG.STEP
	end

	print(string.format("[Seam진단] 지면 %d곳 중 %d곳이 막힘 (%.0f%%) - 평평한데 실제로 몸이 막히는 자리만 셌다",
		points, spots, points > 0 and (spots / points * 100) or 0))
	for key, n in pairs(byName) do
		print(string.format("[Seam진단]   %s : %d곳", key, n))
	end
	for _, s in ipairs(samples) do
		print("[Seam진단]   예: " .. s)
	end
end

-- ===== 확인용 : 안 보이는 충돌 박스를 보이게 =====
local function showCollision()
	local n = 0
	for _, d in ipairs(map:GetDescendants()) do
		if string.sub(d.Name, 1, 8) == "JSN_COL_" then
			pcall(function()
				d.Transparency = 0.65
				d.Color = Color3.fromRGB(230, 90, 90)
			end)
			n = n + 1
		end
	end
	print(string.format("[SeamFiller] DEBUG_SHOW : JSN_COL %d개를 빨갛게 띄웠다 (SeamPatch 는 초록)", n))
end

task.spawn(function()
	task.wait(3)          -- 맵과 CoverRocks 가 다 올라온 뒤에
	refreshParams()
	if not rayParams then
		print("[SeamFiller] RaycastParams 생성 실패 - 중단")
		return
	end

	local checked = 0

	-- X 경계 : Z 를 따라 훑는다
	for _, bx in ipairs(X_BOUNDS) do
		local z = Z_MIN
		while z <= Z_MAX do
			checked = checked + 1
			consider(bx - PROBE_OFFSET, z, bx + PROBE_OFFSET, z,
				bx - PROBE_FAR, z, bx + PROBE_FAR, z)
			z = z + SAMPLE_STEP
		end
		task.wait()       -- 프레임을 양보한다. 한 번에 다 돌면 서버가 멈춘다
	end

	-- Z 경계 : X 를 따라 훑는다
	for _, bz in ipairs(Z_BOUNDS) do
		local x = X_MIN
		while x <= X_MAX do
			checked = checked + 1
			consider(x, bz - PROBE_OFFSET, x, bz + PROBE_OFFSET,
				x, bz - PROBE_FAR, x, bz + PROBE_FAR)
			x = x + SAMPLE_STEP
		end
		task.wait()
	end

	print(string.format("[SeamFiller] 표본 %d곳 중 턱 %d곳 메움 / 비탈이라 건너뜀 %d곳 / 너무 가팔라 포기 %d곳",
		checked, made, skippedAmbient, skippedSlope))

	if DEBUG_SHOW then
		showCollision()
	end
	if DIAGNOSE then
		diagnose()
	end
end)

print("[SeamFiller] ready")
