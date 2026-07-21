# Spatium 앱 전체 정리본

iPhone LiDAR로 현실의 방을 스캔하고, 웹에서 가구를 배치하거나 사진 속 사물을 3D 모델로 만드는 공간 편집 플랫폼.

---

## 1. 프로젝트 소개

Spatium은 실제 공간을 디지털 3D 공간으로 옮겨 인테리어를 미리 구성해볼 수 있는 서비스다. iOS 앱이 Apple RoomPlan과 LiDAR로 방 구조를 수집하면, 웹 3D 에디터에서 그 공간에 가구를 배치·이동·회전하며 결과를 저장한다. 원하는 가구 모델이 없으면 사진을 업로드해 배경을 분리하고 GLB 3D 모델로 직접 생성할 수도 있다.

**해결하려는 문제**
- 실제 치수를 반영하지 않은 인테리어 시안은 가구 크기·동선 판단이 어렵다.
- 원하는 가구의 3D 에셋을 직접 찾거나 제작하는 과정은 일반 사용자에게 부담이 크다.
- 스캔, 편집, 사용자 제작 모델 관리가 서로 다른 도구에 흩어지기 쉽다.

→ Spatium은 **공간 스캔 → 웹 편집 → Image-to-3D → 저장과 복원**을 하나의 흐름으로 연결한다.

---

## 2. 시스템 구성

| 애플리케이션 | 역할 | 기본 포트 |
| --- | --- | ---: |
| `spatium-ios` | LiDAR 방 스캔, 프로젝트 조회, 모바일 3D 편집 | - |
| `spatium-frontend` | 웹 UI, 프로젝트 관리, 3D 공간 편집 | 3000 |
| `spatium-backend` | 인증, 프로젝트·방·가구 REST API, 파일 및 DB 관리 | 8080 |
| `spatium-img-to-3d` | 이미지 분할, 배경 제거, GLB 모델 생성 | 8000 |

### 기술 스택

- **Web**: React 19, React Router 6, Three.js, Axios, Create React App
- **Backend**: Java 17, Spring Boot 4, Spring Security, JWT, Spring Data JPA, Oracle Database, Gradle
- **AI**: Python 3.11+, FastAPI, Uvicorn, PyTorch, TripoSR, Stable Fast 3D, YOLO, GroundingDINO, SAM2, GLB/Trimesh
- **iOS**: Swift, SwiftUI, RoomPlan, RealityKit/SceneKit, GLTFKit2, iOS 17+

### 사용 흐름

1. iOS 앱에서 로그인 후 새 프로젝트 생성
2. LiDAR로 방을 스캔하고 프로젝트에 저장
3. 웹에서 같은 계정으로 로그인해 저장된 방을 엶
4. 3D 에디터에서 가구 배치·크기·위치·회전 조정
5. 필요 시 사진을 업로드해 사물을 분리하고 3D 가구 생성
6. 편집 결과 저장 후 다시 열어 이어서 수정

---

## 3. 주요 기능

### 3-1. 회원 관리 · 인증

- 일반 로그인 및 소셜 로그인(Google, Apple)
- JWT 기반 인증 — Access Token(1시간) / Refresh Token(14일) 이원화, Rotation 및 재사용 탐지
- 프로젝트·룸별 사용자 데이터 접근 제어(소유권 검증)
- 비밀번호 인코딩, 파일 업로드 검증, SQL Injection·XSS 대응 등 보안 설계

→ 상세 내용은 [`보안정리본.md`](./보안정리본.md) 참고.

### 3-2. LiDAR 공간 스캔 (iOS)

- iPhone에서 Apple RoomPlan으로 방 구조를 스캔
- USDZ 모델과 치수 metadata(JSON)를 백엔드에 업로드
- 벽·바닥·문·창문·기존 가구가 실측 크기 그대로 인식됨

### 3-3. 프로젝트 · 룸 관리

- 사용자별 프로젝트와 프로젝트 내 여러 방(룸)을 생성·조회·수정·삭제
- 룸 단건 접근 시에도 상위 프로젝트 소유권부터 확인(IDOR 방지)
- 회원 탈퇴 시 프로젝트·룸 레코드와 저장된 스캔 파일까지 함께 삭제

### 3-4. 3D 인테리어 편집 (웹)

Three.js 기반으로 직접 구현한 에디터 코어. 입력은 iOS RoomPlan 스캔 데이터(USDZ + metadata), 출력은 다시 열어 이어 편집할 수 있는 저장 포맷(JSON).

| 기능 | 설명 |
| --- | --- |
| 스캔한 방 복원 | RoomPlan USDZ + metadata를 Three.js 씬으로 복원. 벽/바닥/문/창문/기존 가구가 실측 크기 그대로 배치 |
| 가구 배치 | 카탈로그에서 선택 → 치수(cm) 입력 → 바닥 클릭으로 배치, GLB가 입력 치수에 맞게 자동 스케일 |
| 이동/회전/높이/크기 조정 | 드래그 이동, 슬라이더로 회전·높이·크기 조정, 벽 충돌 재검사 |
| 벽 충돌 방지 | 가구가 벽·문·창문을 통과할 수 없음 (OBB + Sweep 이동 제한) |
| 문/창문 편집 | 다른 모델로 교체하거나 "개구부로 남기기 / 벽으로 메우기" 선택 삭제 |
| 카메라 기준 벽 투명화 | 시야를 가리는 벽 면만 자동 투명화 |
| 측정 모드 | 방 폭/깊이/높이, 바닥 면적(㎡/평), 바닥 외곽선 표시 |
| 1인칭 시점 / Skyview | 눈높이 WASD 이동 + 드래그 시야 회전, 위에서 내려다보는 뷰 전환 |
| Undo / Redo | 추가·삭제·교체·크기 조정 결과를 snapshot 기준으로 복원 |
| 저장 & 재편집 | 편집 결과를 JSON으로 저장, 원본 USD 없이도 저장본만으로 완전 복원 |
| 사용자 가구(AI 연동) | 사진 → 배경 제거 → 3D 모델 생성 → 내 가구로 등록 → 카탈로그에서 바로 배치 |

**아키텍처**
```text
3dEditor.js (화면)                    ← 카탈로그 / 저장 버튼 / 방 전환 UI
  └─ RoomSceneEditorPage (뷰포트)     ← 선택 패널 / 회전·높이 슬라이더
       └─ useRoomSceneEditor (코어 훅) ← 편집 세션 전체를 관장
            ├─ scene/sceneLoaders     : USD/GLB/JSON 로딩
            ├─ scene/wallColliders    : 벽 판별 + 면 단위 콜라이더 생성
            ├─ scene/objectFactory    : 가구/문/창문 오브젝트 생성
            ├─ scene/collision        : OBB 충돌 판정 + 이동 제한
            ├─ scene/wallVisibility   : 카메라 기준 벽 투명화
            ├─ scene/roomMetadata     : 저장 JSON 직렬화/복원
            └─ scene/roomMeasurements : 면적/치수 계산
```
씬 그래프를 직접 다루는 로직(scene/*)과 React 상태 관리(hooks/*)를 분리해, Three.js 오브젝트는 React 밖에서 관리하고 UI에 필요한 값만 state로 동기화한다.

**핵심 기술 포인트**
- **OBB 충돌 + Sweep 이동 제한**: 회전한 가구도 정확히 판정하는 OBB로 충돌을 검사하고, 이동을 작은 step으로 쪼개 각 step마다 벽 침범 성분을 제거해 빠른 드래그에도 벽을 뚫지 못하게 한다.
- **벽 면(face) 단위 콜라이더**: 불규칙한 스캔 벽 mesh를 면 단위로 분석해, 방 안쪽 경계선 침범 여부로 판정한다. 개구부(문/창문 구멍)를 불필요하게 막지 않는다.
- **문/창문 벽 두께 자동 fitting**: RoomPlan이 두께 0으로 기록하는 문/창문을, 소속 벽의 실측 두께를 측정해 벽 중심에 맞게 재정렬한다.
- **재생 가능한 저장 포맷**: 가구뿐 아니라 방 mesh(geometry+material+transform) 자체도 JSON으로 직렬화해, 원본 USD 없이 저장본만으로 편집 세션을 완전히 재현한다.
- **카메라 기준 벽 투명화**: 매 프레임 카메라 방향과 벽 면 normal을 비교해 시야를 가리는 면만 geometry group 단위로 투명 처리한다.

→ 상세 로직·의사코드는 [`3D_MODELING_LOGIC_COMPLETE.md`](./3D_MODELING_LOGIC_COMPLETE.md), 발표용 요약은 [`3D_EDITOR_PRESENTATION.md`](./3D_EDITOR_PRESENTATION.md) 참고.

### 3-5. 사진 기반 3D 가구 생성 (Image-to-3D)

- 사물 분리: YOLO(기본) 또는 GroundingDINO + SAM2(한국어 자연어 지정 지원)
- 3D 모델 생성: TripoSR 또는 Stable Fast 3D(로컬 무료 모델)로 GLB 생성
- 입력 이미지 한 장 → 배경 제거 → GLB 모델 → 3D 에디터 카탈로그에 등록해 기존 가구와 동일하게 배치
- 입력 권장: 중앙에 위치한 단일 객체, 단순 배경, 여백 있는 PNG/JPEG/WebP. 결과 품질은 원본 이미지 품질에 크게 의존.

---

## 4. 트러블슈팅

### 4-1. 3D 에디터

| 문제 | 원인 | 해결 |
| --- | --- | --- |
| 빠르게 드래그하면 가구가 벽을 통과 | 프레임 사이 이동량이 벽 두께보다 커서 건너뜀(터널링) | 이동을 step 단위로 쪼개 sweep 방식으로 침범 성분 제거 |
| 문/창문이 벽 앞뒤로 튀어나옴 | 스캔 데이터가 두께 0 평면 + 벽 앞면 좌표 | 소속 벽의 실측 두께 측정 후 clamp + 벽 중심 재정렬 |
| 일부 GLB 가구에 정체불명의 검은/흰 판 렌더링 | 에셋 제작 툴의 UI 킷 잔여물 mesh가 GLB에 섞여 export됨 | 이름/재질 패턴 기반 아티팩트 제거를 모든 모델 로딩 경로에 적용 |
| 문/유리창의 유리가 불투명하게 렌더링 | GLB 유리 재질이 alphaMode OPAQUE로 export됨 | 재질명 기반으로 유리를 찾아 투명도 강제 적용 |
| 벽으로 메운 자리가 티 남 | 채움 mesh가 기본 색상이라 원래 벽과 이질감 | 매칭된 벽의 material을 clone해 재질까지 동일하게 적용 |
| 벽을 메운 자리에 있던 가구가 벽에 파묻힘 | 새 벽 생성 후 기존 가구 위치를 재검사하지 않음 | 콜라이더 재생성 후 전체 가구에 벽 제약을 다시 실행 |

### 4-2. 인증 및 사용자 식별

**문제**: 일반/Google/Apple 로그인을 하나의 회원 테이블로 통합해야 했는데, 이메일만으로 식별하면 provider 간 이메일 중복 가능성, Apple의 이메일 비공개 선택 시 식별 불가 상황이 발생할 수 있었다.

**해결**: `Member`에 `provider` + `provider_user_id` 컬럼을 별도로 두고, LOCAL은 이메일을, 소셜은 provider가 발급한 sub 값을 식별 키로 저장. Access/Refresh Token은 내부 `mem_id`(UUID) 기준으로 발급해 provider와 무관하게 동일한 토큰 체계를 유지한다.

→ 보안 관련 구현 상세는 [`보안정리본.md`](./보안정리본.md) 참고.

---

## 5. 참고 문서

- [`README.md`](./README.md) — 설치·실행 방법, 환경 변수, 프로젝트 구조
- [`보안정리본.md`](./보안정리본.md) — 인증·인가·보안 설계 상세
- [`3D_MODELING_LOGIC_COMPLETE.md`](./3D_MODELING_LOGIC_COMPLETE.md) — 3D 에디터 전체 로직 상세
- [`3D_EDITOR_PRESENTATION.md`](./3D_EDITOR_PRESENTATION.md) — 3D 에디터 발표/포트폴리오 요약
- [`spatium-img-to-3d/README.md`](./spatium-img-to-3d/README.md) — Image-to-3D 서버 설치·API
