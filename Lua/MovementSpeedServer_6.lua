local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ★ 2026-08-19 : 맵이 커져서(JSN_Sangok 259 x 271m) 이동을 전반적으로 올렸다.
--   기존 500(walk) / 800(run) 으로는 맵을 가로지르는 데 34초가 걸렸다.
--   700 / 1190 이면 23초. 대략 초당 12m 로 아펙스·타이탄폴 정도의 템포다.
--   Humanoid.WalkSpeed 기본값은 500 이고 서버에서만 설정된다.

-- 사망한 플레이어를 그 자리에 묶어두는 표. CombatServer 가 켜고 끈다.
-- 아래 Heartbeat 루프가 매 프레임 WalkSpeed 를 다시 쓰기 때문에 여기서 같이 봐야 한다.
_G.MovementFreeze = _G.MovementFreeze or {}

-- ★ 확정 (2026-08-20 실측) : ODA 아바타의 보이는 정면 = root 의 LookVector 그대로다.
--   스폰 방향·쿠나이 등 뒤 계산이 이 사실 위에 서 있다. 뒤집지 마라.

local BASE_WALK_SPEED = 700
local RUN_MULTIPLIER = 1.7
local RAMP_TIME = 1.8

-- 점프도 같이 올린다. 넓은 맵에서 지형을 넘어다녀야 한다.
-- 기본값 : JumpHeight 135cm / JumpPower 745 / GravityScale 2.1
local JUMP_HEIGHT = 190

-- ===== 캐릭터 크기 (실험) =====
-- ★ OVERDARE 에는 모델을 키우는 공식 경로가 없다 (2026-08-19 문서 확인).
--   Humanoid 에 BodyHeightScale 류가 없고 AutomaticScalingEnabled 는 미지원,
--   Model:ScaleTo 도 없다. 있는 건 충돌 캡슐(CapsuleHeight/CapsuleRadius)과
--   메시 위치 보정(CharacterMeshPos) 뿐인데 이건 겉모습이 아니다.
--
--   그래서 스킨드 MeshPart 의 Size 를 직접 키워보는 실험을 넣었다.
--   ODA 아바타는 스켈레톤으로 변형되므로 Size 가 안 먹을 수 있다. 결과는 로그로 확인한다.
--   1 이면 아무것도 안 한다.
local CHARACTER_SCALE = 1.25
local MOVE_THRESHOLD_CM_PER_SEC = 30
local SAMPLE_WINDOW = 0.25

local playerStates = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local attackEvent = ReplicatedStorage:WaitForChild("WeaponAttackEvent", 5)

local rightPartRelCFs = {}
local leftPartRelCFs = {}

-- ★ 임포트된 칼 파츠는 게임 월드 기준으로 2.4배 작다.
--   블렌더에서 칼 전체 길이가 0.3347 유닛이고 좌표 추출 배율이 1유닛=240cm 이므로
--   제 크기는 80cm 여야 하는데, FBX 가 100/유닛으로 들어와 33cm 로 임포트됐다.
--   뷰모델의 Config.SCALE = 2.4 도 확대가 아니라 이 단위 보정이다.
--   크기가 안 맞아 보이면 이 숫자 하나만 고치면 된다.
local WORLD_WEAPON_SCALE = 2.4

local function attachWorldWeapon(character)
	if character:FindFirstChild("Wakizashi_Right_Hand_Weapon") then
		return
	end
	local source = ReplicatedStorage:FindFirstChild("Wakizashi_Viewmodel_Split")
		or Workspace:FindFirstChild("Wakizashi_Viewmodel_Split")
		or ReplicatedStorage:FindFirstChild("Wakizashi_Viewmodel_Model")
		or Workspace:FindFirstChild("Wakizashi_Viewmodel_Model")

	if not source then
		return
	end

	local rightModel = Instance.new("Model")
	rightModel.Name = "Wakizashi_Right_Hand_Weapon"

	local leftModel = Instance.new("Model")
	leftModel.Name = "Wakizashi_Left_Hand_Weapon"

	local sourcePivot = source.WorldPivot or CFrame.new()

	-- ★ 칼을 손에 "쥐게" 하려면 기준점이 모델 피벗이 아니라 손잡이여야 한다.
	--    피벗 기준으로 놓으면 칼이 손에서 한참 떨어진 곳에 뜬다.
	--    Wrap(손잡이끈) 파츠의 중심을 쥐는 지점으로 삼는다.
	local gripR, gripL = nil, nil
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") and string.find(d.Name, "Wrap") then
			if string.find(d.Name, "_R_") then
				gripR = d.CFrame
			elseif string.find(d.Name, "_L_") then
				gripL = d.CFrame
			end
		end
	end
	-- 손잡이를 못 찾으면 기존대로 모델 피벗을 쓴다
	gripR = gripR or sourcePivot
	gripL = gripL or sourcePivot

	for _, descendant in ipairs(source:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local name = descendant.Name
			if (name:find("_R_") or name:find("_Blade_R") or name:find("Right")) and not name:find("Arm") then
				local clone = descendant:Clone()
				-- ★ Anchored = false 면 물리에 맡겨져 그냥 낙하해 사라진다.
				--    이 파츠들은 매 프레임 CFrame 으로만 움직이므로 반드시 고정이다.
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				pcall(function() clone.DoubleSided = true end)
				clone.Size = clone.Size * WORLD_WEAPON_SCALE
				-- 위치도 같은 배율로 벌려야 조립이 흐트러지지 않는다 (회전은 그대로)
				local relR = gripR:Inverse() * descendant.CFrame
				rightPartRelCFs[clone] = CFrame.new(relR.Position * WORLD_WEAPON_SCALE) * (relR - relR.Position)
				clone.Parent = rightModel
			elseif (name:find("_L_") or name:find("_Blade_L") or name:find("Left")) and not name:find("Arm") then
				local clone = descendant:Clone()
				-- ★ Anchored = false 면 물리에 맡겨져 그냥 낙하해 사라진다.
				--    이 파츠들은 매 프레임 CFrame 으로만 움직이므로 반드시 고정이다.
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				pcall(function() clone.DoubleSided = true end)
				clone.Size = clone.Size * WORLD_WEAPON_SCALE
				-- 위치도 같은 배율로 벌려야 조립이 흐트러지지 않는다 (회전은 그대로)
				local relL = gripL:Inverse() * descendant.CFrame
				leftPartRelCFs[clone] = CFrame.new(relL.Position * WORLD_WEAPON_SCALE) * (relL - relL.Position)
				clone.Parent = leftModel
			end
		end
	end

	rightModel.Parent = character
	leftModel.Parent = character
end

-- ★ 칼 위치 계산은 클라이언트(ViewmodelController)로 옮겼다.
--   서버의 본은 애니메이션이 반영되지 않는다 (바인드 포즈로 고정). 실측으로 확인했다 :
--   SwordIdle 이 도는 10초 동안 칼 기울기가 72.8 / -14.9 에서 소수점까지 안 변했다.
--   그래서 서버에서 배치하면 칼이 팔을 따라가지 않는다.
--
--   지금 역할 분담 :
--     서버   - 파츠를 만들어 붙인다 (그래야 모든 유저에게 존재한다)
--     클라이언트 - 매 프레임 위치를 잡는다 (자기 쪽 본은 애니메이션이 반영돼 있다)
--
--   서버가 CFrame 을 쓰면 복제되면서 클라이언트가 잡아둔 위치를 덮어쓴다. 그래서 안 쓴다.

-- ★ 아바타는 옷/액세서리와 무관하게 항상 같은 모습으로 고정한다.
--   옷을 입으면 1인칭 뷰모델이 망가지기 때문이다 (파츠가 추가로 붙어 팔 위치·가림이 어긋난다).
--   WrapLayer/WrapTarget 은 ODA 의 변형 의상 시스템이라 몸 형태 자체를 바꾼다. 같이 지운다.
local APPAREL_CLASSES = {
	Shirt = true, Pants = true, ShirtGraphic = true, Accessory = true,
	WrapLayer = true, WrapTarget = true, CharacterMesh = true, Decal = true,
}

local function stripCharacterApparel(character)
	for _, child in ipairs(character:GetDescendants()) do
		local className = ""
		pcall(function() className = child.ClassName end)
		local nameLower = string.lower(child.Name)
		if child.Name:find("Wakizashi") or (child.Parent and child.Parent.Name:find("Wakizashi")) then
			-- Keep world hand weapons
		elseif APPAREL_CLASSES[className] or child:IsA("Shirt") or child:IsA("Pants") then
			pcall(function() child:Destroy() end)
		elseif child:IsA("BasePart") then
			local isStandardPart = nameLower:find("root") or nameLower:find("torso") or nameLower:find("head") or nameLower:find("arm") or nameLower:find("leg") or nameLower:find("foot") or nameLower:find("hand")
			if not isStandardPart then
				pcall(function() child:Destroy() end)
			end
		end
	end
end

if attackEvent then
	attackEvent.OnServerEvent:Connect(function(player, attackIndex)
		if player and player.Character then
			attackEvent:FireAllClients(player, attackIndex)
		end
	end)
end

-- 캐릭터를 키워본다. 공식 경로가 없어서 될지 안 될지 로그로 확인한다.
--   1) 충돌 캡슐 (확실히 먹는다. 다만 겉모습이 아니라 판정 크기다)
--   2) 신체 MeshPart 의 Size (스킨드 메시라 안 먹을 수 있다)
local scaleReported = false
local function applyCharacterScale(character, humanoid)
	if CHARACTER_SCALE == 1 then
		return
	end

	local capOk = pcall(function()
		humanoid.CapsuleHeight = 164 * CHARACTER_SCALE
		humanoid.CapsuleRadius = 24 * CHARACTER_SCALE
		humanoid.CharacterMeshPos = Vector3.new(0, -85 * CHARACTER_SCALE, 0)
	end)

	local meshOk, meshCount = false, 0
	pcall(function()
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and not d.Name:find("Wakizashi") and d.Name ~= "AllyDot" then
				d.Size = d.Size * CHARACTER_SCALE
				meshCount = meshCount + 1
			end
		end
		meshOk = meshCount > 0
	end)

	-- 스케일 적용 결과 로그는 확인이 끝나서 뺐다 (캡슐·파츠 둘 다 true).
	-- 스케일이 다시 의심스러우면 여기서 capOk / meshCount / meshOk 를 찍어봐라.
	if not scaleReported then
		scaleReported = true
	end
end

local function setupPlayer(player, character)
	stripCharacterApparel(character)
	attachWorldWeapon(character)
	character.DescendantAdded:Connect(function(desc)
		task.defer(function()
			stripCharacterApparel(character)
		end)
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	local root = humanoid.RootPart
	if not root then
		return
	end

	-- 이동/점프. WalkSpeed 는 서버에서만 설정된다.
	pcall(function()
		humanoid.WalkSpeed = BASE_WALK_SPEED
	end)
	pcall(function()
		humanoid.JumpHeight = JUMP_HEIGHT
	end)

	applyCharacterScale(character, humanoid)

	playerStates[player] = {
		humanoid = humanoid,
		root = root,
		base = BASE_WALK_SPEED,
		current = BASE_WALK_SPEED,
		moving = false,
		windowStartPos = root.Position,
		windowTime = 0,
	}
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupPlayer(player, character)
	end)
	if player.Character then
		setupPlayer(player, player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if not playerStates[player] then
		player.CharacterAdded:Connect(function(character)
			setupPlayer(player, character)
		end)
		if player.Character then
			setupPlayer(player, player.Character)
		end
	end
end

	RunService.Heartbeat:Connect(function(dt)
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
				-- 만들기만 한다. 위치는 클라이언트가 잡는다 (위 설명 참고)
				attachWorldWeapon(child)
			end
		end
		for player, state in pairs(playerStates) do
			if state.humanoid and state.humanoid.Parent and state.root and state.root.Parent then
			state.windowTime = state.windowTime + dt

			if state.windowTime >= SAMPLE_WINDOW then
				local pos = state.root.Position
				local delta = Vector3.new(pos.X - state.windowStartPos.X, 0, pos.Z - state.windowStartPos.Z)
				local avgSpeed = delta.Magnitude / state.windowTime
				state.moving = avgSpeed > MOVE_THRESHOLD_CM_PER_SEC
				state.windowStartPos = pos
				state.windowTime = 0
			end

			local target = state.moving and (state.base * RUN_MULTIPLIER) or state.base
			local span = math.abs((state.base * RUN_MULTIPLIER) - state.base)
			local rate = span / RAMP_TIME
			if rate <= 0 then
				rate = 1
			end

			if state.current < target then
				state.current = math.min(target, state.current + rate * dt)
			elseif state.current > target then
				state.current = math.max(target, state.current - rate * dt)
			end

			-- 죽었거나 패링당해 기절한 캐릭터는 움직이면 안 된다.
			-- CombatServer 가 켜고 끈다 (사망 / M.stun).
			-- ★ 걷기만 막으면 점프로 도망갈 수 있다. 점프도 같이 죽인다.
			local frozen = _G.MovementFreeze ~= nil and _G.MovementFreeze[player] == true
			if frozen then
				state.current = 0
			end
			-- 상태가 바뀔 때만 점프를 만진다. 매 프레임 쓰면 낭비다.
			if frozen ~= state.jumpKilled then
				state.jumpKilled = frozen
				pcall(function()
					state.humanoid.JumpHeight = frozen and 0 or JUMP_HEIGHT
				end)
			end
			if state.humanoid.WalkSpeed ~= state.current then
				state.humanoid.WalkSpeed = state.current
			end
		else
			playerStates[player] = nil
		end
	end
end)
