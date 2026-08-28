-- 서버측 사운드 신호 (2026-08-25)
--
-- 소리는 전부 클라이언트가 낸다. 서버는 "언제 어디서" 만 알려 준다.
-- 대부분의 전투 소리는 이미 CombatEvent 를 타고 클라로 가고 있어서
-- SoundClient 가 그걸 그냥 듣는다 (SoundDB.PHASE_TO_SOUND).
-- 이 스크립트는 그 바깥의 서버 사건용 문이다.
--
--   _G.SfxAll("capture_done", pos)          -- 전원에게
--   _G.SfxTo(player, "ult_ready")           -- 한 명에게
--   _G.SfxNear("slam", pos, 8000)           -- 반경(cm) 안 사람에게만
--
-- ★ 전원 브로드캐스트는 아껴 써라. 10인이면 한 번에 10개 보이스가 뜬다.
--   자리가 있는 소리는 SfxNear 를 써서 멀리 있는 사람에게는 아예 안 보내는 게 맞다.
--   (클라도 거리 컷을 하지만, 안 보내면 네트워크까지 아낀다.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ev = ReplicatedStorage:FindFirstChild("SoundEvent")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "SoundEvent"
	ev.Parent = ReplicatedStorage
end

local function rootOf(player)
	local ch = player and player.Character
	return ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
end

function _G.SfxTo(player, name, pos)
	if not player or not name then return end
	ev:FireClient(player, { name = name, pos = pos })
end

function _G.SfxAll(name, pos)
	if not name then return end
	ev:FireAllClients({ name = name, pos = pos })
end

function _G.SfxNear(name, pos, radius)
	if not name or not pos then return end
	radius = radius or 8000
	for _, p in ipairs(Players:GetPlayers()) do
		local r = rootOf(p)
		if r and (r.Position - pos).Magnitude <= radius then
			ev:FireClient(p, { name = name, pos = pos })
		end
	end
end

print("[Sound] SoundServer ready")
