-- 프레임 측정용 스크립트 — 읽기 전용, 12번 찍고 스스로 멈춘다
--
-- ============================ 지금까지 밝혀진 것 ============================
--
--  1) 로비 FPS 19~41 (평균 ~28). 누수 아님 (인스턴스 증감 0).
--  2) LobbyUI ON/OFF A/B : 29.7 vs 24.1 → UI 렌더 비용은 노이즈에 묻힌다. 무죄.
--  3) 인구조사 : Workspace 4666 파츠 중 2671(57%)이 완전 투명.
--       화성은 산곡에서 13만 유닛 떨어져 보이지도 않고 코드 어디서도 참조하지 않는다.
--  4) 화성 두 모델을 ServerStorage 로 옮겼다 (삭제 아님).
--
--  ---- 2026-08-25 실측 (여기부터가 이번에 잰 것) ----
--
--  5) ★ 화성 빼기 효과 : 평균 28 → 44.0 fps, 정상 구간 46. 진짜였다.
--       Workspace 파츠 4666 → 3485 (완전투명 1674).
--
--  6) 그 다음 범인을 찾으려고 A/B 를 셋 돌렸다. 전부 무죄였다.
--       초목 1613개 숨김                : -2.6 fps
--       해 그림자 끄기                  : -1.6 fps
--       클라 LocalScript 10개 전부 끄기 : +1.5 fps
--       대조군(아무것도 안 바꾸고 재측정) : -1.6 fps  <- 노이즈 바닥이 +-2 다
--     -> 남은 21ms 는 드로우콜도, 그림자도, 우리 Lua 도 아니다.
--
--  7) ★ 그래서 결론 : fps 를 움직이는 레버는 "Workspace 인스턴스 개수" 하나다.
--       25% 줄이니 fps 가 57% 올랐다. 보이냐 안 보이냐는 상관이 없었다
--       (초목을 숨겨도 안 빨라졌지만, 화성을 Workspace 밖으로 빼니 빨라졌다).
--     -> 다음 최적화는 "예쁜 걸 줄이기" 가 아니라 "개수를 줄이기" 여야 한다.
--       남은 덩어리 : JSN_COL 1669(투명 충돌 슬래브) · JSN_Pine 1096 · JSN_Und 517
--
--  ---- A/B 를 할 때 반드시 지킬 것 ----
--
--  ★ 속성을 왕창 바꾼 직후에 재면 안 된다. 바꾸는 그 순간의 히칭이 측정 창에 들어온다.
--    1판에서 9초 창 중 5.7초를 통째로 멈춘 구간을 "바위·그림자가 31fps 를 먹는다" 로
--    읽을 뻔했다. 바꾼 뒤 4초쯤 쉬고, 매 구간 끝에 원래대로 돌린 뒤 다음으로 가라.
--  ★ 벽시계 시간과 누적 dt 를 같이 찍어라. 둘이 벌어지면 그 구간은 멈춰 있었다는 뜻이라
--    fps 숫자를 믿으면 안 된다.
--  ★ 대조군(아무것도 안 바꾼 재측정)을 꼭 넣어라. 노이즈 바닥을 모르면 +-2 를 성과로 읽는다.
--
-- ==========================================================================

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WINDOW = 3
local MAX_REPORTS = 12

local acc, frames, worst = 0, 0, 0
local last = os.clock()
local reported = 0
local sum, cnt = 0, 0

task.delay(8, function()
	local parts, invisible = 0, 0
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			local cn = d.ClassName
			if cn == "Part" or cn == "MeshPart" or cn == "WedgePart" or cn == "TrussPart" then
				parts = parts + 1
				pcall(function()
					if d.Transparency and d.Transparency >= 0.99 then invisible = invisible + 1 end
				end)
			end
		end
	end)
	print(string.format("[Perf] Workspace 파츠 %d (완전투명 %d)", parts, invisible))
end)

RunService.RenderStepped:Connect(function(dt)
	if reported >= MAX_REPORTS then return end

	local now = os.clock()
	frames = frames + 1
	acc = acc + dt
	if dt > worst then worst = dt end

	if now - last >= WINDOW then
		local el = now - last
		local fps = frames / el
		reported = reported + 1
		if reported > 2 then          -- 앞 두 구간은 로드 히칭이라 뺀다
			sum = sum + fps
			cnt = cnt + 1
		end
		print(string.format("[Perf] %-4s FPS %5.1f  평균 %5.2fms  최악 %6.2fms  (%d프레임, 벽시계 %.1fs / 누적dt %.1fs)",
			_G.InLobby and "로비" or "전장", fps, (acc / math.max(1, frames)) * 1000, worst * 1000, frames, el, acc))
		acc, frames, worst = 0, 0, 0
		last = now
		if reported >= MAX_REPORTS then
			print(string.format("[Perf] === 평균 %.1f fps  (기준선 : 화성 빼기 전 28, 뺀 뒤 44)",
				(cnt > 0) and (sum / cnt) or 0))
			print("[Perf] 측정 종료")
		end
	end
end)

print("[Perf] ready")
