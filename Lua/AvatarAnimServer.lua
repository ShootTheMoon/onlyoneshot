-- 3인칭 아바타 애니메이션
--
-- 지금까지 만든 건 전부 1인칭 뷰모델이라, 남이 볼 때 아바타는 맨손 기본 모션이다.
-- Sword Idle 을 상체에만 얹어서 "칼 들고 있는 자세"를 만든다.
--
-- ★ 확인된 사실 (2026-08-14 로그)
--   공식 문서는 Character.Animate 아래 Idle/IdleAnim 같은 Animation 인스턴스를
--   갈아끼우라고 하는데, 이 프로젝트의 Animate 는 자식이 하나도 없는 LocalScript 다.
--   그래서 그 방법은 못 쓴다. Animator 에 직접 트랙을 얹는 방식으로 간다.
--
--   본 계층도 문서와 일치한다 : Skeleton > Root > ... > RightHand > RightItem.
--   문서에 없던 것 : ThirdPersonCamera / FirstPersonCamera / IKFootRoot / IKHandRoot
--   (IKHandGun > IKLeftHand, IKRightHand) 본이 추가로 있다.
--
-- 서버에서 재생한다. Animator 는 서버에서 클라이언트로 복제되므로 모든 유저가 같이 본다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
-- ★ 이 줄이 빠져 있어서 파일 끝의 WeaponAttackEvent 연결이 nil 참조로 죽었다 (2026-08-18).
--   증상: 트랙은 정상 로드되는데 공격 이벤트가 영영 안 오고 "[AvatarAnim] ready" 도 안 찍힌다.
--   마지막 print 가 안 보이면 그 위 어딘가에서 죽은 것이다. 그게 제일 빠른 단서다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 스튜디오 애니메이션 툴로 직접 만든 클립이다 (FBX 임포트가 아니다).
-- FBX 로 넣은 애니메이션은 자기 스켈레톤이 새로 생겨서 ODA 아바타 본에 안 얹힌다.
-- 그래서 3인칭 모션은 전부 스튜디오 툴로 만든 것만 쓴다.
--   42005100 wakizashiidleanim      (2026-08-16, 현재 사용중. 정면을 보도록 다시 만든 것)
--   42004100 IdleAnimationcomplete  (2026-08-16, 이전)
--   41998100 IdleAnimation          (2026-08-15, 이전)
local SWORD_IDLE = "ovdrassetid://42005100"

-- 상체에만 적용할지 여부 (false면 전신 적용)
local UPPER_BODY_ONLY = false

-- ★ 커스텀 Idle 애니메이션 포즈 적용 여부
local ENABLE_SWORD_POSE = true

-- idle 트랙의 우선순위. Enum.AnimationPriority 의 이름을 그대로 쓴다.
--
-- ★ 실측 (2026-08-16)
--   "Action"(3) : 이동 중에도 계속 재생돼 달리기를 막는다.  <- 원래 값, 달리기 안 나옴
--   "Idle"(5)   : 달리기는 살아나는데 서 있을 때 우리 idle 이 안 보인다.
--                 엔진 기본 idle 과 같은 등급이라 밀린다.
--                 이때도 track.IsPlaying 은 true 다 - 재생은 되는데 화면에서 덮인 것뿐이라
--                 IsPlaying 만 보고 판단하면 안 된다.
--
--   그래서 우선순위 싸움에 맡기지 않고 아래에서 직접 켜고 끈다.
--   Action 으로 두면 서 있을 때 기본 idle 을 확실히 이기고,
--   이동이 시작되면 우리가 Stop 하므로 기본 달리기가 그대로 나온다.
local IDLE_PRIORITY = "Action"

-- idle 을 켜고 끌 때의 페이드 시간(초). 짧으면 딱딱 끊기고 길면 흐물거린다.
local IDLE_FADE = 0.2

-- ===== 걷기 =====
-- 42007100 Runninganimwakizashi (2026-08-17)
--
-- ★ 이 클립은 앞부분이 "걷기 준비동작"이라 그냥 루프 걸면 매 바퀴 그게 다시 나온다.
--   그래서 처음 한 번만 0 부터 재생하고, 되감길 때마다 WALK_LOOP_START 로 밀어준다.
--   결과: 0 -> 끝 (준비동작 포함) -> 0.4 -> 끝 -> 0.4 -> 끝 ...
local WALK_ANIM = "ovdrassetid://42007100"
local WALK_LOOP_START = 0.4    -- 초. 준비동작이 끝나고 걷기 사이클이 시작되는 지점
local WALK_FADE = 0.15
local ENABLE_WALK = true       -- false 면 엔진 기본 이동 모션을 그대로 쓴다

-- ===== 달리기 =====
-- 42026100 walkinganimwakizashi1 (2026-08-17). 걷기와 같은 구조 (앞부분이 준비동작).
-- ※ 에셋 이름이 실제 용도와 뒤바뀌어 있다. 사용자가 지정한 용도를 따른다 :
--     42007100 Runninganimwakizashi   -> 걷기
--     42026100 walkinganimwakizashi1  -> 달리기
local RUN_ANIM = "ovdrassetid://42026100"
local RUN_LOOP_START = 0.4
local RUN_FADE = 0.15

-- 걷기와 달리기를 가르는 속도 (cm/s).
-- MovementSpeedServer 가 이동 중에 WalkSpeed 를 base(500) -> base*1.6(800) 으로
-- RAMP_TIME(1.8초)에 걸쳐 올린다. 그 중간값을 경계로 삼았다.
-- 그래서 "출발해서 가속하는 동안 걷기 -> 최고속도에서 달리기" 로 자연스럽게 넘어간다.
local RUN_SPEED = 650

-- ===== 공격 =====
-- 42081100 wakizashiattack (2026-08-18). 3인칭 아바타용 베기 모션.
--
-- 1인칭 뷰모델의 콤보 인덱스에 맞춰 나간다.
-- (COMBO = { "Attack1", "Attack2", "Attack3" } 의 인덱스와 같다)
--
-- 트리거는 WeaponAttackEvent 다. 클라이언트가 startAttack 에서 인덱스를 서버로 쏘고,
-- MovementSpeedServer 가 그걸 전체에 되뿌린다. 여기서는 서버 수신만 붙여 아바타에 얹는다.
-- 서버에서 재생하므로 모든 유저가 같이 본다.
--
-- ★ delay = 신호를 받고 이만큼 기다렸다 재생한다 (초).
--   1인칭 뷰모델은 클립 시작 후 1초쯤에 실제로 벤다. 3인칭을 즉시 틀면 혼자 먼저
--   휘둘러 속도가 안 맞는다. 1·2타는 0.7 로 사용자가 확정했다 (2026-08-18).
--   어긋나면 이 숫자만 조절하라. 3인칭이 먼저 나가면 올리고, 늦으면 내린다.
--
--   3타는 같은 시점에 X자 참격이 나간다 (ViewmodelController 의 XBLADE_AT = 1.0).
--   아바타가 베는 순간과 참격이 날아가는 순간이 맞아야 하므로 1·2타와 값이 다를 수 있다.
--
-- 여기 없는 인덱스는 3인칭 모션이 안 나온다. 같은 에셋을 쓰는 타끼리는 트랙을 공유한다.
local ATTACK_BY_INDEX = {
	[1] = { anim = "ovdrassetid://42081100", delay = 0.7 },   -- wakizashiattack
	[2] = { anim = "ovdrassetid://42081100", delay = 0.7 },   -- 1타와 같은 클립
	[3] = { anim = "ovdrassetid://42087100", delay = 0.7 },   -- wakizashiattack1 (X자 참격)
}

local ATTACK_FADE = 0.1

-- ===== 비뢰신 (쿠나이 투척 + 순간이동) =====
-- 42088100 (2026-08-18). 1인칭 던지는 모션은 2.1초다.
--
-- 트리거는 RyunochiEvent 의 "raijin_hand" 신호다. 그게 스킬이 시작되는 정확한 순간에
-- 딱 한 번 온다 (ViewmodelController 가 isFlyingRaijinCommitted() 가 켜질 때 쏜다).
-- 같은 신호로 3인칭 왼손 칼도 숨겨진다.
local RAIJIN_ANIM = "ovdrassetid://42088100"
local RAIJIN_DELAY = 0.7      -- 신호 후 이만큼 기다렸다 재생 (공격과 같은 값)
local RAIJIN_SPEED = 0.5      -- 재생 속도 배율. 0.5 = 절반 속도
local RAIJIN_HOLD_AT = 0.63   -- 팔을 뻗은 자세. 여기서 멈춰 순간이동을 기다린다
                              -- ★ 클립 길이가 0.70 이라 1.0 으로 두면 매번 0.63 으로 당겨지며 로그가 떴다
--
-- 홀드 동작:
--   0 -> RAIJIN_HOLD_AT 까지 재생하고 그 자세로 정지한다.
--   순간이동하거나 시간이 초과돼 스킬이 끝나면(raijin_hand hide=false) 남은 구간을 마저 재생한다.
--   ★ HOLD_AT 은 클립 기준 시간이라 속도와 무관하다.
--     0.5배속이면 0.70 지점에 닿기까지 실제로는 1.4초가 걸린다.

-- 이동 트랙(Action)보다 높아야 덮어쓴다. 그래서 한 단계 위인 Action2 를 쓴다.
local ATTACK_PRIORITY = "Action2"

-- true 면 상체에만 적용해서 달리면서 벨 수 있다.
-- 다만 클립에 다리 동작이 들어 있으면 어색해지므로 기본은 전신이다.
local ATTACK_UPPER_BODY = false

-- 정지/이동 전환을 콘솔에 찍는다. 전환이 이상할 때 켜서 본다.
-- (걷기 붙이는 중이라 다시 켰다. 확인 끝나면 false 로)
local DEBUG_STATE = false

-- 구조 출력. 이미 한 번 확인해서 꺼뒀다. 캐릭터 구조가 의심스러우면 다시 켤 것.
local DUMP = false

local dumped = false

local function dumpTree(root, label, maxDepth)
	print("[AvatarAnim] ===== " .. label .. " =====")
	local count = 0
	local function walk(inst, depth)
		if depth > maxDepth then
			return
		end
		for _, c in ipairs(inst:GetChildren()) do
			count = count + 1
			if count > 300 then
				return
			end
			local cls = "?"
			pcall(function()
				cls = c.ClassName
			end)
			local extra = ""
			local ok, id = pcall(function()
				return c.AnimationId
			end)
			if ok and id then
				extra = "  = " .. tostring(id)
			end
			print(string.rep("  ", depth) .. c.Name .. "  <" .. cls .. ">" .. extra)
			walk(c, depth + 1)
		end
	end
	walk(root, 0)
	if count > 300 then
		print("[AvatarAnim] ... 300개가 넘어 생략됨")
	end
	print("[AvatarAnim] ===== " .. label .. " 끝 =====")
end

-- 트랙 하나를 준비한다.
--
-- ★ 2026-08-17 : 여기서 한 번 사고가 났다.
--   ReplicatedStorage 에 배치해둔 Animation 을 Clone() 해서 쓰도록 바꿨더니
--   idle 까지 통째로 안 나왔다. Clone 이 AnimationId 를 안 물고 오는 것으로 보인다.
--   Instance.new + AnimationId 는 검증된 경로다. 이쪽을 쓴다.
--   (ReplicatedStorage 의 IdleAnimation/WalkAnimation 인스턴스는 지우지 마라 —
--    에셋을 월드에 실제로 배치해두는 용도다. 참조만 안 할 뿐이다.)
local function makeTrack(animator, poseName, assetId, priorityName)
	local anim = animator:FindFirstChild(poseName)
	if not anim then
		anim = Instance.new("Animation")
		anim.Name = poseName
		anim.AnimationId = assetId
		anim.Parent = animator
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		print("[AvatarAnim] " .. poseName .. " 로드 실패 : " .. tostring(track))
		return nil
	end

	track.Looped = true

	-- 우선순위 지정이 실제로 먹었는지 확인한다.
	-- pcall 로 조용히 삼키면 "없는 enum 값" 을 못 알아채고 계속 헛짚게 된다.
	local prioOk = pcall(function()
		track.Priority = Enum.AnimationPriority[priorityName]
	end)
	local prioNow = "?"
	pcall(function()
		prioNow = tostring(track.Priority)
	end)

	-- 정상일 땐 조용히 넘어간다. 이상할 때만 찍는다.
	--   Length 0 = 클립이 비어 있다 (에셋ID 의심)
	--   지정실패  = 그 이름의 AnimationPriority enum 이 없다
	local len = 0
	pcall(function()
		len = track.Length or 0
	end)
	if (not prioOk) or len <= 0 then
		print("[AvatarAnim] " .. poseName .. " 이상 : id=" .. tostring(anim.AnimationId)
			.. "  Length=" .. tostring(len)
			.. "  Priority=" .. priorityName .. (prioOk and "" or "(지정실패!)")
			.. " -> " .. prioNow)
	elseif DEBUG_STATE then
		print("[AvatarAnim] " .. poseName .. " : Length=" .. tostring(len)
			.. "  Priority=" .. prioNow)
	end
	return track
end

-- ===== 준비동작이 붙은 이동 클립 =====
-- 걷기/달리기 둘 다 앞부분이 준비동작이라 그냥 루프하면 매 바퀴 그게 다시 나온다.
-- 처음 한 번만 0 부터 재생하고, 되감길 때마다 loopStart 로 밀어준다.
local function makeMoveClip(animator, poseName, assetId, loopStart, fade)
	local track = makeTrack(animator, poseName, assetId, "Action")
	if not track then
		return nil
	end
	local clip = { track = track, loopStart = loopStart, fade = fade, fresh = false, lastTP = nil }
	pcall(function()
		track.DidLoop:Connect(function()
			track.TimePosition = loopStart
		end)
	end)
	return clip
end

-- 매 프레임. DidLoop 이 없거나 안 먹는 환경 대비 : 재생 위치가 되감기면 직접 건너뛴다.
-- 준비동작 재생 중(fresh)에는 건드리지 않는다. 안 그러면 첫 바퀴가 잘린다.
local function clipGuard(clip)
	if not clip then
		return
	end
	local tp = nil
	pcall(function()
		tp = clip.track.TimePosition
	end)
	if not tp then
		return
	end
	if clip.fresh then
		if tp >= clip.loopStart then
			clip.fresh = false
		end
	elseif clip.lastTP and tp < clip.lastTP and tp < clip.loopStart then
		pcall(function()
			clip.track.TimePosition = clip.loopStart
		end)
		tp = clip.loopStart
	end
	clip.lastTP = tp
end

-- fromStill 이면 준비동작(0)부터, 아니면 걷기<->달리기 전환이므로 사이클 중간부터 잇는다.
-- 달리다가 걷기로 바뀔 때 정지 준비동작을 다시 트는 건 어색하다.
local function clipPlay(clip, fromStill)
	if not clip then
		return
	end
	local at = fromStill and 0 or clip.loopStart
	pcall(function()
		clip.track:Play(clip.fade)
		clip.track.TimePosition = at
	end)
	clip.fresh = fromStill
	clip.lastTP = nil
end

local function clipStop(clip)
	if not clip then
		return
	end
	pcall(function()
		clip.track:Stop(clip.fade)
	end)
end

-- 캐릭터별 트랙 묶음. WeaponAttackEvent 핸들러가 여기서 꺼내 쓴다.
local charAnim = {}

-- 지금 켜져 있는 이동/대기 트랙을 끈다.
local function stopLocomotion(rec)
	if rec.state == "still" then
		pcall(function()
			rec.idle:Stop(IDLE_FADE)
		end)
	elseif rec.state == "walk" then
		clipStop(rec.walk)
	elseif rec.state == "run" then
		clipStop(rec.run)
	end
end

-- 한 번 재생하고 끝나는 모션(공격 / 비뢰신)을 얹는다.
--
--   delay 초 기다렸다가 -> 이동 트랙을 끄고 -> 재생 -> 클립 길이만큼 이동 전환을 멈춰 세운다.
--   끝나면 state 를 none 으로 돌려 다음 틱에 속도를 보고 이동 클립을 새로 잡게 한다.
--
-- 딜레이 동안에는 이동 트랙을 그대로 둔다. 여기서 미리 멈추면 기다리는 내내
-- 아바타가 굳어 있다가 뒤늦게 움직이는 그림이 된다.
--
-- 순번(seq)은 신호를 받는 즉시 올린다. 그래야 대기 중이던 예약과 종료 대기가
-- 한꺼번에 무효가 되어, 먼저 걸린 타이머가 뒤 동작을 중간에 끊지 않는다.
local function playOneShot(rec, track, delay, label)
	if not (rec and track) then
		return
	end
	rec.seq = rec.seq + 1
	local seq = rec.seq

	task.delay(delay, function()
		if rec.seq ~= seq then
			return
		end

		stopLocomotion(rec)

		-- 직전 동작이 다른 클립이었으면 그것부터 끈다 (공격과 비뢰신은 에셋이 다르다)
		if rec.playingAttack and rec.playingAttack ~= track then
			pcall(function()
				rec.playingAttack:Stop(0)
			end)
		end
		rec.playingAttack = track
		rec.attacking = true

		pcall(function()
			track:Stop(0)
			track:Play(ATTACK_FADE)
		end)

		local dur = 0.6
		pcall(function()
			if track.Length and track.Length > 0 then
				dur = track.Length
			end
		end)

		task.delay(dur, function()
			if rec.seq == seq then
				rec.attacking = false
				rec.playingAttack = nil
				rec.state = "none"   -- 다음 틱에 이동 상태를 새로 잡게 한다
			end
		end)

		if DEBUG_STATE then
			print(string.format("[AvatarAnim] %s 재생 (%.2f초, 딜레이 %.2f)", label, dur, delay))
		end
	end)
end

-- 이동/1회성 상태를 풀고 다음 틱에 이동 클립을 새로 잡게 한다.
local function releaseOneShot(rec, seq)
	if rec.seq ~= seq then
		return
	end
	rec.attacking = false
	rec.playingAttack = nil
	rec.raijinHolding = false
	rec.state = "none"
end

-- 비뢰신은 "던지는 자세에서 멈춰 순간이동을 기다린다" 는 동작이 있어서 playOneShot 을 못 쓴다.
--   재생 -> RAIJIN_HOLD_AT 에서 정지 -> (스킬 종료 신호) -> 남은 구간 재생 -> 이동 복귀
local function playRaijin(rec)
	if not (rec and rec.raijin) then
		return
	end
	rec.seq = rec.seq + 1
	local seq = rec.seq
	rec.raijinSeq = seq
	rec.raijinHolding = false

	task.delay(RAIJIN_DELAY, function()
		if rec.seq ~= seq then
			return
		end

		stopLocomotion(rec)
		if rec.playingAttack and rec.playingAttack ~= rec.raijin then
			pcall(function()
				rec.playingAttack:Stop(0)
			end)
		end
		rec.playingAttack = rec.raijin
		rec.attacking = true

		-- ★ 대기 구간을 버티려면 Looped = true 여야 한다.
		--   false 로 두면 클립이 끝까지 간 순간 트랙이 죽고 기본 모션으로 돌아가버린다.
		--   아래에서 매 프레임 위치를 못 박으므로 실제로 루프가 돌지는 않는다.
		pcall(function()
			rec.raijin.Looped = true
			rec.raijin:Stop(0)
			rec.raijin:Play(ATTACK_FADE)
			rec.raijin.TimePosition = 0
			rec.raijin:AdjustSpeed(RAIJIN_SPEED)
		end)

		-- 멈출 지점이 클립 길이를 넘으면 영영 도달하지 못한다. 그때는 끝자락으로 당긴다.
		local len = 0
		pcall(function()
			len = rec.raijin.Length or 0
		end)
		local holdAt = RAIJIN_HOLD_AT
		if len > 0 and holdAt >= len then
			holdAt = len * 0.9
			print(string.format("[AvatarAnim] RAIJIN_HOLD_AT(%.2f) 이 클립 길이(%.2f) 보다 뒤다 - %.2f 로 당김",
				RAIJIN_HOLD_AT, len, holdAt))
		end
		rec.raijinHoldAt = holdAt

		if DEBUG_STATE then
			print(string.format("[AvatarAnim] 비뢰신 재생 (Length %.2f, 속도 %.2f배, 딜레이 %.2f, %.2f 에서 정지 예정)",
				len, RAIJIN_SPEED, RAIJIN_DELAY, holdAt))
		end

		task.spawn(function()
			-- 1) 던지는 자세까지 재생되기를 기다린다
			while rec.seq == seq do
				RunService.Heartbeat:Wait()
				local tp = nil
				pcall(function()
					tp = rec.raijin.TimePosition
				end)
				if tp and tp >= holdAt then
					break
				end
			end
			if rec.seq ~= seq then
				return
			end

			rec.raijinHolding = true
			if DEBUG_STATE then
				print(string.format("[AvatarAnim] 비뢰신 정지 (%.2f)", holdAt))
			end

			-- 2) 풀릴 때까지 매 프레임 그 자세에 못 박는다.
			--    AdjustSpeed(0) 만으로는 자세가 유지되지 않아서 위치를 직접 고정한다.
			while rec.seq == seq and rec.raijinHolding do
				pcall(function()
					rec.raijin:AdjustSpeed(0)
					rec.raijin.TimePosition = holdAt
				end)
				RunService.Heartbeat:Wait()
			end
		end)
	end)
end

-- 스킬이 끝났다 (순간이동했거나 시간초과). 멈춰뒀던 나머지를 마저 재생한다.
local function endRaijin(rec)
	if not (rec and rec.raijin) then
		return
	end
	local seq = rec.raijinSeq
	if not seq or rec.seq ~= seq then
		return          -- 그 사이 다른 동작이 끼어들었으면 건드리지 않는다
	end

	local len = 0
	pcall(function()
		len = rec.raijin.Length or 0
	end)
	local holdAt = rec.raijinHoldAt or RAIJIN_HOLD_AT

	-- 고정 루프를 풀고 나머지를 마저 재생한다.
	-- Looped 를 다시 false 로 돌려야 끝에서 처음으로 되감기지 않는다.
	rec.raijinHolding = false
	pcall(function()
		rec.raijin.Looped = false
		rec.raijin:AdjustSpeed(RAIJIN_SPEED)
	end)

	-- 남은 구간을 재생하는 데 걸리는 실제 시간
	local remain = 0.3
	if len > holdAt and RAIJIN_SPEED > 0 then
		remain = (len - holdAt) / RAIJIN_SPEED
	end

	if DEBUG_STATE then
		print(string.format("[AvatarAnim] 비뢰신 종료 - 남은 %.2f초 재생", remain))
	end

	task.delay(remain, function()
		releaseOneShot(rec, seq)
	end)
end

-- 검 자세를 얹고, 꺼지면 다시 켠다
local function applySwordPose(player, character)
	if not ENABLE_SWORD_POSE then
		print("[AvatarAnim] SwordIdle 꺼져 있음 - 기본 이동 애니메이션을 그대로 쓴다")
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		print("[AvatarAnim] Humanoid 를 못 찾았다")
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10)
	if not animator then
		print("[AvatarAnim] Animator 를 못 찾았다")
		return
	end

	-- AnimationPriority 는 숫자가 작을수록 우선한다 :
	--   Action4(0) > Action3(1) > Action2(2) > Action(3) > Movement(4) > Idle(5) > Core(6) > None(7)
	-- 자세한 실측 결과는 위 IDLE_PRIORITY 주석 참고. 등급 싸움이 아니라 직접 켜고 끈다.
	local track = makeTrack(animator, "SwordIdlePose", SWORD_IDLE, IDLE_PRIORITY)
	if not track then
		return
	end
	if UPPER_BODY_ONLY then
		pcall(function()
			track.UpperBodyAnimation = true
		end)
	end
	track:Play(IDLE_FADE)

	if DEBUG_STATE then
		print("[AvatarAnim] SwordIdle 재생 : Length=" .. tostring(track.Length)
			.. "  Priority=" .. IDLE_PRIORITY
			.. "  UpperBody=" .. tostring(track.UpperBodyAnimation)
			.. "  IsPlaying=" .. tostring(track.IsPlaying))
	end

	-- ===== 걷기 / 달리기 트랙 =====
	local walkClip, runClip = nil, nil
	if ENABLE_WALK then
		walkClip = makeMoveClip(animator, "WalkPose", WALK_ANIM, WALK_LOOP_START, WALK_FADE)
		runClip = makeMoveClip(animator, "RunPose", RUN_ANIM, RUN_LOOP_START, RUN_FADE)
	end

	-- ===== 공격 트랙 (타별) =====
	-- 한 번 휘두르고 끝나야 하므로 루프를 끈다.
	-- 1타와 2타처럼 같은 에셋을 쓰는 타끼리는 트랙을 하나만 만들어 공유한다.
	local attackByIndex = {}
	local trackByAsset = {}
	for idx, cfg in pairs(ATTACK_BY_INDEX) do
		local tr = trackByAsset[cfg.anim]
		if not tr then
			tr = makeTrack(animator, "AttackPose" .. tostring(idx), cfg.anim, ATTACK_PRIORITY)
			if tr then
				tr.Looped = false
				if ATTACK_UPPER_BODY then
					pcall(function()
						tr.UpperBodyAnimation = true
					end)
				end
				trackByAsset[cfg.anim] = tr
			end
		end
		attackByIndex[idx] = { track = tr, delay = cfg.delay }
	end

	-- ===== 비뢰신 트랙 =====
	local raijinTrack = makeTrack(animator, "RaijinPose", RAIJIN_ANIM, ATTACK_PRIORITY)
	if raijinTrack then
		raijinTrack.Looped = false
		if ATTACK_UPPER_BODY then
			pcall(function()
				raijinTrack.UpperBodyAnimation = true
			end)
		end
	end

	-- 이 캐릭터의 트랙 묶음. 아래 이동 루프와 공격 이벤트 핸들러가 같이 본다.
	--
	-- ★ 공격을 우선순위로만 덮으려 했더니 안 나왔다. 이 프로젝트에서 우선순위로
	--   덮으려는 시도는 계속 실패했다 (기본 idle 건, IsPlaying 건).
	--   그래서 공격 중에는 이동 트랙을 직접 꺼서 확실히 자리를 비운다.
	-- ★ 이전 묶음이 남아 있으면 죽인다.
	--   setup 이 CharacterAdded 와 초기 스캔 양쪽에서 불려 루프가 두 벌 돌던 적이 있다.
	--   로그에 "walk -> run" 다음 줄이 "still -> walk" 로 나오는 게 그 증상이었다.
	--   (각 루프가 자기 rec 을 들고 같은 아바타를 서로 다른 상태로 몰았다)
	local old = charAnim[player]
	if old then
		old.dead = true
	end

	local rec = {
		character = character,
		animator = animator,        -- 사망 클립을 나중에 얹으려면 필요하다
		idle = track,
		walk = walkClip,
		run = runClip,
		attackByIndex = attackByIndex,
		raijin = raijinTrack,
		raijinSeq = nil,         -- 지금 도는 비뢰신의 순번
		raijinHolding = false,   -- 던지는 자세에서 멈춰 대기 중인가
		raijinHoldAt = nil,      -- 실제로 멈춘 지점 (클립이 짧으면 당겨진다)
		playingAttack = nil,     -- 지금 재생 중인 1회성 트랙 (공격/비뢰신)
		state = "still",
		attacking = false,
		dead = false,
		seq = 0,
	}
	charAnim[player] = rec

	-- ===== idle 상태 전환 =====
	-- 멈추면 켜고, 움직이면 끈다. 우선순위에 맡기지 않고 직접 제어한다.
	--   Priority 만으로 풀려고 했더니 (Idle 등급) 기본 idle 에 밀려 우리 자세가 안 보였다.
	--   Action 등급으로 확실히 이기게 해두고, 이동할 때 우리가 Stop 해서 길을 비켜준다.
	--
	-- Humanoid.MoveDirection 은 OVERDARE 에 없다. RootPart 위치 변화량을 직접 잰다.
	-- 프레임 단위로 재면 값이 깜빡여서 SAMPLE 초 구간으로 끊어 평균 속도를 본다.
	-- (MovementSpeedServer 가 이미 같은 방식을 쓰고 있다)
	task.spawn(function()
		local SAMPLE = 0.25
		local STILL_SPEED = 40        -- cm/s. 이보다 느리면 멈춘 것으로 본다
		local t = 0
		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
		local lastPos = root and root.Position

		while character.Parent and not rec.dead do
			t = t + RunService.Heartbeat:Wait()

			clipGuard(walkClip)
			clipGuard(runClip)

			-- 공격 중에는 이동 트랙을 아예 건드리지 않는다.
			-- 여기서 idle 을 다시 켜면 공격 모션과 겹쳐 서로 뭉갠다.
			if rec.attacking then
				t = 0
				if root then
					lastPos = root.Position
				end
			elseif t >= SAMPLE then
				root = root or character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
				local speed = 0
				if root then
					local p = root.Position
					if lastPos then
						speed = (p - lastPos).Magnitude / t
					end
					lastPos = p
				end
				t = 0

				-- 속도로 상태를 정한다
				local want = "run"
				if speed < STILL_SPEED then
					want = "still"
				elseif speed < RUN_SPEED then
					want = "walk"
				end
				if not walkClip then
					-- 이동 클립이 없으면 엔진 기본 모션에 맡긴다
					want = (want == "still") and "still" or "walk"
				end

				if want ~= rec.state then
					-- 이전 상태를 끄고 새 상태를 켠다.
					-- IsPlaying 은 "화면에 보이는가" 가 아니라 "트랙이 도는가" 라서
					-- 그것만 보고 판단하면 안 된다. 속도 판정을 기준으로 삼는다.
					stopLocomotion(rec)

					local fromStill = (rec.state == "still")
					if want == "still" then
						pcall(function()
							track:Play(IDLE_FADE)
						end)
					elseif want == "walk" then
						clipPlay(walkClip, fromStill)
					elseif want == "run" then
						clipPlay(runClip, fromStill)
					end

					if DEBUG_STATE then
						print(string.format("[AvatarAnim] %s -> %s  (%.0f cm/s)", tostring(rec.state), want, speed))
					end
					rec.state = want
				end
			end
		end
	end)
end

-- setup 이 CharacterAdded 와 초기 스캔 양쪽에서 불려 루프가 두 벌 도는 일이 있었다.
-- rec 을 만들기 전에 WaitForChild 로 양보하는 구간이 있어서 dead 플래그만으로는 경합이 남는다.
-- 그래서 번호를 spawn 전에 동기적으로 매기고, 최신 번호가 아니면 아예 포기시킨다.
local setupSeq = {}

local function setup(player, character)
	local n = (setupSeq[player] or 0) + 1
	setupSeq[player] = n
	task.spawn(function()
		character:WaitForChild("Humanoid", 10)
		if setupSeq[player] ~= n then
			return
		end

		if DUMP and not dumped then
			dumped = true
			dumpTree(character, "캐릭터 " .. character.Name, 2)
			local skel = character:FindFirstChild("Skeleton")
			if skel then
				dumpTree(skel, "Skeleton (본 계층)", 8)
			else
				print("[AvatarAnim] Skeleton 이 캐릭터 아래에 없다 - 본 접근 불가")
			end
		end

		applySwordPose(player, character)
	end)
end

local function hook(player)
	player.CharacterAdded:Connect(function(character)
		charAnim[player] = nil     -- 이전 캐릭터의 트랙은 버린다
		setup(player, character)
	end)
	if player.Character then
		setup(player, player.Character)
	end
end

Players.PlayerAdded:Connect(hook)
for _, player in ipairs(Players:GetPlayers()) do
	hook(player)
end

Players.PlayerRemoving:Connect(function(player)
	charAnim[player] = nil
end)

-- ===== 공격 애니메이션 트리거 =====
-- 뷰모델이 콤보를 시작할 때마다 인덱스를 서버로 쏜다 (ViewmodelController.startAttack).
-- MovementSpeedServer 도 같은 이벤트를 듣고 전체에 되뿌린다. 연결이 둘이어도 문제없다.
local attackEvent = ReplicatedStorage:WaitForChild("WeaponAttackEvent", 5)
if attackEvent then
	attackEvent.OnServerEvent:Connect(function(player, attackIndex)
		-- 무조건 먼저 찍는다. 이게 안 찍히면 문제는 서버가 아니라 클라이언트 신호 쪽이다.
		if DEBUG_STATE then
			print("[AvatarAnim] WeaponAttackEvent 수신 : idx=" .. tostring(attackIndex)
				.. " (" .. type(attackIndex) .. ")")
		end
		local rec = charAnim[player]
		if not rec then
			print("[AvatarAnim] 공격 신호는 왔는데 이 플레이어의 트랙이 없다")
			return
		end
		local slot = (type(attackIndex) == "number") and rec.attackByIndex[attackIndex] or nil
		if not slot then
			if DEBUG_STATE then
				print("[AvatarAnim] idx 가 대상이 아니라 건너뜀 : " .. tostring(attackIndex))
			end
			return
		end
		if not slot.track then
			print("[AvatarAnim] " .. tostring(attackIndex) .. "타 공격 트랙이 없다 - 에셋 로드 로그를 확인하라")
			return
		end

		playOneShot(rec, slot.track, slot.delay, "공격 " .. tostring(attackIndex) .. "타")
	end)
else
	print("[AvatarAnim] WeaponAttackEvent 를 못 찾았다 - 3인칭 공격 모션이 안 나온다")
end

-- ===== 비뢰신 트리거 =====
-- RyunochiEvent 는 RyunochiServer 가 런타임에 만든다. 그래서 기다렸다 잡는다.
-- "raijin_hand" 는 스킬이 시작되는 순간 딱 한 번 온다 (hide=true).
-- 같은 신호로 3인칭 왼손 칼도 숨겨지므로 모션과 칼 숨김이 자동으로 같은 시점이 된다.
local ryuEvent = ReplicatedStorage:WaitForChild("RyunochiEvent", 10)
if ryuEvent then
	ryuEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "raijin_hand" then
			return
		end
		local rec = charAnim[player]
		if not rec then
			return
		end
		if not rec.raijin then
			print("[AvatarAnim] 비뢰신 트랙이 없다 - 에셋 로드 로그를 확인하라")
			return
		end
		if payload.hide then
			playRaijin(rec)     -- 스킬 시작
		else
			endRaijin(rec)      -- 순간이동했거나 시간초과 -> 멈춰둔 나머지를 마저 재생
		end
	end)
else
	print("[AvatarAnim] RyunochiEvent 를 못 찾았다 - 3인칭 비뢰신 모션이 안 나온다")
end


-- ===== 사망 연출 =====
--
-- ★ 물리 래그돌(관절이 풀려 흐물흐물 무너지는 것)은 이 엔진에서 못 만든다.
--   ODA 아바타는 스킨드 메시라 몸통이 파츠로 쪼개져 있지 않다. 끊을 관절이 애초에 없고,
--   PlatformStand / ChangeState / Humanoid.Died 같은 것도 문서에 없다.
--
--   그래서 두 갈래로 간다:
--     1) DEATH.ANIM  스튜디오 애니메이션 툴로 만든 "쓰러지는" 클립. 이게 제대로 된 답이다.
--                    ID 만 아래에 꽂으면 붙고, 마지막 자세에서 멈춰 시체로 남는다.
--                    ★ FBX 로 만든 건 안 붙는다 (임포트가 자기 스켈레톤을 새로 만든다).
--     2) 클립이 없으면 RootPart 를 앞으로 눕혀 통나무처럼 쓰러뜨린다.
--        엔진 캐릭터 컨트롤러가 자세를 되돌릴 수 있어서, 첫 사망 때 결과를 로그로 찍는다.
--          "[AvatarAnim] 눕히기 : 먹힘"        -> 2번으로 버틸 수 있다
--          "[AvatarAnim] 눕히기 : 엔진이 되돌림" -> 1번(사망 클립) 말고는 답이 없다
--
-- ★ 지역변수를 늘리지 않으려고 설정을 테이블 하나에 담았다.

local DEATH = {
	ANIM = nil,        -- 예) "ovdrassetid://42090100"  <- 사망 클립 만들면 여기 넣어라
	FADE = 0.12,       -- 사망 클립 페이드인 (초)
	FALL_TIME = 0.5,   -- (클립이 없을 때) 쓰러지는 데 걸리는 시간
	TILT = 86,         -- 눕는 각도 (도)
	DROP = 70,         -- 쓰러지며 내려앉는 높이 (cm)
	probed = false,    -- 눕히기가 먹히는지 첫 사망 때 한 번만 찍는다

	-- ★ 지워진 인스턴스의 .Parent 를 읽으면 "object is already delete" 로 죽는다.
	--   리스폰하면 옛 캐릭터가 통째로 지워지므로 아래 루프들은 반드시 이걸로 확인한다.
	--   (실측 2026-08-19 : 그냥 character.Parent 로 쓰다가 리스폰마다 에러가 찍혔다)
	alive = function(inst)
		local ok, parent = pcall(function()
			return inst.Parent
		end)
		return ok and parent ~= nil
	end,
}

-- 죽는 순간 CombatServer 가 부른다.
-- 리스폰하면 캐릭터가 통째로 새로 생기므로 여기서 되돌리는 처리는 하지 않는다.
_G.AvatarAnim = {
	playDeath = function(player)
		local character = player and player.Character
		if not character then
			return
		end

		local rec = charAnim[player]
		if rec then
			-- 예약돼 있던 공격/비뢰신 타이머를 전부 무효로 만든다.
			-- seq 를 올리는 것만으로 대기 중인 task.delay 들이 스스로 포기한다.
			rec.seq = rec.seq + 1
			rec.dead = true            -- 이동 상태 루프가 여기서 멈춘다
			rec.raijinHolding = false
			rec.attacking = false
			stopLocomotion(rec)
			if rec.playingAttack then
				pcall(function()
					rec.playingAttack:Stop(0)
				end)
				rec.playingAttack = nil
			end
		end

		-- 1) 사망 클립
		local track = nil
		if DEATH.ANIM and rec and rec.animator then
			track = makeTrack(rec.animator, "DeathPose", DEATH.ANIM, "Action")
			if not track then
				print("[AvatarAnim] 사망 클립 로드 실패 - 눕히기로 넘어간다")
			end
		end

		if track then
			-- ★ Looped = false 로 두면 클립이 끝나는 순간 트랙이 죽고 기본 서 있는 자세로
			--   돌아간다. 비뢰신 홀드와 같은 이유로 루프를 켜고 위치를 직접 못 박는다.
			pcall(function()
				track.Looped = true
				track:Play(DEATH.FADE)
				track.TimePosition = 0
			end)
			task.spawn(function()
				local len = 0
				pcall(function()
					len = track.Length or 0
				end)
				local holdAt = (len > 0) and (len - 0.03) or 0.8
				-- 마지막 자세까지 재생되기를 기다린다
				while DEATH.alive(character) do
					local tp = 0
					pcall(function()
						tp = track.TimePosition or 0
					end)
					if tp >= holdAt then
						break
					end
					RunService.Heartbeat:Wait()
				end
				-- 리스폰까지 그 자세에 못 박는다
				while DEATH.alive(character) do
					pcall(function()
						track:AdjustSpeed(0)
						track.TimePosition = holdAt
					end)
					RunService.Heartbeat:Wait()
				end
			end)
			return
		end

		-- 2) 클립이 없다 - 눕혀본다
		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
		if not root then
			return
		end
		local base = root.CFrame

		task.spawn(function()
			local t = 0
			while DEATH.alive(character) and t < DEATH.FALL_TIME do
				t = t + RunService.Heartbeat:Wait()
				local k = math.min(1, t / DEATH.FALL_TIME)
				-- 뒤로 갈수록 빨라진다. 선형이면 "천천히 눕는" 부자연스러운 그림이 된다.
				local e = k * k
				pcall(function()
					root.CFrame = base
						* CFrame.new(0, -DEATH.DROP * e, 0)
						* CFrame.Angles(-math.rad(DEATH.TILT) * e, 0, 0)
				end)
			end

			-- ★ 실측. 엔진이 자세를 되돌렸으면 몸의 위쪽 축이 여전히 하늘을 향한다.
			if not DEATH.probed then
				DEATH.probed = true
				local upY = nil
				pcall(function()
					upY = root.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0)).Y
				end)
				if upY == nil then
					pcall(function()
						upY = root.CFrame.UpVector.Y
					end)
				end
				if upY == nil then
					print("[AvatarAnim] 눕히기 : 결과를 못 읽음 (CFrame 축 접근 실패)")
				elseif upY > 0.8 then
					print(string.format("[AvatarAnim] 눕히기 : 엔진이 되돌림 (up %.2f) - 사망 클립을 만들어야 한다", upY))
				else
					print(string.format("[AvatarAnim] 눕히기 : 먹힘 (up %.2f)", upY))
				end
			end

			-- 쓰러진 자세를 리스폰까지 유지한다. 안 잡아두면 컨트롤러가 슬금슬금 세운다.
			local fallen = nil
			pcall(function()
				fallen = root.CFrame
			end)
			while DEATH.alive(character) and fallen do
				pcall(function()
					root.CFrame = fallen
				end)
				RunService.Heartbeat:Wait()
			end
		end)
	end,
}

print("[AvatarAnim] ready")
