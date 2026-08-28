-- 전투 판정 (서버 권한)
--
-- 게임의 토대다. 점령/점수/UI 가 전부 여기 얹힌다.
--   한 대 = 즉사.  체력 개념이 없다.
--   오토디펜스 2칸이 먼저 소모되고, 다 떨어진 뒤 맞으면 죽는다.
--   궁극기는 방어·패링·오토디펜스를 전부 무시한다.
--
-- ★ 판정은 반드시 서버가 한다. 클라이언트가 "죽었다" 고 말하게 두면 안 된다.
--   클라이언트는 "때렸다" 는 신호만 보내고, 맞았는지·죽는지는 서버가 정한다.
--
-- 팀은 TeamServer 가 관리한다 (_G.TeamServer). Player.TeamColor 는 클라이언트로
-- 복제되지 않아서 서버 판정에만 쓴다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== 규칙 숫자 =====
local RESPAWN_TIME = 5           -- 죽고 부활까지 (초)
local AUTO_DEFENCE_MAX = 2       -- 오토디펜스 칸 수
local AUTO_DEFENCE_REGEN = 10    -- 까인 시점부터 1칸 차는 데 걸리는 시간 (초)

-- 스폰 무적 : 안 움직이면 STILL 초, 움직이기 시작하면 그 순간부터 MOVED 초
--   7초 가만히 있다가 움직여도 거기서 3초가 더 붙는다 (기획서)
local SPAWN_INVULN_STILL = 8
local SPAWN_INVULN_MOVED = 3
local MOVE_THRESHOLD = 60        -- cm/s. 이보다 빠르면 "움직였다"

-- ★ 근접 판정 검증값.
--   클라이언트가 보낸 대상을 그대로 믿지 않는다. 서버가 거리를 다시 잰다.
--   클라 기준 380 + 관용 반경인데, 이동 보정·지연을 감안해 넉넉히 잡는다.
--   너무 빡빡하면 정상 타격이 씹히고, 너무 넓으면 원거리에서 때릴 수 있다.
local MELEE_MAX_DIST = 700

-- 3타 참격 검증값. 참격 사거리 1500 에 이동·지연 보정을 얹었다.
local XBLADE_MAX_DIST = 1900

-- 궁극기 검증값. 내리찍기 광역 반경 1700 에 이동·지연 보정을 얹었다.
local ULT_MAX_DIST = 2200
local ULT_HIT_WINDOW = 6      -- 궁극기를 쓴 뒤 이 시간 안의 보고만 받아준다 (초)

-- ===== 패링 =====
--
-- 기획서 : 모든 공격에는 시전 딜레이가 있고, 그 짧은 구간에 공격자의 눈에서 흰 별빛이 반짝인다.
--   그 타이밍에 맞춰 block 을 "새로 누르면" 패링이다.
--   미리 켜두고 있던 것은 그냥 방어다 (피해 무효지만 반격은 없다).
--   -> 그래서 판정 기준이 "지금 방어 중인가" 가 아니라 "언제 눌렀는가" 다.
--
-- 시간의 기준점은 공격자가 WeaponAttackEvent 를 쏜 순간(0초)이다.
-- 실제 타격 판정은 1.0초에 들어온다 (ViewmodelController 의 MELEE.AT).
-- ┌──────────────────────────────────────────────────────────────────┐
-- │ ★★ 패링 난이도는 여기 네 줄로만 조절한다. 다른 데 손댈 필요 없다.      │
-- │                                                                  │
-- │   0초        WINDOW_START      WINDOW_END        1.0초           │
-- │   공격시작 ───── 별빛 뜸 ───────── 별빛 꺼짐 ───── 타격 판정       │
-- │                 └──── 이 사이에 눌러야 패링 ────┘                 │
-- │                                                                  │
-- │   창을 좁히려면(어렵게)  : START 를 올리고 END 를 내린다           │
-- │   창을 넓히려면(쉽게)    : 반대로                                  │
-- │   너무 빨리/늦게 뜨면     : 둘을 같은 값만큼 밀어라                 │
-- │   GRACE 는 지연 보정이다. 창을 앞뒤로 이만큼씩 더 넓혀준다.          │
-- │     실제 판정 폭 = (END - START) + GRACE * 2                      │
-- │     지금은 0.20 + 0.16 = 0.36초                                   │
-- │                                                                  │
-- │   별빛이 떠 있는 시간도 (END - START) 라서 같이 짧아진다.           │
-- └──────────────────────────────────────────────────────────────────┘
local PARRY = {
	WINDOW_START = 0.55,   -- 별빛이 뜨는 시점 (초)
	WINDOW_END = 0.75,     -- 별빛이 꺼지는 시점
	GRACE = 0.08,          -- 지연 보정
	STUN = 2,            -- 패링당했을 때 굳는 시간
}

-- ===== 상태 =====
-- [player] = {
--   alive, autoDefence, adRegenAt, invulnUntil, moved, spawnAt, lastPos,
--   kills, deaths, ultCharge
-- }
local S = {}

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if not combatEvent then
	print("[Combat] CombatEvent 를 못 찾음 - 전투 판정이 동작하지 않는다")
end

local function team()
	return _G.TeamServer
end

local function fresh(player)
	return {
		alive = true,
		blocking = false,        -- 방어 버튼 상태. 클라이언트가 바뀔 때마다 보내준다
		autoDefence = AUTO_DEFENCE_MAX,
		adRegenAt = nil,
		spawnAt = os.clock(),
		moved = false,
		invulnUntil = os.clock() + SPAWN_INVULN_STILL,
		lastPos = nil,
		kills = (S[player] and S[player].kills) or 0,      -- 전적은 보존한다
		deaths = (S[player] and S[player].deaths) or 0,
		ultCharge = (S[player] and S[player].ultCharge) or 0,
		ultShown = -1,           -- 마지막으로 클라이언트에 보낸 정수 퍼센트. 바뀔 때만 보낸다
	}
end

local function push(player)
	local st = S[player]
	if not (combatEvent and st) then
		return
	end
	pcall(function()
		combatEvent:FireClient(player, {
			phase = "state",
			alive = st.alive,
			autoDefence = st.autoDefence,
			invuln = math.max(0, (st.invulnUntil or 0) - os.clock()),
			kills = st.kills,
			deaths = st.deaths,
			ult = st.ultCharge,
		})
	end)
end

-- ===== 외부에서 쓰는 것 =====
local M = {}

function M.isAlive(player)
	local st = S[player]
	return st ~= nil and st.alive
end

function M.isInvulnerable(player)
	local st = S[player]
	return st ~= nil and os.clock() < (st.invulnUntil or 0)
end

-- 궁극기 충전. TeamServer 의 상수를 쓴다.
function M.addUlt(player, seconds)
	local st = S[player]
	local T = team()
	if not (st and T) then
		return
	end
	-- ★ 죽어 있거나 로비에 있는 동안은 한 방울도 차면 안 된다.
	--   규칙 : 충전 -> 죽음(멈춤) -> 부활(죽기 전 값에서 이어서).
	--   자연 충전은 아래 틱에서 같은 조건으로 막고, 킬·점령 보상은 여기서 막는다.
	if not st.alive then
		return
	end
	if _G.LobbyWant and _G.LobbyWant[player] then
		return
	end
	st.ultCharge = math.min(1, st.ultCharge + seconds / T.ULT_FULL)
	st.ultShown = math.floor(st.ultCharge * 100)
	push(player)
end

-- ★ 개인 EXP·레벨업은 폐기했다 (2026-08-19 확정). M.addExp 는 없앴다.
--   킬 표시는 크로스헤어 밑 "kill <이름>" 하나뿐이고, 점수는 팀 점수만 센다.

function M.getStats(player)
	return S[player]
end

-- 스폰 직후 캐릭터를 옮겼을 때 부른다 (TeamServer 의 스폰 흩뿌리기).
-- ★ 안 부르면 우리가 옮긴 것을 "움직였다" 로 세서 스폰 무적이 8초에서 3초로 깎인다.
function M.resetSpawnTimer(player)
	local st = S[player]
	if not st then
		return
	end
	local ch = player.Character
	local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
	st.lastPos = root and root.Position or nil
	st.moved = false
	st.invulnUntil = os.clock() + SPAWN_INVULN_STILL
	push(player)
end

function M.isStunned(player)
	local st = S[player]
	return st ~= nil and st.stunUntil ~= nil and os.clock() < st.stunUntil
end

-- 기절. 그 자리에 굳는다.
-- ★ WalkSpeed 에 0 을 직접 넣어봐야 소용없다. MovementSpeedServer 가 매 프레임 다시 쓴다.
--   사망 처리와 같이 _G.MovementFreeze 플래그로 알린다.
function M.stun(player, dur)
	local st = S[player]
	if not st then
		return
	end
	st.stunUntil = os.clock() + dur
	_G.MovementFreeze = _G.MovementFreeze or {}
	_G.MovementFreeze[player] = true
	task.delay(dur, function()
		local cur = S[player]
		-- 그 사이 죽었으면 풀면 안 된다. 시체가 다시 걸어다닌다.
		if cur and cur.alive and cur.stunUntil and os.clock() >= cur.stunUntil then
			cur.stunUntil = nil
			if _G.MovementFreeze then
				_G.MovementFreeze[player] = nil
			end
		end
	end)
end

-- ★ 피격 처리. 모든 무기가 여기로 들어온다.
--   ignoreDefence = true 면 궁극기다. 방어·패링·오토디펜스를 전부 무시한다.
function M.applyHit(attacker, victim, ignoreDefence)
	if not (attacker and victim) then
		return "invalid"
	end
	if attacker == victim then
		return "self"
	end

	local st = S[victim]
	if not (st and st.alive) then
		return "already_dead"
	end

	-- 로비에 있는 사람은 전투와 무관하다. 때리는 쪽도 맞는 쪽도 제외한다.
	if _G.LobbyWant and (_G.LobbyWant[victim] or _G.LobbyWant[attacker]) then
		return "lobby"
	end

	-- 팀킬 금지
	local T = team()
	if T and T.sameTeam(attacker, victim) then
		return "friendly"
	end

	-- 스폰 무적
	if os.clock() < (st.invulnUntil or 0) then
		return "invuln"
	end

	-- ★ 패링. 방어보다 먼저 본다.
	--   "공격이 시작된 뒤 별빛 구간 안에 방어를 새로 눌렀는가" 로만 판정한다.
	--   미리 켜두고 있었다면 blockAt 이 창보다 훨씬 앞이라 여기서 안 걸리고 아래 방어로 간다.
	local pst = S[attacker]
	if not ignoreDefence and pst and pst.attackAt and st.blockAt then
		local dt = st.blockAt - pst.attackAt
		if dt >= (PARRY.WINDOW_START - PARRY.GRACE) and dt <= (PARRY.WINDOW_END + PARRY.GRACE) then
			-- 한 번 성공한 누름으로 계속 패링되면 안 된다. 양쪽 다 소모시킨다.
			st.blockAt = nil
			pst.attackAt = nil
			M.stun(attacker, PARRY.STUN)
			if combatEvent then
				pcall(function()
					combatEvent:FireClient(victim, { phase = "parry", ok = true })
					-- 패링당한 쪽 : 화면 테두리가 검붉게
					combatEvent:FireClient(attacker, { phase = "parried", dur = PARRY.STUN })
					-- 전원 : 머리 위 기절 별 링. 때린 쪽이 뭐가 일어났는지 알아야 한다
					combatEvent:FireAllClients({
						phase = "stunfx",
						who = attacker,
						dur = PARRY.STUN,
					})
				end)
			end
			return "parried"
		end
	end

	-- ★ 방어. 켜고 있으면 피해가 통째로 무효다. 무제한이고 오토디펜스를 깎지 않는다.
	--   (2026-08-19 : st.blocking 을 받아만 놓고 판정에서 아예 안 보고 있었다.
	--    주황 배리어는 떠 있는데 실제로는 그냥 맞고 죽던 상태였다.)
	if not ignoreDefence and st.blocking then
		if combatEvent then
			pcall(function()
				local fr = attacker.Character
					and (attacker.Character:FindFirstChild("HumanoidRootPart")
						or attacker.Character:FindFirstChild("Torso"))
				-- 막았어도 어디서 맞았는지는 알려줘야 한다. 등 뒤를 잡히면 알아야 하니까
				combatEvent:FireClient(victim, {
					phase = "blocked",
					from = fr and fr.Position or nil,
				})
				combatEvent:FireClient(attacker, { phase = "hitmark", blocked = true })
			end)
		end
		return "blocked"
	end

	-- 오토디펜스. 궁극기는 무시한다.
	if not ignoreDefence and st.autoDefence > 0 then
		st.autoDefence = st.autoDefence - 1
		st.adRegenAt = os.clock() + AUTO_DEFENCE_REGEN
		if combatEvent then
			pcall(function()
				-- 맞은 사람 : 어디서 맞았는지 + 막기 모션
				local from = attacker.Character
					and (attacker.Character:FindFirstChild("HumanoidRootPart")
						or attacker.Character:FindFirstChild("Torso"))
				combatEvent:FireClient(victim, {
					phase = "autodefence",
					from = from and from.Position or nil,
					left = st.autoDefence,
				})
				-- 때린 사람 : 히트마크
				combatEvent:FireClient(attacker, { phase = "hitmark", blocked = true })
				-- 전원 : 파란 배리어. 때린 쪽도 막혔다는 걸 봐야 한다
				combatEvent:FireAllClients({ phase = "barrier", who = victim, kind = "auto" })
			end)
		end
		push(victim)
		return "autodefence"
	end

	-- 사망
	st.alive = false
	st.deaths = st.deaths + 1

	-- ★ 사망 연출. 실제 처리는 AvatarAnimServer 가 한다 (애니메이션을 쥐고 있는 쪽이다).
	--   여기서 직접 하면 이동 상태 루프와 매 프레임 싸운다.
	pcall(function()
		local A = _G.AvatarAnim
		if A and A.playDeath then
			A.playDeath(victim)
		end
	end)

	-- 시체가 걸어다니면 안 된다. MovementSpeedServer 가 매 프레임 WalkSpeed 를 다시 쓰기 때문에
	-- 여기서 한 번 0 을 넣어봐야 다음 프레임에 되돌아온다. 그래서 플래그로 알린다.
	_G.MovementFreeze = _G.MovementFreeze or {}
	_G.MovementFreeze[victim] = true

	local ast = S[attacker]
	if ast then
		ast.kills = ast.kills + 1
		if T then
			T.addScore(T.teamNameOf(attacker), 1)      -- 팀 점수는 킬당 1점
			M.addUlt(attacker, T.ULT_GAIN_KILL)
		end
		-- 죽인 사람에게만 "kill <이름>" + 처치 히트마크
		if combatEvent then
			pcall(function()
				combatEvent:FireClient(attacker, { phase = "killfeed", name = victim.Name })
				combatEvent:FireClient(attacker, { phase = "hitmark", killed = true })
			end)
		end
		push(attacker)
	end

	if combatEvent then
		pcall(function()
			combatEvent:FireAllClients({
				phase = "kill",
				killer = attacker,
				victim = victim,
				killerTeam = T and T.teamNameOf(attacker) or nil,   -- 킬로그 색깔용
				respawn = RESPAWN_TIME,
			})
		end)
	end
	push(victim)

	-- 리스폰. 기획서 : 죽으면 전장으로 바로 돌아가는 게 아니라 로비로 나갔다가
	-- PLAY 를 눌러 다시 들어온다. 킬캠 5초가 끝나는 이 시점에 로비로 보낸다.
	pcall(function()
		local L = _G.LobbyServer
		if L and L.onDeath then
			L.onDeath(victim)
		end
	end)
	task.delay(RESPAWN_TIME, function()
		if not Players:FindFirstChild(victim.Name) then
			return
		end
		pcall(function()
			victim:LoadCharacter()
		end)
	end)

	return "killed"
end

-- ★ 전투가 아닌 사망. 지금은 경기구역 이탈이 유일하다.
--   applyHit 은 "때린 사람" 이 있어야 돌아간다. 여기는 가해자가 없으므로
--   팀 점수·궁극기 충전·킬 카운트를 건드리지 않고 죽는 부분만 그대로 한다.
--   killer 자리에 플레이어가 없으니 이름만 killerName 으로 보낸다.
--   (HUD 킬로그와 킬캠이 killerName 을 대신 읽는다)
function M.killByWorld(victim, label)
	if not victim then
		return "invalid"
	end
	local st = S[victim]
	if not (st and st.alive) then
		return "already_dead"
	end
	if _G.LobbyWant and _G.LobbyWant[victim] then
		return "lobby"
	end

	st.alive = false
	st.deaths = st.deaths + 1

	pcall(function()
		local A = _G.AvatarAnim
		if A and A.playDeath then
			A.playDeath(victim)
		end
	end)

	_G.MovementFreeze = _G.MovementFreeze or {}
	_G.MovementFreeze[victim] = true

	if combatEvent then
		pcall(function()
			combatEvent:FireAllClients({
				phase = "kill",
				victim = victim,
				killerName = label or "THE BOUNDARY",
				respawn = RESPAWN_TIME,
			})
		end)
	end
	push(victim)

	pcall(function()
		local L = _G.LobbyServer
		if L and L.onDeath then
			L.onDeath(victim)
		end
	end)
	task.delay(RESPAWN_TIME, function()
		if not Players:FindFirstChild(victim.Name) then
			return
		end
		pcall(function()
			victim:LoadCharacter()
		end)
	end)

	return "killed"
end

-- ===== 공격 시작 감지 : 눈 별빛(패링 텔레그래프) =====
--
-- AvatarAnimServer 가 3인칭 모션에 쓰는 WeaponAttackEvent 를 여기서도 듣는다.
-- 클라이언트가 이걸 쏘는 순간이 "공격 시작 0초" 이고, 패링 창의 기준점이다.
--
-- ★ 별빛은 전원에게 보낸다. 3인칭 표시라 상대가 봐야 의미가 있다.
local weaponAttackEvent = ReplicatedStorage:WaitForChild("WeaponAttackEvent", 10)
if weaponAttackEvent and combatEvent then
	weaponAttackEvent.OnServerEvent:Connect(function(player)
		local st = S[player]
		if not (st and st.alive) then
			return
		end
		st.attackAt = os.clock()

		task.delay(PARRY.WINDOW_START, function()
			-- 그 사이 죽었거나 리스폰했으면 띄우지 않는다
			if S[player] ~= st or not st.alive then
				return
			end
			pcall(function()
				combatEvent:FireAllClients({
					phase = "telegraph",
					who = player,
					dur = PARRY.WINDOW_END - PARRY.WINDOW_START,
				})
			end)
		end)
	end)
elseif not weaponAttackEvent then
	print("[Combat] WeaponAttackEvent 를 못 찾음 - 패링 별빛이 안 뜬다")
end

_G.CombatServer = M

-- ===== 클라이언트 히트 보고 수신 =====
-- ★ 클라이언트는 "이 사람을 겨눴다" 만 말한다. 맞았는지·죽는지는 여기서 정한다.
--   거리를 서버가 다시 재는 게 핵심이다. 안 그러면 맵 반대편에서도 죽일 수 있다.
if combatEvent then
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "melee" then
			return
		end
		local target = payload.target
		if type(target) ~= "userdata" or not target:IsA("Player") then
			return
		end
		if not M.isAlive(player) then
			return
		end
		-- 기절 중에는 때릴 수 없다. 클라이언트가 뭘 보내든 서버가 막는다
		if M.isStunned(player) then
			return
		end

		local a = player.Character
			and (player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Torso"))
		local b = target.Character
			and (target.Character:FindFirstChild("HumanoidRootPart")
				or target.Character:FindFirstChild("Torso"))
		if not (a and b) then
			return
		end

		-- 서버가 거리를 다시 잰다. 클라이언트 값을 믿지 않는다.
		if (a.Position - b.Position).Magnitude > MELEE_MAX_DIST then
			return
		end

		M.applyHit(player, target, false)
	end)

	-- 궁극기를 썼다는 보고. 충전량을 0 으로 되돌린다.
	-- ★ 클라이언트가 "썼다" 고 말하는 것만 믿지 않는다. 가득 차 있을 때만 받아준다.
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "ultused" then
			return
		end
		local st = S[player]
		if st and st.ultCharge >= 1 then
			st.ultCharge = 0
			st.ultUsedAt = os.clock()      -- 궁극기 피격 보고를 받아줄 기준 시각
			push(player)
		end
	end)

	-- ===== 쿠나이가 사람에게 박혔다 / 빠졌다 =====
	--
	-- ★ 박힌 쿠나이는 피격 판정이 아니다 (기획서). 안 죽고 오토디펜스도 안 깎인다.
	--   여기서 하는 일은 "박혔다" 는 사실을 전원에게 알리는 것뿐이다.
	--   박힌 당사자는 화면이 살짝 어두워지는 경고를 받는다.
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "kunai_stick" then
			return
		end
		local target = payload.target
		if type(target) ~= "userdata" or not target:IsA("Player") then
			return
		end
		pcall(function()
			combatEvent:FireAllClients({
				phase = "kunai_stuck",
				who = target,
				by = player,
				on = payload.on and true or false,
			})
		end)
	end)

	-- ===== 3타 참격(XBlade) 피격 보고 =====
	--
	-- 참격은 근접 사거리 밖(최대 15m)까지 날아간다. 근접과 같은 규칙을 쓰되
	-- (방어·패링·오토디펜스 다 적용) 거리 한계만 참격 사거리에 맞춘다.
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "xblade" then
			return
		end
		if not M.isAlive(player) or M.isStunned(player) then
			return
		end
		local target = payload.target
		if type(target) ~= "userdata" or not target:IsA("Player") then
			return
		end

		local a = player.Character
			and (player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Torso"))
		local b = target.Character
			and (target.Character:FindFirstChild("HumanoidRootPart")
				or target.Character:FindFirstChild("Torso"))
		if not (a and b) then
			return
		end
		if (a.Position - b.Position).Magnitude > XBLADE_MAX_DIST then
			return
		end

		M.applyHit(player, target, false)
	end)

	-- ===== 궁극기 피격 보고 =====
	--
	-- ★ 궁극기는 방어·패링·오토디펜스를 전부 무시한다 (기획서). 피하는 것만이 답이다.
	--   그래서 applyHit 에 ignoreDefence = true 로 넣는다.
	--
	-- ★ 이건 즉사기라 클라이언트를 특히 믿으면 안 된다. 두 겹으로 막는다:
	--   1) 실제로 궁극기를 쓴 직후(ULT_HIT_WINDOW 초)에만 받아준다
	--   2) 서버가 거리를 다시 잰다
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "ult" then
			return
		end
		local st = S[player]
		if not (st and st.alive and st.ultUsedAt) then
			return
		end
		if os.clock() - st.ultUsedAt > ULT_HIT_WINDOW then
			return
		end

		local target = payload.target
		if type(target) ~= "userdata" or not target:IsA("Player") then
			return
		end

		local a = player.Character
			and (player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Torso"))
		local b = target.Character
			and (target.Character:FindFirstChild("HumanoidRootPart")
				or target.Character:FindFirstChild("Torso"))
		if not (a and b) then
			return
		end
		if (a.Position - b.Position).Magnitude > ULT_MAX_DIST then
			return
		end

		M.applyHit(player, target, true)
	end)

	-- 방어 상태 중계.
	-- 주황 배리어는 남들에게도 보여야 하는데 방어는 클라이언트 입력이라 서버를 거쳐 뿌린다.
	combatEvent.OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or payload.phase ~= "block" then
			return
		end
		local st = S[player]
		if st then
			-- ★ 누른 "시각" 을 남긴다. 패링은 지금 켜져 있는지가 아니라
			--   공격의 별빛 구간 안에 새로 눌렀는지로 판정한다.
			if payload.on and not st.blocking then
				st.blockAt = os.clock()
			end
			st.blocking = payload.on and true or false
		end
		pcall(function()
			combatEvent:FireAllClients({
				phase = "barrier",
				who = player,
				kind = "block",
				on = payload.on and true or false,
			})
		end)
	end)
end

-- ===== 캐릭터 수명 =====
local function onCharacter(player, character)
	-- 새 몸으로 살아났다. 사망 때 걸어둔 이동 정지를 푼다.
	if _G.MovementFreeze then
		_G.MovementFreeze[player] = nil
	end
	S[player] = fresh(player)
	push(player)

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("Torso", 5)
	if root then
		S[player].lastPos = root.Position
	end
end

local function hook(player)
	player.CharacterAdded:Connect(function(ch)
		onCharacter(player, ch)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(hook)
Players.PlayerRemoving:Connect(function(player)
	S[player] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

-- ===== 틱 : 무적 해제 / 오토디펜스 회복 / 궁극기 충전 =====
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc = acc + dt
	if acc < 0.25 then
		return
	end
	local step = acc
	acc = 0

	local now = os.clock()
	local T = team()

	for player, st in pairs(S) do
		local ch = player.Character
		local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))

		-- 움직이기 시작하면 무적을 MOVED 초로 다시 잡는다.
		-- 이미 그보다 짧게 남았으면 줄이지 않는다 (기획서 : 3초가 "추가" 된다).
		if root and st.alive and not st.moved then
			if st.lastPos then
				local v = (root.Position - st.lastPos).Magnitude / step
				if v > MOVE_THRESHOLD then
					st.moved = true
					local target = now + SPAWN_INVULN_MOVED
					if target > (st.invulnUntil or 0) then
						st.invulnUntil = target
					end
					push(player)
				end
			end
			st.lastPos = root.Position
		elseif root then
			st.lastPos = root.Position
		end

		-- 오토디펜스 회복
		if st.autoDefence < AUTO_DEFENCE_MAX and st.adRegenAt and now >= st.adRegenAt then
			st.autoDefence = st.autoDefence + 1
			if st.autoDefence < AUTO_DEFENCE_MAX then
				st.adRegenAt = now + AUTO_DEFENCE_REGEN
			else
				st.adRegenAt = nil
			end
			push(player)
		end

		-- 궁극기 자연 충전
		--
		-- ★ 여기서 push 를 안 해서 클라이언트가 이 값을 영영 못 받고 있었다 (2026-08-20).
		--   addUlt(킬·점령)만 push 를 부르니, 그때까지 조용히 쌓인 양이 킬 순간에
		--   한꺼번에 드러나 "킬할 때만 수십 퍼센트씩 확 오른다" 로 보였다.
		--   실제로 킬이 주는 건 2초 = 1.33% 뿐이다.
		--
		--   매 틱(0.25초) 보내면 낭비라, 화면에 찍히는 정수 퍼센트가 바뀔 때만 보낸다.
		--   150초 동안 100번이니 초당 0.67회다.
		-- 로비에 있는 동안은 충전이 멈춘다. 안 싸우는데 게이지가 차면 안 된다.
		local inLobby = _G.LobbyWant ~= nil and _G.LobbyWant[player] == true
		if T and st.alive and not inLobby and st.ultCharge < 1 then
			st.ultCharge = math.min(1, st.ultCharge + step / T.ULT_FULL)
			local shown = math.floor(st.ultCharge * 100)
			if shown ~= st.ultShown then
				st.ultShown = shown
				push(player)
			end
		end
	end
end)

print("[CombatServer] ready")
