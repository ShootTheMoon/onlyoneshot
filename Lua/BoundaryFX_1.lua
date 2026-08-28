-- 경기구역 연출 (클라이언트)
--
--   1) 평소엔 아무것도 없다가, 경계에 바짝 붙으면 그 자리만 빨간 판이 나타난다
--   2) 밖으로 나가면 화면이 검어지면서 10초 카운트다운
--
-- ★ 투명도로 감추지 않는다. 이 엔진은 Transparency 를 제대로 안 먹는다 (2026-08-21 실측).
--   Transparency = 1 로 둔 빨간 벽이 그대로 다 보였고, 울타리도 흐려지질 않았다.
--   그래서 "있다/없다" 로만 다룬다. 멀면 파츠를 Workspace 에서 빼버리고,
--   가까워지면 그 자리에만 만들어 넣는다. 이건 어떤 엔진에서도 확실하다.
--
-- ★ 경계 사각형은 서버가 내려준다 (phase = "boundary", state = "rect").
--   빨간 벽은 서버가 ServerStorage 로 치워버려서 클라이언트에는 아예 없다.
--
-- 판은 재사용한다. 매번 만들고 부수면 그게 더 비싸다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- ===== 조절값 =====
local FENCE = {
	-- ★ 여기가 조절점이다.
	--   SHOW 안에 들어온 조각만 실제로 나타난다. 밖은 존재 자체가 없다.
	SHOW = 600,        -- 경계가 나타나기 시작하는 거리 (cm) = 6m
	SEG = 400,         -- 판 하나의 가로 길이 (cm) = 4m. 짧을수록 "그 부분만" 이 좁아진다
	HEIGHT = 1600,     -- 판 높이 (cm)
	THICK = 30,        -- 판 두께 (cm)
	SINK = 250,        -- 판 아래를 지면보다 이만큼 밑에서 시작한다 (경사에서 틈이 안 생기게)

	-- 구역 밖으로 나갔을 때는 얘기가 다르다. 돌아갈 방향이 보여야 한다.
	OUT_SHOW = 12000,  -- 밖에 있을 때 보이는 거리 (cm) = 120m

	POOL_MAX = 48,     -- 동시에 띄우는 최대 판 수. 밖에 있을 때만 여기까지 간다
	COLOR = Color3.fromRGB(235, 55, 55),
	RATE = 0.06,       -- 갱신 주기 (초)
	RAY_UP = 9000,     -- 지면을 찾을 때 이 높이에서 아래로 쏜다
	RAY_DOWN = 14000,
}

local OOB = {
	DIM_START = 0.30,  -- 나가자마자의 어두움
	DIM_END = 0.74,    -- 죽기 직전의 어두움
	TITLE = "OUT OF BOUNDS",
	SUB = "RETURN TO THE COMBAT ZONE",
	COLOR = Color3.fromRGB(255, 70, 70),
}

-- ===== 경계 =====
local rect = nil
local edges = {}      -- { { vary = "x"/"z", fixed, a, b, n, step } }

local function setupEdges(r)
	edges = {}
	local function add(vary, fixed, a, b)
		local n = math.max(1, math.floor((b - a) / FENCE.SEG + 0.5))
		edges[#edges + 1] = { vary = vary, fixed = fixed, a = a, b = b, n = n, step = (b - a) / n }
	end
	add("x", r.maxZ, r.minX, r.maxX)    -- 북
	add("x", r.minZ, r.minX, r.maxX)    -- 남
	add("z", r.maxX, r.minZ, r.maxZ)    -- 동
	add("z", r.minX, r.minZ, r.maxZ)    -- 서
end

local function slotPos(e, i)
	local c = e.a + e.step * (i + 0.5)
	if e.vary == "x" then
		return c, e.fixed
	end
	return e.fixed, c
end

-- ===== 판 만들기 / 치우기 =====
local folder = nil
local rayParams = nil
local gyCache = {}    -- [key] = 지면 높이. 같은 자리를 두 번 재지 않는다
local active = {}     -- [key] = Part (지금 Workspace 에 나와 있는 것)
local pool = {}       -- 치워둔 것. 재사용한다
local made = 0

local function ensureFolder()
	if folder and folder.Parent then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "BoundaryFence"
	folder.Parent = Workspace

	local ok, rp = pcall(function()
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { folder }
		return p
	end)
	rayParams = ok and rp or nil
end

local function groundY(x, z)
	if not rayParams then
		return nil
	end
	local ok, res = pcall(function()
		return Workspace:Raycast(
			Vector3.new(x, FENCE.RAY_UP, z),
			Vector3.new(0, -FENCE.RAY_DOWN, 0),
			rayParams)
	end)
	if ok and res then
		return res.Position.Y
	end
	return nil
end

local function newPart()
	local p = Instance.new("Part")
	p.Name = "BoundSeg"
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color = FENCE.COLOR
	pcall(function()
		p.CanTouch = false
		p.CanQuery = false      -- ★ 화살·쿠나이가 여기 막히면 안 된다
		p.Material = Enum.Material.Neon
	end)
	return p
end

local function place(key, e, i)
	local p = table.remove(pool)
	if not p then
		if made >= FENCE.POOL_MAX then
			return
		end
		p = newPart()
		made = made + 1
	end

	local x, z = slotPos(e, i)
	if e.vary == "x" then
		p.Size = Vector3.new(e.step, FENCE.HEIGHT, FENCE.THICK)
	else
		p.Size = Vector3.new(FENCE.THICK, FENCE.HEIGHT, e.step)
	end

	local gy = gyCache[key]
	if not gy then
		gy = groundY(x, z) or 1200
		gyCache[key] = gy
	end
	p.CFrame = CFrame.new(x, gy + FENCE.HEIGHT * 0.5 - FENCE.SINK, z)
	p.Parent = folder
	active[key] = p
end

local function release(key)
	local p = active[key]
	if not p then
		return
	end
	active[key] = nil
	-- ★ Destroy 가 아니라 Parent = nil 이다. 화면에서는 완전히 사라지고 재사용은 된다.
	pcall(function()
		p.Parent = nil
	end)
	pool[#pool + 1] = p
end

local function releaseAll()
	for key in pairs(active) do
		release(key)
	end
end

-- ===== 구역 밖 화면 =====
local gui, veil, title, sub, count

local function buildGui()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "BoundaryWarning"
	pcall(function()
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
	end)
	gui.Parent = pg

	veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.new(1, 0, 1, 0)
	veil.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	veil.BackgroundTransparency = 1
	veil.ZIndex = 8
	veil.Visible = false
	pcall(function()
		veil.BorderSizePixel = 0
	end)
	veil.Parent = gui

	local function label(name, y, size, color)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.new(0.5, 0, y, 0)
		t.Size = UDim2.new(0.8, 0, 0, size + 12)
		t.BackgroundTransparency = 1
		t.TextColor3 = color
		t.TextSize = size
		t.Text = ""
		t.ZIndex = 9
		t.Visible = false
		pcall(function()
			t.BorderSizePixel = 0
			t.TextStrokeTransparency = 0.4
		end)
		pcall(function()
			t.Bold = true
		end)
		t.Parent = gui
		return t
	end

	title = label("Title", 0.30, 40, OOB.COLOR)
	sub = label("Sub", 0.36, 22, Color3.fromRGB(235, 235, 235))
	count = label("Count", 0.46, 76, OOB.COLOR)
	return true
end

-- ===== 서버에서 오는 것 =====
local oobUntil = 0        -- os.clock 기준. 0 이면 구역 안
local oobTotal = 10

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or payload.phase ~= "boundary" then
			return
		end

		if payload.state == "rect" then
			local rx1, rx2 = tonumber(payload.minX), tonumber(payload.maxX)
			local rz1, rz2 = tonumber(payload.minZ), tonumber(payload.maxZ)
			if not (rx1 and rx2 and rz1 and rz2) then
				return
			end
			-- 같은 값이면 다시 세우지 않는다. 서버가 3초마다 계속 보낸다.
			if rect and rect.minX == rx1 and rect.maxX == rx2
				and rect.minZ == rz1 and rect.maxZ == rz2 then
				return
			end
			rect = { minX = rx1, maxX = rx2, minZ = rz1, maxZ = rz2 }
			releaseAll()
			gyCache = {}
			setupEdges(rect)
			ensureFolder()
			print(string.format("[BoundaryFX] 경기구역 X[%.0f..%.0f] Z[%.0f..%.0f]",
				rx1, rx2, rz1, rz2))
			return
		end

		if payload.state == "out" then
			local left = tonumber(payload.left) or 10
			oobUntil = os.clock() + left
			oobTotal = math.max(oobTotal, left)
		else
			oobUntil = 0
			oobTotal = 10
		end
	end)
else
	print("[BoundaryFX] CombatEvent 를 못 찾음 - 경기구역이 안 나온다")
end

-- 죽거나 리스폰하면 경고를 무조건 지운다.
-- 서버가 "in" 을 보내기 전에 화면이 검은 채로 남으면 안 된다.
LocalPlayer.CharacterAdded:Connect(function()
	oobUntil = 0
	oobTotal = 10
end)

-- ===== 매 프레임 =====
local nextTick = 0
local cand = {}       -- 후보 목록. 매 틱 새로 만들지 않고 비워 쓴다

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local left = (oobUntil > 0) and (oobUntil - now) or 0
	if left <= 0 then
		left = 0
		oobUntil = 0
	end
	local outside = left > 0
	local lobby = _G.InLobby and true or false

	-- --- 경고 화면 ---
	if gui then
		local show = outside and not lobby
		if veil.Visible ~= show then
			veil.Visible = show
			title.Visible = show
			sub.Visible = show
			count.Visible = show
		end
		if show then
			-- 시간이 갈수록 어두워진다
			local k = 1 - math.clamp(left / math.max(oobTotal, 0.001), 0, 1)
			veil.BackgroundTransparency = 1 - (OOB.DIM_START + (OOB.DIM_END - OOB.DIM_START) * k)
			-- 마지막 3초는 깜빡인다
			local blink = (left <= 3) and (math.floor(now * 6) % 2 == 0)
			title.Text = blink and "" or OOB.TITLE
			sub.Text = OOB.SUB
			count.Text = tostring(math.max(0, math.ceil(left)))
		end
	end

	-- --- 울타리 ---
	if now < nextTick or not rect then
		return
	end
	nextTick = now + FENCE.RATE

	local ch = LocalPlayer.Character
	local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
	if (not root) or lobby then
		releaseAll()
		return
	end

	local pos = root.Position
	local show = outside and FENCE.OUT_SHOW or FENCE.SHOW
	local show2 = show * show

	-- 가까운 조각을 모은다. 변마다 수직거리로 먼저 걸러서 대부분은 아예 안 본다.
	for i = #cand, 1, -1 do
		cand[i] = nil
	end
	for ei, e in ipairs(edges) do
		local perp, proj
		if e.vary == "x" then
			perp = math.abs(pos.Z - e.fixed)
			proj = pos.X
		else
			perp = math.abs(pos.X - e.fixed)
			proj = pos.Z
		end
		if perp <= show then
			-- 이 변에서 닿을 수 있는 좌우 폭
			local reach = math.sqrt(math.max(0, show2 - perp * perp))
			local i0 = math.floor((proj - e.a) / e.step)
			local span = math.ceil(reach / e.step) + 1
			local lo = math.max(0, i0 - span)
			local hi = math.min(e.n - 1, i0 + span)
			for i = lo, hi do
				local x, z = slotPos(e, i)
				local dx, dz = x - pos.X, z - pos.Z
				local d2 = dx * dx + dz * dz
				if d2 <= show2 then
					cand[#cand + 1] = { key = ei .. "_" .. i, e = e, i = i, d = d2 }
				end
			end
		end
	end

	-- 가까운 것부터. 파츠 수가 모자라면 먼 것이 잘린다.
	table.sort(cand, function(A, B)
		return A.d < B.d
	end)

	local keep = {}
	for n = 1, math.min(#cand, FENCE.POOL_MAX) do
		keep[cand[n].key] = cand[n]
	end

	-- 멀어진 것은 치운다 (여기서 화면에서 사라진다)
	for key in pairs(active) do
		if not keep[key] then
			release(key)
		end
	end

	-- 가까워진 것은 내놓는다
	for key, it in pairs(keep) do
		if not active[key] then
			place(key, it.e, it.i)
		end
	end
end)

buildGui()
print("[BoundaryFX] ready")
