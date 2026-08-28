-- 사운드 카탈로그 (2026-08-25)
--
-- 여기만 채우면 소리가 난다. 스크립트는 더 안 고쳐도 된다.
--
-- ★ id 형식은 "ovdrassetid://<contentId>" 다.
--   MeshId / TextureId / AnimationId 와 같은 체계다 (레벨 파일에서 확인).
--   contentId 는 Studio 의 에셋 스토어에서 오디오를 고르면 나온다.
--   id 가 "" 인 슬롯은 그냥 조용히 넘어간다 — 소리 없이도 게임은 그대로 돈다.
--   무엇이 비어 있는지는 SoundClient 가 접속 10초 뒤에 한 번 찍어 준다.
--
-- ★ 엔진 동시 보이스 상한은 32 다 (로그: "Audio Mixer ... Max Channels (voices): 32").
--   10인 PvP 에서 발소리·칼질이 겹치면 금방 닿는다. SoundClient 가 24 로 잘라 쓴다.
--   그래서 "빈도 높은 소리" 일수록 cd(쿨다운)를 넉넉히 줘야 한다.
--
-- 필드
--   id    : "ovdrassetid://..."  (비우면 무음)
--   vol   : 0~1
--   min   : 이 거리(cm)까지는 원음 그대로
--   max   : 이 거리(cm)를 넘으면 안 들린다. 넘으면 아예 재생하지 않는다(보이스 절약)
--   group : "SFX" | "UI" | "Music"  (SoundGroup 으로 묶어 한 번에 볼륨을 만진다)
--   pitch : 재생속도 무작위 폭. 0.06 이면 0.94~1.06. 같은 소리 반복이 기계처럼 들리는 걸 막는다
--   cd    : 같은 이름의 최소 재생 간격(초). 연타·다중 히트로 보이스가 터지는 걸 막는다
--   loop  : 배경음처럼 물려 돌릴 것

local M = {}

-- 1 m = 100 cm. 이 맵은 산곡 260x260 m 다.
local M_ = 100

M.SOUNDS = {
	----------------------------------------------------------------- 근접 전투
	sword_swing   = { id = "", vol = 0.75, min = 3 * M_,  max = 35 * M_,  group = "SFX", pitch = 0.08, cd = 0.05 },
	sword_hit     = { id = "", vol = 0.90, min = 3 * M_,  max = 45 * M_,  group = "SFX", pitch = 0.06, cd = 0.05 },
	sword_blocked = { id = "", vol = 0.85, min = 3 * M_,  max = 45 * M_,  group = "SFX", pitch = 0.05, cd = 0.05 },
	parry_success = { id = "", vol = 1.00, min = 5 * M_,  max = 60 * M_,  group = "SFX", pitch = 0.03, cd = 0.10 },
	parry_taken   = { id = "", vol = 0.95, min = 5 * M_,  max = 60 * M_,  group = "SFX", pitch = 0.03, cd = 0.10 },
	stun          = { id = "", vol = 0.70, min = 3 * M_,  max = 30 * M_,  group = "SFX", pitch = 0.04, cd = 0.20 },

	----------------------------------------------------------------- 투척 · 활
	kunai_throw   = { id = "", vol = 0.70, min = 3 * M_,  max = 40 * M_,  group = "SFX", pitch = 0.08, cd = 0.05 },
	kunai_stuck   = { id = "", vol = 0.65, min = 2 * M_,  max = 30 * M_,  group = "SFX", pitch = 0.10, cd = 0.05 },
	bow_draw      = { id = "", vol = 0.60, min = 2 * M_,  max = 25 * M_,  group = "SFX", pitch = 0.05, cd = 0.15 },
	bow_release   = { id = "", vol = 0.80, min = 3 * M_,  max = 45 * M_,  group = "SFX", pitch = 0.06, cd = 0.05 },

	----------------------------------------------------------------- 궁극기 · 특수
	ult_ready     = { id = "", vol = 0.85, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 1.00 },
	ult_used      = { id = "", vol = 1.00, min = 10 * M_, max = 120 * M_, group = "SFX", pitch = 0,    cd = 0.50 },
	slam          = { id = "", vol = 1.00, min = 10 * M_, max = 120 * M_, group = "SFX", pitch = 0.04, cd = 0.20 },
	xblade        = { id = "", vol = 0.95, min = 8 * M_,  max = 100 * M_, group = "SFX", pitch = 0.04, cd = 0.20 },
	telegraph     = { id = "", vol = 0.80, min = 8 * M_,  max = 80 * M_,  group = "SFX", pitch = 0,    cd = 0.30 },
	raijin_tp     = { id = "", vol = 0.85, min = 5 * M_,  max = 70 * M_,  group = "SFX", pitch = 0.05, cd = 0.15 },
	raijin_throw  = { id = "", vol = 0.80, min = 5 * M_,  max = 70 * M_,  group = "SFX", pitch = 0.05, cd = 0.10 },
	barrier_auto  = { id = "", vol = 0.75, min = 3 * M_,  max = 40 * M_,  group = "SFX", pitch = 0.04, cd = 0.10 },
	barrier_block = { id = "", vol = 0.75, min = 3 * M_,  max = 40 * M_,  group = "SFX", pitch = 0.04, cd = 0.10 },

	----------------------------------------------------------------- 생사 · 점수
	kill          = { id = "", vol = 0.90, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.30 },
	death         = { id = "", vol = 0.90, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.50 },
	hurt          = { id = "", vol = 0.70, min = 0,       max = 0,        group = "UI",  pitch = 0.08, cd = 0.15 },
	score         = { id = "", vol = 0.60, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.30 },
	capture_tick  = { id = "", vol = 0.50, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.90 },
	capture_done  = { id = "", vol = 0.85, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 1.00 },
	boundary_warn = { id = "", vol = 0.70, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 1.50 },

	----------------------------------------------------------------- UI · 진행
	ui_click      = { id = "", vol = 0.55, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.04 },
	countdown     = { id = "", vol = 0.80, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 0.50 },
	match_start   = { id = "", vol = 0.90, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 2.00 },
	match_over    = { id = "", vol = 0.90, min = 0,       max = 0,        group = "UI",  pitch = 0,    cd = 2.00 },

	----------------------------------------------------------------- 이동
	-- 발소리는 이 게임에서 제일 자주 나는 소리다. 보이스 예산을 제일 먼저 먹는다.
	-- 남의 발소리는 max 를 짧게 잡아 근처 사람 것만 들리게 한다.
	footstep      = { id = "", vol = 0.45, min = 2 * M_,  max = 22 * M_,  group = "SFX", pitch = 0.12, cd = 0.18 },
	jump          = { id = "", vol = 0.50, min = 2 * M_,  max = 20 * M_,  group = "SFX", pitch = 0.10, cd = 0.20 },
	land          = { id = "", vol = 0.55, min = 2 * M_,  max = 25 * M_,  group = "SFX", pitch = 0.10, cd = 0.20 },

	----------------------------------------------------------------- 배경음
	bgm_lobby     = { id = "", vol = 0.35, min = 0,       max = 0,        group = "Music", pitch = 0, cd = 0, loop = true },
	bgm_battle    = { id = "", vol = 0.30, min = 0,       max = 0,        group = "Music", pitch = 0, cd = 0, loop = true },
}

-- CombatEvent 의 phase 를 소리 이름으로 옮긴다.
-- ★ 이렇게 두면 기존 전투/HUD 스크립트를 한 줄도 안 고쳐도 된다.
--   CombatEvent 는 이미 클라이언트로 날아오고 있으니 SoundClient 가 그걸 듣기만 하면 된다.
--   새 소리를 붙이고 싶으면 여기 한 줄만 추가해라.
M.PHASE_TO_SOUND = {
	hitmark      = "sword_hit",
	blocked      = "sword_blocked",
	block        = "sword_blocked",
	parry        = "parry_success",
	parried      = "parry_taken",
	stunfx       = "stun",
	kill         = "kill",
	killfeed     = "kill",
	score        = "score",
	capture      = "capture_tick",
	ult          = "ult_ready",
	ultused      = "ult_used",
	slam         = "slam",
	xblade       = "xblade",
	telegraph    = "telegraph",
	raijin_tp    = "raijin_tp",
	raijin_throw = "raijin_throw",
	kunai_stuck  = "kunai_stuck",
	boundary     = "boundary_warn",
	autodefence  = "barrier_auto",
	barrier      = "barrier_auto",
}

-- 그룹 기본 볼륨. 나중에 설정 UI 를 붙이면 여기를 만지면 된다.
M.GROUPS = {
	SFX   = 1.0,
	UI    = 0.9,
	Music = 0.5,
}

-- 동시에 살릴 수 있는 Sound 개수. 엔진 상한 32 보다 낮게 잡아 여유를 둔다.
M.VOICE_BUDGET = 24

return M
