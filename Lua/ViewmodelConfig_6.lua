-- 뷰모델 조정값 모음.
-- 이 파일 숫자만 고치고 Play 를 다시 누르면 바로 반영된다.
--
-- ※ 주의(AI 포함): 아래 값들은 사용자가 실제 화면을 보며 맞춘 확정값이다.
--   애니메이션을 추가하거나 스크립트를 갱신할 때 임의로 되돌리지 말 것.
return {
	-- 카메라 기준 뷰모델 위치 (cm)
	--   X : 오른쪽(+) / 왼쪽(-)
	--   Y : 위(+)     / 아래(-)
	--   Z : 앞(-)     / 뒤(+)
	OFFSET_X = -10,   -- 확정값. 건드리지 말 것
	OFFSET_Y = -35,
	OFFSET_Z = -55,

	-- 뷰모델 확대 배율
	SCALE = 2.4,

	-- 스폰 후 뷰모델을 숨겨두는 시간(초). 카메라가 자리를 잡을 때까지 기다린다.
	INTRO_DELAY = 1,

		-- 뷰모델 중심으로 삼을 기준점. 임포트된 파츠 좌표 기준이며,
		-- 지금은 Wakizashi_Viewmodel_Split 안의 양팔(Right_Arm_Mesh, Left_Arm_Mesh)의 중점이다.
		-- 이 X 를 키우면 뷰모델이 오른쪽으로, 줄이면 왼쪽으로 간다.
		--
		-- ★ 2026-08-24 재실측. 레벨의 Wakizashi_Viewmodel_Split 에서 직접 뽑았다.
		--   Right_Arm_Mesh (871.558594, 75.402748, 4607.296875)
		--   Left_Arm_Mesh  (832.898987, 70.655594, 4611.125488)
		--   -> 중점        (852.228790, 73.029171, 4609.211182)
		--
		--   옛 값은 792.228790 / 23.029174 / 4679.211182 로, 중점에서 정확히
		--   (-60, -50, +70) 벗어나 있었다. SCALE 2.4 를 타면 화면에서
		--   (144, 120, -168) cm 짜리 이동이 된다 — 뷰모델이 화면 오른쪽으로
		--   쳐박혀 보이던 원인이다. OFFSET_X(-10) 보다 14배 큰 항이라
		--   좌우 위치를 실제로 지배하는 건 OFFSET 이 아니라 여기다.
		--
		--   되돌리려면 아래 세 줄을 792.228790 / 23.029174 / 4679.211182 로.
		--   모델을 다시 임포트하거나 레벨에서 옮기면 여기를 다시 재야 한다.
		PIVOT_X = 852.228790,
		PIVOT_Y = 73.029171,
		PIVOT_Z = 4609.211182,

	-- 연타할 때 이어질 공격 순서.
	-- 이름은 ViewmodelAnimData 안의 항목이거나,
	-- ReplicatedStorage 의 "ViewmodelAnim<이름>" 모듈이면 자동으로 찾는다.
	COMBO = { "Attack1", "Attack2", "Attack3" },

	-- ===== 캐릭터별 뷰모델 =====
	-- 로비 LOADOUT 에서 고른 나라에 따라 다른 뷰모델을 쓴다.
	--   SOURCE : Workspace 에 있는 원본 모델 이름
	--   PIVOT  : 그 모델 안 양팔(Right_Arm_Mesh, Left_Arm_Mesh) CFrame 의 중점
	--   OFFSET : 카메라 기준 화면 위치 { X, Y, Z } cm. 없으면 위 전역 OFFSET_* 을 쓴다
	--   ANIM   : false 면 클립 포즈를 아예 안 먹인다
	--
	-- ★★ PIVOT 은 반드시 "레벨에 임포트된 뒤" 다시 재라. 절대 좌표라서
	--   모델을 다시 임포트하거나 레벨에서 옮기면 그 즉시 무효가 된다.
	--   2026-08-24 에 이걸로 크게 헤맸다 — 와키자시 PIVOT 이 실제 중점에서
	--   (-60, -50, +70) 벗어나 있었고, SCALE 2.4 를 타면 화면에서 144cm 라
	--   뷰모델이 화면 오른쪽으로 쳐박혀 보였다. OFFSET_X(-10) 의 14배 항이라
	--   좌우 위치를 지배하는 건 OFFSET 이 아니라 PIVOT 이다.
	CHARACTERS = {
		japan = {
			SOURCE = "Wakizashi_Viewmodel_Split",
			-- 위 전역 PIVOT_* / OFFSET_* 과 같은 값 (2026-08-24 재실측 확정)
			PIVOT = { 852.228790, 73.029171, 4609.211182 },
			OFFSET = { -10, -35, -55 },
			ANIM = true,
		},
		korea = {
			-- 2026-08-24 임포트 (Gukgung_Viewmodel_Merged.fbx).
			-- 활/화살은 하나로 합쳐져 있고 시위만 따로다 (17링, 애니메이팅용).
			-- 배율 검증 : 양팔 간격 블렌더 0.26014 -> 레벨 26.02 = 정확히 100배.
			SOURCE = "Gukgung_Viewmodel_Merged",
			PIVOT = { -540.620941, 18.364028, -1038.147034 },
			-- 사용자가 화면 보며 맞춘 값. X 는 오른쪽(+) / 왼쪽(-), 단위 cm.
			-- japan 과 완전히 별개다 (japan 은 -10 그대로).
			OFFSET = { 30, -35, -55 },

			-- ===== 이 나라가 쓸 클립 목록 =====
			-- 왼쪽이 컨트롤러가 부르는 이름, 오른쪽이 ReplicatedStorage 의 모듈 이름이다
			-- (실제 인스턴스 이름은 "ViewmodelAnim" + 오른쪽 값).
			--
			-- ★ 여기 없는 이름은 "국궁엔 아직 없는 동작"이라 아예 재생되지 않는다.
			--   이 표를 지우면 와키자시 공격/막기 클립이 국궁 팔을 그대로 몰고 간다 —
			--   팔 파츠 이름이 나라끼리 같아서 이름만으로는 안 걸러지기 때문이다.
			--   Attack1/2/3, BlockIn, BlockOut, Draw, KunaiThrow, Ryunochi 를
			--   일부러 안 넣었다. 국궁 클립을 만들면 그때 여기에 한 줄씩 추가하면 된다.
			CLIPS = {
				-- 기준(rest) 프레임 블렌더 60, 회전중심 (0.106209, 0.218530, -0.140583)
				Intro = "GukgungIntro",

				-- 기본공격 = 시위를 놓는 순간. 버튼을 떼면 재생된다.
				-- Attack2 / Attack3 을 일부러 안 넣었다 -> 콤보가 안 이어진다.
				-- 활은 3연타로 휘두르는 무기가 아니라 한 발씩 쏘는 무기다.
				Attack1 = "GukgungFire",   -- 블렌더 f39~43, 0.167초

				-- 버튼을 누르고 있는 동안 재생. 시간이 아니라 차징 게이지로
				-- 재생 위치를 정한다 (0% = 첫 프레임, 100% = 마지막 프레임).
				BowDraw = "GukgungDraw",   -- 블렌더 f10~34

				-- 당기기~발사가 한 덩어리인 옛 클립. 지금은 안 쓴다.
				-- 차징을 끄고 예전처럼 한 방에 돌리고 싶으면
				-- 아래 CHARGE_TIME 을 지우고 Attack1 을 이걸로 바꾸면 된다.
				-- BowWhole = "GukgungAttack",
			},

			-- ★ 이 값이 있으면 기본공격 버튼이 '유지형' 이 된다.
			--   꾹 누르는 동안 BowDraw 가 게이지를 따라 재생되고, 떼면 Attack1 이 나간다.
			--   0% -> 100% 까지 걸리는 시간(초). 이 줄을 지우면 예전처럼 눌렀다 떼면 한 방이다.
			--   기획 : 0~50% 는 얼마 못 가 땅에 박히고, 51~100% 는 포물선으로 제대로 날아간다.
			--   떼는 순간의 세기(0~1)는 _G.BowPower 로 나간다. 아직 읽는 쪽은 없다.
			CHARGE_TIME = 1.2,

			-- 인트로 재생 속도. 1 = 클립 원래 속도(2.08초).
			--   0.5 -> 절반 속도라 4.17초 (느리게)
			--   0.8 -> 2.60초
			--   2   -> 1.04초            (빠르게)
			-- 클립을 다시 뽑을 필요 없이 이 숫자만 고치고 Play 를 다시 누르면 된다.
			INTRO_SPEED = 0.8,

			-- ★ 국궁 전용 클립이 아직 하나도 없다.
			--   ViewmodelAnimData.PART_ORDER 에 "Right_Arm_Mesh" / "Left_Arm_Mesh" 가 있는데
			--   국궁 팔 이름도 똑같아서, 그냥 두면 와키자시 팔 모션이 국궁 팔에 먹는다.
			--   팔만 칼 휘두르듯 움직이고 활은 제자리에 멈춰 있게 된다.
			--   false 면 클립 포즈를 안 먹이고 idle 자세를 유지한다.
			--   (호흡/흔들림은 카메라 기준이라 그대로 살아 있다)
			--
			--   2026-08-25 : 인트로 클립(ViewmodelAnimGukgungIntro)이 생겨서 풀었다.
			--   false 로 두면 prepareViewmodelParts 가 모든 파츠의 PoseName 을 "__noanim"
			--   으로 박아버려서, 포즈 조회 `pose[item.PoseName]` 가 항상 nil 이 된다.
			--   국궁 전용 클립까지 통째로 안 나오므로 클립이 하나라도 있으면 true 여야 한다.
			--
			--   2026-08-26 : 위 CLIPS 표로 해결됐다. 공격/막기 버튼을 눌러도
			--   와키자시 모션이 안 나온다 (국궁 클립이 없으니 아무 모션도 안 나온다).
			--   단, 뷰모델만 그렇다 — 3인칭 아바타는 AvatarAnimServer 가 아직
			--   무기 구분 없이 wakizashiattack 을 재생한다. 남들 눈엔 칼을 휘두른다.
			--
			--   추출 기준값 : 기준 프레임 60 (1 이나 10 이 아니다)
			--     회전중심 (0.106209, 0.218530, -0.140583) / posScale 240
			--     R = (x,y,z) -> (-x, z, y)
			ANIM = true,
		},
	},

	-- ===== 파츠 색상 =====
	-- 블렌더 머티리얼 색을 sRGB 로 변환한 값이다.
	-- nil 로 두거나 항목을 지우면 그 파츠는 색을 건드리지 않는다.
	--
	-- 참고: MeshPart 는 파츠당 색을 하나만 가질 수 있다.
	--   팔은 블렌더에서도 단색이라 정확히 같지만,
	--   칼은 블렌더에서 7개 머티리얼(칼날/하몬/츠바/손잡이끈/황동...)로 나뉘어 있어
	--   여기서는 가장 넓은 면적인 칼날색으로 대표시켰다.
		COLORS = {
			Right_Arm_Mesh      = { 63, 63, 69 },     -- 검은 슈트 (블렌더 Viewmodel_Suit)
			Left_Arm_Mesh       = { 63, 63, 69 },
			Wakizashi_R_Blade   = { 182, 182, 182 },  -- 칼날 강철색
			Wakizashi_L_Blade   = { 182, 182, 182 },
			Wakizashi_R_Hamon   = { 230, 230, 230 },
			Wakizashi_L_Hamon   = { 230, 230, 230 },
			Wakizashi_R_Guard   = { 36, 36, 38 },
			Wakizashi_L_Guard   = { 36, 36, 38 },
			Wakizashi_R_Wrap    = { 22, 22, 24 },
			Wakizashi_L_Wrap    = { 22, 22, 24 },
			Wakizashi_R_Brass   = { 180, 132, 55 },
			Wakizashi_L_Brass   = { 180, 132, 55 },
			Wakizashi_R_RaySkin = { 210, 210, 200 },
			Wakizashi_L_RaySkin = { 210, 210, 200 },

			-- 쿠나이는 임포트할 때 머티리얼이 안 쪼개져서 MeshPart 하나로 들어왔다.
			-- 색을 하나만 줄 수 있어서 면적이 넓은 칼날 강철색으로 대표시켰다.
			-- (검은 손잡이 끈까지 살리려면 블렌더에서 재질별로 분리해 다시 임포트해야 한다)
			Kunai               = { 176, 179, 184 },
			-- 재질별로 쪼개서 다시 임포트하면 손잡이 끈을 따로 검게 줄 수 있다
			Kunai_Steel         = { 176, 179, 184 },  -- 칼날 + 고리
			Kunai_Wrap          = { 20, 20, 23 },     -- 손잡이 끈 (검정)

			-- ===== 국궁 (korea) =====
			-- 합쳐진 MeshPart 라 파츠당 색이 하나다. 넓은 면적 기준으로 대표색을 골랐다.
			Gukgung_Bow         = { 190, 172, 157 },  -- 활 몸통
			Gukgung_String      = { 227, 218, 211 },  -- 시위
			Arrow_Gukgung       = { 120, 96, 62 },    -- 화살 (대나무 대)
		},

		-- 색과 함께 적용할 재질. nil 이면 건드리지 않는다.
		-- 금속 느낌을 주려면 "Metal", 무광이면 "Plastic".
		MATERIALS = {
			Right_Arm_Mesh      = "Plastic",
			Left_Arm_Mesh       = "Plastic",
			Wakizashi_R_Blade   = "Metal",
			Wakizashi_L_Blade   = "Metal",
			Wakizashi_R_Hamon   = "Metal",
			Wakizashi_L_Hamon   = "Metal",
			Wakizashi_R_Guard   = "Metal",
			Wakizashi_L_Guard   = "Metal",
			Wakizashi_R_Wrap    = "Plastic",
			Wakizashi_L_Wrap    = "Plastic",
			Wakizashi_R_Brass   = "Metal",
			Wakizashi_L_Brass   = "Metal",
			Wakizashi_R_RaySkin = "Plastic",
			Wakizashi_L_RaySkin = "Plastic",
			Kunai               = "Metal",
			Kunai_Steel         = "Metal",
			Kunai_Wrap          = "Plastic",

			Gukgung_Bow         = "Plastic",
			Gukgung_String      = "Plastic",
			Arrow_Gukgung       = "Plastic",
		},
}
