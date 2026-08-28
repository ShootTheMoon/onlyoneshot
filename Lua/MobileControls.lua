
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local CIRCLE_IMAGE = "ovdrassetid://40281100"
local NEUTRAL_COLOR = Color3.new(1, 1, 1)
local IDLE_TRANSPARENCY = 0.7
local ACTIVE_TRANSPARENCY = 0.4

local humanoid = nil

local function getHumanoid()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CombatButtons"
screenGui.Parent = playerGui

local function makeButton(name, text, xScale, yScale, size)
	local btn = Instance.new("ImageButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.new(xScale, 0, yScale, 0)
	btn.Size = UDim2.new(0, size, 0, size)
	btn.Image = CIRCLE_IMAGE
	btn.ImageColor3 = NEUTRAL_COLOR
	btn.ImageTransparency = IDLE_TRANSPARENCY
	btn.BackgroundTransparency = 1
	btn.ZIndex = 10
	btn.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Bold = true
	label.ZIndex = 11
	label.Parent = btn

	return btn
end

local attackBtn = makeButton("AttackButton", "attack", 0.90, 0.80, 140)
local heavyBtn = makeButton("HeavyAttackButton", "heavyattack", 0.74, 0.68, 110)
local blockBtn = makeButton("BlockButton", "block", 0.90, 0.58, 110)
local ultimateBtn = makeButton("UltimateButton", "Ult", 0.80, 0.38, 125)
local jumpBtn = makeButton("JumpButton", "jump", 0.70, 0.84, 105)

-- ★ 공격/강공격/궁극기 버튼은 여기서 처리하지 않는다.
--   ViewmodelController 가 같은 버튼에 따로 연결해서 실제 동작을 맡는다.
--   예전엔 여기 print 만 하는 빈 핸들러가 있었는데,
--   "버튼 눌림" 로그가 찍히니 공격이 나간 줄 착각하게 만들어 진단이 두 번 샜다. 그래서 지웠다.

-- ★ 패링당해 기절 중이면 아무 조작도 못 한다 (HUD 가 _G.StunUntil 을 채워준다).
--   걷기는 서버가 WalkSpeed 로 막지만 점프·버튼은 클라이언트 입력이라 여기서 막아야 한다.
local function stunned()
	return _G.StunUntil ~= nil and os.clock() < _G.StunUntil
end

-- 로비에서는 조작 버튼을 통째로 감춘다. 메뉴 위에 공격 버튼이 겹치면 안 된다.
-- ★ nil 과 false 를 비교하면 영영 안 켜진다. 불리언으로 맞춰 비교한다.
game:GetService("RunService").Heartbeat:Connect(function()
	local want = not _G.InLobby
	if screenGui.Enabled ~= want then
		pcall(function()
			screenGui.Enabled = want
		end)
	end
end)

local blocking = false
blockBtn.Activated:Connect(function()
	if stunned() then
		return
	end
	blocking = not blocking
	blockBtn.ImageTransparency = blocking and ACTIVE_TRANSPARENCY or IDLE_TRANSPARENCY
end)

jumpBtn.Activated:Connect(function()
	if stunned() then
		return
	end
	humanoid = humanoid or getHumanoid()
	if humanoid then
		local ok, err = pcall(function()
			humanoid.Jump = true
		end)
		if not ok then
			print("[MobileControls] Jump set failed: " .. tostring(err))
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	blocking = false
	humanoid = nil
end)

print("[MobileControls] ready")
