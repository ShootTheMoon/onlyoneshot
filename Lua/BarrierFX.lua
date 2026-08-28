-- 방어 배리어 연출
--
--   파란 배리어 : 오토디펜스가 공격을 막은 순간 잠깐 (누구에게 맞았든 전원이 본다)
--   주황 배리어 : 방어를 켜고 있는 동안 계속
--
-- ★ 파츠를 서버가 복제하지 않는다. 서버는 "누가 / 어떤 배리어" 만 알리고
--   각 클라이언트가 자기 화면에 그린다. 이 프로젝트의 다른 연출과 같은 방식이고 훨씬 가볍다.
--
-- 캐릭터 밑에 두면 안 된다. MovementSpeedServer.stripCharacterApparel 이
-- 표준 신체 부위가 아닌 BasePart 를 전부 지운다. 그래서 Workspace 에 띄우고 매 프레임 따라간다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AUTO_COLOR = Color3.fromRGB(110, 165, 230)   -- 오토디펜스 : 파랑
local BLOCK_COLOR = Color3.fromRGB(225, 150, 70)   -- 일반 방어 : 주황

local AUTO_HOLD = 0.35        -- 파란 배리어가 떠 있는 시간 (초)
local SIZE = 250              -- 배리어 지름 (cm). 캐릭터가 약 205cm 라 250 이면 몸에 붙는다
local RISE = 20               -- 캐릭터 중심에서 위로 (cm)

-- 재질. Neon 은 조명과 무관하게 색을 그대로 뿜어서 밝게 보인다.
-- 투명도를 올려도 아직 눈부시면 여기를 Enum.Material.SmoothPlastic 으로 바꿔라.
local MATERIAL = Enum.Material.Neon

-- ★ 배리어 너머로 적이 보여야 한다. 안 보이면 방어가 곧 시야 차단이 되어버린다.
--   주황(방어)은 계속 떠 있으므로 더 옅게, 파랑(피격)은 순간이라 조금 진하게 둔다.
local BLOCK_TRANSPARENCY = 0.94   -- 켜고 있는 동안 계속 보이는 것
local AUTO_TRANSPARENCY = 0.88    -- 0.35초만 번쩍이는 것

local shells = {}             -- [player] = { part = Part, autoUntil = 0, blocking = false }

local function shellOf(player)
	local s = shells[player]
	if s and s.part and s.part.Parent then
		return s
	end
	local p = Instance.new("Part")
	p.Name = "Barrier"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(SIZE, SIZE, SIZE)
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Transparency = 1
	pcall(function()
		p.CanTouch = false
		p.CanQuery = false
		p.Material = MATERIAL
	end)
	p.Parent = Workspace

	s = s or {}
	s.part = p
	s.autoUntil = s.autoUntil or 0
	s.blocking = s.blocking or false
	shells[player] = s
	return s
end

local function clear(player)
	local s = shells[player]
	if s and s.part then
		pcall(function()
			s.part:Destroy()
		end)
	end
	shells[player] = nil
end

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent", 10)
if combatEvent then
	combatEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or payload.phase ~= "barrier" then
			return
		end
		local who = payload.who
		if type(who) ~= "userdata" then
			return
		end
		local s = shellOf(who)
		if payload.kind == "auto" then
			s.autoUntil = os.clock() + AUTO_HOLD
		elseif payload.kind == "block" then
			s.blocking = payload.on and true or false
		end
	end)
else
	print("[BarrierFX] CombatEvent 를 못 찾음 - 배리어가 안 나온다")
end

Players.PlayerRemoving:Connect(clear)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for player, s in pairs(shells) do
		local ch = player.Character
		local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
		if not (root and s.part and s.part.Parent) then
			if not ch then
				clear(player)
			end
		else
			local auto = now < (s.autoUntil or 0)
			if auto or s.blocking then
				-- 오토디펜스가 우선. 막힌 순간이 더 중요한 정보다.
				s.part.Color = auto and AUTO_COLOR or BLOCK_COLOR
				s.part.Transparency = auto and AUTO_TRANSPARENCY or BLOCK_TRANSPARENCY
				s.part.CFrame = CFrame.new(root.Position + Vector3.new(0, RISE, 0))
			else
				s.part.Transparency = 1
			end
		end
	end
end)

print("[BarrierFX] ready")
