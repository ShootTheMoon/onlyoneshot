-- 용의 이빨 (Ryunochi) 서버 릴레이
--
-- 용 머리와 파괴 연출은 원래 클라이언트에서만 보였다.
-- 모든 유저에게 보이게 하려면 서버를 한 번 거쳐 전체에 뿌려야 한다.
-- (기존 WeaponAttackEvent 와 같은 방식)
--
-- RemoteEvent 를 여기서 만들면 클라이언트로 자동 복제되므로
-- 월드 파일에 인스턴스를 미리 넣어둘 필요가 없다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ev = ReplicatedStorage:FindFirstChild("RyunochiEvent")
if not ev then
	ev = Instance.new("RemoteEvent")
	ev.Name = "RyunochiEvent"
	ev.Parent = ReplicatedStorage
end

-- 이제 궁극기 전용이 아니라 스킬 연출 공용 통로다.
--   "start"     궁극기 시작   { origin, dir }
--   "slam"      궁극기 착지   { origin, pos, dir }
--   "raijin_throw" 쿠나이 투척 { origin, dir, groundY }
--   "raijin_tp"    순간이동    { from, to }
--   "xblade"       3타 X자 참격 { origin, dir }
--   "raijin_hand"  비뢰신 중 손의 칼 숨김 { hide }
--   "bow_shot"     국궁 화살 발사 { origin, dir, power }
local ALLOWED = {
	start = true,
	slam = true,
	raijin_throw = true,
	raijin_tp = true,
	xblade = true,
	raijin_hand = true,
	bow_shot = true,
}

ev.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		return
	end
	if not ALLOWED[payload.phase] then
		return
	end
	-- 보낸 사람을 포함해 전원에게 그대로 전달한다.
	-- 각 클라이언트가 자기 쪽에서 같은 이펙트를 만든다 (파츠 복제보다 훨씬 가볍다).
	ev:FireAllClients(player, payload)
end)

print("[RyunochiServer] ready")
