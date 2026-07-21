# Spatium 3D 공간 편집 통합 가이드

> 이 문서는 `3D_EDITOR_PRESENTATION.md`, `3D_MODELING_LOGIC.md`, `3D_MODELING_LOGIC_COMPLETE.md`의 내용을 하나로 통합한 단일 기준 문서다.  
> 구현 구조, 핵심 알고리즘, 웹·iOS 차이, 저장·복원, 트러블슈팅, 발표 흐름까지 이 파일 하나에서 확인할 수 있다.

---

## 목차

1. [프로젝트 소개와 핵심 기능](#1-프로젝트-한-줄-소개)
2. [설계 원칙과 전체 아키텍처](#3-핵심-설계-원칙)
3. [데이터 흐름과 씬 초기화](#5-데이터-흐름과-진입-방식)
4. [방 Mesh와 벽 Collider](#7-방-mesh와-벽-collider)
5. [가구·문·창문 생성](#8-가구문창문-생성)
6. [선택과 transform 편집](#9-선택과-transform-편집)
7. [OBB 충돌과 Sweep 이동](#10-obb-충돌과-sweep-이동)
8. [문·창문 삭제와 벽 infill](#11-문창문-삭제와-벽-infill)
9. [꾸미기, 카메라, 측정](#12-꾸미기-모드와-피규어)
10. [Undo / Redo와 저장·복원](#14-undo--redo와-상태-관리)
11. [성능, 설정, 트러블슈팅](#16-성능과-견고성)
12. [코드 책임 맵과 의사코드](#19-코드-책임-맵)
13. [발표·포트폴리오 정리](#21-발표포트폴리오용-핵심-설명)

---

## 1. 프로젝트 한 줄 소개

**iPhone LiDAR와 RoomPlan으로 스캔한 실제 방을 3D로 복원하고, 실측 치수 기반으로 가구를 배치·편집하며, 벽 충돌과 방 구조 변경까지 반영해 다시 열 수 있는 형태로 저장하는 3D 인테리어 에디터다.**

입력과 출력은 다음과 같다.

```text
입력
  ├─ RoomPlan USDZ 공간 모델
  ├─ 방·벽·문·창문·가구의 metadata JSON
  └─ 가구 카탈로그와 GLB 모델

편집
  ├─ 추가·선택·이동·회전·높이·크기 조정
  ├─ 문·창문 교체·삭제·벽 메우기
  ├─ 벽 충돌 제한과 카메라 모드
  └─ Undo / Redo와 측정 표시

출력
  └─ 원본 공간 파일 없이도 편집 상태를 재생할 수 있는 metadata JSON
```

Spatium은 단순한 3D 뷰어가 아니다. 실제 공간의 치수와 구조를 편집 가능한 모델로 만들고, 사용자의 모든 transform을 공간 제약 안에서 처리한 뒤, 방 구조 변경을 포함한 전체 결과를 저장하는 시스템이다.

---

## 2. 핵심 기능

| 기능 | 설명 |
| --- | --- |
| 스캔 공간 복원 | RoomPlan USDZ와 metadata를 이용해 벽·바닥·문·창문·기존 가구를 실측 크기로 복원한다. |
| 가구 배치 | 카탈로그 모델을 선택하고 초기 가로·세로·높이를 입력해 바닥 중앙에 배치한다. |
| transform 편집 | 드래그 이동, Y축 회전, 수직 높이, 균일 크기 조정을 지원한다. |
| 벽 충돌 방지 | 회전을 반영하는 OBB와 Sweep 이동으로 가구가 벽을 통과하지 못하게 한다. |
| 문·창문 편집 | 같은 reference 계열로 교체하고, 삭제할 때 개구부 유지 또는 벽 메우기를 선택한다. |
| 카메라 모드 | 일반 3D, Skyview, 눈높이 1인칭 시점을 제공한다. |
| 벽 투명화 | 카메라 시야를 가리는 벽 면만 투명하게 처리한다. |
| 측정 | 방 폭·깊이·높이·면적과 선택 가구의 크기를 표시한다. |
| 꾸미기 | 전용 책장·서랍장 선반 위에 피규어를 배치하고 부모 가구와 함께 이동시킨다. |
| Undo / Redo | transform뿐 아니라 추가·삭제·교체·벽 메우기까지 snapshot으로 복원한다. |
| 저장·재편집 | 객체와 방 Mesh를 함께 직렬화해 저장본만으로 편집 세션을 복원한다. |
| 사용자 가구 | 이미지 기반 3D 생성 파이프라인과 연결된 사용자 모델도 카탈로그에서 배치한다. |

---

## 3. 핵심 설계 원칙

### 3.1 공통 편집 모델

웹과 iOS는 렌더러가 다르지만 동일한 개념 모델을 사용한다.

```text
공간(Room) + 객체(Object) + 변환값(Transform) + 제약조건(Constraint)
```

- 공간은 벽·바닥과 개구부를 포함한다.
- 객체는 일반 가구, 문·창문 reference, 피규어, 벽 infill로 구분한다.
- transform은 위치, 회전, 크기 및 실측 치수를 포함한다.
- 제약조건은 벽 충돌, 높이 범위, 표면 배치 가능 영역을 의미한다.

### 3.2 렌더러와 편집 상태 분리

렌더러는 Mesh와 Node를 표시하고, 편집 상태는 객체의 의미와 저장 가능한 값을 관리한다.

```text
편집 상태
  ├─ 객체 ID·종류·모델 경로
  ├─ position / rotation / scale
  ├─ dimensions
  └─ 교체·삭제·꾸미기 등 편집 속성

렌더러
  ├─ 웹: Three.js Object3D / Scene
  └─ iOS: SCNNode / SCNScene
```

Three.js 객체를 매 프레임 React state에 넣지 않는다. 렌더링과 드래그 중에는 ref로 직접 갱신하고, 선택 정보·충돌 요약·저장 가능 여부 등 UI에 필요한 최소 값만 state로 동기화한다. iOS에서도 SceneKit Coordinator가 실제 Node를 관리하고, 편집 완료 시 ViewModel에 결과를 반영한다.

### 3.3 단위와 좌표 규약

- 내부 계산 단위는 미터(m)다.
- UI는 센티미터(cm), 제곱미터(㎡), 평으로 변환해 표시한다.
- 바닥 평면은 X-Z, 높이는 Y축이다.
- 일반 가구 회전은 Y축 회전을 기준으로 한다.
- 가구 position은 바닥을 기준으로 한 중심 좌표로 관리한다.
- GLB의 원본 pivot에 의존하지 않고 geometry bounds로 실제 바닥 위치를 보정한다.
- 크기 변경은 세 축의 비율을 유지하는 균일 scale을 기본으로 한다.

이 규약이 RoomPlan, GLB, Three.js, SceneKit 사이의 좌표 불일치를 방지한다.

---

## 4. 전체 아키텍처

### 4.1 웹

```text
3dEditor.js
  ├─ 프로젝트·방 정보 로딩
  ├─ 가구 카탈로그 로딩
  ├─ 저장·취소·방 전환 UI
  └─ RoomSceneEditorPage
       ├─ 뷰포트와 편집 패널
       ├─ 1인칭·Skyview·측정 UI
       └─ useRoomSceneEditor
            ├─ Three.js scene / camera / renderer / OrbitControls
            ├─ 방 모델과 metadata 로딩
            ├─ 가구·문·창문 Object3D 생성
            ├─ pointer 기반 선택·이동·회전
            ├─ 벽 face Collider와 OBB 충돌
            ├─ 벽 투명화·측정·꾸미기
            ├─ Undo / Redo snapshot
            └─ replayable metadata 저장
```

| 계층 | 책임 |
| --- | --- |
| `3dEditor.js` | 라우트 데이터, 프로젝트·방, 카탈로그, 저장 버튼 |
| `RoomSceneEditorPage.js` | Three.js 뷰포트, 선택 패널, 슬라이더, 사용자 안내 |
| `useRoomSceneEditor.js` | 씬·입력·충돌·편집·저장을 연결하는 세션 orchestration |
| `hooks/*` | 선택, scene config, Skyview 등 UI와 세션의 부분 상태 |
| `scene/*` | 모델 생성, 충돌, 직렬화, 표시, 측정 등 순수 로직 |

### 4.2 iOS

```text
RoomEditorView
  └─ RoomEditorSceneView (UIViewRepresentable)
       └─ Coordinator
            ├─ SceneKit scene / camera / gesture
            ├─ USDZ room shell 로딩
            ├─ FurnitureModelLoader (GLTFKit2)
            ├─ hitTest 기반 선택·이동
            ├─ WallCollider + FurnitureFootprint
            └─ RoomEditorViewModel
                 ├─ RoomLayout
                 ├─ transform·선택 상태
                 ├─ Undo / Redo
                 ├─ local draft
                 └─ metadata 저장
```

### 4.3 웹과 iOS의 대응 관계

| 단계 | 웹 | iOS | 공통 의미 |
| --- | --- | --- | --- |
| 공간 렌더링 | Three.js Scene | SceneKit SCNScene | 방 shell과 객체 표시 |
| 모델 로딩 | USDLoader / GLTFLoader | USDZ / GLTFKit2 | 공간·가구 모델 로드 |
| 선택 | Raycaster | `SCNView.hitTest` | 편집 객체 식별 |
| 바닥 이동 | Ray와 Plane 교차 | floor Node hitTest | 입력을 월드 좌표로 변환 |
| transform | Object3D transform | SCNNode transform | 위치·회전·크기 변경 |
| 충돌 | OBB + face Collider | Footprint + WallCollider | 벽 통과 방지 |
| 상태 저장 | `_spatiumRoom` metadata | `RoomLayout` + `editedObjects` | 편집 결과 재현 |

웹과 앱의 주요 차이는 렌더러, 입력 방식, 로컬 Draft 정책이다. 핵심 transform과 제약 의미는 같다. 앱은 서버 저장 전 종료에 대비한 로컬 Draft를 제공하고, 웹은 미저장 변경 경고를 사용한다.

---

## 5. 데이터 흐름과 진입 방식

```text
RoomPlan 스캔
  ↓
USDZ 공간 모델 + metadata JSON
  ↓
프로젝트 / 룸 조회
  ↓
방 shell 로딩과 Mesh 분류
  ↓
metadata로 가구·문·창문 복원
  ↓
선택·이동·회전·높이·크기 편집
  ↓
충돌과 제약을 통과한 transform 반영
  ↓
객체와 방 변경 사항 직렬화
  ↓
서버 저장
  ↓
다음 진입 시 저장본 우선 복원
```

### 5.1 웹 진입 데이터

웹은 URL query의 `projectId`, `roomId`로 대상을 결정한다.

```text
/member/editor?projectId=...&roomId=...
```

| 데이터 | 호출 또는 출처 | 용도 |
| --- | --- | --- |
| 프로젝트 정보 | `getProjectInfo(projectId)` | 프로젝트명 표시 |
| 방 씬 데이터 | `getRoomSceneData(roomId)` | 방 모델과 metadata |
| 방 목록 | `getRoomList(projectId)` | 방 전환 |
| 가구 카탈로그 | `/data/furniture_catalog.json` | 추가·교체 모델 |
| scene config | `room-scene-config.json` | URL·색상·충돌 파라미터 |

### 5.2 방 모델 복원 우선순위

초기 소스 후보는 다음과 같다.

1. API 응답의 `roomScene.model.dataBase64`
2. scene config의 `room.modelUrl`
3. metadata의 `_spatiumRoom`

실제 표시 단계에서는 `_spatiumRoom`이 존재하면 저장된 방을 원본 USD보다 우선한다. 벽 메우기, 벽 색상, 방 Mesh 변경을 포함한 편집 결과를 보존하기 위해서다.

### 5.3 앱 진입 모드

- **서버 룸 모드**: 서버에서 layout과 metadata를 조회해 기존 방을 편집한다.
- **스캔 직후 모드**: 서버에 아직 업로드하지 않은 USDZ와 `EditableScanItem`으로 편집을 시작하고, 저장 시 새 룸으로 업로드한다.

`RoomEditorViewModel`은 원격 조회 여부, 오프라인 상태, 대상 room ID와 Draft를 모드별로 관리한다.

---

## 6. 씬 초기화

### 6.1 웹 초기화 순서

```text
loadSceneConfig()
  ↓
WebGLRenderer / CSS2DRenderer / Scene / Camera / OrbitControls 생성
  ↓
방 모델과 metadata 병렬 로딩
  ↓
_spatiumRoom이 있으면 저장된 JSON 방 복원
  ↓
prepareRoomModel()
  ↓
createWallColliders()
  ↓
가구·문·창문 생성
  ↓
initializeWallConstraints()
  ↓
카메라 framing, 첫 선택과 UI 상태 동기화
```

웹 씬은 역할별 레이어로 분리한다.

| 레이어 | 내용 |
| --- | --- |
| `worldGroup` | 방 shell과 바닥 |
| `furnitureLayer` | 일반 가구 |
| `referenceLayer` | 문·창문 reference |
| `selectionLayer` | 선택 edge와 보조 표시 |
| `wallDiagnosticLayer` | Collider 디버그 표시 |
| `roomMeasurementLayer` | 치수선·라벨·면적 |

### 6.2 iOS 씬 초기화

- 스캔 방은 USDZ shell의 벽·바닥을 배경으로 사용하고 감지 가구는 별도 GLB Node로 복원한다.
- 서버 layout에 방 shell이 없으면 면적과 천장 높이로 기본 박스 방을 만든다.
- 위치·회전만 바뀌면 기존 Node를 재사용한다.
- 추가·삭제·교체처럼 구조가 바뀔 때만 필요한 Node를 재생성한다.

---

## 7. 방 Mesh와 벽 Collider

### 7.1 Mesh 분류

`prepareRoomModel()`은 방 hierarchy를 순회하며 이름 패턴과 `userData`로 Mesh를 분류한다.

- 벽 Mesh: `isUsdWallMesh()`
- 바닥 Mesh: `isUsdFloorMesh()`
- 저장에서 제외할 교체 Mesh: `isUsdReplacedMesh()`
- 기타 방 Mesh와 reference 관련 Mesh

이 결과는 Collider 생성, 방 측정, 벽 색상, `_spatiumRoom` 저장에서 재사용한다.

### 7.2 벽 전체 박스가 아닌 face 단위 Collider

스캔 벽은 반듯한 직육면체가 아니라 삼각형 Mesh다. Mesh 전체 bounds 하나를 Collider로 쓰면 문·창문 개구부까지 막고, ㄱ자 벽이나 불규칙한 벽 주변에서 잘못된 충돌이 생긴다.

따라서 `createWallColliders(roomModel)`은 벽 삼각형을 분석해 실제 벽 면 단위 Collider 생성을 시도한다.

| 필드 | 의미 |
| --- | --- |
| `obb` | 벽 face의 충돌 영역 |
| `spanAxes` | 길이·높이 overlap 판정 축 |
| `spanPolygon` | 벽 면을 2D로 투영한 경계 |
| `roomFacingNormal` | 방 안쪽 방향 |
| `roomFacingProjection` | 방 내부 경계 projection |
| `triangleStart`, `triangleCount` | face preview용 triangle 범위 |
| `object` | 원본 wall Mesh |

face 분석이 어려운 Mesh는 geometry bounds 기반 OBB로 fallback한다. 이중 경로로 일반 USD와 예외 Mesh를 모두 처리한다.

### 7.3 방 안쪽 경계 기준 판정

벽과 가구의 박스가 단순히 교차하는지만 보지 않고, 가구 footprint가 방 안쪽 경계를 넘었는지 검사한다.

```text
가구 중심과 roomFacingNormal 비교
  ↓
가구 OBB를 normal 방향으로 투영
  ↓
벽의 room-facing projection과 비교
  ↓
경계를 넘는 inward 이동 성분 제한
```

이 방식은 벽 바깥쪽이나 문·창문 개구부 근처의 불필요한 차단을 줄인다.

---

## 8. 가구·문·창문 생성

### 8.1 일반 가구 생성

일반 가구는 `sourceType: "object"`이며 추가·이동·회전·높이·크기·삭제·교체가 가능하다.

| 함수 | 결과 |
| --- | --- |
| `createEditableFurniture()` | 모델이 없을 때 dimensions 기반 fallback box |
| `createEditableFurnitureModel()` | GLB clone과 실측 크기 보정이 적용된 객체 |

GLB 생성 순서는 다음과 같다.

1. 카탈로그에서 모델 URL 또는 경로를 찾는다.
2. 캐시된 GLB template의 scene을 clone한다.
3. hierarchy 전체 geometry bounds를 계산한다.
4. `fitModelToTargetSize()`로 metadata 또는 사용자 입력 치수에 맞춘다.
5. pivot을 보정해 바닥면이 객체 position의 Y에 닿게 한다.
6. bounds에서 충돌용 `localObb`를 만든다.
7. 보이지 않는 pick hit box와 선택·충돌 edge를 만든다.
8. root `userData`에 편집 정보와 원본 transform을 기록한다.

### 8.2 GLB 정리와 재질 보정

- 제작 도구의 UI 잔여 Mesh가 함께 export된 경우 이름·재질 패턴으로 제거한다.
- 문·창문 유리가 OPAQUE로 저장되었으면 재질 이름을 기준으로 투명도를 보정한다.
- 재질은 인스턴스별로 clone해 한 모델의 변경이 다른 인스턴스로 전파되지 않게 한다.
- 모델 로드에 실패해도 입력 dimensions의 fallback box로 편집을 계속한다.

### 8.3 문·창문 reference

문과 창문은 `sourceType: "door"`, `sourceType: "window"`인 방 구조 reference다.

- 일반 가구처럼 이동하거나 높이를 조정하지 않는다.
- 같은 reference 계열의 다른 모델로 교체할 수 있다.
- 삭제 시 개구부 유지와 벽 메우기 중 선택한다.
- 일반 가구의 이동·회전·높이·크기 충돌 검사에서는 문·창문의 world OBB도 장애물로 포함한다.
- reference 자신은 움직이는 충돌 제약 대상에서 제외된다.

```text
activeColliders()
  = wallColliders
  + referenceRoots의 world OBB
```

reference Collider는 `roomFacingNormal` 없이 단순 OBB 교차로 판정한다.

### 8.4 문·창문 벽 두께 fitting

RoomPlan은 문·창문을 `dimensions.z = 0`에 가까운 평면으로 기록하고, 위치를 벽 앞면 기준으로 저장할 수 있다. 고정 fallback 두께를 좌우 대칭 적용하면 모델이 벽 앞뒤로 튀어나온다.

이를 막기 위한 흐름은 다음과 같다.

```text
문·창문 저장 위치
  ↓
nearestWallMesh()
  벽 Mesh의 world Box3와 위치 간 거리로 가장 가까운 벽 선택
  ↓
localThicknessAxis()
  벽 로컬 bounds의 가장 짧은 축을 두께 방향으로 선택
  ↓
geometryProjectionRange()
  전체 벽 정점을 축에 투영해 실제 min / max / center 측정
  ↓
fitReferenceToWallThickness()
  모델 두께를 실측 두께에서 margin을 뺀 값 이하로 clamp
  ↓
reference 위치를 벽 두께 중심으로 재정렬
```

문·창문은 개구부 위에 있어 face triangle과 직접 겹치지 않을 수 있으므로, 소속 벽 탐색에는 face Collider가 아닌 벽 Mesh 전체 bounds를 사용한다. 0.5m 안에 적절한 벽이 없으면 기존 위치와 fallback 두께를 유지한다.

---

## 9. 선택과 transform 편집

### 9.1 선택

웹은 pointer down 시 Raycaster로 pick target을 찾고 `userData.editableRoot`를 따라 실제 편집 root를 선택한다. iOS는 `SCNView.hitTest`를 사용한다.

선택 시 갱신되는 값은 다음과 같다.

- ID, source type, category
- dimensions와 현재 transform
- 회전·높이·크기 슬라이더 값
- 교체·삭제·꾸미기 가능 여부
- 충돌 상태와 선택 edge

### 9.2 바닥 이동

드래그 시작점과 객체 중심의 offset을 보존해 선택 순간 객체가 포인터 중심으로 튀지 않게 한다.

```text
pointer / touch 시작
  ↓
editable root와 grab offset 저장
  ↓
현재 입력을 바닥 X-Z 좌표로 변환
  ↓
목표 position과 movement vector 계산
  ↓
constrainedMovementBeforeWallCollision()
  ↓
허용된 이동만 객체와 편집 상태에 반영
```

드래그 이동 중 Y는 시작 높이로 고정된다. 수직 이동은 별도 높이 제어만 사용한다.

### 9.3 높이

`setSelectedElevationCm()`은 바닥에서 가구 하단까지의 간격을 cm로 받는다.

```text
최소 높이 = 0
최대 높이 = 천장 Y - 바닥 Y - 가구 높이
```

일반 가구만 사용할 수 있고, 적용 후 벽·reference와 충돌하면 이전 위치로 되돌린다. 자동 벽 스냅은 없으며 사용자가 직접 값을 지정한다.

### 9.4 회전

- 회전은 Y축 기준이다.
- 웹은 드래그 angle delta와 슬라이더 직접 입력을 지원한다.
- iOS는 `-180, -90, 0, 90, 180`도 근처에서 스냅한다.
- 적용 후 충돌하면 마지막 유효 quaternion 또는 각도로 rollback한다.

### 9.5 크기

- 새 가구 추가 모달은 초기 가로·세로·높이를 정한다.
- 배치 후 크기 슬라이더는 선택 객체의 가장 긴 변을 기준으로 root scale을 균일하게 바꾼다.
- 객체 비율과 하단 높이를 유지한다.
- 변경된 footprint가 벽이나 reference와 충돌하면 마지막 유효 크기로 되돌린다.

---

## 10. OBB 충돌과 Sweep 이동

### 10.1 AABB를 사용하지 않는 이유

AABB는 월드 축에 정렬되어 있어 회전된 가구의 실제 폭과 깊이를 정확히 표현하지 못한다. 가구가 벽에 닿기 전에 막히거나, 반대로 회전된 모서리가 벽을 통과할 수 있다.

Spatium은 객체의 local OBB를 world transform으로 변환한다.

```text
object.userData.localObb + object.matrixWorld = world OBB
```

웹은 Three.js OBB를 사용하고, iOS는 동일한 의미를 `FurnitureFootprint`로 계산한다.

### 10.2 벽 방향 projection

```text
halfWidth + halfDepth + rotationY
  ↓
벽 normal 방향 projection radius 계산
  ↓
벽 span과 높이 overlap 확인
  ↓
room-facing boundary 침범 여부 판정
```

### 10.3 Sweep 이동

한 프레임의 이동량이 벽 두께보다 크면 객체가 벽을 건너뛰는 tunneling이 생긴다. 따라서 요청 이동을 `sweepStep` 크기의 작은 이동으로 나눈다.

```text
요청 movement
  ↓
작은 step으로 분할
  ↓
각 step에서 모든 active collider 검사
  ↓
벽 안쪽으로 향하는 성분 제거
  ↓
접선 방향은 유지해 벽을 따라 slide
  ↓
허용된 step 누적
```

충돌 뒤 전체 이동을 취소하는 방식이 아니라, 충돌 지점까지 이동하고 벽에 붙은 채 평행 이동할 수 있게 한다.

### 10.4 초기 침투 해소

추가·교체·크기 확대 또는 새 벽 infill 생성 직후 객체가 이미 벽 안에 있을 수 있다.

```text
현재 footprint 계산
  ↓
침범한 Collider 검색
  ↓
침투량 × roomFacingNormal만큼 방 안쪽으로 이동
  ↓
전체 Collider 재검사
  ↓
침투가 없어질 때까지 제한 횟수 내 반복
```

### 10.5 충돌 상태 표시

`refreshCollisionState()`가 객체에 충돌 요약을 기록한다.

```js
object.userData.collisions = ["wall"];
```

`showCollisionHighlight`가 활성화되면 edge나 fallback fill을 충돌 색상으로 바꾸고, 비활성화 시 선택 edge를 유지한다.

---

## 11. 문·창문 삭제와 벽 infill

문·창문 삭제는 `deleteSelectedReference(fillWithWall)`의 두 경로로 나뉜다.

### 11.1 개구부 유지

`fillWithWall: false`이면 reference Object만 제거하고 기존 방 Mesh의 구멍은 남긴다. 현재 문·창문 목록을 그대로 저장하므로 재로딩 후에도 reference가 다시 생기지 않는다.

### 11.2 벽으로 메우기

`fillWithWall: true`이면 다음 순서로 실제 벽 구조를 변경한다.

1. reference의 `localObb`에서 가로·높이를 구하고 약간의 padding을 더한다.
2. `measureWallThicknessAtPosition()`으로 소속 벽의 두께와 중심을 측정한다.
3. `createWallInfillMesh()`로 채움 box를 만든다.
4. 매칭 벽 material을 clone해 색상·roughness·metalness·texture를 유지한다.
5. `userData.isUsdWallMesh = true`를 설정해 일반 벽으로 취급한다.
6. reference를 제거한다.
7. 모든 벽 Collider를 다시 생성한다.
8. 기존 가구에 `initializeWallConstraints()`를 다시 적용한다.

infill 이름은 `Infill_...` 패턴을 사용해 교체된 Door·Window Mesh로 잘못 분류되어 저장에서 빠지지 않게 한다. 생성한 Mesh는 `_spatiumRoom.walls`에 포함되므로 다시 열어도 벽으로 남는다.

---

## 12. 꾸미기 모드와 피규어

꾸미기는 전용 모델 경로의 책장·서랍장처럼 실제 선반 표면이 있는 가구만 지원한다.

### 12.1 진입과 카메라

1. 꾸미기 가능한 가구를 선택한다.
2. 현재 카메라와 OrbitControls 제한을 저장한다.
3. 가구 정면에서 약 25도 위의 시점으로 전환한다.
4. orbit을 정면 기준 좌우·상하 제한과 근접 줌 범위로 제한한다.
5. 카탈로그를 사용자 가구와 `figure` 항목으로 바꾼다.
6. 완료 시 원래 카메라와 제어 범위를 복원한다.

`computeDecorView()`는 가구 로컬 +Z와 방 중심을 이용해 정면을 결정하고, OBB가 카메라 FOV 안에 들어오는 거리를 계산한다.

### 12.2 표면 배치와 이동 제한

- 투명 hit box가 아닌 실제 가구 triangle Mesh에 Raycast한다.
- 월드 normal의 Y가 0.7 이상인 위쪽 면만 선반 표면으로 인정한다.
- 최초 클릭 지점의 support point에 피규어를 배치한다.
- 허공이나 옆면으로 끌면 현재 선반 높이의 평면과 입력 Ray를 교차시킨다.
- `constrainedSupportPoint()`가 step 분할과 축별 slide를 적용해 표면 가장자리까지만 이동시킨다.
- 피규어는 일반 벽 OBB 충돌 대상이 아니라 부모 가구의 유효 표면 제약을 사용한다.

### 12.3 부모·자식과 저장

웹의 피규어는 `sourceType: "figure"`이며 가구 root의 자식으로 붙는다. 부모가 이동·회전하면 함께 움직인다. `objectToEditableJson()`은 부모 항목의 `decorations` 배열에 피규어의 부모 로컬 transform을 저장하고, 복원 시 가구 생성 후 다시 부착한다.

피규어는 회전·교체·삭제와 균일 크기 조정을 지원한다. 크기 변경 시 하단이 선반 표면에 붙어 있도록 Y도 보정한다. 부모 가구를 다른 모델로 교체하면 기존 피규어는 함께 삭제된다.

iOS는 부모의 비균일 scale이 자식 모델을 찌그러뜨리지 않도록 별도 decor container를 부모 transform과 동기화한다.

---

## 13. 카메라, 벽 표시, 측정

### 13.1 카메라 모드

| 모드 | 동작 |
| --- | --- |
| 일반 3D | OrbitControls 또는 SceneKit 기본 카메라 제어 |
| Skyview | 방 전체를 위에서 내려다보는 시점 |
| 1인칭 | 눈높이 고정, 방 bounds 안에서 이동, 드래그로 시야 회전 |

웹 1인칭은 WASD·방향키로 카메라가 보는 수평 방향을 기준으로 이동한다. Skyview 전환 전에는 position, target, 제어 제한을 저장하고 복귀 시 복원한다.

### 13.2 카메라 기준 벽 투명화

`updateViewFacingWalls()`는 매 프레임 카메라 방향과 벽 face normal을 비교한다.

- triangle 정보가 있으면 geometry group별 material index를 바꿔 해당 면만 투명화한다.
- face 정보가 부족하면 벽 Object 전체 opacity를 낮춘다.
- 문·창문 reference가 시야를 가릴 때도 같은 기준으로 투명화한다.

벽 전체를 숨기지 않고 시야를 가리는 면만 처리해 3인칭 인테리어 뷰가 자연스럽게 유지된다.

### 13.3 벽 색상

`applyRoomWallColor()`는 모든 wall material에 선택 색상을 적용한다. 투명화 preview 복원 후에도 색상이 유지되도록 original material state에도 반영한다. 새 infill 생성 뒤에도 다시 적용한다.

### 13.4 측정

`calculateRoomMeasurements()`는 바닥 triangle과 외곽선을 분석한다.

| 값 | 의미 |
| --- | --- |
| `width` | 방 폭 |
| `depth` | 방 깊이 |
| `height` | 방 높이 |
| `area` | 바닥 면적 |
| `areaSource` | `floor` 또는 `bounds` fallback |
| `outlineSegments` | 바닥 외곽선 |
| `heightSegment` | 높이 측정선 |

웹은 CSS2DRenderer, iOS는 SceneKit 선·텍스트 Node를 사용한다. 단순 전체 bounds보다 바닥 외곽과 벽 segment를 우선해 불규칙한 방에서도 안정적인 값을 만든다.

---

## 14. Undo / Redo와 상태 관리

### 14.1 Snapshot 범위

Undo / Redo는 단순 transform 배열이 아니라 replayable metadata snapshot을 사용한다.

- 일반 가구와 문·창문 목록
- 피규어와 부모 로컬 transform
- 추가·삭제·교체 결과
- 벽 infill과 방 Mesh
- 벽 색상
- 객체별 transform과 dimensions

### 14.2 복원 전략

- 객체 수, 모델, 방 구조가 같고 transform만 바뀌면 기존 Node에 transform만 적용한다.
- 추가·삭제·교체·벽 메우기처럼 구조가 바뀌면 씬을 재생성한다.
- 슬라이더의 연속 입력은 하나의 history transaction으로 묶어 한 번의 Undo로 돌아가게 한다.
- iOS는 이력을 약 30개 수준으로 제한하고 로컬 Draft와 별도로 관리한다.

---

## 15. 저장과 복원

### 15.1 객체 저장 단위

```json
{
  "id": "object-id",
  "sourceType": "object",
  "name": "bed",
  "modelUrl": ".../bed.glb",
  "dimensions": { "x": 1.24, "y": 0.70, "z": 1.97 },
  "position": { "x": 0.4, "y": 0.0, "z": -0.6 },
  "rotation": { "x": 0, "y": 1.57, "z": 0 },
  "scale": { "x": 1, "y": 1, "z": 1 }
}
```

`objectToEditableJson()`은 ID, source type, catalog 정보, 모델 URL, m·cm dimensions, position, rotation, transform matrix columns, collision, decorations 등을 직렬화한다.

### 15.2 방 Mesh 직렬화

`serializeRoomModelToJson()`은 현재 방을 `_spatiumRoom`에 저장한다.

- 벽, 바닥, 기타 room Mesh
- position, normal, UV, index geometry attribute
- world matrix와 transform
- material 정보
- 벽·바닥 판별 metadata

`createRoomModelFromJson()`은 이 정보를 Three.js Group으로 복원하고 Collider와 측정에 필요한 `userData`도 되살린다.

### 15.3 replayable metadata

`createReplayableMetadataJson()`은 기존 metadata를 clone한 뒤 현재 씬의 실제 상태로 갱신한다.

| 필드 | 내용 |
| --- | --- |
| `objects` | 현재 일반 가구와 decorations |
| `doors` | 현재 남아 있는 문 reference |
| `windows` | 현재 남아 있는 창문 reference |
| `_spatiumRoom` | 현재 방 geometry·material·transform |
| `_spatiumExport` | 버전, 시간, scene config, 모델 URL, 편집 항목 |

현재 문·창문 목록을 그대로 저장하므로 reference 삭제가 재로딩 후 되돌아오지 않는다. 벽 infill은 방 Mesh 안에 저장한다.

### 15.4 웹 저장 API

```text
현재 씬 순회
  ↓
객체·reference·decor 직렬화
  ↓
방 Mesh 직렬화
  ↓
FormData 생성
  ├─ projectId
  ├─ roomId
  ├─ area (optional)
  └─ metadata.json Blob
  ↓
POST /api/rooms/save
```

### 15.5 iOS 저장과 Draft

iOS는 편집 상태를 `RoomLayout`으로 관리하고 서버에는 `editedObjects` metadata로 내보낸다. 스캔 직후 모드는 USDZ와 metadata를 함께 업로드해 새 룸을 만든다.

안전장치는 다음과 같다.

- 저장 전 fingerprint로 변경 여부 비교
- Undo / Redo history
- 임시 Draft 파일 저장
- 앱 재진입 시 복구 가능한 Draft 탐지
- 서버 저장 성공 후 Draft 제거

### 15.6 복원 우선순위

```text
저장 metadata의 방·객체 정보
  ↓ 없으면
원본 USDZ + 원본 metadata
  ↓ 없으면
기본 박스 방 + fallback object
```

저장본 우선 정책이 가구 삭제, reference 교체, 벽 infill, 사용자 모델과 색상 변경을 보존한다.

---

## 16. 성능과 견고성

### 16.1 모델 캐시

같은 GLB를 매번 파싱하지 않고 template을 캐시한 뒤 clone한다. iOS는 메모리 경고 시 template cache를 비워 피크 메모리를 낮춘다.

### 16.2 증분 갱신

- 위치·회전·크기만 바뀌면 기존 Mesh·Node의 transform만 갱신한다.
- 추가·삭제·교체·방 구조 변경 때만 필요한 Node나 씬을 재생성한다.
- 정적인 문·창문 Collider는 캐시할 수 있다.
- 벽 Collider 전체 재생성은 벽 infill처럼 방 구조가 바뀔 때 수행한다.

### 16.3 리소스 정리

객체 삭제와 씬 종료 시 geometry, material, texture를 dispose한다. Pointer capture, CADisplayLink, gesture recognizer도 종료 시 해제한다.

---

## 17. 설정 파일

웹 설정 위치:

```text
spatium-frontend/public/config/room-scene-config.json
```

| 키 | 의미 |
| --- | --- |
| `models` | category별 기본 GLB URL |
| `colors.category` | fallback box 색상 |
| `colors.collision` | 충돌 edge 색상 |
| `colors.collisionFill` | 충돌 fill 색상 |
| `colors.selectedEdge` | 선택 edge 색상 |
| `colors.defaultEdge` | 기본 edge 색상 |
| `colors.doorReference` | 문 reference 색상 |
| `colors.windowReference` | 창문 reference 색상 |
| `referenceFallbackThickness` | 벽 탐색 실패 시 문·창문 두께 |
| `debug.showReferenceLabels` | reference 방향 디버그 라벨 |
| `debug.showCameraAngle` | 카메라 yaw·pitch 표시 |
| `wallConstraints.collisionEpsilon` | OBB 교차 허용 오차 |
| `wallConstraints.sweepStep` | 이동 Sweep step |
| `wallConstraints.sweepRotationStepDegrees` | 회전 Sweep 설정 |
| `wallConstraints.colliderHalfThickness` | Collider 최소 반두께 |
| `wallConstraints.boundaryEpsilon` | 방 안쪽 경계 허용 오차 |
| `wallConstraints.boundarySpanPadding` | 벽 span overlap padding |
| `wallConstraints.logWallDiagnostics` | 충돌 진단 로그 |
| `wallConstraints.showColliderDebug` | Collider 시각화 |
| `wallConstraints.showCollisionHighlight` | 충돌 바운딩 박스 강조 여부 |

`showWallDiagnostics`, `clampIterations`, `sweepMaxSteps` 같은 호환 설정도 남아 있지만 핵심 흐름은 위 항목을 중심으로 동작한다.

---

## 18. 주요 문제와 해결

| 문제 | 원인 | 해결 |
| --- | --- | --- |
| 빠른 드래그 시 벽 통과 | 프레임 간 이동량이 벽보다 큼 | 이동 벡터를 step으로 나누는 Sweep 적용 |
| 회전 가구가 너무 일찍 막히거나 파묻힘 | AABB가 회전을 반영하지 못함 | local OBB와 회전 footprint 사용 |
| 문·창문이 벽 앞뒤로 튀어나옴 | RoomPlan이 평면·벽 앞면 좌표로 저장 | 실제 벽 두께 측정, clamp, 중심 재정렬 |
| 개구부까지 충돌로 막힘 | 벽 Mesh 전체 bounds 사용 | triangle 기반 벽 face Collider 생성 |
| 일부 GLB에 검은 판·UI 잔여물이 보임 | 제작 도구 Mesh가 함께 export됨 | 이름·재질 패턴 기반 아티팩트 제거 |
| 유리가 불투명함 | GLB alphaMode가 OPAQUE | 유리 재질 탐지 후 투명도 보정 |
| 벽 infill 색이 주변과 다름 | 기본 재질로 새 Mesh 생성 | 소속 벽 material clone 사용 |
| 벽을 메운 뒤 기존 가구가 파묻힘 | Collider 변경 후 재검사 누락 | Collider 재생성 후 전체 penetration resolve |
| 앱 종료 후 미저장 편집 소실 | 서버 저장 전 프로세스 종료 | 로컬 Draft 저장·복구 |

이 문제 해결 과정에서 나온 핵심 원칙은 다음과 같다.

1. 스캔 데이터는 이상적인 CAD가 아니므로 bounds fallback과 실측 보정이 필요하다.
2. 충돌은 현재 위치의 교차만 볼 것이 아니라 이동 경로까지 검사해야 한다.
3. 방 구조 변경은 시각 Mesh, Collider, 기존 객체, 저장 metadata를 함께 갱신해야 한다.
4. 외부 GLB는 geometry뿐 아니라 이름·재질·alpha 설정도 정규화해야 한다.

---

## 19. 코드 책임 맵

### 19.1 웹

| 하고 싶은 일 | 파일 |
| --- | --- |
| 에디터 화면·프로젝트·저장 UI | `spatium-frontend/src/pages/3dEditor.js` |
| 뷰포트·선택 패널·슬라이더 | `spatium-frontend/src/pages/roomSceneEditor/RoomSceneEditorPage.js` |
| 편집 세션 orchestration | `spatium-frontend/src/pages/roomSceneEditor/hooks/useRoomSceneEditor.js` |
| 선택·replace 상태 | `hooks/useSelectionState.js` |
| scene config 상태 | `hooks/useSceneConfigStatus.js` |
| Skyview 전환 | `hooks/useSkyviewMode.js` |
| transform·dimensions 계산 | `scene/editorTransforms.js` |
| 방·GLB·JSON 로딩과 저장 호출 | `scene/sceneLoaders.js` |
| 가구·문·창문 생성 | `scene/objectFactory.js` |
| 벽 Collider 생성 | `scene/wallColliders.js` |
| OBB 충돌과 이동 제한 | `scene/collision.js` |
| 저장·복원 직렬화 | `scene/roomMetadata.js` |
| 벽 투명화·색상 | `scene/wallVisibility.js`, `scene/floorColor.js` |
| reference 표시 | `scene/referenceVisibility.js` |
| 방 치수·면적 | `scene/roomMeasurements.js`, `scene/measurementLabels.js` |
| 꾸미기 표면 제약 | `scene/decorSurface.js` |
| 꾸미기 카메라 | `scene/decorCamera.js` |
| 카메라 애니메이션 | `scene/cameraTransitions.js` |
| 공통 Three.js 유틸 | `scene/threeUtils.js` |

### 19.2 iOS

| 역할 | 파일 |
| --- | --- |
| 편집 상태·저장·Undo / Redo | `Features/Editor/RoomEditorViewModel.swift` |
| SceneKit 씬·제스처·카메라 | `Features/Editor/RoomEditorSceneView.swift` |
| SwiftUI 편집 화면 | `Features/Editor/RoomEditorView.swift` |
| GLB 로딩·bounds·pivot | `Core/Services/FurnitureModelLoader.swift` |
| layout·transform 모델 | `Core/Models/RoomLayout.swift` |
| 스캔 객체 metadata | `Core/Models/EditableScanItem.swift` |
| 저장 요청 추상화 | `Core/Services/RoomEditorService.swift` |

---

## 20. 전체 로직 의사코드

```text
openRoom(roomId):
  roomData = fetchRoomScene(roomId)
  metadata = fetchMetadata(roomId)

  scene = createRendererScene()
  roomModel = restoreSavedRoom(metadata._spatiumRoom)
              ?? loadUsdRoom(roomData)
              ?? createFallbackRoom()

  prepareRoomModel(roomModel)
  wallColliders = createWallColliders(roomModel)
  objects = restoreObjects(metadata)

  for item in objects:
    model = loadOrFallbackModel(item)
    fitModelToDimensions(model, item.dimensions)

    if item is door or window:
      fitReferenceToWallThickness(model, roomModel)

    createPickTargetAndLocalObb(model)
    addToScene(model)

  initializeWallConstraints(activeColliders())
  frameRoomOrFirstObject()

onPointerMove(pointer):
  object = selectedEditableRoot()
  proposed = projectPointerToFloor(pointer, grabOffset)
  movement = proposed - object.position
  allowed = constrainedMovementBeforeWallCollision(
    object,
    movement,
    activeColliders()
  )
  object.position += allowed
  syncMinimalUiState(object)

onRotateElevationOrResize(value):
  before = lastValidTransform(object)
  applyTransform(object, value)
  if hasCollision(object, activeColliders()):
    restoreTransform(object, before)
  else:
    commitHistorySnapshot()

deleteReference(fillWithWall):
  if fillWithWall:
    wall = measureContainingWall(reference)
    infill = createWallInfill(reference, wall)
    roomModel.add(infill)
  removeReference()
  rebuildWallColliders()
  resolveAllFurniturePenetration()
  commitHistorySnapshot()

save():
  editedItems = serializeObjectsReferencesAndDecor()
  roomJson = serializeRoomModelToJson(roomModel)
  metadata = createReplayableMetadataJson(
    originalMetadata,
    editedItems,
    roomJson
  )
  uploadMetadata(metadata)

reopen():
  restoreSavedRoomAndObjects(metadata)
```

---

## 21. 발표·포트폴리오용 핵심 설명

### 21.1 기술 하이라이트

1. **회전 대응 OBB + Sweep 이동**  
   가구의 실제 회전을 충돌에 반영하고 빠른 드래그 경로를 step 단위로 검사해 벽 tunneling을 막았다.

2. **벽 face 단위 Collider**  
   불규칙한 스캔 Mesh를 전체 박스로 단순화하지 않고 실제 벽 면을 분석해 개구부와 ㄱ자 벽을 자연스럽게 처리했다.

3. **문·창문 자동 두께 fitting**  
   RoomPlan의 평면 reference 한계를 실제 벽 geometry 측정으로 보정해 모델이 벽 밖으로 돌출되는 문제를 해결했다.

4. **방 구조까지 포함하는 재생 가능한 저장**  
   가구 transform만 저장하지 않고 방 Mesh와 material까지 `_spatiumRoom`에 직렬화해 벽 메우기 결과도 원본 없이 복원한다.

5. **카메라 기준 벽 면 투명화**  
   전체 벽을 숨기지 않고 시야를 가리는 face만 처리해 방 내부를 자연스럽게 보여준다.

6. **일관된 Undo / Redo**  
   추가·삭제·교체·꾸미기·벽 infill까지 동일한 replayable snapshot으로 복원한다.

### 21.2 5분 데모 순서

1. 저장된 방을 열고 실제 스캔 공간 복원을 보여준다. 약 30초.
2. 가구를 추가하고 치수를 입력한 뒤 배치한다. 약 30초.
3. 가구를 빠르게 벽 쪽으로 드래그해 벽 통과 방지와 slide를 보여준다. 약 40초.
4. 회전·높이·크기 조정을 보여준다. 약 40초.
5. 문 또는 창문을 교체하고, 다른 reference는 벽으로 메운다. 약 50초.
6. 1인칭과 Skyview, 카메라 기준 벽 투명화를 보여준다. 약 40초.
7. 측정 모드와 벽 색상 변경을 보여준다. 약 30초.
8. Undo / Redo로 방 구조 변경까지 복구한다. 약 30초.
9. 저장 후 방을 다시 열어 가구와 벽 infill이 복원되는 것을 보여준다. 약 40초.

### 21.3 발표 마무리 문장

**Spatium의 3D 에디터는 스캔 공간을 보여주는 데서 끝나지 않고, 실제 치수와 공간 제약을 반영해 인테리어를 편집하고, 방 구조 변경까지 다시 재생할 수 있는 형태로 저장한다.**

---

## 22. 빠른 판단 기준

| 질문 | 답 |
| --- | --- |
| 가구가 왜 회전해도 벽을 뚫지 않는가? | local OBB를 world OBB로 변환하고 벽 normal에 투영하기 때문이다. |
| 빠르게 끌어도 왜 벽을 건너뛰지 않는가? | 이동 경로를 작은 step으로 나누어 검사하기 때문이다. |
| 문·창문이 왜 벽 두께에 맞는가? | 가장 가까운 벽의 실제 geometry projection을 측정해 두께와 중심을 보정하기 때문이다. |
| 문을 벽으로 메우면 왜 진짜 벽처럼 동작하는가? | infill Mesh, wall metadata, Collider, 기존 가구 재검사를 모두 갱신하기 때문이다. |
| 저장본만으로 왜 다시 열 수 있는가? | 객체 transform뿐 아니라 방 geometry와 material을 `_spatiumRoom`에 저장하기 때문이다. |
| 웹과 iOS의 핵심 차이는 무엇인가? | 렌더러·입력 방식·Draft 정책이며, 편집 데이터와 제약 의미는 동일하다. |
