-- 용의 이빨 (Ryunochi) — 용 머리 + 파괴 연출
--
-- 블렌더 Ryunochi_FX.blend 의 오브젝트 치수를 그대로 파츠로 옮긴 것이다.
-- 메시 임포트가 필요 없도록 전부 박스로 근사했다 (사용자 승인: "네모도 괜찮아").
--
-- 좌표계 변환 : 블렌더(+Y 앞, +Z 위)  ->  게임(+Z 앞, +Y 위)
--   game = (bx, bz, by) * SCALE
-- 용 로컬 +Z 가 진행 방향이다. 컨트롤러의 alignZCFrame 과 같은 규약.

local M = {}

M.SCALE = 260                     -- 블렌더 1단위 = 260cm. 머리 길이 약 10.7m
local S = M.SCALE

local HINGE_B = { 0.0, -0.55, -0.20 }        -- 블렌더 기준 아래턱 힌지
M.SNOUT_Z = 1.94 * S              -- 머리 원점에서 코끝까지 (cm). 뒤따라오는 거리 계산에 쓴다

-- ★ 실루엣 모드 : 전부 흰색 불투명. 부위별 색을 죽여 형태만 보이게 한다.
--   아래 SPEC 의 색은 그대로 남겨뒀으니 false 로 바꾸면 원래 배색으로 돌아간다.
M.SILHOUETTE = true
M.SILHOUETTE_COLOR = Color3.fromRGB(255, 255, 255)
-- "Neon" 으로 바꾸면 음영이 사라져 완전히 납작한 흰 실루엣이 된다.
-- "Plastic" 은 음영이 남아 용의 입체가 읽힌다.
M.SILHOUETTE_MATERIAL = "Plastic"

-- 색 (레퍼런스: 주홍 비늘 / 크림 뿔 / 금 갈기 / 호박 눈)
local C_SCALE = Color3.fromRGB(219, 71, 20)
local C_CREAM = Color3.fromRGB(240, 229, 209)
local C_GOLD  = Color3.fromRGB(242, 178, 46)
local C_TOOTH = Color3.fromRGB(250, 247, 237)
local C_MAW   = Color3.fromRGB(117, 23, 28)
local C_EYE   = Color3.fromRGB(255, 189, 36)
local C_ROCK  = Color3.fromRGB(86, 82, 78)

-- 블렌더 좌표(cx,cy,cz)/크기(sx,sy,sz) 를 게임 벡터로
local function bpos(x, y, z)
	return Vector3.new(x * S, z * S, y * S)
end
local function bsize(x, y, z)
	return Vector3.new(x * S, z * S, y * S)
end

-- kind : "head" 는 머리에 고정, "jaw" 는 힌지에서 회전
local SPEC = {
	-- 두개골 / 주둥이
	{ n = "Skull",     k = "head", p = { 0.00, -0.25, 0.30 }, s = { 1.42, 1.55, 0.92 }, c = C_SCALE },
	{ n = "Snout",     k = "head", p = { 0.00,  1.15, 0.08 }, s = { 0.82, 1.62, 0.62 }, c = C_SCALE },
	{ n = "Nose",      k = "head", p = { 0.00,  1.82, 0.16 }, s = { 0.62, 0.34, 0.42 }, c = C_SCALE },
	-- 눈두덩
	{ n = "BrowL",     k = "head", p = { 0.50,  0.20, 0.52 }, s = { 0.42, 0.82, 0.26 }, c = C_SCALE },
	{ n = "BrowR",     k = "head", p = {-0.50,  0.20, 0.52 }, s = { 0.42, 0.82, 0.26 }, c = C_SCALE },
	-- 입 안쪽 (어두운 면)
	{ n = "MawUpper",  k = "head", p = { 0.00,  0.75,-0.11 }, s = { 1.06, 2.10, 0.10 }, c = C_MAW },
	-- 눈 (네온)
	{ n = "EyeL",      k = "head", p = { 0.52,  0.22, 0.29 }, s = { 0.30, 0.46, 0.20 }, c = C_EYE, mat = "Neon" },
	{ n = "EyeR",      k = "head", p = {-0.52,  0.22, 0.29 }, s = { 0.30, 0.46, 0.20 }, c = C_EYE, mat = "Neon" },
	-- 갈기 (뒤로 흐르는 술)
	{ n = "ManeT",     k = "head", p = { 0.00, -1.15, 0.62 }, s = { 0.46, 1.30, 0.42 }, c = C_GOLD },
	{ n = "ManeL",     k = "head", p = { 0.56, -0.95, 0.16 }, s = { 0.34, 1.40, 0.46 }, c = C_GOLD },
	{ n = "ManeR",     k = "head", p = {-0.56, -0.95, 0.16 }, s = { 0.34, 1.40, 0.46 }, c = C_GOLD },
}

-- 뿔 : 뒤로 눕혀 뻗는 3토막씩
for _, sx in ipairs({ 1, -1 }) do
	local tag = sx > 0 and "L" or "R"
	local segs = {
		{ p = { sx * 0.46, -0.68, 0.52 }, s = { 0.26, 0.72, 0.26 } },
		{ p = { sx * 0.56, -1.32, 0.60 }, s = { 0.20, 0.72, 0.20 } },
		{ p = { sx * 0.70, -1.86, 0.56 }, s = { 0.14, 0.56, 0.14 } },
		{ p = { sx * 0.72, -1.02, 0.96 }, s = { 0.13, 0.30, 0.52 } },   -- 위로 갈라진 가지
	}
	for i, sg in ipairs(segs) do
		table.insert(SPEC, { n = "Horn" .. tag .. i, k = "head", p = sg.p, s = sg.s, c = C_CREAM })
	end
end

-- 윗니
for i = 0, 4 do
	local y = 0.30 + i * 0.32
	local w = 0.11 - i * 0.008
	local h = 0.20 - i * 0.014
	for _, sx in ipairs({ 1, -1 }) do
		table.insert(SPEC, {
			n = "ToothU" .. (sx > 0 and "L" or "R") .. i, k = "head",
			p = { sx * (0.40 - i * 0.025), y, -0.16 - h * 0.5 },
			s = { w, w, h }, c = C_TOOTH,
		})
	end
end
-- 큰 송곳니
for _, sx in ipairs({ 1, -1 }) do
	table.insert(SPEC, {
		n = "Fang" .. (sx > 0 and "L" or "R"), k = "head",
		p = { sx * 0.42, 0.46, -0.32 }, s = { 0.15, 0.15, 0.34 }, c = C_TOOTH,
	})
end

-- 아래턱 : 힌지 기준으로 함께 회전한다
table.insert(SPEC, { n = "Jaw",   k = "jaw", p = { 0.00, 0.64, -0.42 }, s = { 1.08, 2.52, 0.44 }, c = C_SCALE })
table.insert(SPEC, { n = "MawLow",k = "jaw", p = { 0.00, 0.64, -0.20 }, s = { 0.92, 2.20, 0.08 }, c = C_MAW })
table.insert(SPEC, { n = "Beard", k = "jaw", p = { 0.00, 1.10, -0.86 }, s = { 0.22, 0.60, 0.56 }, c = C_GOLD })
for i = 0, 4 do
	local y = 0.28 + i * 0.32
	local w = 0.10 - i * 0.008
	local h = 0.18 - i * 0.012
	for _, sx in ipairs({ 1, -1 }) do
		table.insert(SPEC, {
			n = "ToothL" .. (sx > 0 and "L" or "R") .. i, k = "jaw",
			p = { sx * (0.36 - i * 0.025), y, -0.20 + h * 0.5 },
			s = { w, w, h }, c = C_TOOTH,
		})
	end
end

M.SPEC = SPEC

local function newPart(name, size, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color = color
	p.Transparency = 0
	-- 실루엣 모드는 용 파츠에만 적용한다. 바위·파편은 원래 색을 쓴다.
	if M.SILHOUETTE and string.sub(name, 1, 4) == "Ryu_"
		and name ~= "Ryu_Rock" and name ~= "Ryu_Shard" then
		p.Color = M.SILHOUETTE_COLOR
		material = M.SILHOUETTE_MATERIAL
	end
	pcall(function()
		p.CanQuery = false
		p.CanTouch = false
		if material == "Neon" then
			p.Material = Enum.Material.Neon
		else
			p.Material = Enum.Material.Plastic
		end
	end)
	p.Parent = parent
	return p
end

-- 용 머리를 만든다. 반환 핸들로 자세·투명도를 조절한다.
function M.build(parent)
	local model = Instance.new("Model")
	model.Name = "Ryunochi_Dragon"
	model.Parent = parent or workspace

	local head, jaw = {}, {}
	for _, d in ipairs(SPEC) do
		local part = newPart("Ryu_" .. d.n, bsize(d.s[1], d.s[2], d.s[3]), d.c, d.mat, model)
		local entry = { Part = part, Offset = bpos(d.p[1], d.p[2], d.p[3]) }
		if d.k == "jaw" then
			table.insert(jaw, entry)
		else
			table.insert(head, entry)
		end
	end

	return {
		Model = model,
		Head = head,
		Jaw = jaw,
		Hinge = bpos(HINGE_B[1], HINGE_B[2], HINGE_B[3]),
	}
end

-- baseCF : 용 머리의 기준 CFrame (로컬 +Z 가 진행 방향)
-- jawDeg : 아래턱 벌린 각도(도). 0 이면 다문 상태
function M.setPose(h, baseCF, jawDeg)
	if not (h and h.Model and h.Model.Parent) then
		return
	end
	for _, e in ipairs(h.Head) do
		if e.Part.Parent then
			e.Part.CFrame = baseCF * CFrame.new(e.Offset)
		end
	end
	-- 힌지에서 X축(좌우축)으로 회전 -> 턱이 아래로 벌어진다
	local rot = CFrame.new(h.Hinge) * CFrame.Angles(math.rad(-jawDeg), 0, 0) * CFrame.new(-h.Hinge)
	for _, e in ipairs(h.Jaw) do
		if e.Part.Parent then
			e.Part.CFrame = baseCF * rot * CFrame.new(e.Offset)
		end
	end
end

function M.setTransparency(h, t)
	if not (h and h.Model and h.Model.Parent) then
		return
	end
	if t < 0 then t = 0 end
	if t > 1 then t = 1 end
	for _, list in ipairs({ h.Head, h.Jaw }) do
		for _, e in ipairs(list) do
			if e.Part.Parent then
				e.Part.Transparency = t
			end
		end
	end
end

function M.destroy(h)
	if h and h.Model and h.Model.Parent then
		h.Model:Destroy()
	end
end

-- ===== 착지 카메라 흔들림 =====
--
-- 원래 ViewmodelController 에 두려던 것인데, 그 스크립트의 메인 청크 지역변수가
-- 이미 199개라 12개를 더 얹으니 Luau 한도(200)를 넘겨 스크립트 전체가 로드에
-- 실패했다. 그래서 이쪽으로 옮겼다. 컨트롤러는 Dragon.shakeUpdate/shakeStart 만 부른다.
-- 여기 있는 건 전부 M.* 아니면 지역 테이블 하나라 컨트롤러의 지역변수를 늘리지 않는다.

M.SHAKE_TIME = 0.55      -- ★ 흔들리는 총 시간 (초). 늘리면 여운이 오래 남는다
M.SHAKE_ROT = 3.4        -- ★ 회전 세기 (도). 이게 체감의 대부분이다
M.SHAKE_POS = 26         -- 위치 흔들림 (cm)
M.SHAKE_FREQ = 33        -- 진동수. 키우면 잘게 떨리고 낮추면 크게 출렁인다
M.SHAKE_RANGE = 4000     -- 남의 궁극기가 흔들림을 주는 최대 거리 (cm) = 40m

local shake = { left = 0, strength = 1, seed = { 0, 0, 0 }, cf = CFrame.new(), bound = false }

function M.shakeStart(strength)
	if not strength or strength <= 0 then
		return
	end
	shake.strength = strength
	shake.left = M.SHAKE_TIME
	shake.seed = { math.random() * 6.283, math.random() * 6.283, math.random() * 6.283 }
end

-- dt 로 흔들림을 갱신하고, 뷰모델이 쓸 카메라 CFrame 을 돌려준다.
-- 아래 BindToRenderStep 이 안 잡혔으면 카메라에도 여기서 직접 얹는다.
function M.shakeUpdate(dt, cam)
	if shake.left > 0 then
		shake.left = shake.left - dt
		if shake.left < 0 then
			shake.left = 0
		end
		-- 처음이 가장 세고 제곱으로 잦아든다. 선형이면 끝이 질질 끌린다.
		local k = shake.left / M.SHAKE_TIME
		local decay = k * k * shake.strength
		local t = (M.SHAKE_TIME - shake.left) * M.SHAKE_FREQ
		-- 축마다 주기를 어긋나게 해야 규칙적인 흔들림으로 안 보인다
		local rx = math.sin(t + shake.seed[1]) * math.rad(M.SHAKE_ROT) * decay
		local ry = math.sin(t * 0.83 + shake.seed[2]) * math.rad(M.SHAKE_ROT) * decay
		local rz = math.sin(t * 1.17 + shake.seed[3]) * math.rad(M.SHAKE_ROT * 1.4) * decay
		local px = math.cos(t * 0.91 + shake.seed[2]) * M.SHAKE_POS * 0.6 * decay
		local py = math.sin(t * 1.31 + shake.seed[1]) * M.SHAKE_POS * decay
		shake.cf = CFrame.new(px, py, 0) * CFrame.Angles(rx, ry, rz)
	else
		shake.cf = CFrame.new()
	end

	if not cam then
		return nil
	end
	if shake.left <= 0 then
		return cam.CFrame
	end
	local out = cam.CFrame * shake.cf
	if not shake.bound then
		pcall(function()
			cam.CFrame = out
		end)
	end
	return out
end

-- 기본 카메라 스크립트가 매 프레임 Camera.CFrame 을 덮어쓴다.
-- 그보다 늦은 우선순위로 얹어야 흔들림이 살아남는다 (Camera = 200).
-- OVERDARE 에 BindToRenderStep 이 없을 수도 있어 실패하면 위에서 직접 쓴다.
pcall(function()
	game:GetService("RunService"):BindToRenderStep("RyunochiCameraShake", 201, function()
		if shake.left > 0 then
			local cam = workspace.CurrentCamera
			if cam then
				cam.CFrame = cam.CFrame * shake.cf
			end
		end
	end)
	shake.bound = true
end)

-- ===== 파괴 연출 =====

-- 직선 경로를 따라 갈라진 지면 조각이 솟아오른다
function M.buildCracks(fromPos, toPos, parent)
	local model = Instance.new("Model")
	model.Name = "Ryunochi_Cracks"
	model.Parent = parent or workspace

	local delta = toPos - fromPos
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local len = flat.Magnitude
	if len < 1 then
		model:Destroy()
		return nil
	end
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)

	local shards = {}
	local N = 16
	for i = 0, N - 1 do
		local t = i / (N - 1)
		for _, sx in ipairs({ 1, -1 }) do
			local off = (60 + math.random() * 130) * sx
			local pos = fromPos + dir * (len * t) + side * off
			local w = 60 + math.random() * 90
			local p = newPart("Ryu_Shard", Vector3.new(w, 40 + math.random() * 90, w * (0.6 + math.random())),
				C_ROCK, nil, model)
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6.283, 0)
				* CFrame.Angles(math.rad((math.random() - 0.5) * 40), 0, math.rad((math.random() - 0.5) * 40))
			table.insert(shards, { Part = p, Base = pos, Rise = 30 + math.random() * 90, Delay = t * 0.35 })
		end
	end
	return { Model = model, Shards = shards, elapsed = 0 }
end

-- 내리찍은 지점을 둘러싸는 바위 고리
function M.buildRockRing(center, parent)
	local model = Instance.new("Model")
	model.Name = "Ryunochi_RockRing"
	model.Parent = parent or workspace

	local rocks = {}
	local N = 14
	for i = 1, N do
		local a = (i / N) * 6.283 + math.random() * 0.2
		local r = 320 + math.random() * 180
		local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local w = 110 + math.random() * 130
		local p = newPart("Ryu_Rock", Vector3.new(w, w * (1.1 + math.random() * 0.9), w * (0.7 + math.random() * 0.6)),
			C_ROCK, nil, model)
		-- 바깥으로 기울어 솟는다
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
			* CFrame.Angles(math.rad(14 + math.random() * 26), 0, math.rad((math.random() - 0.5) * 30))
		table.insert(rocks, { Part = p, Base = pos, Rise = 120 + math.random() * 200, Delay = math.random() * 0.12 })
	end
	return { Model = model, Rocks = rocks, elapsed = 0 }
end

-- 정면으로 퍼지는 부채꼴 바위.
-- 고리는 착지 지점을 "둘러싸는" 그림이라 1인칭 정면에는 별로 안 잡힌다.
-- 이건 시선 정면을 채우는 용도라 고리와 겹쳐서 같이 터진다.
function M.buildRockFan(center, dir, parent)
	if not (center and dir) then
		return nil
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end
	flat = flat.Unit
	local side = Vector3.new(-flat.Z, 0, flat.X)

	local model = Instance.new("Model")
	model.Name = "Ryunochi_RockFan"
	model.Parent = parent or workspace

	local rocks = {}
	local ROWS = 3                  -- 앞으로 늘어놓는 줄 수. 늘리면 더 멀리까지 이어진다
	local SPREAD = math.rad(58)     -- 한쪽으로 벌어지는 각도. 키우면 넓게 퍼진다
	local STEP = 300                -- 줄 간격 (cm)
	for row = 1, ROWS do
		local dist = 280 + row * STEP
		local n = 4 + row * 2       -- 멀수록 개수를 늘려야 부채꼴이 성기지 않는다
		for i = 1, n do
			local f = (n == 1) and 0 or ((i - 1) / (n - 1) * 2 - 1)   -- -1 ~ 1
			local a = f * SPREAD
			local pos = center
				+ flat * (dist * math.cos(a) + (math.random() - 0.5) * 140)
				+ side * (dist * math.sin(a) + (math.random() - 0.5) * 140)
			local w = 90 + math.random() * 150
			local p = newPart("Ryu_Rock", Vector3.new(w, w * (1.2 + math.random() * 1.1), w * (0.7 + math.random() * 0.6)),
				C_ROCK, nil, model)
			-- 진행 방향으로 비스듬히 넘어가며 솟는다
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6.283, 0)
				* CFrame.Angles(math.rad(16 + math.random() * 32), 0, math.rad((math.random() - 0.5) * 30))
			table.insert(rocks, {
				Part = p, Base = pos,
				Rise = 150 + math.random() * 260,
				-- 가까운 줄부터 순서대로 솟아 앞으로 번져나간다
				Delay = (row - 1) * 0.08 + math.random() * 0.06,
			})
		end
	end
	return { Model = model, Rocks = rocks, elapsed = 0 }
end

-- 솟아오른 뒤 서서히 사라진다
-- 반환 false 면 수명이 끝난 것
function M.updateDebris(d, dt, riseTime, holdTime, fadeTime)
	if not (d and d.Model and d.Model.Parent) then
		return false
	end
	d.elapsed = d.elapsed + dt
	local list = d.Rocks or d.Shards
	local total = riseTime + holdTime + fadeTime

	for _, r in ipairs(list) do
		if r.Part.Parent then
			local t = d.elapsed - (r.Delay or 0)
			local up = 0
			if t > 0 then
				local a = t / riseTime
				if a > 1 then a = 1 end
				up = r.Rise * (1 - (1 - a) * (1 - a))     -- 빠르게 솟았다 감속
			end
			local base = r.Base
			r.Part.CFrame = CFrame.new(base.X, base.Y + up - r.Part.Size.Y * 0.35, base.Z)
				* (r.Part.CFrame - r.Part.CFrame.Position)
			if d.elapsed > riseTime + holdTime then
				local f = (d.elapsed - riseTime - holdTime) / fadeTime
				r.Part.Transparency = math.min(1, f)
			end
		end
	end

	if d.elapsed >= total then
		d.Model:Destroy()
		return false
	end
	return true
end

return M
