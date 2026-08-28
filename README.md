# ONLY ONE SHOT

**OVERDARE**(Unreal 기반 Roblox 계열 UGC 플랫폼, Luau 스크립트) 위에서 만든 근접전 FPS.
"한 방"이 승부를 가르는 검·궁 전투를 조선 산곡 지형 위에서 벌인다.

![산곡 맵 인게임](screenshots/20260826_110436.jpg)

## 현재 월드

| 항목 | 값 |
|---|---|
| 라이브 맵 | `Workspace/JSN_Sangok` — 조선 산곡, 260 × 260 m, **3,396 인스턴스** (MeshPart 1,725 / Part 1,669) |
| 그 외 Workspace | 로비, 무기 뷰모델(와키자시·국궁), 아레나 경계, 창덕궁 도착 마커 |
| ServerStorage(비활성) | 경복궁 253 · 수원 화성 배치 339 + 충돌 992 = **1,584 인스턴스** |
| 서버 스크립트 | 10종 (전투·팀·캡처·로비·경계·이동속도·사운드 등) |
| 클라이언트 | StarterPlayerScripts LocalScript 12종 |

전체 트리는 [`docs/world-tree.md`](docs/world-tree.md). Studio 프로젝트 파일(`.ovdrjm`)은
개당 29 MB의 UTF-16 JSON이라 리포에 넣지 않고, [`docs/dump_world_tree.py`](docs/dump_world_tree.py)로
요약을 재생성한다.

## 경복궁·화성이 창고에 있는 이유

둘 다 Blender에서 만들어 Studio로 임포트까지 끝냈지만 현재 월드에 없다.
화성을 `ServerStorage`로 옮긴 **그 변경 하나로 로비 프레임이 28 fps → 44 fps**가 됐다.
모바일 타깃에서 유산 스캔 기반 맵의 인스턴스 밀도가 한계였다는 뜻이고,
되살리려면 LOD·아틀라스 작업이 선행되어야 한다. 기록은 마일스톤 002·003·004에 있다.

## 구성

```
Lua/          Studio에 배포된 스크립트 41종
              서버: CombatServer, TeamServer, CaptureServer, BoundaryServer, LobbyServer,
                    MovementSpeedServer, AvatarAnimServer, RyunochiServer, SeamFiller, SoundServer
              클라: HUD, Crosshair, LobbyUI, MobileControls, FirstPersonLock, FriendlyHighlight,
                    ParryFX, BarrierFX, BoundaryFX, PerfProbe
              뷰모델 애니메이션: ViewmodelAnim* (발도·막기·쿠나이·국궁 인트로/드로우/발사)
docs/         프로젝트 현황, 마일스톤 4건, 월드 트리
screenshots/  인게임 캡처
```

## 마일스톤

| # | 내용 |
|---|---|
| [001](docs/milestones/001-war-city-remake.md) | 전쟁 폐허 도시 리메이크 (이전 베를린 맵 대체 — 현재는 이것도 교체됨) |
| [002](docs/milestones/002-gyeongbokgung-import.md) | 경복궁 임포트 완료 — 스케일 이중적용 160개 보정, 회랑 29개 복구 |
| [003](docs/milestones/003-hwaseong-v23-import.md) | 수원 화성 v23 — MODEL 150 / MeshPart 189, DEM 충돌 슬랩 992개 검증 |
| [004](docs/milestones/004-perf-and-sound.md) | 성능 개선과 사운드 레이어 |

## 관련 리포

- [overdare-map-pipeline](https://github.com/ShootTheMoon/overdare-map-pipeline) — Blender → OVERDARE 변환·배치 툴킷

## 라이선스

코드(`Lua/`, `docs/*.py`)는 MIT. 스크린샷에 보이는 3D 에셋은 국가유산청 3D 스캔(KOGL 제1유형) 기반
파생물이며, 출처 표기는 해당 에셋 팩 리포를 따른다.
