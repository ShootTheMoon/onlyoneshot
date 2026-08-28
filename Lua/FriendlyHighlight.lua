-- 플레이어 표시 (화면 좌표 방식)
--
--   아군 : 머리 위 파란 점. 벽에 가려져도 항상 보인다
--   적군 : 평소엔 표시 없음. 크로스헤어를 맞추면 빨간 테두리 + 이름
--
-- ★ 왜 3D 파츠가 아니라 UI 인가 (2026-08-19 실측)
--   Fill 의 DepthMode = AlwaysOnTop 이 문서엔 "가려져도 앞에 그린다" 고 돼 있는데
--   실제로는 엄폐물 뒤 아군이 안 보였다. 문서와 동작이 다르다.
--
--   그래서 관통을 렌더링 옵션에 맡기지 않는다.
--   Camera:WorldToViewportPoint 로 화면 좌표를 구해 ScreenGui 에 그린다.
--   UI 는 3D 월드 위에 무조건 그려지므로 엄폐 문제가 원천적으로 없다.
--   덤으로 거리와 무관하게 크기가 일정해서 먼 아군도 잘 보인다.
--
-- 팀 판단은 Player.TeamColor 다. 복제가 의심스러워 최초 1회 로그로 실측한다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- ★ 2026-08-19 실측 : Player.TeamColor 는 클라이언트로 복제되지 않는다.
--   서버는 red/blue 로 제대로 배정했는데 클라이언트에서 읽으면 전부 "Grey" 로 나왔다.
--   그래서 전부 같은 팀으로 보여 적군까지 아군 표시가 됐다.
--   TeamServer 가 TeamEvent 로 명시적으로 내려주는 값을 쓴다.
local teamOf = {}                -- [player] = "red" / "blue"

local teamEvent = ReplicatedStorage:WaitForChild("TeamEvent", 10)
if teamEvent then
	teamEvent.OnClientEvent:Connect(function(list)
		if type(list) ~= "table" then
			return
		end
		-- ★ 팀 목록이 아닌 것(점수 갱신 등)은 무시한다.
		--   안 그러면 아래에서 teamOf 를 통째로 비워버려 아군 마커가 사라진다.
		if list.phase then
			return
		end
		teamOf = {}
		for _, pair in ipairs(list) do
			if pair[1] and pair[2] then
				teamOf[pair[1]] = pair[2]
			end
		end
	end)
else
	print("[Markers] TeamEvent 를 못 찾음 - 아군/적군 구분이 안 된다")
end

local ALLY_COLOR = Color3.fromRGB(80, 170, 255)
local ENEMY_COLOR = Color3.fromRGB(255, 70, 70)

local CIRCLE_IMAGE = "ovdrassetid://40281100"   -- MobileControls 가 쓰는 원형 PNG 재사용

local DOT_SIZE = 16              -- 아군 점 지름 (px)
local HEAD_OFFSET = 130          -- 머리 위로 띄우는 높이 (cm)
local CENTER_RADIUS = 110        -- 크로스헤어에서 이 픽셀 안에 들어와야 적군이 강조된다
local ENEMY_RANGE = 20000        -- 이 거리(cm=200m) 밖은 강조하지 않는다
local NAME_SIZE = 22             -- 적군 이름 글자 크기 (px)

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)

local gui = Instance.new("ScreenGui")
gui.Name = "PlayerMarkers"
gui.Parent = playerGui

local marks = {}                 -- [player] = { dot = ImageLabel, name = TextLabel, outline = Outline }
local teamLogged = false
local lastShownWho = nil         -- 아군 점 구성이 바뀔 때만 로그를 찍기 위한 것

local function isAlly(player)
	if player == LocalPlayer then
		return false
	end
	local me, other = teamOf[LocalPlayer], teamOf[player]
	-- 팀을 아직 모르면 아군으로 치지 않는다.
	-- 모르는 상태에서 아군 표시를 하면 적에게 위치를 알려주는 꼴이 된다.
	if not (me and other) then
		return false
	end
	return me == other
end

local function getMark(player)
	local m = marks[player]
	if m and m.dot and m.dot.Parent then
		return m
	end

	local dot = Instance.new("ImageLabel")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
	dot.BackgroundTransparency = 1
	dot.Image = CIRCLE_IMAGE
	dot.ImageColor3 = ALLY_COLOR
	dot.Visible = false
	dot.ZIndex = 5
	dot.Parent = gui

	-- 적군 이름표는 뺐다. 빨간 테두리만으로 충분하고 화면이 지저분해진다.
	m = { dot = dot, outline = nil }
	marks[player] = m
	return m
end

local function clearMark(player)
	local m = marks[player]
	if not m then
		return
	end
	pcall(function()
		m.dot:Destroy()
	end)
	if m.outline then
		pcall(function()
			m.outline:Destroy()
		end)
	end
	marks[player] = nil
end

local function setEnemyOutline(player, character, on)
	local m = marks[player]
	if not m then
		return
	end
	if on then
		if not (m.outline and m.outline.Parent) then
			pcall(function()
				local o = Instance.new("Outline")
				o.Name = "EnemyOutline"
				o.Color = ENEMY_COLOR
				o.Thickness = 0.4
				o.Adornee = character
				o.Parent = character
				m.outline = o
			end)
		end
	elseif m.outline then
		pcall(function()
			m.outline:Destroy()
		end)
		m.outline = nil
	end
end

local function headOf(character)
	local h = character:FindFirstChild("Head")
	if h and h:IsA("BasePart") then
		return h
	end
	return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
end

local function hasLineOfSight(camPos, target, character)
	local ok, res = pcall(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local skip = { character }
		if LocalPlayer.Character then
			table.insert(skip, LocalPlayer.Character)
		end
		local vm = Workspace:FindFirstChild("Wakizashi_Viewmodel_Runtime")
		if vm then
			table.insert(skip, vm)
		end
		rp.FilterDescendantsInstances = skip
		return Workspace:Raycast(camPos, target - camPos, rp)
	end)
	if not ok then
		return true
	end
	return res == nil
end

RunService.RenderStepped:Connect(function()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local vs = cam.ViewportSize
	local cx, cy = vs.X / 2, vs.Y / 2

	-- 파란 점이 몇 개 떠 있고 누구 것인지 센다.
	-- "내 점이 보인다" 는 증상의 정체를 확인하기 위한 것. 바뀔 때만 찍는다.
	local shown, shownWho = 0, ""

	-- 팀 배정 로그는 TeamServer 가 이미 찍는다. 여기서 또 찍으면 인원수만큼 중복된다.
	-- 아군 점 개수 로그도 뺐다. 점이 바뀔 때마다 찍혀서 로그를 통째로 덮었다.
	-- 다시 필요하면 이 자리와 아래 shownWho 비교 자리에 print 를 되살려라.

	for _, player in ipairs(Players:GetPlayers()) do
		local ch = player.Character
		local head = ch and headOf(ch)

		if player == LocalPlayer or not head then
			clearMark(player)
		else
			local m = getMark(player)
			local worldPos = head.Position + Vector3.new(0, HEAD_OFFSET, 0)
			local sp, onScreen = cam:WorldToViewportPoint(worldPos)

			-- ★ sp.Z 는 카메라 기준 깊이다. 음수면 카메라 "뒤" 에 있다는 뜻인데,
			--   그때도 X/Y 는 좌우가 뒤집힌 거울상으로 화면 안에 찍힌다.
			--   그래서 아군 반대편으로 180도 돌면 없는 점이 나타난다.
			--   onScreen 만 믿으면 안 되고 깊이를 직접 걸러야 한다.
			if not onScreen or sp.Z <= 0 then
				m.dot.Visible = false
				setEnemyOutline(player, ch, false)
			elseif isAlly(player) then
				-- ===== 아군 : 파란 점, 벽 뒤에서도 항상 =====
				m.dot.ImageColor3 = ALLY_COLOR
				m.dot.Position = UDim2.new(0, sp.X, 0, sp.Y)
				m.dot.Visible = true
				setEnemyOutline(player, ch, false)
				shown = shown + 1
				shownWho = shownWho .. " " .. player.Name
			else
				-- ===== 적군 : 크로스헤어를 맞췄을 때만 (테두리만, 이름표 없음) =====
				m.dot.Visible = false
				local dx, dy = sp.X - cx, sp.Y - cy
				local centered = (dx * dx + dy * dy) <= (CENTER_RADIUS * CENTER_RADIUS)
				local near = (camPos - head.Position).Magnitude <= ENEMY_RANGE
				setEnemyOutline(player, ch,
					centered and near and hasLineOfSight(camPos, head.Position, ch))
			end
		end
	end

	lastShownWho = shownWho
end)

Players.PlayerRemoving:Connect(clearMark)

print("[PlayerMarkers] ready")
