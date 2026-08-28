local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- 조정 숫자는 ViewmodelConfig, 애니메이션 데이터는 ViewmodelAnimData 에서 관리한다.
local Config = require(ReplicatedStorage:WaitForChild("ViewmodelConfig"))
local Anim = require(ReplicatedStorage:WaitForChild("ViewmodelAnimData"))

local VIEWMODEL_SOURCE_NAME = "Wakizashi_Viewmodel_Split"
local RUNTIME_VIEWMODEL_NAME = "Wakizashi_Viewmodel_Runtime"

local POSE_ALIAS_BY_PART: {[string]: string} = {
	Wakizashi_R_Blade = "Wakizashi_Blade_R",
	Wakizashi_R_Hamon = "Wakizashi_Blade_R",
	Wakizashi_R_Guard = "Wakizashi_Blade_R",
	Wakizashi_R_Wrap = "Wakizashi_Blade_R",
	Wakizashi_R_Brass = "Wakizashi_Blade_R",
	Wakizashi_R_RaySkin = "Wakizashi_Blade_R",
	Wakizashi_L_Blade = "Wakizashi_Blade_L",
	Wakizashi_L_Hamon = "Wakizashi_Blade_L",
	Wakizashi_L_Guard = "Wakizashi_Blade_L",
	Wakizashi_L_Wrap = "Wakizashi_Blade_L",
	Wakizashi_L_Brass = "Wakizashi_Blade_L",
	Wakizashi_L_RaySkin = "Wakizashi_Blade_L",
	-- 쿠나이는 임포트할 때 머티리얼별로 쪼개진다 (Steel / Wrap)
	Kunai = "Kunai",
	Kunai_Steel = "Kunai",
	Kunai_Wrap = "Kunai",
	M_Kunai_Steel = "Kunai",
	M_Kunai_Wrap = "Kunai",
}

-- 이름이 Kunai 로 시작하는 파츠는 전부 쿠나이로 취급한다.
-- (임포트 결과 이름이 위 표와 달라도 걸리도록)
local function isKunaiPartName(name: string): boolean
	return string.sub(name, 1, 5) == "Kunai"
end

local CAMERA_OFFSET = CFrame.new(Config.OFFSET_X, Config.OFFSET_Y, Config.OFFSET_Z)
local VIEWMODEL_SCALE = Config.SCALE
local VIEWMODEL_DIRECTION_FIX = CFrame.Angles(0, math.rad(180), 0)
local SOURCE_PIVOT = CFrame.new(Config.PIVOT_X, Config.PIVOT_Y, Config.PIVOT_Z)
local INTRO_DELAY = Config.INTRO_DELAY

local COMBO = Config.COMBO or Anim.COMBO
local COLORS = Config.COLORS or {}
local MATERIALS = Config.MATERIALS or {}

local POS_SCALE = Anim.POS_SCALE
local PART_ORDER = Anim.PART_ORDER

local BREATHE_Y_SPEED, BREATHE_Y_AMOUNT = 1.4, 1.6
local BREATHE_X_SPEED, BREATHE_X_AMOUNT = 0.7, 0.9
local BREATHE_ROT_AMOUNT = 0.8
local SPRING_STIFFNESS, SPRING_DAMPING = 140, 16

local viewmodel = nil
local viewmodelPartsByName = {}

local breatheTime = 0
local kickOffset, kickVelocity = 0, 0

local introPlayed, introActive = false, false
local introElapsed, introDelayLeft = 0, 0

-- 공격 콤보 상태
local attackActive = false
local attackIndex = 0
local attackElapsed = 0
local comboQueued = false

-- 막기 상태: "none"(안 막음) / "in"(켜는 중) / "hold"(막고 정지) / "out"(푸는 중)
local blockState = "none"
local blockElapsed = 0

-- ★ 오토디펜스는 "잠깐 막고 마는" 반응이다. 버튼 방어처럼 hold 로 붙잡으면 안 된다.
--   붙잡히면 맞은 뒤 바로 반격을 못 해서 일방적으로 밀린다.
--   자동 경로임을 표시해두고, BlockIn 이 끝나면 hold 로 가지 않고 바로 BlockOut 으로 넘긴다.
local autoBlockPose = false

-- ===== 근접 히트 판정 =====
-- ★ 판정 자체는 서버(CombatServer)가 한다. 여기서는 "누구를 겨눴다" 만 보고한다.
--   클라이언트가 "죽였다" 고 말하게 두면 조작당한다. 서버가 거리·팀·무적을 다시 검사한다.
--
-- 지역변수 한도(200개) 때문에 테이블 하나로 묶었다. 낱개 local 로 늘리면 뷰모델이 안 뜬다.
-- 방어 상태 전송·오토디펜스 수신도 이 이벤트를 쓰므로 막기 함수보다 앞에 둔다.
local MELEE = {
	RANGE = 380,               -- 칼이 닿는 거리 (cm)
	RADIUS = 130,              -- 조준이 빗나가도 잡아주는 관용 반경 (cm)
	AT = 1.0,                  -- 공격 시작 후 이 시점에 판정 (XBLADE_AT 과 같은 순간)
	fired = false,             -- 한 타에 한 번만
	event = ReplicatedStorage:WaitForChild("CombatEvent", 10),
}

-- 쿠나이 스킬 상태. 막기/공격 함수보다 먼저 선언해야 거기서 참조할 수 있다.
local flyingRaijinActive = false
local flyingRaijinElapsed = 0
local flyingRaijinKunaiSpawned = false
local flyingRaijinProjectile = nil

-- 쿨타임은 쿠나이가 나가 있는 동안(TP 가능 구간)에는 흐르지 않는다.
-- 순간이동을 했거나, 회수 못 하고 쿠나이가 사라진 그 시점부터 10초가 돈다.
local FLYINGRAIJIN_COOLDOWN = 10
local flyingRaijinCooldown = 0
local flyingRaijinButton = nil
local flyingRaijinButtonText = "skill"

-- 3타 X자 참격 이펙트 상태
local xblade = nil
local xbladeDash = nil
local xbladeSpawned = false
local xbladeDashStarted = false

-- 칼 다시 빼드는 모션. 쿠나이 스킬이 끝난 뒤(순간이동/시간초과 둘 다) 이어서 나간다.
local DRAW_CLIP_NAME = "Draw"
local drawActive = false
local drawElapsed = 0

-- ===== 궁극기 [용의 이빨 / Ryunochi] 상태 =====
-- 재생 중에는 플레이어가 아무것도 조작하지 못하고, 스크립트가 이동을 전부 대신한다.
-- 클립의 jumpAt(71f) 에서 점프하고, 공중에 떠 있는 동안은 airHoldStart(71f) 자세에서
-- 시간을 멈춘다. 실제로 착지하면 대기가 풀려 80f(착지) 를 지나 100f 까지 이어 재생된다.
local RYUNOCHI_CLIP_NAME = "Ryunochi"
local ultActive = false
local ultElapsed = 0
local ultCooldown = 0
local ultMotion = nil       -- { dir, vy, jumped, grounded, rayParams }
local ultButton = nil
local ultButtonText = "ult"

-- 궁극기 중에는 공격·막기·강공격이 전부 잠긴다.
local function isUltCommitted()
	return ultActive
end

-- 쿠나이를 던져놓고 아직 회수(순간이동)하지 않은 상태.
-- 이 동안에는 공격도 막기도 안 된다.
local function isFlyingRaijinCommitted()
	return flyingRaijinActive or flyingRaijinProjectile ~= nil or drawActive
end

-- 클립 조회. 먼저 ViewmodelAnimData 안에서 찾고, 없으면
-- ReplicatedStorage 의 "ViewmodelAnim<이름>" 모듈을 찾아 쓴다.
local clipCache = {}
local function getClip(name)
	if not name then
		return nil
	end

	-- ★ 나라별 클립 분리 (2026-08-26).
	--   팔 파츠 이름(Right_Arm_Mesh / Left_Arm_Mesh)이 나라끼리 똑같아서, 여기서 거르지 않으면
	--   국궁을 들고도 와키자시 공격/막기 클립이 국궁 팔을 그대로 몰고 간다.
	--   (팔만 칼 휘두르듯 움직이고 활은 제자리에 멈춰 있다)
	--
	--   CLIPS 표를 가진 나라는 그 표에 적힌 클립만 쓴다. 왼쪽이 컨트롤러가 부르는 이름,
	--   오른쪽이 실제 모듈 이름이다. 표에 없는 이름은 "그 나라엔 아직 없는 동작"이라
	--   nil 로 돌려보낸다. 부르는 쪽은 전부 nil 을 정상 처리한다 —
	--   공격/막기는 그냥 안 나가고, 궁극기/스킬은 이미 없음 로그를 찍는다.
	--
	--   CLIPS 가 없는 나라(일본)는 이 블록을 그냥 지나쳐서 예전과 똑같이 동작한다.
	--   clipCache 는 '바뀐 뒤' 이름으로 걸리므로 나라끼리 섞이지 않는다.
	local ch = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
	if ch and ch.CLIPS then
		name = ch.CLIPS[name]
		if not name then
			return nil
		end
	end

	if clipCache[name] ~= nil then
		return clipCache[name] or nil
	end

	local clip = Anim[name]
	if not clip then
		local mod = ReplicatedStorage:FindFirstChild("ViewmodelAnim" .. name)
		if mod then
			local ok, result = pcall(require, mod)
			if ok then
				clip = result
			else
				print("[ViewmodelController] '" .. name .. "' 모듈 로드 실패")
			end
		end
	end

	if not clip then
		print("[ViewmodelController] 애니메이션을 찾을 수 없음: " .. name)
	end
	clipCache[name] = clip or false
	return clip
end

-- OVERDARE CFrame 에는 쿼터니언 생성자가 없어서 회전행렬로 만들어 넣는다.
local function quatToCFrame(px, py, pz, qw, qx, qy, qz)
	local x2, y2, z2 = qx + qx, qy + qy, qz + qz
	local xx, xy, xz = qx * x2, qx * y2, qx * z2
	local yy, yz, zz = qy * y2, qy * z2, qz * z2
	local wx, wy, wz = qw * x2, qw * y2, qw * z2
	return CFrame.fromMatrix(
		Vector3.new(px, py, pz),
		Vector3.new(1 - (yy + zz), xy + wz, xz - wy),
		Vector3.new(xy - wz, 1 - (xx + zz), yz + wx),
		Vector3.new(xz + wy, yz - wx, 1 - (xx + yy))
	)
end

-- posScale: 클립마다 다를 수 있다.
--   기존 클립들은 Wakizashi_Viewmodel_Model 기준으로 뽑혀 269 를 쓴다.
--   새로 뽑는 클립은 실제로 쓰이는 Wakizashi_Viewmodel_Split 기준(240)이 정확하다.
local function deltaAt(partIndex, row, posScale)
	local s = posScale or POS_SCALE
	local o = 2 + (partIndex - 1) * 7
	return quatToCFrame(
		row[o] * s, row[o + 1] * s, row[o + 2] * s,
		row[o + 3], row[o + 4], row[o + 5], row[o + 6]
	)
end

-- partOrder: 클립마다 움직이는 파츠 목록이 다를 수 있다.
-- 생략하면 기존 4파츠 순서(PART_ORDER)를 쓴다.
local function evaluate(frames, t, partOrder, posScale)
	partOrder = partOrder or PART_ORDER
	local a, b = frames[1], frames[#frames]
	for i = 1, #frames - 1 do
		if t >= frames[i][1] and t <= frames[i + 1][1] then
			a, b = frames[i], frames[i + 1]
			break
		end
	end

	local span = b[1] - a[1]
	local alpha = 0
	if span > 0 then
		alpha = (t - a[1]) / span
		if alpha < 0 then alpha = 0 end
		if alpha > 1 then alpha = 1 end
	end

	local result = {}
	for i, partName in ipairs(partOrder) do
		result[partName] = deltaAt(i, a, posScale):Lerp(deltaAt(i, b, posScale), alpha)
	end
	return result
end

local function currentAttackClip()
	return getClip(COMBO[attackIndex])
end

-- ===== 칼 다시 빼드는 모션 =====
-- Draw 클립의 첫 자세가 KunaiThrow 의 정지 자세(holdAt)와 동일해서
-- 던진 자세에서 튐 없이 그대로 이어진다.
local function startDraw()
	if getClip(DRAW_CLIP_NAME) then
		drawActive = true
		drawElapsed = 0
	end
end

local function updateDraw(dt)
	if not drawActive then
		return nil
	end
	local clip = getClip(DRAW_CLIP_NAME)
	if not clip then
		drawActive = false
		return nil
	end
	drawElapsed = drawElapsed + dt
	if drawElapsed >= clip.full then
		drawActive = false
		return nil
	end
	return evaluate(clip.frames, drawElapsed, clip.parts, clip.posScale)
end

local weaponAttackEvent = ReplicatedStorage:WaitForChild("WeaponAttackEvent", 5)

-- 스킬 연출 공용 통로. 서버(RyunochiServer)가 전원에게 되뿌린다.
-- 쿠나이 던지기처럼 이 파일 위쪽에서도 쏴야 해서 여기로 올려뒀다.
-- (선언보다 위에서 부르면 지역변수가 아니라 nil 전역이 잡힌다)
local ryuEvent = ReplicatedStorage:WaitForChild("RyunochiEvent", 10)

local function ryuFire(payload)
	if ryuEvent then
		pcall(function()
			ryuEvent:FireServer(payload)
		end)
	end
end

-- ===== 남의 연출 상한 =====
-- 여러 명이 동시에 스킬을 쓰면 파츠가 폭발적으로 늘어난다.
-- 궁극기 한 번에 용 44 + 균열 32 + 바위 38 = 114개, 순간이동 한 번에 연막 28개다.
-- 인원이 늘어도 프레임이 버티도록 거리로 한 번, 개수로 한 번 거른다.
-- 내 연출은 상한에 걸리지 않는다. 남의 것만 줄인다.
local FX_LIMIT = {
	-- ★ 2026-08-19 : 18000(180m) 이었는데 맵이 바뀌면서 남의 이펙트가 전부 사라졌다.
	--   경복궁은 61x116m 라 대각선 131m, 통째로 180m 안이라 이 컷이 한 번도 발동한 적이 없었다.
	--   JSN_Sangok 은 259x271m 라 대각선 375m. 조금만 떨어져도 전부 걸러졌다.
	--   맵을 새로 넣을 때마다 이 값이 맵을 덮는지 확인할 것.
	RANGE = 40000,     -- 이 거리 밖에서 벌어진 남의 연출은 아예 안 만든다 (cm) = 400m
	KUNAI = 8,         -- 동시에 그리는 남의 쿠나이
	DRAGONS = 4,       -- 동시에 그리는 남의 용
	DEBRIS = 9,        -- 동시에 남아있는 파괴 연출 세트. 궁극기 한 번에 3세트(균열/고리/부채꼴)
	LOGS = 10,         -- 동시에 남아있는 통나무
	PUFFS = 160,       -- 동시에 떠 있는 연막 덩어리
	XBLADES = 6,       -- 동시에 그리는 남의 X자 참격. 하나에 파츠 30개다
}

-- 카메라에서 이만큼 떨어진 곳의 연출은 만들 필요가 없다.
-- 어차피 화면에서 점만도 못하게 보이는데 파츠 비용은 똑같이 든다.
local function fxTooFar(pos)
	if not pos then
		return false
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return false
	end
	local d = (cam.CFrame.Position - pos).Magnitude
	if d > FX_LIMIT.RANGE then
		-- 이게 찍히면 남의 이펙트가 거리 때문에 안 만들어진 것이다.
		-- 맵을 키웠는데 이펙트가 안 보이면 제일 먼저 의심할 자리다.
		print(string.format("[FX] 거리 컷 : %.0fm > %.0fm - 남의 연출을 만들지 않음",
			d / 100, FX_LIMIT.RANGE / 100))
		return true
	end
	return false
end

local otherAttackStates = {}

if weaponAttackEvent then
	weaponAttackEvent.OnClientEvent:Connect(function(attackingPlayer, attackIdx)
		if attackingPlayer and attackingPlayer ~= LocalPlayer then
			otherAttackStates[attackingPlayer] = {
				index = attackIdx,
				elapsed = 0,
			}
		end
	end)
end

-- 이 신호로 3인칭 아바타 공격 모션과 남의 화면 뷰모델 재생이 같이 돈다.
-- (AvatarAnimServer 와 MovementSpeedServer 가 각각 듣는다)
local function fireServerAttack(idx)
	if not weaponAttackEvent then
		print("[Viewmodel] WeaponAttackEvent 가 nil - 서버로 공격 신호를 못 보낸다")
		return
	end
	pcall(function()
		weaponAttackEvent:FireServer(idx)
	end)
end

-- ===== 3인칭 칼 배치 =====
--
-- 서버는 파츠를 만들기만 하고, 위치는 여기서 잡는다.
-- 서버의 본은 애니메이션이 반영되지 않아 (바인드 포즈 고정) 칼이 팔을 안 따라가기 때문이다.
-- 자기 쪽 본은 애니메이션이 반영돼 있으므로 여기서 계산해야 팔을 따라간다.
--
-- 내 칼은 1인칭에서 숨겨져 있으니 남의 것만 잡으면 된다.
-- 내 칼을 남들이 보는 위치는 그쪽 클라이언트가 각자 잡는다.
local WORLD_WEAPON = {
	-- 임포트된 칼이 월드 기준 2.4배 작다. 서버가 Size 를 이미 키웠으니 위치도 같은 배율로 벌린다.
	SCALE = 2.4,
	-- 캐릭터 기준 미세 보정 (cm) : X=오른쪽 Y=위 Z=앞
	--
	-- ★ 0 이 기본값이다. 손잡이(Wrap) 중심이 본에 정확히 얹히도록 만들어놨기 때문에
	--   보정이 없어야 손에 제대로 쥔 그림이 나온다.
	--   예전에 20/14 를 쓰던 건 서버의 "바인드 포즈" 본에 맞춘 값이라 여기선 안 맞는다.
	RIGHT_OFFSET = Vector3.new(0, 0, 0),
	--   왼손 칼이 손을 뚫고 앞으로 나와 있어서 Z=11 을 0 으로 되돌렸다 (2026-08-16).
	--   Z 는 캐릭터 정면 방향이라 키우면 앞으로, 줄이면 뒤로 간다.
	LEFT_OFFSET = Vector3.new(0, 0, 0),
	-- 손 기준 회전. 아래 FROM_BLENDER 가 false 일 때만 쓰인다.
	RIGHT_ROT = CFrame.Angles(0, 0, 0),
	LEFT_ROT = CFrame.Angles(0, 0, 0),

	-- ★ 칼이 향하는 방향을 블렌더 기준자세(프레임 10)에서 그대로 가져온다.
	--   본의 회전을 쓰면 손목 관례가 달라서 엉뚱한 자세(칼끝으로 찌르는 모양)가 나온다.
	--   위치는 본을 따라가고 방향만 여기서 정하므로, 팔은 그대로 따라다닌다.
	--   false 로 하면 예전처럼 본 회전 + ROT 보정 방식으로 돌아간다.
	FROM_BLENDER = true,

	-- 캐릭터 기준 성분 : R = 오른쪽, F = 앞, U = 위
	--   DIR  = 칼 길이 방향 (손잡이 -> 칼끝)
	--   EDGE = 날 폭 방향. 이게 칼을 자기 축으로 얼마나 굴릴지를 정한다
	--
	--   블렌더 FakeFPSCamera 로 확인 : 카메라의 오른쪽 = 블렌더 +X. 부호 그대로 쓴다.
	--
	--   ★ 블렌더의 Right/Left 이름이 화면 좌우와 반대다. 실측 :
	--       Right_Arm_Mesh 손 = 카메라 기준 오른쪽 -0.216  (화면 왼쪽)
	--       Left_Arm_Mesh  손 = 카메라 기준 오른쪽 +0.171  (화면 오른쪽)
	--     그래서 _L_ 칼이 캐릭터의 오른손, _R_ 칼이 왼손이다. 아래 HANDS 에서 바꿔 붙인다.
	--
	--   오른손(_L_ 칼) : 칼끝이 앞을 향한다
	--   왼손(_R_ 칼)   : 옆으로 눕고 날이 앞을 향한다
	RIGHT_DIR = { R = 0.010, F = 0.995, U = 0.103 },
	-- EDGE 를 통째로 뒤집으면 칼이 자기 길이축으로 180도 굴러 날/등이 바뀐다.
	-- 블렌더에서 잰 값 그대로 넣으니 날이 위로 갔다. 날 축 부호가 반대여서 뒤집었다.
	RIGHT_EDGE = { R = 0.095, F = -0.104, U = 0.990 },
	LEFT_DIR = { R = 0.958, F = 0.150, U = 0.245 },
	LEFT_EDGE = { R = -0.165, F = 0.985, U = 0.045 },
}

-- 어느 칼을 어느 본에 붙일지. 위 설명대로 이름과 실제 좌우가 반대라 바꿔 단다.
local HANDS = {
	{ model = "Wakizashi_Left_Hand_Weapon", blade = "Wakizashi_L_Blade", bone = "RightItem", right = true },
	-- hideOnRaijin : 비뢰신(쿠나이 투척) 동안 이 손의 칼을 숨긴다.
	-- 쿠나이를 쥔 손에 칼이 그대로 붙어 있으면 이상하다.
	-- ★ 이름이 화면 좌우와 반대다. bone = LeftItem 이 캐릭터의 왼손이다.
	{ model = "Wakizashi_Right_Hand_Weapon", blade = "Wakizashi_R_Blade", bone = "LeftItem", right = false,
		hideOnRaijin = true },
}

-- 비뢰신 중 칼을 숨길 대상. 지역변수 한도(200개) 때문에 테이블 하나로 묶었다.
--   hide[player] = true  이면 그 플레이어의 해당 손 칼을 안 그린다
--   last         = 내 상태를 마지막으로 서버에 알린 값 (바뀔 때만 쏜다)
local RAIJIN_HAND = { hide = {}, last = false }

local worldWeaponRestCFrames = {}

-- 손잡이(Wrap) 기준 상대 위치. 원본 모델에서 이름으로 짝을 찾아 한 번만 계산하고 캐시한다.
local function getWorldWeaponRestCFrame(part, worldWeapon)
	if worldWeaponRestCFrames[part] then
		return worldWeaponRestCFrames[part]
	end
	local source = Workspace:FindFirstChild("Wakizashi_Viewmodel_Split")
		or ReplicatedStorage:FindFirstChild("Wakizashi_Viewmodel_Split")
	if not source then
		return CFrame.new()
	end
	local tag = string.find(worldWeapon.Name, "Right") and "_R_" or "_L_"
	local grip, src = nil, nil
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == part.Name then
				src = d
			end
			if string.find(d.Name, "Wrap") and string.find(d.Name, tag) then
				grip = d.CFrame
			end
		end
	end
	if not (grip and src) then
		return CFrame.new()
	end
	local rel = grip:Inverse() * src.CFrame
	-- 위치만 배율을 먹이고 회전은 그대로 둔다
	local rest = CFrame.new(rel.Position * WORLD_WEAPON.SCALE) * (rel - rel.Position)
	worldWeaponRestCFrames[part] = rest
	return rest
end

-- CFrame 의 로컬 축을 꺼낸다. RightVector/UpVector 는 이 프로젝트에서 쓴 적이 없어
-- 곱셈과 .Position 만으로 구한다 (둘 다 이미 검증된 경로다).
local function localAxis(cf, x, y, z)
	return (cf * CFrame.new(x, y, z)).Position - cf.Position
end

-- 두 방향으로 정규직교 프레임을 만든다.
-- ※ CFrame.fromMatrix 는 반드시 인자 4개로 부른다. 3개면 OVERDARE 에서 축이 어긋난다.
local function orthoFrame(a, b)
	if not (a and b) or a.Magnitude < 0.0001 then
		return nil
	end
	a = a.Unit
	local c = a:Cross(b)
	if c.Magnitude < 0.0001 then
		return nil          -- 두 방향이 나란하면 프레임을 못 만든다
	end
	c = c.Unit
	return CFrame.fromMatrix(Vector3.new(), a, c:Cross(a), c)
end

-- 캐릭터 기준 보정을 월드 벡터로. 위(Y)는 캐릭터가 기울어도 월드 기준 위 그대로다.
local function worldWeaponShift(root, offset)
	local shift = Vector3.new(0, offset.Y, 0)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then
		return shift
	end
	flat = flat.Unit
	return shift + Vector3.new(-flat.Z, 0, flat.X) * offset.X + flat * offset.Z
end

local function updateOtherPlayersWorldWeapons(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		-- 캐릭터가 없으면(리스폰/접속종료) 숨김 상태를 흘려보낸다.
		-- 안 그러면 스킬 도중에 죽은 사람의 칼이 영영 안 보인다.
		if not player.Character then
			RAIJIN_HAND.hide[player] = nil
		end
		if player ~= LocalPlayer and player.Character then
			local char = player.Character
			local skel = char:FindFirstChild("Skeleton")
			local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
			if skel and root then
				for _, hand in ipairs(HANDS) do
					local model = char:FindFirstChild(hand.model)

					-- 비뢰신 중이면 쿠나이를 쥔 손의 칼을 숨긴다.
					-- 위치 계산은 건너뛴다. 어차피 안 보이는데 매 프레임 CFrame 을 잡을 이유가 없다.
					if model and hand.hideOnRaijin and RAIJIN_HAND.hide[player] then
						for _, part in ipairs(model:GetChildren()) do
							if part:IsA("BasePart") then
								part.Transparency = 1
							end
						end
						model = nil
					end

					-- ODA 아바타는 손 파츠가 없다. 장비 부착 본이 RightItem / LeftItem 이다.
					local bone = skel:FindFirstChild(hand.bone, true)
					local ok, boneCF = pcall(function()
						return bone and bone.TransformedWorldCFrame
					end)
					if model and ok and boneCF then
						local isRight = hand.right
						local off = isRight and WORLD_WEAPON.RIGHT_OFFSET or WORLD_WEAPON.LEFT_OFFSET
						local rot = isRight and WORLD_WEAPON.RIGHT_ROT or WORLD_WEAPON.LEFT_ROT
						-- 기본 : 본 회전을 그대로 쓴다
						local base = CFrame.new(worldWeaponShift(root, off)) * boneCF * rot

						if WORLD_WEAPON.FROM_BLENDER then
							-- 방향을 블렌더 기준자세에서 가져온다. 위치는 본을 그대로 따른다.
							local blade = model:FindFirstChild(hand.blade)
							local relB = blade and getWorldWeaponRestCFrame(blade, model)
							if relB then
								local look = root.CFrame.LookVector
								local f = Vector3.new(look.X, 0, look.Z)
								if f.Magnitude > 0.001 then
									f = f.Unit
									local u = Vector3.new(0, 1, 0)
									local r = Vector3.new(-f.Z, 0, f.X)
									local d = isRight and WORLD_WEAPON.RIGHT_DIR or WORLD_WEAPON.LEFT_DIR
									local e = isRight and WORLD_WEAPON.RIGHT_EDGE or WORLD_WEAPON.LEFT_EDGE
									-- 목표 자세 (월드) 와 지금 칼이 그립 안에서 놓인 자세
									local want = orthoFrame(r * d.R + f * d.F + u * d.U,
										r * e.R + f * e.F + u * e.U)
									-- relB.Position 은 손잡이에서 칼날로 가는 방향 = 칼 길이 축 (부호 확실)
									local have = orthoFrame(relB.Position, localAxis(relB, 0, 1, 0))
									if want and have then
										base = CFrame.new(boneCF.Position + worldWeaponShift(root, off))
											* (want * have:Inverse())
									end
								end
							end
						end
						for _, part in ipairs(model:GetChildren()) do
							if part:IsA("BasePart") then
								part.Anchored = true
								part.CanCollide = false
								part.Transparency = 0
								part.CFrame = base * getWorldWeaponRestCFrame(part, model)
							end
						end
					end
				end
			end
		end
	end
end

-- ===== 막기 (토글) =====
-- 버튼을 누르면 BlockIn 을 재생하고 마지막 자세에서 정지("hold"),
-- 다시 누르면 BlockOut 을 재생하고 평상시 자세로 돌아온다.
local function isBlocking()
	return blockState == "in" or blockState == "hold"
end

local function onBlockPressed()
	-- ★ 패링당해 기절 중이면 아무 조작도 못 한다. HUD 가 _G.StunUntil 을 채워준다.
	--   지역변수 한도가 196/200 이라 여기에 변수를 못 늘려서 전역으로 받는다.
	if _G.StunUntil and os.clock() < _G.StunUntil then
		return
	end
	if introActive or introDelayLeft > 0 then
		return
	end
	-- 쿠나이를 던져놓은 동안·궁극기 중에는 막기도 안 된다.
	-- (스킬 포즈가 우선순위상 막기를 덮어써서 상태만 어긋나기 때문)
	if isFlyingRaijinCommitted() or isUltCommitted() then
		return
	end

	if isBlocking() then
		blockState = "out"
		blockElapsed = 0
	else
		blockState = "in"
		blockElapsed = 0
		attackActive = false
		comboQueued = false
	end
	autoBlockPose = false      -- 버튼으로 누른 방어는 붙잡히는 게 맞다
	-- 방어 상태를 서버에 알린다. 주황 배리어가 남들 화면에도 떠야 한다.
	if MELEE.event then
		pcall(function()
			MELEE.event:FireServer({ phase = "block", on = (blockState ~= "out") })
		end)
	end
end

-- ★ 오토디펜스가 막아준 순간, 방어를 안 켜고 있었어도 막기 모션이 나가야 한다.
--   "내가 모르는 데서 맞아 죽지 않게" 하는 장치라 반응이 눈에 보여야 한다.
--   이미 막고 있었다면 자세를 유지한다 (다시 재생하면 끊긴다).
local function playAutoDefencePose()
	-- 이미 버튼으로 막고 있으면 건드리지 않는다. 그 자세가 우선이다.
	if blockState == "hold" or (blockState == "in" and not autoBlockPose) then
		return
	end
	autoBlockPose = true
	blockState = "in"
	blockElapsed = 0
end

-- 오토디펜스가 막아줬다는 서버 신호를 받아 막기 모션을 낸다.
if MELEE.event then
	MELEE.event.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.phase == "autodefence" then
			playAutoDefencePose()
		end
	end)
end

local function updateBlock(dt)
	if blockState == "none" then
		return nil
	end

	local clip = getClip(blockState == "out" and "BlockOut" or "BlockIn")
	if not clip then
		blockState = "none"
		return nil
	end

	-- 정지 구간: 버튼을 다시 누를 때까지 마지막 자세를 유지한다.
	if blockState == "hold" then
		return evaluate(clip.frames, clip.full, clip.parts, clip.posScale)
	end

	blockElapsed = blockElapsed + dt

	if blockElapsed >= clip.full then
		if blockState == "in" then
			if autoBlockPose then
				-- 오토디펜스 반응은 붙잡지 않는다. 바로 풀리는 동작으로 넘어간다.
				blockState = "out"
				blockElapsed = 0
				return evaluate(clip.frames, clip.full, clip.parts, clip.posScale)
			end
			blockState = "hold"
			return evaluate(clip.frames, clip.full, clip.parts, clip.posScale)
		end
		blockState = "none"
		autoBlockPose = false
		return nil
	end

	return evaluate(clip.frames, blockElapsed, clip.parts, clip.posScale)
end

-- ===== 쿠나이 투척 스킬 =====
-- 버튼 -> 던지는 모션 재생 -> clip.throwAt 시점에 뷰모델 쿠나이가 사라지고
-- 월드 투사체가 앞으로 약 10m 날아가다 떨어진다.
local FLYINGRAIJIN_CLIP_NAME = "KunaiThrow"
-- 비행은 2단계다.
--   1) 직선 구간 : 중력 없이 조준선 그대로 FLYINGRAIJIN_STRAIGHT 만큼 곧게 나간다. 회전 없음.
--   2) 급강하    : 전진 속도가 줄고 강한 중력이 걸려 뚝 떨어진다.
-- 회전은 아예 넣지 않는다. 쿠나이는 항상 진행 방향을 향한다.
local FLYINGRAIJIN_SPEED = 3500            -- 비행 속도 (cm/s) = 30 m/s
local FLYINGRAIJIN_STRAIGHT = 2000         -- 곧게 나가는 거리 (cm) = 10m
local FLYINGRAIJIN_DROP_GRAVITY = 4000     -- 직선 구간 이후 낙하 가속 (cm/s^2). 크게 하면 더 뚝 떨어진다
local FLYINGRAIJIN_DROP_SPEED = 0.35       -- 떨어지기 시작하면 전진 속도가 이 비율로 줄어든다
local FLYINGRAIJIN_MAX_TIME = 4            -- 안전장치. 이 시간 넘으면 강제로 멈춘다 (초)
local FLYINGRAIJIN_GROUND_DROP = 120       -- 캐릭터 중심에서 발밑까지 (cm)
-- 박힌 뒤 남아있는 시간 (초). 이 안에 눌러야 순간이동한다.
-- ★ 땅에 박은 건 자리를 잡아두고 쓰는 것이라 여유를 준다.
--   사람에게 박은 건 추격이라 짧아야 긴장이 산다.
local FLYINGRAIJIN_LIFETIME_GROUND = 5
local FLYINGRAIJIN_LIFETIME_PLAYER = 3

-- 이 쿠나이의 수명. 사람에게 박혔는지에 따라 다르다.
local function raijinLifetime(p)
	return (p and p.stuckTo) and FLYINGRAIJIN_LIFETIME_PLAYER or FLYINGRAIJIN_LIFETIME_GROUND
end
local FLYINGRAIJIN_HALF_LEN = 19           -- 쿠나이 중심에서 칼끝까지 (cm). 벽에 꽂을 때 파고드는 보정
local FLYINGRAIJIN_MUZZLE = 60             -- 카메라 앞 몇 cm 에서 출발할지

-- (flyingRaijinActive / flyingRaijinElapsed / flyingRaijinKunaiSpawned / flyingRaijinProjectile 은 파일 상단에 선언돼 있다)

-- 쿠나이 기준자세. 임포트된 위치가 아니라 블렌더에서 계산한 값을 쓴다.
-- 재질별로 쪼개져 들어온 경우 조각마다 위치가 다르므로 clip.kunaiRests 를 먼저 본다.
local kunaiRestCache = {}
local function getKunaiRest(clip, partName)
	if kunaiRestCache[partName] ~= nil then
		return kunaiRestCache[partName] or nil
	end
	local r = nil
	if clip then
		if clip.kunaiRests then
			r = clip.kunaiRests[partName]
		end
		r = r or clip.kunaiRest
	end
	local cf = nil
	if r then
		cf = CFrame.new(r[1], r[2], r[3])
	end
	kunaiRestCache[partName] = cf or false
	return cf
end

-- 쿠나이 메시는 로컬 +Z 가 칼끝이다.
-- 실측: 임포트된 Kunai 파츠의 Size = (1.536, 1.797, 15.943) -> Z 가 압도적으로 길다.
--
-- ※ CFrame.fromMatrix 를 인자 3개로 부르면 OVERDARE 에서 축 해석이 어긋난다.
--   (그래서 쿠나이가 옆면을 보이며 날아갔다)
--   quatToCFrame 은 인자 4개로 부르고 애니메이션 전체가 이걸로 정상 동작하므로
--   여기서는 검증된 그 경로만 쓴다.
--
-- 로컬 +Z 를 heading 으로 보내는 최소 회전 쿼터니언을 직접 만든다.
local function alignZCFrame(pos, heading)
	local f = heading
	if f.Magnitude < 0.0001 then
		f = Vector3.new(0, 0, 1)
	end
	f = f.Unit

	local d = f.Z                       -- (0,0,1) 과의 내적
	if d > 0.99999 then
		return CFrame.new(pos)
	end
	if d < -0.99999 then
		-- 정반대 방향: 수직축(0,1,0) 기준 180도
		return quatToCFrame(pos.X, pos.Y, pos.Z, 0, 0, 1, 0)
	end

	-- (0,0,1) x f
	local cx, cy, cz = -f.Y, f.X, 0
	local w = 1 + d
	local n = math.sqrt(w * w + cx * cx + cy * cy + cz * cz)
	return quatToCFrame(pos.X, pos.Y, pos.Z, w / n, cx / n, cy / n, cz / n)
end

-- 레이가 맞은 파츠가 누구 몸인지 찾는다.
-- ★ Players:GetPlayerFromCharacter 가 이 엔진에 있는지 확인된 적이 없어서 직접 훑는다.
-- ★ 지역변수 한도(196/200) 때문에 MELEE 테이블에 얹는다.
function MELEE.playerFromPart(inst)
	if not inst then
		return nil
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch and pl ~= LocalPlayer then
			local cur = inst
			for _ = 1, 6 do          -- 몸통 밑 6단계까지만 거슬러 올라간다
				if cur == ch then
					return pl
				end
				cur = cur.Parent
				if not cur then
					break
				end
			end
		end
	end
	return nil
end

-- ★★ 투사체 전용 레이캐스트. 풀에 막히는 문제를 여기서 끝낸다.
--
--   레이캐스트는 CanCollide 와 무관하게 맞는다 (Seam 진단에서 이미 겪은 것과 같은 함정).
--   이 맵은 소나무(JSN_Pine)도 풀(JSN_Und)도 CanCollide = 0 이다. 충돌은 전부 JSN_COL 이 맡는다.
--   그래서 몸은 풀숲을 그냥 통과하는데 쿠나이만 풀잎 하나에 막혀 떨어지고 있었다 (2026-08-20).
--   두 번째 캐릭터가 활이라 그대로 두면 화살이 전부 풀에 막힌다.
--
--   해법 : "실제로 막는 것(CanCollide = true) 이거나 사람" 일 때만 맞은 것으로 친다.
--   아니면 그 지점 조금 너머에서 다시 쏜다. 풀숲을 뚫고 지나간다.
MELEE.CAST_SKIP = 6          -- 통과로 판정한 뒤 이만큼 앞에서 다시 쏜다 (cm)
MELEE.CAST_TRIES = 6         -- 한 번에 최대 몇 겹까지 뚫고 갈지

function MELEE.castSolid(origin, delta, params)
	local from = origin
	local rest = delta
	local far = origin + delta
	for _ = 1, MELEE.CAST_TRIES do
		if rest.Magnitude < 0.01 then
			return nil
		end
		local ok, res = pcall(function()
			return Workspace:Raycast(from, rest, params)
		end)
		if not (ok and res and res.Instance) then
			return nil
		end
		local solid = false
		pcall(function()
			solid = res.Instance.CanCollide == true
		end)
		if solid or MELEE.playerFromPart(res.Instance) then
			return res
		end
		-- 통과한다. 맞은 지점 조금 너머에서 다시 쏜다
		from = res.Position + rest.Unit * MELEE.CAST_SKIP
		rest = far - from
	end
	return nil
end

-- 쿠나이가 사람에게 박혔다 / 빠졌다를 서버에 알린다.
-- 서버가 전원에게 되뿌리고, 박힌 당사자의 화면이 살짝 어두워진다 (기획서의 경고 표시).
function MELEE.tellStick(target, on)
	if not (target and MELEE.event) then
		return
	end
	pcall(function()
		MELEE.event:FireServer({ phase = "kunai_stick", target = target, on = on and true or false })
	end)
end

local function destroyFlyingRaijinProjectile()
	local p = flyingRaijinProjectile
	if p then
		-- 내가 던진 쿠나이가 사람에게 박혀 있었다면 경고를 꺼줘야 한다
		if p.mine and p.stuckTo then
			MELEE.tellStick(p.stuckTo, false)
		end
		if p.Model and p.Model.Parent then
			p.Model:Destroy()
		end
	end
	flyingRaijinProjectile = nil
end

-- 런타임 뷰모델의 쿠나이 파츠를 복제한다. 이미 색과 2.4배 크기가 적용돼 있다.
-- 못 찾으면 nil 을 돌려주고 호출부에서 박스로 대체한다.
local function cloneFlyingRaijinPieces(parent)
	local clip = getClip(FLYINGRAIJIN_CLIP_NAME)
	local found = {}
	local sum = Vector3.new(0, 0, 0)
	for name, item in pairs(viewmodelPartsByName) do
		if item.IsKunai and item.Part and item.Part.Parent then
			local rest = getKunaiRest(clip, name)
			local restPos = rest and rest.Position or item.RestCFrame.Position
			table.insert(found, { Source = item.Part, Rest = restPos })
			sum = sum + restPos
		end
	end
	if #found == 0 then
		return nil
	end

	local center = sum / #found
	local pieces = {}
	for _, f in ipairs(found) do
		local c = f.Source:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.CastShadow = false
		c.Transparency = 0
		pcall(function()
			c.CanQuery = false
		end)
		c.Parent = parent
		table.insert(pieces, { Part = c, Offset = f.Rest - center })
	end
	return pieces
end

-- 벽/건물 충돌용 레이캐스트 설정. 자기 자신·뷰모델·내 캐릭터는 제외한다.
local function buildRayParams(model)
	local ok, params = pcall(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local list = { model }
		if viewmodel then
			table.insert(list, viewmodel)
		end
		local char = LocalPlayer.Character
		if char then
			table.insert(list, char)
		end
		rp.FilterDescendantsInstances = list
		return rp
	end)
	if ok then
		return params
	end
	print("[Viewmodel] RaycastParams 생성 실패 - 벽 충돌 판정 없이 진행")
	return nil
end

-- 쿠나이 한 발을 만든다. 던진 사람이 본인이든 남이든 같은 코드로 만든다.
-- 남의 쿠나이도 똑같은 궤적을 그려야 해서 생성/비행을 공용으로 뺐다.
local function buildFlyingRaijinKunai(origin, aim, groundY)
	local model = Instance.new("Model")
	model.Name = "Kunai_Projectile"
	model.Parent = Workspace

	local pieces = cloneFlyingRaijinPieces(model)
	if not pieces then
		-- 쿠나이 메시를 못 찾은 경우에만 박스로 대체
		local box = Instance.new("Part")
		box.Name = "Kunai_Fallback"
		box.Size = Vector3.new(5, 5, 45)
		box.Anchored = true
		box.CanCollide = false
		box.CastShadow = false
		box.Color = Color3.fromRGB(150, 152, 156)
		pcall(function()
			box.CanQuery = false
			box.Material = Enum.Material.Metal
		end)
		box.Parent = model
		pieces = { { Part = box, Offset = Vector3.new(0, 0, 0) } }
	end

	local cf = alignZCFrame(origin, aim)
	for _, pc in ipairs(pieces) do
		pc.Part.CFrame = cf * CFrame.new(pc.Offset)
	end

	return {
		Model = model,
		Pieces = pieces,
		elapsed = 0,
		origin = origin,
		pos = origin,          -- 순간이동 목적지로 쓴다 (매 프레임 갱신)
		dir = aim,
		groundY = groundY,
		landed = false,
		rayParams = buildRayParams(model),
	}
end

local function spawnFlyingRaijinKunai()
	destroyFlyingRaijinProjectile()

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end

	-- 조준선 그대로 곧게 나간다 (위로 띄우지 않는다)
	local aim = cam.CFrame.LookVector.Unit
	local origin = cam.CFrame.Position + aim * FLYINGRAIJIN_MUZZLE

	-- 바닥 높이는 캐릭터 발밑 기준으로 잡는다
	local groundY = origin.Y - 300
	local char = LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
		if root then
			groundY = root.Position.Y - FLYINGRAIJIN_GROUND_DROP
		end
	end

	flyingRaijinProjectile = buildFlyingRaijinKunai(origin, aim, groundY)
	-- 내가 던진 것 표시. 박힘 알림은 던진 사람만 보낸다 (남의 쿠나이도 같은 코드로 날아간다)
	flyingRaijinProjectile.mine = true

	-- 남들 화면에도 같은 궤적을 그리게 한다. 초기값만 보내고 각자 계산한다
	-- (매 프레임 위치를 보내는 것보다 훨씬 가볍고 궤적도 매끄럽다).
	ryuFire({ phase = "raijin_throw", origin = origin, dir = aim, groundY = groundY })
end

-- 쿠나이 한 발의 비행을 한 프레임 진행시킨다. 박히면 p.landed 가 true 가 된다.
-- 본인 것과 남의 것이 같은 궤적을 그리도록 이 함수를 공용으로 쓴다.
local function stepFlyingRaijinFlight(p, dt)
	local t = p.elapsed
	local tStraight = FLYINGRAIJIN_STRAIGHT / FLYINGRAIJIN_SPEED
	local pos, heading

	if t < tStraight then
		-- 1단계: 중력 없이 곧게. 자세도 고정이라 전혀 흔들리지 않는다.
		pos = p.origin + p.dir * (FLYINGRAIJIN_SPEED * t)
		heading = p.dir
	else
		-- 2단계: 전진 속도가 줄고 강한 중력으로 뚝 떨어진다.
		local td = t - tStraight
		local fwd = FLYINGRAIJIN_SPEED * FLYINGRAIJIN_DROP_SPEED
		pos = p.origin + p.dir * (FLYINGRAIJIN_STRAIGHT + fwd * td)
			- Vector3.new(0, 0.5 * FLYINGRAIJIN_DROP_GRAVITY * td * td, 0)
		-- 진행 방향을 그대로 따라가므로 코가 자연스럽게 아래로 처진다
		heading = p.dir * fwd - Vector3.new(0, FLYINGRAIJIN_DROP_GRAVITY * td, 0)
	end

	-- 이전 위치에서 새 위치까지 레이캐스트해서 벽/건물을 통과하지 않게 한다
	local stop = false
	if p.rayParams then
		local seg = pos - p.pos
		if seg.Magnitude > 0.01 then
			-- 풀·나무는 뚫고 지나간다 (MELEE.castSolid 설명 참고)
			local res = MELEE.castSolid(p.pos, seg, p.rayParams)
			if res then
				-- 칼끝이 표면에 닿도록 중심을 조금 뒤로 물린다
				local back = heading
				if back.Magnitude > 0.0001 then
					back = back.Unit * FLYINGRAIJIN_HALF_LEN
				else
					back = Vector3.new(0, 0, 0)
				end
				pos = res.Position - back
				stop = true
				-- ★ 적에게 박혔나. 박히면 그 사람을 따라다닌다 (기획서 B안).
				--   박힌 쿠나이는 피격 판정이 아니다. 안 죽고 오토디펜스도 안 깎인다.
				p.stuckTo = MELEE.playerFromPart(res.Instance)
			end
		end
	end

	-- 바닥 아래로 내려갔거나 너무 오래 날아도 멈춘다
	if pos.Y <= p.groundY or t >= FLYINGRAIJIN_MAX_TIME then
		stop = true
	end

	p.pos = pos
	local cf = alignZCFrame(pos, heading)
	for _, pc in ipairs(p.Pieces) do
		if pc.Part.Parent then
			pc.Part.CFrame = cf * CFrame.new(pc.Offset)
		end
	end

	if stop then
		p.landed = true
		p.elapsed = 0

		if p.stuckTo then
			local ch = p.stuckTo.Character
			local troot = ch
				and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
			if troot then
				-- 대상 기준의 상대 위치·자세를 기억해둔다.
				-- 그 사람이 걸어다녀도 쿠나이가 몸에 붙은 채로 따라간다.
				p.stuckCF = troot.CFrame:Inverse() * cf
				if p.mine then
					MELEE.tellStick(p.stuckTo, true)
				end
			else
				p.stuckTo = nil
			end
		end
	end
end

local function updateFlyingRaijinProjectile(dt)
	if not flyingRaijinProjectile then
		return
	end
	local p = flyingRaijinProjectile
	if not (p.Model and p.Model.Parent) then
		flyingRaijinProjectile = nil
		return
	end

	p.elapsed = p.elapsed + dt

	if p.landed then
		-- ★ 사람에게 박혔으면 그 사람을 따라다닌다 (기획서 B안).
		--   순간이동은 "누른 시점의 적 위치" 를 기준으로 하므로 p.pos 도 같이 갱신해야 한다.
		if p.stuckTo and p.stuckCF then
			local ch = p.stuckTo.Character
			local troot = ch
				and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
			if troot then
				local cf = troot.CFrame * p.stuckCF
				p.pos = cf.Position
				for _, pc in ipairs(p.Pieces) do
					if pc.Part.Parent then
						pc.Part.CFrame = cf * CFrame.new(pc.Offset)
					end
				end
			end
		end

		if p.elapsed >= raijinLifetime(p) then
			-- 회수 실패. 쿠나이가 사라지는 이 시점부터 쿨타임이 돌고,
			-- 던진 자세에서 칼 다시 빼드는 모션으로 이어진다.
			destroyFlyingRaijinProjectile()
			flyingRaijinCooldown = FLYINGRAIJIN_COOLDOWN
			flyingRaijinActive = false
			startDraw()
		end
		return
	end

	stepFlyingRaijinFlight(p, dt)
end

-- 남이 던진 쿠나이. 궤적만 똑같이 그리고, 박힌 뒤 수명이 다하면 지운다.
-- 시전자가 순간이동하면 raijin_tp 를 받아 그때 지운다.
local raijinRemote = {}

local function updateRemoteKunai(dt)
	for player, p in pairs(raijinRemote) do
		if not (p.Model and p.Model.Parent) then
			raijinRemote[player] = nil
		else
			p.elapsed = p.elapsed + dt
			if p.landed then
				if p.elapsed >= raijinLifetime(p) then
					p.Model:Destroy()
					raijinRemote[player] = nil
				end
			else
				stepFlyingRaijinFlight(p, dt)
			end
		end
	end
end

local function destroyRemoteKunai(player)
	local p = raijinRemote[player]
	if p then
		if p.Model and p.Model.Parent then
			p.Model:Destroy()
		end
		raijinRemote[player] = nil
	end
end

-- ===== 순간이동 (쿠나이 대체술) =====
local FLYINGRAIJIN_TELEPORT_UP = 60            -- 도착 지점에서 띄우는 높이 (cm)
local FLYINGRAIJIN_BEHIND = 220                -- 적에게 박혔을 때 등 뒤로 떨어지는 거리 (cm)

-- ★ 적의 등 뒤로 나올 때 몸을 180도 더 꺾는다.
--   ★★ 주의 : 이건 "몸" 방향이지 "보는 방향" 이 아니다.
--   1인칭이라 화면이 향하는 쪽은 기본 카메라 스크립트가 쥐고 있어서, 여기서 root 를 돌려도
--   플레이어가 보는 각도는 안 바뀐다 (용 궁극기 흔들림이 매 프레임 다시 얹어야 했던 것과 같은 이유).
--   남들 화면에서 내 아바타가 어느 쪽을 보는지만 달라진다.
local FLYINGRAIJIN_TP_FACE_FLIP = true
-- 연막/통나무 값 모음.
-- 낱개 local 로 두면 이 스크립트의 지역변수 한도(200)를 잡아먹어서 테이블로 묶었다.
local FR_FX = {
	SMOKE_PUFFS = 14,          -- 연막 덩어리 수
	SMOKE_LIFE = 0.45,         -- 각 덩어리가 사라지기까지 (초)
	SMOKE_SPREAD = 0.12,       -- 출발점->도착점 순서대로 터지는 데 걸리는 시간 (초)
	SMOKE_SIZE0 = 25,          -- 처음 크기 (cm)
	SMOKE_SIZE1 = 115,         -- 부풀었을 때 크기 (cm)
	SMOKE_JITTER = 35,         -- 경로에서 흩어지는 정도 (cm)
	SMOKE_BURST = 7,           -- 출발점/도착점에 추가로 터뜨리는 덩어리 수
	SMOKE_BURST_SCALE = 1.6,   -- 그 덩어리들의 크기 배수
	SMOKE_BURST_JITTER = 95,   -- 그 덩어리들이 흩어지는 정도 (cm)
	LOG_LIFE = 6,              -- 통나무가 남아있는 시간 (초)
	LOG_FADE = 1.2,            -- 사라지기 전 흐려지는 시간 (초)
}

local smokePuffs = {}
local logProps = {}

-- 부풀면서 사라지는 구체. 연막과 참격 폭발이 같이 쓴다.
-- o: { size0, size1, life, delay, color, alpha0, neon }
local function makePuff(pos, o)
	o = o or {}
	-- 여러 명이 동시에 순간이동하면 여기가 제일 먼저 터진다.
	-- 넘치면 새로 안 만들고 조용히 흘린다 (수명이 0.45초라 금방 자리가 난다).
	if #smokePuffs >= FX_LIMIT.PUFFS then
		return
	end
	local size0 = o.size0 or FR_FX.SMOKE_SIZE0
	local puff = Instance.new("Part")
	puff.Name = "FX_Puff"
	puff.Anchored = true
	puff.CanCollide = false
	puff.CastShadow = false
	puff.Size = Vector3.new(size0, size0, size0)
	puff.CFrame = CFrame.new(pos)
	puff.Color = o.color or Color3.fromRGB(206, 206, 212)
	puff.Transparency = 1
	pcall(function()
		puff.Shape = Enum.PartType.Ball
		puff.CanQuery = false
		puff.Material = o.neon and Enum.Material.Neon or Enum.Material.Plastic
	end)
	puff.Parent = Workspace
	table.insert(smokePuffs, {
		Part = puff,
		elapsed = 0,
		delay = o.delay or 0,
		life = o.life or FR_FX.SMOKE_LIFE,
		size0 = size0,
		size1 = o.size1 or FR_FX.SMOKE_SIZE1,
		alpha0 = o.alpha0 or 0.25,
	})
end

local function spawnFlyingRaijinSmoke(fromPos, toPos)
	local delta = toPos - fromPos

	-- 1) 출발점 -> 도착점 경로를 따라 순서대로 퍼지는 꼬리
	for i = 0, FR_FX.SMOKE_PUFFS - 1 do
		local t = (FR_FX.SMOKE_PUFFS > 1) and (i / (FR_FX.SMOKE_PUFFS - 1)) or 0
		local j = Vector3.new(
			(math.random() - 0.5) * FR_FX.SMOKE_JITTER,
			(math.random() - 0.5) * FR_FX.SMOKE_JITTER * 0.6,
			(math.random() - 0.5) * FR_FX.SMOKE_JITTER
		)
		makePuff(fromPos + delta * t + j, { delay = t * FR_FX.SMOKE_SPREAD })
	end

	-- 2) 양 끝에 큰 뭉치. 도착점 쪽이 있어야 순간이동한 자리에서 연막이 보인다.
	for i = 1, FR_FX.SMOKE_BURST do
		local j1 = Vector3.new(
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER,
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER * 0.7,
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER
		)
		local j2 = Vector3.new(
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER,
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER * 0.7,
			(math.random() - 0.5) * FR_FX.SMOKE_BURST_JITTER
		)
		local big = {
			size0 = FR_FX.SMOKE_SIZE0 * FR_FX.SMOKE_BURST_SCALE,
			size1 = FR_FX.SMOKE_SIZE1 * FR_FX.SMOKE_BURST_SCALE,
		}
		makePuff(fromPos + j1, { size0 = big.size0, size1 = big.size1, delay = 0 })
		makePuff(toPos + j2, { size0 = big.size0, size1 = big.size1, delay = FR_FX.SMOKE_SPREAD })
	end
end

local function spawnFlyingRaijinLog(atPos)
	local template = {}
	local trunk = nil
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 9) == "KunaiLog_" then
			table.insert(template, child)
			if child.Name == "KunaiLog_Trunk" then
				trunk = child
			end
		end
	end
	if #template == 0 then
		print("[Viewmodel] KunaiLog_ 파츠를 찾을 수 없음")
		return
	end
	-- 통나무는 6초나 남아있어서 인원이 많으면 계속 쌓인다.
	-- 넘치면 제일 오래된 것부터 치운다 (새 연출이 안 나오는 것보다 낫다).
	while #logProps >= FX_LIMIT.LOGS do
		local oldest = table.remove(logProps, 1)
		if oldest and oldest.Model and oldest.Model.Parent then
			oldest.Model:Destroy()
		end
	end
	local originPos = (trunk or template[1]).Position

	local model = Instance.new("Model")
	model.Name = "Kunai_Log"
	model.Parent = Workspace

	-- 살짝 기울고 아무 방향으로 돌아간 채로 꽂힌다
	local base = CFrame.new(atPos) * CFrame.Angles(math.rad(11), math.random() * 6.283, 0)
	for _, src in ipairs(template) do
		local c = src:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.Transparency = 0
		pcall(function()
			c.CanQuery = false
		end)
		-- 각 조각의 자기 회전(원기둥을 세우는 90도)은 유지하고 위치만 옮긴다
		c.CFrame = base * CFrame.new(src.Position - originPos) * (src.CFrame - src.Position)
		c.Parent = model
	end
	table.insert(logProps, { Model = model, elapsed = 0 })
end

local function updateEffects(dt)
	for i = #smokePuffs, 1, -1 do
		local s = smokePuffs[i]
		if not (s.Part and s.Part.Parent) then
			table.remove(smokePuffs, i)
		else
			s.elapsed = s.elapsed + dt
			local t = s.elapsed - s.delay
			if t < 0 then
				s.Part.Transparency = 1
			elseif t >= s.life then
				s.Part:Destroy()
				table.remove(smokePuffs, i)
			else
				local a = t / s.life
				local size = s.size0 + (s.size1 - s.size0) * a
				s.Part.Size = Vector3.new(size, size, size)
				s.Part.Transparency = s.alpha0 + (1 - s.alpha0) * a
			end
		end
	end

	for i = #logProps, 1, -1 do
		local L = logProps[i]
		if not (L.Model and L.Model.Parent) then
			table.remove(logProps, i)
		else
			L.elapsed = L.elapsed + dt
			if L.elapsed >= FR_FX.LOG_LIFE then
				L.Model:Destroy()
				table.remove(logProps, i)
			elseif L.elapsed > FR_FX.LOG_LIFE - FR_FX.LOG_FADE then
				local a = (L.elapsed - (FR_FX.LOG_LIFE - FR_FX.LOG_FADE)) / FR_FX.LOG_FADE
				for _, part in ipairs(L.Model:GetChildren()) do
					if part:IsA("BasePart") then
						part.Transparency = a
					end
				end
			end
		end
	end
end

-- 강공격 버튼에 쿨타임 상태를 표시한다.
--   쿠나이가 나가 있음 -> "TP" (하늘색, 진하게)   순간이동 가능
--   쿨타임 중          -> 남은 초 (회색, 흐리게)
--   준비됨             -> 원래 글자
local function updateFlyingRaijinButton()
	if not flyingRaijinButton then
		return
	end
	local label = flyingRaijinButton:FindFirstChild("Label")
	local text, color, transparency

	if flyingRaijinProjectile then
		-- ★ 사람에게 박혔으면 빨강, 땅에 박혔으면 평소 파랑.
		--   화면을 안 보고도 "지금 누르면 적 뒤로 간다" 를 버튼 색만으로 알 수 있어야 한다.
		if flyingRaijinProjectile.stuckTo then
			text, color, transparency = "TP", Color3.fromRGB(255, 80, 80), 0.2
		else
			text, color, transparency = "TP", Color3.fromRGB(120, 220, 255), 0.3
		end
	elseif flyingRaijinCooldown > 0 then
		text, color, transparency = tostring(math.ceil(flyingRaijinCooldown)), Color3.fromRGB(90, 90, 95), 0.8
	else
		text, color, transparency = flyingRaijinButtonText, Color3.new(1, 1, 1), 0.7
	end

	if label and label.Text ~= text then
		label.Text = text
	end
	pcall(function()
		flyingRaijinButton.ImageColor3 = color
		flyingRaijinButton.ImageTransparency = transparency
	end)
end

local function doFlyingRaijinTeleport()
	local p = flyingRaijinProjectile
	if not p then
		return
	end
	local char = LocalPlayer.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
	if not root then
		return
	end

	local fromPos = root.Position
	local toPos = p.pos or fromPos
	local target = nil

	-- ★ 적에게 박힌 쿠나이면 "그 순간의 적 뒤" 로 나온다 (기획서).
	--   쿠나이가 적을 따라다니므로 p.pos 는 이미 최신이지만, 도착 지점은 몸 안이 아니라
	--   등 뒤여야 한다. 딜레이 모션 때문에 나오자마자 때리지는 못한다.
	if p.stuckTo then
		local ch = p.stuckTo.Character
		local troot = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
		if troot then
			-- ★★ 확정 (2026-08-20 실측) : ODA 아바타의 보이는 정면 = LookVector 그대로다.
			--   그래서 "등 뒤" 는 -LookVector 쪽이고, 바라보게 세울 때 뒤집을 필요도 없다.
			--   예전엔 반대로 알고 있어서 적의 앞쪽으로 튀어나왔다.
			toPos = troot.Position - troot.CFrame.LookVector * FLYINGRAIJIN_BEHIND
			target = CFrame.new(
				toPos + Vector3.new(0, FLYINGRAIJIN_TELEPORT_UP, 0),
				Vector3.new(troot.Position.X, toPos.Y + FLYINGRAIJIN_TELEPORT_UP, troot.Position.Z))
			if FLYINGRAIJIN_TP_FACE_FLIP then
				target = target * CFrame.Angles(0, math.pi, 0)
			end
		end
	end

	spawnFlyingRaijinLog(fromPos)                          -- 던진 자리에 통나무
	spawnFlyingRaijinSmoke(fromPos, toPos)                 -- 이동 방향으로 연막

	-- 땅에 박힌 경우 : 방향(바라보는 각)은 유지하고 위치만 옮긴다
	target = target
		or CFrame.new(toPos + Vector3.new(0, FLYINGRAIJIN_TELEPORT_UP, 0)) * (root.CFrame - root.Position)
	local ok = pcall(function()
		root.CFrame = target
	end)
	if not ok then
		print("[Viewmodel] 순간이동 실패 - 서버 권한이 필요할 수 있음")
	end

	destroyFlyingRaijinProjectile()
	flyingRaijinActive = false
	-- 순간이동을 마친 이 시점부터 쿨타임이 돈다
	flyingRaijinCooldown = FLYINGRAIJIN_COOLDOWN
	-- 던진 자세에서 칼 다시 빼드는 모션으로 이어진다
	startDraw()

	-- 이 두 지점을 호출부가 서버로 넘겨 남들 화면에도 같은 연출을 띄운다.
	-- (여기서 직접 못 보내는 이유 : ryuFire 가 이 함수보다 아래에 선언돼 있다)
	return fromPos, toPos
end

-- ===== 3타 X자 참격 이펙트 =====
-- 일반공격 콤보 마지막(Attack3)에서만 나간다.
-- 살짝 앞으로 대쉬하면서 진행 방향을 향한 X자 참격이 날아가고,
-- 벽이나 플레이어에 맞으면 터진다. 아무것도 안 맞으면 10m 근처에서
-- 색이 빠지며 사라진다.
-- 칼 앞에 있는 적을 찾는다. 카메라 정면으로 훑되 반경을 줘서 조준이 조금 빗나가도 잡는다.
-- 가장 가까운 적 하나만 돌려준다.
local function findMeleeTarget()
	local cam = Workspace.CurrentCamera
	local myChar = LocalPlayer.Character
	if not (cam and myChar) then
		return nil
	end
	local origin = cam.CFrame.Position
	local dir = cam.CFrame.LookVector

	local best, bestD = nil, MELEE.RANGE + MELEE.RADIUS
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			local root = p.Character:FindFirstChild("HumanoidRootPart")
				or p.Character:FindFirstChild("Torso")
			if root then
				local rel = root.Position - origin
				local along = rel:Dot(dir)                -- 정면으로 얼마나 떨어졌나
				if along > 0 and along <= MELEE.RANGE then
					-- 시선축에서 옆으로 얼마나 벗어났나
					local off = (rel - dir * along).Magnitude
					if off <= MELEE.RADIUS and along < bestD then
						best, bestD = p, along
					end
				end
			end
		end
	end
	return best
end

-- ===== 궁극기 피격 판정 =====
--
-- ★ 근접처럼 "정면 원뿔" 이 아니다. 용이 지나가는 자리를 통째로 쓸어버리는 기술이라
--   시선과 무관하게 내 주변 반경으로 잡는다. 궁극기가 직선으로 전진하니
--   프레임마다 훑으면 지나간 경로가 자연스럽게 판정 범위가 된다.
--
-- ★ 한 사람당 한 번만 보낸다. 매 프레임 쏘면 서버가 같은 사람을 계속 때린다.
--
-- ★ 지역변수 한도(196/200) 때문에 MELEE 테이블에 얹는다. 낱개 local 로 늘리면 뷰모델이 안 뜬다.
--
-- ★ 내리찍는 순간은 따로 한 번 더, 훨씬 넓게 훑는다.
--   지나가며 스치는 것과 내리찍는 것은 다른 공격이다. 기획대로 내리찍은 자리 주변에
--   서 있기만 해도 죽어야 한다.
MELEE.ULT_RADIUS = 900       -- 용이 지나가며 휩쓰는 반경 (cm) = 9m
MELEE.ULT_SLAM_RADIUS = 1700 -- 내리찍는 순간의 광역 반경 (cm) = 17m
MELEE.ultHit = {}            -- 이번 궁극기에서 이미 보낸 대상

function MELEE.scanUlt(radius)
	radius = radius or MELEE.ULT_RADIUS
	local myChar = LocalPlayer.Character
	local myRoot = myChar
		and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
	if not (myRoot and MELEE.event) then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and not MELEE.ultHit[p] and p.Character then
			local root = p.Character:FindFirstChild("HumanoidRootPart")
				or p.Character:FindFirstChild("Torso")
			if root and (root.Position - myRoot.Position).Magnitude <= radius then
				MELEE.ultHit[p] = true
				pcall(function()
					MELEE.event:FireServer({ phase = "ult", target = p })
				end)
			end
		end
	end
end

-- ===== 3타 참격(XBlade) 피격 판정 =====
--
-- ★ 참격은 근접 판정(380cm)보다 훨씬 멀리 날아간다 (최대 1500cm).
--   그래서 사람에게 닿아 터지는 연출은 나오는데 정작 맞은 판정이 아니었다 (2026-08-20).
--   참격이 날아가는 동안 그 위치 주변을 훑어 따로 보고한다.
--
-- ★ 같은 3타에서 근접 판정과 참격 판정이 둘 다 들어가면 오토디펜스가 한 번에 두 칸 날아간다.
--   그래서 근접으로 이미 보낸 대상은 여기 명단에 미리 넣어 두 번 안 나가게 한다.
MELEE.XBLADE_RADIUS = 260    -- 참격에 닿는 반경 (cm)
MELEE.xbladeHit = {}         -- 이번 참격에서 이미 보낸 대상

function MELEE.scanXblade(pos)
	if not (pos and MELEE.event) then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and not MELEE.xbladeHit[p] and p.Character then
			local root = p.Character:FindFirstChild("HumanoidRootPart")
				or p.Character:FindFirstChild("Torso")
			if root and (root.Position - pos).Magnitude <= MELEE.XBLADE_RADIUS then
				MELEE.xbladeHit[p] = true
				pcall(function()
					MELEE.event:FireServer({ phase = "xblade", target = p })
				end)
			end
		end
	end
end

local XBLADE_ON_CLIP = "Attack3"   -- 이 클립에서만 참격이 나간다
local XBLADE_AT = 1.0              -- ★ 3타 시작 후 이 시점에 참격이 나간다 (초). 타이밍은 여기서 조절
local XBLADE_DASH_LEAD = 0.05      -- 대쉬가 참격보다 얼마나 먼저 시작할지 (초)
local XBLADE_DASH_DIST = 260         -- 앞으로 밀려나는 거리 (cm)
local XBLADE_DASH_TIME = 0.18        -- 대쉬에 걸리는 시간 (초)
local XBLADE_SPEED = 1300            -- 참격 비행 속도 (cm/s). 낮출수록 오래 보인다
local XBLADE_FADE_START = 900        -- 이 거리부터 흐려지기 시작 (cm)
local XBLADE_MAX_RANGE = 1500        -- 이 거리에서 완전히 사라짐 (cm)
-- 획 하나는 초승달 모양이다. 가운데가 두껍고 양 끝으로 갈수록 뾰족해진다.
local XBLADE_STROKE_LEN = 340        -- 획의 전체 길이 (cm)
local XBLADE_STROKE_BOW = 105        -- 정면에서 봤을 때 휘는 정도 (cm). 0 이면 직선
local XBLADE_STROKE_SCURVE = 1       -- 0 = 초승달(C) / 1 = S자.  ★ 모양 손잡이
                                  -- 0 이면 두 획의 아래쪽이 서로 감겨 바닥이 둥글어지고
                                  -- 1 이면 가운데가 곧아져 교차점이 날카로워진다
local XBLADE_STROKE_DEPTH = 85       -- 옆에서 봤을 때 가운데가 뒤로 밀리는 정도 (cm)
local XBLADE_STROKE_W = 30           -- 획 가운데의 폭 (cm). 끝으로 갈수록 0 에 수렴
local XBLADE_STROKE_T = 13           -- 획 가운데의 두께 (cm)
local XBLADE_STROKE_ROLL = 46        -- X 를 이루는 두 획의 벌어진 각도 (도). 키우면 옆으로 넓은 X
local XBLADE_ARC_SEGMENTS = 15       -- 획을 몇 조각으로 그릴지. 올리면 매끄럽다
local XBLADE_COLOR = Color3.fromRGB(120, 210, 255)   -- 하늘색
local XBLADE_BURST = 12              -- 터질 때 구체 수
local XBLADE_BURST_LIFE = 0.45
local XBLADE_BURST_SIZE0 = 45
local XBLADE_BURST_SIZE1 = 300
local XBLADE_BURST_JITTER = 110

-- 남이 쓴 참격. [player] = 상태.  내 것(xblade)과 같은 구조를 쓴다.
local xbladeRemote = {}

-- 인자를 주면 그 상태만, 안 주면 내 참격을 없앤다.
local function destroyXblade(s)
	local target = s or xblade
	if target and target.Model and target.Model.Parent then
		target.Model:Destroy()
	end
	if not s or s == xblade then
		xblade = nil
	end
end

local function spawnXbladeBurst(pos)
	for _ = 1, XBLADE_BURST do
		local j = Vector3.new(
			(math.random() - 0.5) * XBLADE_BURST_JITTER,
			(math.random() - 0.5) * XBLADE_BURST_JITTER,
			(math.random() - 0.5) * XBLADE_BURST_JITTER
		)
		makePuff(pos + j, {
			size0 = XBLADE_BURST_SIZE0,
			size1 = XBLADE_BURST_SIZE1,
			life = XBLADE_BURST_LIFE,
			color = XBLADE_COLOR,
			alpha0 = 0,
			neon = true,
		})
	end
end

-- 참격 하나를 만들어 상태를 돌려준다. 내 것과 남의 것이 같은 함수를 쓴다.
-- casterChar 를 주면 시전자가 자기 참격에 맞아 즉시 터지는 걸 막는다.
local function buildXblade(origin, aim, casterChar)
	local model = Instance.new("Model")
	model.Name = "Xblade_Slash"
	model.Parent = Workspace

	-- 진행 방향을 정면으로 보는 평면 위에, 초승달 모양 획 두 개를 서로 반대로
	-- 기울여 겹쳐서 X 를 만든다.
	--
	-- 획 하나의 형태 (u = -1 ~ 1 로 훑는다):
	--   x = 길이방향
	--   y = BOW * u(1-u^2)   -> S 자. 가운데는 곧고 양 끝이 서로 반대로 휘어
	--                           네 꼭짓점이 모두 바깥으로 뻗고 교차점이 날카로워진다.
	--                           포물선(1-u^2)로 하면 두 획의 아래쪽이 서로 감기며
	--                           바닥이 둥글게 뭉친다.
	--   z = -DEPTH * (1-u^2) -> 옆에서 보면 가운데가 뒤로 밀린 초승달
	--   두께/폭 = sin(pi*t)^0.6                     -> 양 끝이 뾰족하게 빠진다
	local N = XBLADE_ARC_SEGMENTS
	local bars = {}

	-- u(1-u^2) 의 최대값이 0.3849 라 2.598 을 곱해 BOW 가 실제 최대 휨이 되게 맞춘다
	local S_NORM = 2.598
	local sc = XBLADE_STROKE_SCURVE

	local function strokePoint(u)
		local uu = 1 - u * u
		-- C 자(항상 한쪽으로 볼록) 와 S 자(양 끝이 반대로) 를 섞는다
		local bendC = uu
		local bendS = S_NORM * u * uu
		return Vector3.new(
			XBLADE_STROKE_LEN * 0.5 * u,
			XBLADE_STROKE_BOW * ((1 - sc) * bendC + sc * bendS),
			-XBLADE_STROKE_DEPTH * uu
		)
	end

	for _, angle in ipairs({ XBLADE_STROKE_ROLL, -XBLADE_STROKE_ROLL }) do
		local roll = CFrame.Angles(0, 0, math.rad(angle))
		for i = 0, N - 1 do
			local t = i / (N - 1)
			local u = 2 * t - 1
			local p = strokePoint(u)

			-- 접선 방향(정면 평면 기준)으로 조각을 눕힌다
			local du = 0.02
			local a = strokePoint(math.max(-1, u - du))
			local b = strokePoint(math.min(1, u + du))
			local tan = b - a
			local yaw = math.atan2(tan.Y, tan.X)

			-- 양 끝으로 갈수록 가늘어진다
			local taper = math.sin(math.pi * t) ^ 0.6
			local segLen = (XBLADE_STROKE_LEN / (N - 1)) * 1.45

			local seg = Instance.new("Part")
			seg.Name = "Xblade_Arc"
			seg.Size = Vector3.new(segLen, XBLADE_STROKE_W * taper + 2, XBLADE_STROKE_T * taper + 1.5)
			seg.Anchored = true
			seg.CanCollide = false
			seg.CastShadow = false
			seg.Color = XBLADE_COLOR
			seg.Transparency = 0
			pcall(function()
				seg.CanQuery = false
				seg.Material = Enum.Material.Neon
			end)
			seg.Parent = model

			table.insert(bars, {
				Part = seg,
				Local = roll * CFrame.new(p) * CFrame.Angles(0, 0, yaw),
			})
		end
	end

	local cf = alignZCFrame(origin, aim)
	for _, b in ipairs(bars) do
		b.Part.CFrame = cf * b.Local
	end

	-- buildRayParams 는 내 캐릭터를 빼준다. 남의 참격이면 시전자도 같이 빼야 한다.
	local rp = buildRayParams(model)
	if rp and casterChar then
		pcall(function()
			local list = rp.FilterDescendantsInstances
			table.insert(list, casterChar)
			rp.FilterDescendantsInstances = list
		end)
	end

	return {
		Model = model,
		Bars = bars,
		origin = origin,
		pos = origin,
		dir = aim,
		travelled = 0,
		rayParams = rp,
	}
end

local function spawnXblade()
	destroyXblade()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local aim = cam.CFrame.LookVector.Unit
	local origin = cam.CFrame.Position + aim * 120
	xblade = buildXblade(origin, aim, nil)

	-- 남들 화면에도 그려지도록 서버를 거쳐 전원에게 뿌린다.
	-- 파츠를 복제하지 않고 초기값만 보내 각자 같은 궤적을 계산한다.
	ryuFire({ phase = "xblade", origin = origin, dir = aim })
end

-- 참격 하나를 한 프레임 진행시킨다. 끝났으면 false 를 돌려준다.
-- 내 것과 남의 것이 같은 계산을 쓰므로 궤적이 화면마다 어긋나지 않는다.
local function stepXblade(s, dt)
	if not (s.Model and s.Model.Parent) then
		return false
	end

	local step = XBLADE_SPEED * dt
	local nextPos = s.pos + s.dir * step

	-- 벽이나 플레이어에 닿으면 그 자리에서 터진다.
	-- 풀·나무는 뚫고 지나간다 (쿠나이와 같은 이유. MELEE.castSolid 설명 참고)
	if s.rayParams then
		local res = MELEE.castSolid(s.pos, s.dir * step, s.rayParams)
		if res then
			spawnXbladeBurst(res.Position)
			destroyXblade(s)
			return false
		end
	end

	s.travelled = s.travelled + step
	s.pos = nextPos

	-- 사거리 끝에서 색이 빠지며 사라진다
	if s.travelled >= XBLADE_MAX_RANGE then
		destroyXblade(s)
		return false
	end
	local fade = 0
	if s.travelled > XBLADE_FADE_START then
		fade = (s.travelled - XBLADE_FADE_START) / (XBLADE_MAX_RANGE - XBLADE_FADE_START)
	end

	local cf = alignZCFrame(s.pos, s.dir)
	for _, b in ipairs(s.Bars) do
		if b.Part.Parent then
			b.Part.CFrame = cf * b.Local
			b.Part.Transparency = fade
		end
	end
	return true
end

local function updateXblade(dt)
	-- ★ 참조를 먼저 붙잡아둔다.
	--   destroyXblade 가 전역 xblade 를 nil 로 만들기 때문에, stepXblade 가 끝난 뒤에
	--   xblade.pos 를 읽으면 nil 을 인덱싱해서 죽는다 (실측 2026-08-20).
	local s = xblade
	if s then
		local alive = stepXblade(s, dt)
		-- 터지며 사라진 프레임의 자리도 봐야 한다. 살아 있는지와 무관하게 한 번 훑는다
		MELEE.scanXblade(s.pos)
		if not alive then
			xblade = nil
		end
	end
	for p, s in pairs(xbladeRemote) do
		if not stepXblade(s, dt) then
			xbladeRemote[p] = nil
		end
	end
end

local function updateXbladeDash(dt)
	if not xbladeDash then
		return
	end
	local char = LocalPlayer.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
	if not root then
		xbladeDash = nil
		return
	end

	xbladeDash.elapsed = xbladeDash.elapsed + dt
	if xbladeDash.elapsed >= XBLADE_DASH_TIME then
		xbladeDash = nil
		return
	end

	local step = XBLADE_DASH_DIST * (dt / XBLADE_DASH_TIME)
	-- 벽에 파고들지 않게 앞을 확인한다
	local blocked = false
	local ok, res = pcall(function()
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local list = { char }
		if viewmodel then
			table.insert(list, viewmodel)
		end
		if xblade and xblade.Model then
			table.insert(list, xblade.Model)
		end
		rp.FilterDescendantsInstances = list
		return Workspace:Raycast(root.Position, xbladeDash.dir * (step + 70), rp)
	end)
	if ok and res then
		blocked = true
	end
	if blocked then
		xbladeDash = nil
		return
	end

	pcall(function()
		root.CFrame = root.CFrame + xbladeDash.dir * step
	end)
end

-- 3타가 시작될 때 앞으로 살짝 밀어준다. 수평 방향으로만 (위를 봐도 안 뜨게)
local function startXbladeDash()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local f = cam.CFrame.LookVector
	local flat = Vector3.new(f.X, 0, f.Z)
	if flat.Magnitude > 0.01 then
		xbladeDash = { elapsed = 0, dir = flat.Unit }
	end
end

-- ===== 궁극기 [용의 이빨 / Ryunochi] =====
-- 재생 중에는 조작이 전부 잠기고 스크립트가 이동을 대신한다.
--   ~ jumpAt      : 바닥에 붙은 채 조준 방향으로 직선 전진
--   jumpAt ~      : 점프. 중력이 약해서 천천히 떨어진다
--   airHold 구간  : 착지 전이면 그 자세에서 멈춰 기다린다
local RYUNOCHI_COOLDOWN = 0        -- ★ 안 쓴다. 궁극기는 쿨타임이 아니라 충전량(_G.UltCharge)으로 열린다
local RYUNOCHI_SPEED = 900         -- 직선 전진 속도 (cm/s) = 9 m/s
local RYUNOCHI_JUMP_SPEED = 1250   -- 점프 초기 상승 속도 (cm/s)
local RYUNOCHI_GRAVITY = 1100      -- 체공 중력 (cm/s^2). ★ 낮출수록 느리게 떨어진다
local RYUNOCHI_GROUND_DROP = 120   -- 캐릭터 중심에서 발밑까지 (cm)
local RYUNOCHI_AIR_MAX = 3         -- 체공 대기 안전장치 (초). 이 시간 넘으면 그냥 진행
local RYUNOCHI_WALL_PAD = 60       -- 벽 앞에서 멈추는 여유 (cm)

-- ===== 용 머리 + 파괴 연출 =====
-- 모든 유저에게 보여야 하므로 서버(RyunochiServer)를 거쳐 전원에게 뿌린다.
-- 각 클라이언트가 자기 쪽에서 같은 이펙트를 만든다 (파츠 복제보다 가볍다).
local Dragon = require(ReplicatedStorage:WaitForChild("RyunochiDragon"))

-- 용은 플레이어 뒤를 따라온다. 캐릭터가 앞서고 용이 바로 뒤를 쫓는 그림.
-- (머리를 플레이어에 겹치면 1인칭 시야를 통째로 가려버린다)
local RYU = {
	FOLLOW_GAP = 40,       -- ★ 코끝에서 플레이어까지 거리 (cm). 줄이면 더 바짝 쫓는다
	HEIGHT = 130,          -- 머리 높이 (cm). 캐릭터보다 살짝 위
	LAG = 9,               -- 따라붙는 탄력. 낮출수록 늘어지며 쫓아온다
	LAG_CHOMP = 26,        -- 무는 순간의 탄력. 높을수록 확 튀어나온다
	-- 무는 순간 용이 앞으로 확 튀어나온다. 1인칭 정면으로 들어와야 물어뜯는 게 보인다.
	LUNGE = 780,           -- ★ 튀어나오는 거리 (cm). 0 이면 뒤에 머문다
	JAW_OPEN = 30,         -- 벌린 턱 각도 (도)
	-- 무는 시점은 고정 시각이 아니라 "실제로 착지한 순간"이다.
	-- 체공이 길어지면 그만큼 늦게 물고, 늦게 터진다.
	SLAM_FALLBACK = 5.0,   -- 착지 신호가 끝내 안 오면 이 시점에 그냥 문다 (초)
	CHOMP_TIME = 0.12,     -- 무는 데 걸리는 시간 (초). 짧을수록 강하게 보인다
	FADE_DELAY = 0.5,      -- 문 뒤 이만큼 버티다 사라지기 시작한다 (초)
	FADE_TIME = 1.5,       -- 사라지는 데 걸리는 시간. 길수록 서서히
	ROCK_AHEAD = 450,      -- ★ 바위 고리를 착지 지점보다 앞에 만든다 (cm). 1인칭 시야로 들어온다
	DEBRIS_RISE = 0.45,    -- 바위가 솟는 시간. 늘리면 천천히 솟는다
	DEBRIS_HOLD = 3.0,     -- 남아있는 시간
	DEBRIS_FADE = 2.0,     -- 사라지는 시간
}

local ryuFX = {}        -- [player] = { h, elapsed, dir, origin }
local ryuDebris = {}

local function ryuSpawn(player, origin, dir)
	local old = ryuFX[player]
	if old then
		Dragon.destroy(old.h)
		ryuFX[player] = nil
	end
	-- 용 하나가 파츠 44개다. 멀거나 이미 여러 마리 떠 있으면 만들지 않는다.
	-- 내 용은 여기 안 걸린다 (아래 호출부에서 본인은 거리 검사를 건너뛴다).
	if player ~= LocalPlayer then
		if fxTooFar(origin) then
			return
		end
		local n = 0
		for _ in pairs(ryuFX) do
			n = n + 1
		end
		if n >= FX_LIMIT.DRAGONS then
			return
		end
	end
	local ok, handle = pcall(function()
		return Dragon.build(Workspace)
	end)
	if not ok or not handle then
		-- pcall 이 에러를 삼키면 원인을 못 찾는다. 내용을 그대로 찍는다.
		print("[Ryunochi] 용 머리 생성 실패 : " .. tostring(handle))
		return
	end
	ryuFX[player] = { h = handle, elapsed = 0, dir = dir, origin = origin }
end

local function ryuUpdate(dt)
	for player, fx in pairs(ryuFX) do
		fx.elapsed = fx.elapsed + dt

		-- 시전자를 따라다닌다. 캐릭터를 못 찾으면 직선 추정으로 이어간다.
		local char = player and player.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
		local pos = root and root.Position
			or (fx.origin + fx.dir * (RYUNOCHI_SPEED * fx.elapsed))

		-- 착지 신호(fx.slamAt)가 오기 전까지는 계속 뒤를 쫓는다.
		local st = fx.slamAt or RYU.SLAM_FALLBACK
		local since = fx.elapsed - st
		local chomp = 0
		if since >= 0 then
			chomp = since / RYU.CHOMP_TIME
			if chomp > 1 then chomp = 1 end
		end

		-- 코끝이 플레이어 뒤 RYU.FOLLOW_GAP 에 오도록 머리 원점을 물린다.
		-- 무는 순간에는 RYU.LUNGE 만큼 앞으로 튀어나와 시야로 들어온다.
		local lunge = RYU.LUNGE * (chomp * (2 - chomp))     -- 튀어나왔다가 감속
		local back = Dragon.SNOUT_Z + RYU.FOLLOW_GAP - lunge
		local want = pos - fx.dir * back + Vector3.new(0, RYU.HEIGHT, 0)
		if fx.pos then
			-- 평소엔 늘어지게, 무는 순간엔 즉각적으로 (안 그러면 보간이 튀어나오는 맛을 죽인다)
			local k = (since >= 0) and RYU.LAG_CHOMP or RYU.LAG
			fx.pos = fx.pos + (want - fx.pos) * math.min(1, k * dt)
		else
			fx.pos = want
		end
		local base = alignZCFrame(fx.pos, fx.dir)

		Dragon.setPose(fx.h, base, RYU.JAW_OPEN * (1 - chomp))

		if since > RYU.FADE_DELAY then
			Dragon.setTransparency(fx.h, (since - RYU.FADE_DELAY) / RYU.FADE_TIME)
		end

		if since >= RYU.FADE_DELAY + RYU.FADE_TIME then
			Dragon.destroy(fx.h)
			ryuFX[player] = nil
		end
	end

	for i = #ryuDebris, 1, -1 do
		if not Dragon.updateDebris(ryuDebris[i], dt, RYU.DEBRIS_RISE, RYU.DEBRIS_HOLD, RYU.DEBRIS_FADE) then
			table.remove(ryuDebris, i)
		end
	end
end

if ryuEvent then
	ryuEvent.OnClientEvent:Connect(function(player, payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.phase == "raijin_throw" then
			-- 남이 던진 쿠나이. 초기값만 받아 각자 같은 궤적을 계산한다.
			-- (이 이벤트는 이제 궁극기 전용이 아니라 스킬 연출 공용 통로다)
			if player ~= LocalPlayer and payload.origin and payload.dir
				and not fxTooFar(payload.origin) then
				destroyRemoteKunai(player)
				local n = 0
				for _ in pairs(raijinRemote) do
					n = n + 1
				end
				if n < FX_LIMIT.KUNAI then
					raijinRemote[player] = buildFlyingRaijinKunai(
						payload.origin, payload.dir, payload.groundY or (payload.origin.Y - 300))
				end
			end
		elseif payload.phase == "bow_shot" then
			-- 남이 쏜 화살. 초기값만 받아 각자 같은 궤적을 계산한다.
			-- 쏜 본인은 이미 자기 화면에 그렸으니 건너뛴다.
			if player ~= LocalPlayer and payload.origin and payload.dir
				and not fxTooFar(payload.origin) then
				MELEE.bowShoot(payload.origin, payload.dir, payload.power)
			end
		elseif payload.phase == "raijin_tp" then
			-- 순간이동 연출. 시전자 본인은 이미 자기 화면에 그렸으니 건너뛴다.
			if player ~= LocalPlayer and payload.from and payload.to then
				destroyRemoteKunai(player)     -- 회수됐으니 쿠나이도 같이 사라진다
				-- 출발점과 도착점 둘 다 멀면 볼 일이 없다. 하나라도 가까우면 그린다.
				if not (fxTooFar(payload.from) and fxTooFar(payload.to)) then
					spawnFlyingRaijinLog(payload.from)
					spawnFlyingRaijinSmoke(payload.from, payload.to)
				end
			end
		elseif payload.phase == "raijin_hand" then
			-- 비뢰신 중인 사람의 칼을 숨길지 여부. 시전자 본인 것은 1인칭이라 상관없다.
			if player ~= LocalPlayer then
				RAIJIN_HAND.hide[player] = payload.hide and true or nil
			end
		elseif payload.phase == "xblade" then
			-- 남이 쓴 3타 X자 참격. 시전자 본인은 이미 자기 화면에 그렸다.
			if player ~= LocalPlayer and payload.origin and payload.dir
				and not fxTooFar(payload.origin) then
				-- 연타로 겹치지 않게 그 사람의 이전 참격은 지운다
				if xbladeRemote[player] then
					destroyXblade(xbladeRemote[player])
					xbladeRemote[player] = nil
				end
				local n = 0
				for _ in pairs(xbladeRemote) do
					n = n + 1
				end
				if n < FX_LIMIT.XBLADES then
					xbladeRemote[player] = buildXblade(
						payload.origin, payload.dir, player.Character)
				end
			end
		elseif payload.phase == "start" then
			ryuSpawn(player, payload.origin, payload.dir)
		elseif payload.phase == "slam" then
			-- 착지한 그 순간에 용이 물도록 시각을 기록한다
			local fx = ryuFX[player]
			if fx and not fx.slamAt then
				fx.slamAt = fx.elapsed
			end

			-- 파괴 연출은 한 번에 파츠 70개다. 멀리서 터진 건 만들지 않는다.
			-- (카메라 흔들림은 아래에서 따로 처리하므로 여기서 return 하면 안 된다)
			local far = (player ~= LocalPlayer) and fxTooFar(payload.pos)
			if not far then
				-- 넘치면 제일 오래된 세트부터 치운다
				while #ryuDebris >= FX_LIMIT.DEBRIS do
					local oldest = table.remove(ryuDebris, 1)
					if oldest and oldest.Model and oldest.Model.Parent then
						oldest.Model:Destroy()
					end
				end

				local c = Dragon.buildCracks(payload.origin, payload.pos, Workspace)
				if c then
					table.insert(ryuDebris, c)
				end
				-- 바위 고리는 착지 지점보다 조금 앞에 만든다 (1인칭에서 보이게)
				local center = payload.pos
				if payload.dir then
					center = center + payload.dir * RYU.ROCK_AHEAD
				end
				local r = Dragon.buildRockRing(center, Workspace)
				if r then
					table.insert(ryuDebris, r)
				end
				-- 고리는 둘러싸는 그림이라 1인칭 정면이 비어 보인다.
				-- 정면 부채꼴을 하나 더 겹쳐서 시야를 채운다.
				local fan = Dragon.buildRockFan(payload.pos, payload.dir, Workspace)
				if fan then
					table.insert(ryuDebris, fan)
				end
			end

			-- 착지 충격으로 카메라를 턴다. 시전자는 최대치, 남은 거리만큼 약하게.
			local cam = Workspace.CurrentCamera
			if cam and payload.pos then
				local s = 1
				if player ~= LocalPlayer then
					s = 1 - (cam.CFrame.Position - payload.pos).Magnitude / Dragon.SHAKE_RANGE
				end
				if s > 0 then
					Dragon.shakeStart(s)
				end
			end
		end
	end)
else
	print("[Ryunochi] RyunochiEvent 를 찾지 못함 - 용 이펙트가 나오지 않는다")
end

local function ultGetRoot()
	local char = LocalPlayer.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
	return root, char
end

-- 발밑 바닥 높이. 못 찾으면 nil
local function ultGroundY(root)
	if not (ultMotion and ultMotion.rayParams and root) then
		return nil
	end
	local ok, res = pcall(function()
		return Workspace:Raycast(root.Position, Vector3.new(0, -5000, 0), ultMotion.rayParams)
	end)
	if ok and res then
		return res.Position.Y + RYUNOCHI_GROUND_DROP
	end
	return nil
end

local function endUlt()
	local _, char = ultGetRoot()
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and ultMotion and ultMotion.prevWalkSpeed then
		pcall(function()
			humanoid.WalkSpeed = ultMotion.prevWalkSpeed
		end)
		pcall(function()
			humanoid.AutoRotate = true
		end)
	end
	ultActive = false
	ultElapsed = 0
	ultMotion = nil
	ultCooldown = RYUNOCHI_COOLDOWN
end

local function startUltMotion()
	local cam = Workspace.CurrentCamera
	local root, char = ultGetRoot()
	if not (cam and root) then
		return false
	end
	-- 조준 방향을 수평으로 눕혀 고정한다. 이후 카메라를 돌려도 진로는 안 바뀐다.
	local f = cam.CFrame.LookVector
	local flat = Vector3.new(f.X, 0, f.Z)
	if flat.Magnitude < 0.01 then
		return false
	end

	local rp = nil
	local ok, params = pcall(function()
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		local list = {}
		if char then
			table.insert(list, char)
		end
		if viewmodel then
			table.insert(list, viewmodel)
		end
		p.FilterDescendantsInstances = list
		return p
	end)
	if ok then
		rp = params
	end

	ultMotion = {
		dir = flat.Unit,
		vy = 0,
		jumped = false,
		grounded = false,
		airWait = 0,
		rayParams = rp,
		prevWalkSpeed = nil,
		startPos = root.Position,
		slamFired = false,
	}

	-- 용 머리 소환. 서버를 거쳐 모든 유저 화면에 뜬다.
	ryuFire({ phase = "start", origin = root.Position, dir = flat.Unit })

	-- 이동 입력 차단. WalkSpeed 는 서버 전용이라 실패할 수 있다(그래도 CFrame 을
	-- 매 프레임 덮어쓰기 때문에 조작은 먹히지 않는다).
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			ultMotion.prevWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 0
		end)
		pcall(function()
			humanoid.AutoRotate = false
		end)
	end
	return true
end

-- 이동은 전부 여기서 직접 만든다 (조작 불가 + 직선 + 느린 낙하)
local function updateUltMovement(dt)
	if not (ultActive and ultMotion) then
		return
	end
	local root = ultGetRoot()
	if not root then
		return
	end
	local m = ultMotion
	local pos = root.Position

	-- 수평: 항상 같은 방향으로 직선. 벽이 있으면 그 앞에서 멈춘다.
	local step = RYUNOCHI_SPEED * dt
	local moved = m.dir * step
	if m.rayParams then
		-- 궁극기 돌진도 풀에 막히면 안 된다 (MELEE.castSolid 설명 참고)
		local res = MELEE.castSolid(pos, m.dir * (step + RYUNOCHI_WALL_PAD), m.rayParams)
		if res then
			moved = Vector3.new(0, 0, 0)
		end
	end

	-- 수직: 점프 전엔 바닥에 붙고, 점프 후엔 약한 중력으로 천천히 떨어진다.
	local newY = pos.Y
	if m.jumped then
		m.vy = m.vy - RYUNOCHI_GRAVITY * dt
		newY = pos.Y + m.vy * dt
		local gy = ultGroundY(root)
		if gy and m.vy < 0 and newY <= gy then
			newY = gy
			m.vy = 0
			m.grounded = true
			-- 내리찍는 순간. 착지 한 번에만 넓게 훑는다
			if not m.slammed then
				m.slammed = true
				MELEE.scanUlt(MELEE.ULT_SLAM_RADIUS)
			end
		end
	else
		local gy = ultGroundY(root)
		if gy then
			newY = gy
		end
	end

	local target = Vector3.new(pos.X + moved.X, newY, pos.Z + moved.Z)
	pcall(function()
		root.CFrame = CFrame.new(target) * (root.CFrame - root.Position)
	end)
end

local function updateUlt(dt)
	if not ultActive then
		return nil
	end
	local clip = getClip(RYUNOCHI_CLIP_NAME)
	if not clip then
		endUlt()
		return nil
	end

	-- 용이 지나가는 동안 매 프레임 주변을 훑는다 (한 사람당 한 번만 나간다)
	MELEE.scanUlt()

	local m = ultMotion

	-- 체공 대기: 점프했는데 아직 안 떨어졌으면 airHoldStart(71f) 자세에서 시간을 멈춘다.
	-- 착지하는 순간 대기가 풀려 71f -> 80f(착지) -> 100f 가 이어서 재생된다.
	local waiting = false
	if m and clip.airHoldStart and m.jumped and not m.grounded
		and ultElapsed >= clip.airHoldStart then
		m.airWait = (m.airWait or 0) + dt
		if m.airWait < RYUNOCHI_AIR_MAX then
			waiting = true
		end
	end

	if not waiting then
		ultElapsed = ultElapsed + dt
	end

	-- 점프 발동
	if m and clip.jumpAt and not m.jumped and ultElapsed >= clip.jumpAt then
		m.jumped = true
		m.vy = RYUNOCHI_JUMP_SPEED
		m.grounded = false
	end

	-- 내리찍기 = 실제로 땅에 닿는 순간. 용이 콱 물고, 지나온 길에 균열 + 앞쪽에 바위 고리.
	-- (고정 시각으로 하면 체공이 길어졌을 때 공중에서 터져버린다)
	if m and m.jumped and m.grounded and not m.slamFired then
		m.slamFired = true
		local root = ultGetRoot()
		if root then
			ryuFire({ phase = "slam", origin = m.startPos, pos = root.Position, dir = m.dir })
		end
	end

	if ultElapsed >= clip.full then
		-- 안전장치: 어떤 이유로든 착지 신호가 안 나갔으면 끝에서라도 터뜨린다
		if m and not m.slamFired then
			m.slamFired = true
			local root = ultGetRoot()
			if root then
				ryuFire({ phase = "slam", origin = m.startPos, pos = root.Position, dir = m.dir })
			end
		end
		endUlt()
		return nil
	end

	local t = waiting and clip.airHoldStart or ultElapsed
	return evaluate(clip.frames, t, clip.parts, clip.posScale)
end

local function onUltPressed()
	-- ★ 패링당해 기절 중이면 아무 조작도 못 한다. HUD 가 _G.StunUntil 을 채워준다.
	--   지역변수 한도가 196/200 이라 여기에 변수를 못 늘려서 전역으로 받는다.
	if _G.StunUntil and os.clock() < _G.StunUntil then
		return
	end
	if introActive or introDelayLeft > 0 then
		return
	end
	if isBlocking() or isFlyingRaijinCommitted() or isUltCommitted() then
		return
	end
	-- ★ 궁극기는 쿨타임이 아니라 충전량으로 열린다.
	--   서버(CombatServer)가 0%->100% 를 관리하고 HUD 가 _G.UltCharge 에 넣어준다.
	--   예전엔 여기 15초짜리 자체 쿨타임이 있어서 게이지와 완전히 따로 놀았다 (2026-08-19).
	if (_G.UltCharge or 0) < 1 then
		return
	end
	if not getClip(RYUNOCHI_CLIP_NAME) then
		print("[ViewmodelController] 궁극기 클립 없음: " .. RYUNOCHI_CLIP_NAME)
		return
	end
	attackActive = false
	comboQueued = false
	ultActive = true
	ultElapsed = 0

	-- 쓰는 즉시 충전량을 비운다. 최종 판단은 서버가 하고, 서버가 다시 채워준다.
	-- 여기서 안 비우면 모션이 끝날 때까지 게이지가 100% 로 남아 있어 두 번 쓴 것처럼 보인다.
	_G.UltCharge = 0
	MELEE.ultHit = {}      -- 이번 궁극기의 피격 명단을 새로 시작한다
	if MELEE.event then
		pcall(function()
			MELEE.event:FireServer({ phase = "ultused" })
		end)
	end

	if not startUltMotion() then
		ultActive = false
	end
end

-- 궁극기 버튼에 쿨타임을 표시한다 (강공격 버튼과 같은 방식)
local function updateUltButton()
	if not ultButton then
		return
	end
	local label = ultButton:FindFirstChild("Label")
	local text, color, transparency
	-- 버튼에는 남은 쿨타임이 아니라 충전 퍼센트를 보여준다
	if (_G.UltCharge or 0) < 1 then
		text = tostring(math.floor((_G.UltCharge or 0) * 100)) .. "%"
		color, transparency = Color3.fromRGB(90, 90, 95), 0.8
	else
		text, color, transparency = ultButtonText, Color3.new(1, 1, 1), 0.7
	end
	if label and label.Text ~= text then
		label.Text = text
	end
	pcall(function()
		ultButton.ImageColor3 = color
		ultButton.ImageTransparency = transparency
	end)
end

local function onFlyingRaijinPressed()
	-- ★ 패링당해 기절 중이면 아무 조작도 못 한다. HUD 가 _G.StunUntil 을 채워준다.
	--   지역변수 한도가 196/200 이라 여기에 변수를 못 늘려서 전역으로 받는다.
	if _G.StunUntil and os.clock() < _G.StunUntil then
		return
	end
	if introActive or introDelayLeft > 0 then
		return
	end
	if isBlocking() or isUltCommitted() then
		return
	end

	-- 쿠나이가 이미 나가 있으면 두 번째 입력은 순간이동이다.
	-- 회수는 쿨타임과 무관하게 항상 된다.
	if flyingRaijinProjectile then
		local tpFrom, tpTo = doFlyingRaijinTeleport()
		-- 연막과 통나무는 남들 화면에도 떠야 "쟤가 순간이동 썼다"를 안다.
		-- 위치 자체는 캐릭터가 복제되니 알아서 옮겨진다.
		if tpFrom and tpTo then
			ryuFire({ phase = "raijin_tp", from = tpFrom, to = tpTo })
		end
		return
	end

	if flyingRaijinActive or flyingRaijinCooldown > 0 then
		return
	end
	if not getClip(FLYINGRAIJIN_CLIP_NAME) then
		return
	end
	flyingRaijinActive = true
	flyingRaijinElapsed = 0
	flyingRaijinKunaiSpawned = false
	attackActive = false
	comboQueued = false
end

-- 반환: pose, clip  (clip 은 뷰모델 쿠나이 표시 판정에 쓴다)
local function updateFlyingRaijin(dt)
	if not flyingRaijinActive then
		return nil, nil
	end
	local clip = getClip(FLYINGRAIJIN_CLIP_NAME)
	if not clip then
		flyingRaijinActive = false
		return nil, nil
	end

	flyingRaijinElapsed = flyingRaijinElapsed + dt

	if not flyingRaijinKunaiSpawned and flyingRaijinElapsed >= (clip.throwAt or clip.full) then
		flyingRaijinKunaiSpawned = true
		spawnFlyingRaijinKunai()
	end

	-- 쿠나이가 나가 있는 동안은 던진 자세(holdAt)에서 계속 멈춘다.
	-- 벽에 박혀 있어도 유지되고, 순간이동하거나 쿠나이가 사라져야 풀린다.
	local hold = clip.holdAt
	if hold and flyingRaijinElapsed >= hold and flyingRaijinProjectile then
		flyingRaijinElapsed = hold
		return evaluate(clip.frames, hold, clip.parts, clip.posScale), clip
	end

	if flyingRaijinElapsed >= clip.full then
		flyingRaijinActive = false
		return nil, nil
	end

	return evaluate(clip.frames, flyingRaijinElapsed, clip.parts, clip.posScale), clip
end

local function startAttack(index)
	attackActive = true
	attackIndex = index
	attackElapsed = 0
	comboQueued = false
	xbladeSpawned = false
	MELEE.fired = false
	xbladeDashStarted = false
	fireServerAttack(index)
end

local function onAttackPressed()
	-- ★ 패링당해 기절 중이면 아무 조작도 못 한다. HUD 가 _G.StunUntil 을 채워준다.
	--   지역변수 한도가 196/200 이라 여기에 변수를 못 늘려서 전역으로 받는다.
	if _G.StunUntil and os.clock() < _G.StunUntil then
		return
	end
	if introActive or introDelayLeft > 0 then
		return
	end

	-- 막고 있거나, 쿠나이를 던져놓고 아직 회수하지 않은 동안, 궁극기 중에는 공격이 안 나간다.
	if isBlocking() or isFlyingRaijinCommitted() or isUltCommitted() then
		return
	end

	if not attackActive then
		startAttack(1)
		return
	end

	-- 컷 지점이 있고 그 전에 누른 경우에만 다음 타를 예약.
	-- 마지막 타는 cut 이 없어서(nil) 예약이 걸리지 않는다.
	local clip = currentAttackClip()
	if clip and clip.cut and attackElapsed < clip.cut and attackIndex < #COMBO then
		comboQueued = true
	end
end

-- ===== 활 차징 =====
-- 기본공격 버튼을 꾹 누르는 동안 시위를 당기고, 떼는 순간 쏜다.
--
-- 차징 무기인지는 Config.CHARACTERS[나라].CHARGE_TIME 이 있는지로 정한다.
-- 그 값이 없는 나라(일본)는 예전 그대로 "떼는 순간 한 번 공격" 이다.
--
-- ★ 최상위 지역변수를 못 늘려서(한도 200) 함수도 상태도 전부 MELEE 테이블에 매단다.
--   local 을 하나라도 늘리면 에러 한 줄 없이 스크립트 전체가 로드에 실패한다.

function MELEE.chargeTime()
	local ch = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
	return ch and ch.CHARGE_TIME
end

function MELEE.bowDown()
	if not MELEE.chargeTime() then
		return                     -- 차징 무기가 아니면 누를 때는 아무 일도 없다
	end
	-- 막을 조건은 onAttackPressed 와 똑같이 건다.
	if _G.StunUntil and os.clock() < _G.StunUntil then
		return
	end
	if introActive or introDelayLeft > 0 then
		return
	end
	if isBlocking() or isFlyingRaijinCommitted() or isUltCommitted() then
		return
	end
	if attackActive then
		return                     -- 앞서 쏜 발사 동작이 아직 안 끝났다
	end
	MELEE.charging = true
	MELEE.chargeT = 0
end

function MELEE.bowUp()
	-- 차징 중이 아니면 아무 일도 안 한다. 그래서 두 번 불려도 안전하다
	-- (버튼 밖에서 떼는 경우를 대비해 전역에서도 한 번 더 부른다).
	if not MELEE.charging then
		return
	end
	MELEE.charging = false
	-- 발사 세기 0~1. 발사체 로직이 이 값으로 사거리와 궤적을 정한다.
	--   기획 : 0~50% 는 얼마 못 가 땅에 박히고, 51~100% 는 포물선으로 제대로 날아간다.
	--   아직 읽는 쪽이 없다. 화살 발사체를 만들 때 여기서 가져다 쓴다.
	_G.BowPower = math.min((MELEE.chargeT or 0) / MELEE.chargeTime(), 1)
	_G.BowCharge = 0
	MELEE.chargeT = 0
	onAttackPressed()

	-- 실제로 날아가는 화살을 내보낸다. 조준선 그대로 나간다.
	local cam = Workspace.CurrentCamera
	if cam then
		local aim = cam.CFrame.LookVector.Unit
		local org = cam.CFrame.Position + aim * MELEE.ARROW.MUZZLE
		MELEE.bowShoot(org, aim, _G.BowPower)
		-- 남들 화면에도 같은 화살을 그린다. 초기값만 보내고 각자 계산한다.
		ryuFire({ phase = "bow_shot", origin = org, dir = aim, power = _G.BowPower })
	end
end

function MELEE.bowCharge(dt)
	if not MELEE.charging then
		return nil
	end
	local c = getClip("BowDraw")
	local full = MELEE.chargeTime()
	if not (c and full) then
		MELEE.charging = false
		return nil
	end
	MELEE.chargeT = (MELEE.chargeT or 0) + dt
	local a = MELEE.chargeT / full
	if a > 1 then
		a = 1                      -- 100% 에서 계속 눌러도 당긴 자세를 유지한다
	end
	_G.BowCharge = a              -- HUD 가 게이지를 그릴 수 있게 내보낸다. 아직 그리는 쪽은 없다
	-- ★ 시간이 아니라 게이지로 재생 위치를 정한다. 이게 차징의 핵심이다.
	return evaluate(c.frames, a * c.duration, c.parts, c.posScale)
end

-- ===== 활시위 =====
-- 블렌더에서 시위의 V자는 Hook 모디파이어가 '정점'을 휘게 해서 만든 것이라
-- 오브젝트 변환에 안 잡힌다. 클립은 파츠별 위치+회전만 싣기 때문에
-- 아무리 잘 애니메이팅해도 시위 당김은 게임으로 안 넘어온다.
-- 그래서 원본 시위 파츠는 숨기고, 활 양 끝에서 넉 지점까지 직선 두 개로 직접 그린다.
--
-- 넉 지점은 따로 계산하지 않는다. 화살 뒤끝을 그대로 쓴다 —
-- 화살은 이미 클립이 차징 게이지대로 당겨주고 있어서 몇 %든 저절로 맞는다.

-- ★ 활 양 끝과 넉 지점. 파츠 로컬 좌표(cm) 다.
--
--   처음에는 Size 에서 가장 긴 축을 시위 방향으로 삼았는데 그게 틀렸다.
--   메시에 회전이 구워진 채로 임포트돼서 파츠의 로컬 축이 시위 방향과 20도쯤
--   어긋나 있다 (시위 Size 가 (99.282, 36.282, 5.505) 인 이유다 —
--   길이 105.534 짜리 실이 20도 기울어 있어서 bbox 가 저렇게 나온다).
--   그래서 축이 아니라 '실제 끝점'을 재서 박는다.
--
--   블렌더 프레임 10(시위 안 당긴 대기 자세)에서 실측했다.
--   ★ 모델을 다시 임포트하면 이 값도 다시 재야 한다.
--   검산 : TIP_A ~ TIP_B 거리 = 105.534cm = 실제 시위 길이.
MELEE.BOW = {
	TIP_A = Vector3.new(-49.576, 17.934, 2.247),
	TIP_B = Vector3.new(49.629, -17.731, -2.630),
	NOCK = Vector3.new(-3.450, -5.401, -41.933),   -- 화살 뒤끝 (화살 파츠 기준)
	THICK = 1.1,                                    -- 실측 굵기 0.86~1.26cm
}

function MELEE.makeSeg(parent, color, thick)
	local p = Instance.new("Part")
	p.Name = "Gukgung_String_Seg"
	p.Size = Vector3.new(thick, thick, thick)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color = color
	pcall(function()
		p.CanQuery = false
		p.Material = Enum.Material.Fabric
	end)
	p.Parent = parent
	return p
end

-- 두 점을 잇는 막대 하나를 놓는다. alignZCFrame 이 로컬 +Z 를 방향에 맞춘다.
function MELEE.setSeg(p, a, b, thick, hidden)
	local d = b - a
	local len = d.Magnitude
	if hidden or len < 0.01 then
		p.Transparency = 1
		return
	end
	p.Transparency = 0
	p.Size = Vector3.new(thick, thick, len)
	p.CFrame = alignZCFrame(a + d * 0.5, d)
end

function MELEE.bowString(base)
	local si = viewmodelPartsByName["Gukgung_String"]
	local ai = viewmodelPartsByName["Arrow_Gukgung"]
	if not (si and ai and si.Part.Parent and ai.Part.Parent) then
		return
	end
	local sp, ap = si.Part, ai.Part
	local B = MELEE.BOW

	-- 원본 시위는 한 덩어리라 절대 안 휜다. 항상 숨긴다.
	if sp.Transparency < 1 then
		sp.Transparency = 1
	end

	-- 로비 등에서 뷰모델이 통째로 숨겨지면 시위도 같이 숨긴다.
	-- 이 두 파츠는 viewmodelPartsByName 에 없어서 setViewmodelVisible 이 못 건드린다.
	local bi = viewmodelPartsByName["Gukgung_Bow"]
	local off = (bi ~= nil) and (bi.Part.Transparency >= 1)

	-- 실측 로컬 좌표를 각 파츠의 현재 자세로 옮긴다.
	-- 넉은 화살 파츠 기준이라, 화살이 당겨지면 저절로 따라온다 —
	-- 차징 몇 % 인지 따로 볼 필요가 없다.
	local nock = ap.CFrame * B.NOCK
	if not (MELEE.strA and MELEE.strA.Parent) then
		MELEE.strA = MELEE.makeSeg(sp.Parent, sp.Color, B.THICK)
		MELEE.strB = MELEE.makeSeg(sp.Parent, sp.Color, B.THICK)
	end
	MELEE.setSeg(MELEE.strA, sp.CFrame * B.TIP_A, nock, B.THICK, off)
	MELEE.setSeg(MELEE.strB, sp.CFrame * B.TIP_B, nock, B.THICK, off)
end

-- ===== 화살 발사체 =====
-- 뷰모델의 화살은 클립이 그리는 '그림'일 뿐이라 손을 떠나지 않는다.
-- 실제로 날아가는 화살은 여기서 따로 만든다.
--
-- 남들 화면에도 보여야 하므로 서버(RyunochiServer)를 한 번 거쳐 전원에게 뿌린다.
-- 매 프레임 위치를 보내지 않고 초기값만 보낸 뒤 각자 같은 궤적을 계산한다.
-- 쿠나이가 쓰는 방식과 같다 — 훨씬 가볍고 궤적도 매끄럽다.
--
-- ★ 조정용 숫자. 전부 cm 기준 (이 프로젝트의 길이 단위).
--   기획의 "0~50% 는 나가다 땅에 박히고 51~100% 는 포물선으로 제대로" 는
--   속도 하나로 자연히 나온다. 느리면 중력에 금방 지고, 빠르면 멀리 간다.
--   실제로 쏴보고 이 숫자들만 만지면 된다.
MELEE.ARROW = {
	MUZZLE = 120,       -- 카메라에서 이만큼 앞에서 생겨난다
	SPEED_MIN = 2600,   -- 차징 0% 의 속도 (cm/s) = 26m/s
	SPEED_MAX = 9000,   -- 차징 100% 의 속도 = 90m/s
	GRAVITY = 1800,     -- 낙하 가속도 (cm/s^2). 키우면 더 많이 휜다
	LIFE = 5,           -- 이 시간이 지나면 사라진다 (초)
	STUCK = 3,          -- 박힌 뒤 남아있는 시간 (초)
	MAX = 24,           -- 동시에 떠 있는 화살 상한 (남의 것 포함)
}
MELEE.arrows = {}

function MELEE.bowShoot(origin, dir, power)
	local A = MELEE.ARROW
	if dir.Magnitude < 0.0001 then
		return
	end
	dir = dir.Unit

	-- 상한을 넘으면 가장 오래된 것부터 지운다 (여럿이 쏘면 파츠가 계속 쌓인다)
	while #MELEE.arrows >= A.MAX do
		local old = table.remove(MELEE.arrows, 1)
		if old and old.part and old.part.Parent then
			old.part:Destroy()
		end
	end

	local p = Instance.new("Part")
	p.Name = "Gukgung_Arrow"
	p.Size = Vector3.new(2, 2, 70)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Color = Color3.fromRGB(120, 96, 62)
	pcall(function()
		p.CanQuery = false
		p.Material = Enum.Material.Wood
	end)
	p.CFrame = alignZCFrame(origin, dir)
	p.Parent = Workspace

	local a = math.clamp(power or 1, 0, 1)
	table.insert(MELEE.arrows, {
		part = p,
		pos = origin,
		vel = dir * (A.SPEED_MIN + (A.SPEED_MAX - A.SPEED_MIN) * a),
		t = 0,
		stuck = nil,
	})
end

function MELEE.stepArrows(dt)
	local A = MELEE.ARROW
	for i = #MELEE.arrows, 1, -1 do
		local a = MELEE.arrows[i]
		a.t = a.t + dt
		local dead = false

		if a.stuck then
			-- 박힌 화살은 그 자리에 그대로 두고 시간만 센다
			dead = (a.t - a.stuck) >= A.STUCK
		else
			a.vel = a.vel - Vector3.new(0, A.GRAVITY * dt, 0)
			local nxt = a.pos + a.vel * dt
			-- ★ castSolid 를 쓴다. 그냥 Raycast 를 쓰면 CanCollide=0 인 풀잎에
			--   화살이 전부 막힌다 (쿠나이가 이미 겪은 함정. 위 castSolid 주석 참고).
			local hit = nil
			pcall(function()
				hit = MELEE.castSolid(a.pos, nxt - a.pos, buildRayParams(nil))
			end)
			if hit then
				a.pos = hit.Position
				a.stuck = a.t
			else
				a.pos = nxt
				if a.t >= A.LIFE then
					dead = true
				end
			end
			if a.part.Parent then
				-- 나는 동안은 속도 방향을 본다 (그래서 포물선을 따라 고개를 숙인다)
				a.part.CFrame = alignZCFrame(a.pos, a.vel)
			end
		end

		if dead then
			if a.part and a.part.Parent then
				a.part:Destroy()
			end
			table.remove(MELEE.arrows, i)
		end
	end
end

local function updateAttack(dt)
	if not attackActive then
		return nil
	end

	local clip = currentAttackClip()
	if not clip then
		attackActive = false
		return nil
	end

	attackElapsed = attackElapsed + dt

	if comboQueued and clip.cut and attackElapsed >= clip.cut then
		startAttack(attackIndex + 1)
		clip = currentAttackClip()
		if not clip then
			attackActive = false
			return nil
		end
	end

	-- 휘두르는 순간에 근접 판정. 모든 타에서 나간다.
	-- 서버가 거리·팀·무적을 다시 검사하므로 여기서는 후보만 보낸다.
	if not MELEE.fired and attackElapsed >= MELEE.AT then
		MELEE.fired = true
		local target = findMeleeTarget()
		if target and MELEE.event then
			-- 3타는 참격도 같이 나간다. 근접으로 보낸 사람은 참격에서 또 보내지 않는다
			MELEE.xbladeHit[target] = true
			pcall(function()
				MELEE.event:FireServer({ phase = "melee", target = target, index = attackIndex })
			end)
		end
	end

	-- 3타 휘두르는 순간에 맞춰 대쉬 -> X자 참격 순으로 나간다
	if COMBO[attackIndex] == XBLADE_ON_CLIP then
		if not xbladeDashStarted and attackElapsed >= XBLADE_AT - XBLADE_DASH_LEAD then
			xbladeDashStarted = true
			MELEE.xbladeHit = {}      -- 이번 참격의 명단을 새로 시작 (근접 판정보다 먼저 돈다)
			startXbladeDash()
		end
		if not xbladeSpawned and attackElapsed >= XBLADE_AT then
			xbladeSpawned = true
			spawnXblade()
		end
	end

	if attackElapsed >= clip.full then
		attackActive = false
		return nil
	end

	return evaluate(clip.frames, attackElapsed, clip.parts, clip.posScale)
end

local function setViewmodelVisible(visible)
	local t = visible and 0 or 1
	for _, item in pairs(viewmodelPartsByName) do
		-- 쿠나이는 스킬 쓸 때만 보인다. 여기서 켜지 않는다.
		if item.Part.Parent and not item.IsKunai then
			item.Part.Transparency = t
		end
	end
end

local function findSource()
	return ReplicatedStorage:FindFirstChild(VIEWMODEL_SOURCE_NAME)
		or Workspace:FindFirstChild(VIEWMODEL_SOURCE_NAME)
end

local function removeOldRuntimeViewmodels()
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == RUNTIME_VIEWMODEL_NAME then
			child:Destroy()
		end
	end
end

local function materialFromName(name: string)
	if name == "Metal" then
		return Enum.Material.Metal
	end
	if name == "Plastic" then
		return Enum.Material.Plastic
	end
	return nil
end

-- Config 에 지정된 색/재질을 입힌다. 지정이 없는 파츠는 건드리지 않는다.
local function applyAppearance(part)
	local c = COLORS[part.Name]
	if c then
		local ok = pcall(function()
			part.Color = Color3.fromRGB(c[1], c[2], c[3])
		end)
		if not ok then
			print("[ViewmodelController] Color 적용 실패: " .. part.Name)
		end
	end

	local material = materialFromName(MATERIALS[part.Name])
	if material then
		pcall(function()
			part.Material = material
		end)
	end
end

local function prepareViewmodelParts(model)
	viewmodelPartsByName = {}

	-- 이 나라 전용 클립이 아직 없으면 포즈를 아예 안 먹인다.
	-- 팔 파츠 이름(Right_Arm_Mesh / Left_Arm_Mesh)이 나라끼리 겹쳐서,
	-- 그냥 두면 남의 나라 팔 모션이 그대로 적용된다.
	-- 포즈 조회가 `pose and pose[item.PoseName]` 라 이름만 안 맞추면 rest 자세로 남는다.
	local ch = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
	local noAnim = (ch ~= nil) and (ch.ANIM == false)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 0
			pcall(function()
				part.DoubleSided = true
			end)

			applyAppearance(part)

			local relativeCFrame = SOURCE_PIVOT:Inverse() * part.CFrame
			local relativePosition = relativeCFrame.Position * VIEWMODEL_SCALE
			local relativeRotation = relativeCFrame - relativeCFrame.Position
			part.Size = part.Size * VIEWMODEL_SCALE

			local isKunai = isKunaiPartName(part.Name)
			if isKunai then
				part.Transparency = 1   -- 스킬 쓰기 전까지 숨김
			end

			viewmodelPartsByName[part.Name] = {
				Part = part,
				PoseName = noAnim and "__noanim" or (isKunai and "Kunai" or (POSE_ALIAS_BY_PART[part.Name] or part.Name)),
				IsKunai = isKunai,
				RestCFrame = CFrame.new(relativePosition) * relativeRotation,
			}
		end
	end
end

local function setupViewmodel()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
	removeOldRuntimeViewmodels()
	viewmodelPartsByName = {}

	attackActive = false
	attackIndex = 0
	attackElapsed = 0
	comboQueued = false

	blockState = "none"
	blockElapsed = 0

	flyingRaijinActive = false
	flyingRaijinElapsed = 0
	flyingRaijinKunaiSpawned = false
	flyingRaijinCooldown = 0
	xbladeSpawned = false
	MELEE.fired = false
	xbladeDashStarted = false
	drawActive = false
	drawElapsed = 0
	MELEE.charging = false        -- 나라를 바꾸면 당기던 것도 푼다
	MELEE.chargeT = 0
	-- 시위 막대는 옛 뷰모델과 함께 지워졌다. 다음 프레임에 새로 만들게 비운다.
	MELEE.strA = nil
	MELEE.strB = nil
	xbladeDash = nil

	ultActive = false
	ultElapsed = 0
	ultCooldown = 0
	ultMotion = nil
	destroyFlyingRaijinProjectile()
	destroyXblade()

		-- 로비 LOADOUT 에서 고른 나라에 맞는 뷰모델로 갈아끼운다.
		-- ★ 최상위 지역변수를 새로 만들지 않는다. 이 스크립트는 한도(200)에 정확히 붙어 있어서
		--   local 을 하나만 늘려도 "Out of local registers" 로 통째로 로드에 실패한다.
		--   기존 변수에 값만 다시 넣는다 (함수 안쪽 지역변수는 예산이 따로라 상관없다).
		local ch = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
		if ch then
			if ch.SOURCE then
				VIEWMODEL_SOURCE_NAME = ch.SOURCE
			end
			if ch.PIVOT then
				SOURCE_PIVOT = CFrame.new(ch.PIVOT[1], ch.PIVOT[2], ch.PIVOT[3])
			end
			if ch.OFFSET then
				CAMERA_OFFSET = CFrame.new(ch.OFFSET[1], ch.OFFSET[2], ch.OFFSET[3])
			else
				CAMERA_OFFSET = CFrame.new(Config.OFFSET_X, Config.OFFSET_Y, Config.OFFSET_Z)
			end
		end

		local source = findSource()
		if not source then
			print("[ViewmodelController] source NOT FOUND: " .. VIEWMODEL_SOURCE_NAME)
			return
		end
		viewmodel = source:Clone()
	viewmodel.Name = RUNTIME_VIEWMODEL_NAME
	viewmodel.Parent = Workspace
	prepareViewmodelParts(viewmodel)

	-- 무엇을 어떤 값으로 만들었는지 남긴다. 나라별 값이 서로 물리면 여기서 바로 드러난다.
	do
		local cnt = 0
		for _ in pairs(viewmodelPartsByName) do cnt = cnt + 1 end
		local p, o = SOURCE_PIVOT.Position, CAMERA_OFFSET.Position
		print(string.format(
			"[VM] pick=%s src=%s parts=%d pivot=(%.1f, %.1f, %.1f) offset=(%.0f, %.0f, %.0f)",
			tostring(_G.MyPick), tostring(VIEWMODEL_SOURCE_NAME), cnt,
			p.X, p.Y, p.Z, o.X, o.Y, o.Z))

		-- 클립 게이트가 실제로 도는지 한 줄로 드러낸다.
		-- gate=off 인데 국궁이면 나라별 분리가 안 먹은 것이고,
		-- attack=nil 이면 공격 버튼을 눌러도 아무 모션도 안 나온다는 뜻이다.
		-- 여기 찍히는 이름이 곧 실제로 재생될 클립이다.
		local g = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
		g = g and g.CLIPS
		print(string.format(
			"[VM] gate=%s attack=%s block=%s intro=%s",
			g and "on" or "off",
			tostring(g and g.Attack1 or (g and "nil" or COMBO[1])),
			tostring(g and (g.BlockIn or "nil") or "BlockIn"),
			tostring(g and (g.Intro or "nil") or "Intro")))
	end

	if not introPlayed then
		introPlayed = true
		introDelayLeft = INTRO_DELAY
		introActive = false
		introElapsed = 0
		setViewmodelVisible(false)
	end
end

	RunService.RenderStepped:Connect(function(dt)
		-- 로비에서는 뷰모델(팔·칼)이 보이면 안 된다. 3인칭으로 내 아바타를 보는 화면이다.
		-- 상태 플래그는 MELEE 테이블에 얹는다 (지역변수 한도 196/200)
		-- 로비에서 고른 나라가 바뀌었으면 그 자리에서 뷰모델을 다시 만든다.
		--
		-- ★ 반드시 아래 로비 return 보다 "먼저" 봐야 한다. 뒤에 두면 로비에 있는 동안
		--   여기까지 오지 못해 갱신이 안 되고, VIEWMODEL_SOURCE_NAME / SOURCE_PIVOT /
		--   CAMERA_OFFSET 이 앞 캐릭터 값으로 남는다. 그러면 나라별로 따로 둔 값이
		--   서로 묶인 것처럼 보인다.
		--
		-- 상태는 MELEE 테이블에 얹는다 (최상위 지역변수 한도 200 때문에 새 local 을 못 만든다).
		if MELEE.pick ~= _G.MyPick then
			MELEE.pick = _G.MyPick
			-- 나라가 바뀌면 인트로도 처음부터 다시 튼다.
			-- setupViewmodel 안의 인트로 초기화가 `if not introPlayed then` 으로 막혀 있어서,
			-- 이걸 안 내리면 INTRO_DELAY(1초) 가 다시 안 걸리고 인트로도 안 나온다.
			-- 스폰 직후 로비에 들어가기 전 짧은 순간에 딜레이가 이미 소진되기 때문이다.
			introPlayed = false
			setupViewmodel()
			-- 새로 만든 파츠는 숨김 상태를 다시 판단해야 한다.
			-- 안 지우면 로비에서 방금 만든 뷰모델이 그대로 보인다.
			MELEE.vmHidden = nil
		end

		if _G.InLobby then
			if not MELEE.vmHidden then
				MELEE.vmHidden = true
				setViewmodelVisible(false)
			end
			return
		elseif MELEE.vmHidden then
			MELEE.vmHidden = false
			setViewmodelVisible(true)
		end

		dt = dt or (1 / 60)

		-- 비뢰신 상태가 바뀔 때만 서버에 알린다 (매 프레임 쏘면 낭비다).
		-- 남들이 내 왼손 칼을 숨겨야 할지 판단하는 근거가 된다.
		-- isFlyingRaijinCommitted() 는 던지는 모션 ~ 쿠나이가 박혀 있는 동안 ~ 칼 다시 빼기까지 참이다.
		local raijinNow = isFlyingRaijinCommitted()
		if raijinNow ~= RAIJIN_HAND.last then
			RAIJIN_HAND.last = raijinNow
			ryuFire({ phase = "raijin_hand", hide = raijinNow })
		end

		updateOtherPlayersWorldWeapons(dt)
		Camera = Workspace.CurrentCamera
		if not Camera or not viewmodel then
			return
		end

	if introDelayLeft > 0 then
		introDelayLeft = introDelayLeft - dt
		if introDelayLeft <= 0 then
			introDelayLeft = 0
			setViewmodelVisible(true)
			introActive = true
			introElapsed = 0
		else
			return
		end
	end

	breatheTime = breatheTime + dt
	local bobY = math.sin(breatheTime * BREATHE_Y_SPEED) * BREATHE_Y_AMOUNT
	local bobX = math.cos(breatheTime * BREATHE_X_SPEED) * BREATHE_X_AMOUNT
	local roll = math.sin(breatheTime * BREATHE_X_SPEED) * math.rad(BREATHE_ROT_AMOUNT)

	local accel = (-kickOffset * SPRING_STIFFNESS) - (kickVelocity * SPRING_DAMPING)
	kickVelocity = kickVelocity + accel * dt
	kickOffset = kickOffset + kickVelocity * dt

	-- 흔들림은 카메라와 뷰모델에 같이 먹여야 한 덩어리로 흔들린다.
	-- 실제 계산은 Dragon 모듈에 있다 (여기 지역변수 한도가 199/200 이라 못 넣는다).
	local breathe = CFrame.new(bobX, bobY + kickOffset, 0) * CFrame.Angles(0, 0, roll)
	local baseCFrame = (Dragon.shakeUpdate(dt, Camera) or Camera.CFrame)
		* CAMERA_OFFSET * breathe * VIEWMODEL_DIRECTION_FIX

	updateFlyingRaijinProjectile(dt)
	updateRemoteKunai(dt)
	updateXblade(dt)
	updateXbladeDash(dt)
	updateUltMovement(dt)
	ryuUpdate(dt)
	updateEffects(dt)
	MELEE.stepArrows(dt)

	if flyingRaijinCooldown > 0 then
		flyingRaijinCooldown = flyingRaijinCooldown - dt
		if flyingRaijinCooldown < 0 then
			flyingRaijinCooldown = 0
		end
	end
	if ultCooldown > 0 then
		ultCooldown = ultCooldown - dt
		if ultCooldown < 0 then
			ultCooldown = 0
		end
	end
	updateFlyingRaijinButton()
	updateUltButton()

	-- 우선순위: 인트로 > 궁극기 > 스킬(쿠나이) > 막기 > 공격 > 기본 자세
	local pose, flyingRaijinClip = nil, nil
	if introActive then
		introElapsed = introElapsed + dt
		-- 나라마다 인트로가 다르다. getClip 이 CLIPS 표를 보고 알아서 갈라준다
		-- (korea 는 CLIPS.Intro = "GukgungIntro"). 표가 없는 나라는 ViewmodelAnimData.Intro
		-- 즉 와키자시 인트로로 떨어진다.
		-- ★ 최상위 지역변수를 못 늘려서 여기서 매번 조회한다. getClip 이 캐시하므로 부담 없다.
		local ic = getClip("Intro") or Anim.Intro
		-- 재생 속도 = Config.CHARACTERS[나라].INTRO_SPEED.
		--   1 = 클립 원래 속도, 0.5 = 절반 속도(두 배로 길게), 2 = 두 배로 빠르게.
		--   클립 데이터를 다시 뽑지 않고 그 숫자만으로 조절한다. 0 이하나 없으면 1 로 친다.
		-- ★ 지역변수를 늘리지 않으려고 it 하나에 몰아 담는다. 이 스크립트는 한도(200)에
		--   붙어 있어서 하나만 늘려도 에러 없이 통째로 로드에 실패한다.
		local it = Config.CHARACTERS and Config.CHARACTERS[_G.MyPick or "japan"]
		it = introElapsed * ((it and it.INTRO_SPEED and it.INTRO_SPEED > 0 and it.INTRO_SPEED) or 1)
		if it >= ic.duration then
			introActive = false
		else
			pose = evaluate(ic.frames, it, ic.parts, ic.posScale)
		end
	elseif ultActive then
		pose = updateUlt(dt)
	else
		pose, flyingRaijinClip = updateFlyingRaijin(dt)
		if not pose then
			pose = updateDraw(dt)
		end
		if not pose then
			pose = updateBlock(dt)
			if not pose then
				-- 차징이 공격보다 먼저다. 누르고 있는 동안 당긴 자세를 유지한다.
				pose = MELEE.bowCharge(dt)
			end
			if not pose then
				pose = updateAttack(dt)
			end
		end
	end

	-- 뷰모델 쿠나이는 스킬 중 손을 떠나기 전까지만 보인다
	local kunaiVisible = false
	if flyingRaijinClip then
		kunaiVisible = flyingRaijinElapsed < (flyingRaijinClip.kunaiHide or flyingRaijinClip.full)
	end
	local kunaiClip = flyingRaijinClip or getClip(FLYINGRAIJIN_CLIP_NAME)

		for _, item in pairs(viewmodelPartsByName) do
			local part = item.Part
			if part.Parent then
				local delta = pose and pose[item.PoseName]
				if item.IsKunai then
					part.Transparency = kunaiVisible and 0 or 1
					local rest = getKunaiRest(kunaiClip, part.Name) or item.RestCFrame
					if delta then
						part.CFrame = baseCFrame * delta * rest
					else
						part.CFrame = baseCFrame * rest
					end
				elseif delta then
					part.CFrame = baseCFrame * delta * item.RestCFrame
				else
					part.CFrame = baseCFrame * item.RestCFrame
				end
			end
		end

		-- 파츠 자리가 다 정해진 뒤에 시위를 그린다. 순서를 바꾸면 한 프레임 늦게 따라온다.
		MELEE.bowString(baseCFrame)
end)

task.spawn(function()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	local gui = playerGui:WaitForChild("CombatButtons", 10)
	if not gui then
		return
	end
	local btn = gui:WaitForChild("AttackButton", 10)
	if btn then
		-- ★ 활은 꾹 누르는 동안 차징이라 '유지형' 버튼이어야 한다.
		--   Activated 는 뗄 때 한 번만 오는 신호라 누르고 있는 시간을 알 수 없다.
		--   그래서 누름/뗌을 따로 받는다.
		--
		--   일본(차징 아님)은 검증된 Activated 경로를 그대로 쓴다. 아래 새 경로가
		--   이 엔진에서 안 먹더라도 와키자시는 멀쩡하도록 갈라놨다.
		btn.Activated:Connect(function()
			if not MELEE.chargeTime() then
				onAttackPressed()
			end
		end)
		btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				MELEE.bowDown()
			end
		end)
		btn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				MELEE.bowUp()
			end
		end)
		-- 손가락(커서)이 버튼 밖으로 미끄러진 채 떼면 위 InputEnded 가 안 온다.
		-- 그대로 두면 영원히 당긴 채로 굳으므로 전역에서 한 번 더 받는다.
		-- MELEE.charging 일 때만 부르므로 일본 쪽에는 영향이 없다.
		game:GetService("UserInputService").InputEnded:Connect(function(input)
			if MELEE.charging
				and (input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch) then
				MELEE.bowUp()
			end
		end)
	end
	local blockBtn = gui:WaitForChild("BlockButton", 10)
	if blockBtn then
		blockBtn.Activated:Connect(onBlockPressed)
	end
	-- 쿠나이 투척 = 강공격 버튼. 궁극기로 옮기려면 이 줄만 바꾸면 된다.
	local skillBtn = gui:WaitForChild("HeavyAttackButton", 10)
	if skillBtn then
		skillBtn.Activated:Connect(onFlyingRaijinPressed)
		flyingRaijinButton = skillBtn
		local label = skillBtn:FindFirstChild("Label")
		if label then
			flyingRaijinButtonText = label.Text      -- 쿨타임 끝나면 이 글자로 되돌린다
		end
	end
	-- 궁극기 버튼
	local ultBtn = gui:WaitForChild("UltimateButton", 10)
	if ultBtn then
		ultBtn.Activated:Connect(onUltPressed)
		ultButton = ultBtn
		local label = ultBtn:FindFirstChild("Label")
		if label then
			ultButtonText = label.Text
		end
	end
end)

if LocalPlayer.Character then
	setupViewmodel()
end

LocalPlayer.CharacterAdded:Connect(function()
	setupViewmodel()
end)

-- ★ 카나리아. 이 줄이 안 찍히면 위 어딘가에서 스크립트가 죽은 것이다.
--   (인수인계 §2-5 : 서비스 선언 하나만 빠져도 조용히 죽는데, 위쪽 로그는 멀쩡히 찍힌다)
--   물려 있어야 할 것들을 같이 찍어 어디가 끊겼는지 한 줄로 보이게 한다.
print(string.format(
	"[Viewmodel] ready | ryuEvent=%s | Dragon=%s | attackEvent=%s | FX_RANGE=%dm | source=%s",
	tostring(ryuEvent ~= nil),
	tostring(Dragon ~= nil),
	tostring(weaponAttackEvent ~= nil),
	FX_LIMIT.RANGE / 100,
	tostring(findSource() ~= nil)))
