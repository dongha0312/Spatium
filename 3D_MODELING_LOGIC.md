# Spatium 3D Editor Logic

> 현재 코드 기준 3D 에디터 로직 정리  
> 대상: `spatium-frontend/src/pages/3dEditor.js`, `spatium-frontend/src/pages/roomSceneEditor`

Spatium 3D 에디터는 **방 스캔 데이터**를 Three.js 씬으로 복원하고, 사용자가 **가구를 배치/이동/회전/교체/삭제**한 뒤 다시 로드 가능한 metadata JSON으로 저장하는 구조다.

핵심은 `useRoomSceneEditor.js` 훅이다. 이 훅이 방 모델, 벽 콜라이더, 가구 오브젝트, 포인터 입력, 충돌 판정, 저장 데이터를 하나의 편집 세션으로 연결한다. 선택 상태, 씬 설정 로딩, Skyview 전환, 벽/문/창문 표시, 치수 라벨, transform 계산은 별도 모듈과 훅으로 분리되어 있다.

---

## 목차

1. [한눈에 보는 구조](#한눈에-보는-구조)
2. [화면과 데이터 흐름](#화면과-데이터-흐름)
3. [씬 초기화](#씬-초기화)
4. [방 모델과 벽 콜라이더](#방-모델과-벽-콜라이더)
5. [가구, 문, 창문 오브젝트](#가구-문-창문-오브젝트)
6. [선택, 이동, 회전](#선택-이동-회전)
7. [벽 충돌과 이동 제한](#벽-충돌과-이동-제한)
8. [벽 표시와 측정 표시](#벽-표시와-측정-표시)
9. [저장과 복원](#저장과-복원)
10. [설정 파일](#설정-파일)
11. [현재 구현 특징](#현재-구현-특징)

---

## 한눈에 보는 구조

```text
3dEditor.js
  ├─ 프로젝트/방 정보 로딩
  ├─ 가구 카탈로그 로딩
  ├─ 저장/취소/방 전환 UI
  └─ RoomSceneEditorPage
       └─ useRoomSceneEditor
            ├─ Three.js scene / camera / renderer / controls
            ├─ room model 로딩 및 복원
            ├─ wall collider 생성
            ├─ furniture / door / window 생성
            ├─ pointer 기반 선택/이동/회전
            ├─ OBB 기반 벽 충돌 판정
            ├─ scene helper 모듈 기반 표시/계산 처리
            ├─ editor state hook 기반 상태 관리
            └─ metadata JSON 저장
```

| 계층 | 파일 | 책임 |
| --- | --- | --- |
| 화면 | `spatium-frontend/src/pages/3dEditor.js` | 프로젝트/방 로딩, 카탈로그, 툴바, 저장 버튼 |
| Three.js 래퍼 | `pages/roomSceneEditor/RoomSceneEditorPage.js` | 뷰포트, 선택 정보 패널, 회전 슬라이더, ref 액션 노출 |
| 에디터 코어 | `hooks/useRoomSceneEditor.js` | 씬 생성, 입력 처리, 오브젝트 편집, 충돌, 저장 orchestration |
| 선택 상태 훅 | `hooks/useSelectionState.js` | 선택 오브젝트 ref, 선택 정보, 회전값, replace mode, 삭제/초기화 가능 여부 |
| 설정 로딩 훅 | `hooks/useSceneConfigStatus.js` | scene config 로딩, status/error 상태 관리 |
| Skyview 훅 | `hooks/useSkyviewMode.js` | Skyview 카메라 전환, 기본 카메라 view 캡처/복구 |
| transform 유틸 | `scene/editorTransforms.js` | base64 URL 변환, dimensions 정규화, transform 직렬화, 회전 계산, fallback reference 생성 |
| 벽 표시 유틸 | `scene/wallVisibility.js` | 카메라 방향 기준 벽 투명화, 벽 색상 적용 |
| reference 표시 유틸 | `scene/referenceVisibility.js` | 문/창문 reference visibility, debug label, room-facing normal |
| 측정 label 유틸 | `scene/measurementLabels.js` | CSS2D 치수 라벨 생성, cm/m2/py 포맷, 안정 dimension 계산 |
| 오브젝트 생성 | `scene/objectFactory.js` | 가구/문/창문 모델 생성, GLB 크기 보정, OBB/pick box 생성 |
| 벽 콜라이더 | `scene/wallColliders.js` | 방 mesh에서 벽/바닥 판별, 벽 면 단위 collider 생성 |
| 충돌 | `scene/collision.js` | OBB 기반 벽 충돌, 이동 제한, 시각 상태 갱신 |
| 저장 데이터 | `scene/roomMetadata.js` | 편집 상태와 방 mesh를 JSON으로 직렬화/복원 |
| 방 측정 | `scene/roomMeasurements.js` | 바닥 면적, 외곽선, 폭/깊이/높이 계산 |
| 로더 | `scene/sceneLoaders.js` | USD/GLB/JSON 로딩, metadata 저장 API 호출 |
| 설정 | `scene/sceneConfig.js` | 모델 URL, 색상, 벽 제약 파라미터 조회 |
| 유틸 | `scene/threeUtils.js` | 행렬 변환, 라벨, dispose, 카메라 framing |

---

## 화면과 데이터 흐름

### 1. 라우트 진입

`3dEditor.js`는 URL query의 `projectId`, `roomId`를 기준으로 편집 대상 방을 결정한다.

```text
/member/editor?projectId=...&roomId=...
```

로드되는 데이터는 다음과 같다.

| 데이터 | 호출 | 사용처 |
| --- | --- | --- |
| 프로젝트 이름 | `getProjectInfo(projectId)` | 상단 프로젝트 라벨 |
| 방 씬 데이터 | `getRoomSceneData(roomId)` | Three.js 방 모델과 metadata |
| 프로젝트의 방 목록 | `getRoomList(projectId)` | 좌측 방 드롭다운 |
| 가구 카탈로그 | `/data/furniture_catalog.json` | 좌측 가구 목록 |

### 2. 에디터 액션

상위 화면은 `RoomSceneEditorPage`에 ref를 연결해 내부 에디터 액션을 호출한다.

| 사용자 동작 | 호출 |
| --- | --- |
| 가구 클릭 | `editorRef.current.addFurniture(item)` |
| 저장 | `editorRef.current.saveEditedSceneJson({ projectId, roomId })` |
| 선택 가구 삭제 | `deleteSelectedObject()` |
| 선택 가구 교체 | `startReplaceSelectedObject()` 후 카탈로그 클릭 |

저장 시에는 metadata JSON이 `FormData`에 담겨 `POST /api/rooms/save`로 전송된다.

---

## 씬 초기화

### 중심 함수

```js
useRoomSceneEditor({
  isSkyview,
  showMeasurements,
  wallColor,
  roomScene,
  onSceneChanged,
})
```

### 초기화 순서

```text
loadSceneConfig()
  ↓
renderer / CSS2DRenderer / scene / camera / OrbitControls 생성
  ↓
roomScene.model.dataBase64 또는 config의 room.modelUrl 선택
  ↓
roomScene.metadata 또는 config의 room.metadataUrl 선택
  ↓
USD 방 모델 로드
  ↓
metadata._spatiumRoom이 있으면 JSON 방 모델 우선 복원
  ↓
prepareRoomModel()
  ↓
createWallColliders()
  ↓
metadata.objects / doors / windows 복원
  ↓
initializeWallConstraints()
  ↓
첫 가구 선택 및 frameObject()
```

### 방 모델 선택 우선순위

1. API에서 받은 `roomScene.model.dataBase64`
2. 설정 파일의 `room.modelUrl`
3. metadata에 저장된 `_spatiumRoom` JSON 복원 결과

실제 렌더링에서는 `_spatiumRoom`이 있으면 이를 우선 사용한다. 따라서 저장된 편집 결과는 원본 USD 모델 없이도 다시 열 수 있다.

---

## 방 모델과 벽 콜라이더

### `loadUsdRoomModel(url)`

위치: `scene/sceneLoaders.js`

USD/USDZ 방 모델을 `USDLoader`로 로드한다. 일반 URL에는 timestamp query를 붙여 캐시를 피하고, `blob:` URL은 그대로 사용한다. 로드 실패 시 에러를 던지지 않고 `null`을 반환한다.

### `prepareRoomModel(model)`

위치: `scene/wallColliders.js`

방 모델을 순회하며 각 mesh가 벽인지, 바닥인지, 저장 직렬화에서 제외할 mesh인지 userData에 표시한다. 이 정보는 벽 충돌체 생성, 방 측정, `_spatiumRoom` 저장에서 공통으로 사용된다.

### 벽/바닥 판별

| 함수 | 역할 |
| --- | --- |
| `isUsdWallMesh(object)` | USD/JSON 방 mesh가 벽인지 판별 |
| `isUsdFloorMesh(object)` | USD/JSON 방 mesh가 바닥인지 판별 |
| `isUsdReplacedMesh(object)` | 저장 직렬화에서 제외할 교체 mesh 판별 |

판별에는 USD 계층 이름 패턴과 `userData.isUsdWallMesh`, `userData.isUsdFloorMesh`가 함께 사용된다.

### `createWallColliders(roomModel)`

위치: `scene/wallColliders.js`

방 모델에서 벽 충돌체 배열을 만든다.

```text
roomModel
  └─ wall mesh
       ├─ 실제 벽 face 단위 collider 생성 시도
       └─ 실패 시 geometry bounds 기반 OBB fallback 생성
```

각 wall collider에는 다음 정보가 들어간다.

| 필드 | 의미 |
| --- | --- |
| `obb` | 벽 실체 또는 벽 면을 나타내는 OBB |
| `spanAxes` | 벽 길이/높이 방향 overlap 판정 축 |
| `spanPolygon` | 벽 face를 2D 투영한 span polygon |
| `roomFacingNormal` | 방 안쪽을 향하는 normal |
| `roomFacingProjection` | 방 내부 경계 projection |
| `triangleStart`, `triangleCount` | 벽 face preview용 triangle 범위 |
| `object` | 원본 wall mesh |

`roomFacingNormal`이 있는 벽은 단순 OBB 교차가 아니라 **방 내부 경계선을 침범했는지**를 기준으로 더 자연스럽게 충돌을 판정한다.

---

## 가구, 문, 창문 오브젝트

### 일반 가구

일반 가구는 `sourceType: "object"`이며, 추가/이동/회전/삭제/교체가 가능하다.

| 함수 | 상황 | 결과 |
| --- | --- | --- |
| `createEditableFurniture(item, index)` | GLB 템플릿이 없을 때 | dimensions 기반 fallback box |
| `createEditableFurnitureModel(modelTemplate, item, index)` | GLB 템플릿이 있을 때 | 실제 모델 clone 및 크기 보정 |

`createEditableFurnitureModel()`의 주요 작업:

1. GLB scene clone
2. `fitModelToTargetSize()`로 metadata dimensions에 맞게 스케일 조정
3. `getBaseGeometryBounds()`로 mesh bounds 계산
4. bounds에서 `localObb` 생성
5. 보이지 않는 pick hit box 생성
6. 선택/충돌 표시용 edge line 생성
7. root group의 `userData`에 편집 상태 저장

### 문과 창문

문과 창문은 reference object로 관리된다.

| 타입 | 함수 | 특징 |
| --- | --- | --- |
| 문 | `createDoorModel()` | `sourceType: "door"`, `editable: false` |
| 창문 | `createWindowModel()` | `sourceType: "window"`, `editable: false` |

현재 UI에서는 새 문/창문을 직접 추가하지 않는다. 기존 문/창문을 선택한 뒤 Replace로 같은 reference 계열 모델만 교체한다.

#### 삭제: 개구부로 남기기 / 벽으로 메우기

문/창문은 일반 가구와 달리 "삭제" 대신 두 가지 삭제 방식을 제공한다 (`deleteSelectedReference(fillWithWall)`).

| 방식 | 동작 |
| --- | --- |
| 개구부로 삭제 (`fillWithWall: false`) | reference object만 제거한다. 벽에는 원래 있던 개구부(구멍)가 그대로 남는다 |
| 벽으로 메우기 (`fillWithWall: true`) | `createWallInfillMesh()`로 그 자리를 채우는 박스 mesh를 만들어 `roomModel`에 추가한 뒤 reference object를 제거한다 |

`createWallInfillMesh()`는 [벽 두께에 맞춘 fitting](#벽-두께에-맞춘-fitting)과 같은 `measureWallThicknessAtPosition()`을 재사용해서, 문/창문이 속한 벽의 실측 두께/중심에 맞춰 채움 박스를 만든다. 크기는 reference의 `localObb`(가로/세로)에 여유 패딩(6cm)을 더한 값이다. 만든 mesh에는 `userData.isUsdWallMesh = true`를 직접 표시해 일반 벽과 동일하게 취급되게 하며, 이름은 `Infill_...`로 시작해 `isUsdReplacedMesh()`의 `Door`/`Window` 이름 패턴에 걸리지 않게 한다(걸리면 저장에서 제외됨).

색상은 `materialForWallInfill()`이 `measureWallThicknessAtPosition()`이 찾아준 매칭된 벽 mesh의 material을 그대로 `clone()`해서 쓴다 — 색상뿐 아니라 roughness/metalness, 있다면 텍스처까지 원래 벽과 동일해진다(매칭된 벽을 못 찾은 경우에만 `roomMaterialDefault` fallback). 사용자가 벽 색상을 따로 지정한 상태라면, 콜라이더 재생성 뒤 호출되는 `applyRoomWallColor()`가 새 mesh도 포함해서 다시 덮어써 일관되게 유지된다.

벽으로 메운 뒤에는 벽 콜라이더를 다시 만들고(`createWallColliders(roomModel)`) 기존 가구도 다시 밀어낸다(`initializeWallConstraints`) — 방금 벽이 생긴 자리에 가구가 있었을 수 있기 때문이다.

`createReplayableMetadataJson()`은 현재 씬의 문/창문 목록을 그대로 저장하므로(더 이상 "편집 없으면 원본 유지" 폴백을 쓰지 않는다), 삭제 결과가 저장에도 정확히 반영된다. 벽으로 메운 경우 새 mesh는 `_spatiumRoom.walls`에 포함되어 재로딩 시에도 벽으로 남는다.

#### 벽 두께에 맞춘 fitting

RoomPlan 스캔 데이터의 문/창문은 항상 `dimensions.z = 0`이다(문/창문은 평면으로만 기록됨). 그래서 두께는 `room-scene-config.json`의 `referenceFallbackThickness`(기본 0.08m)로만 정해지고, 위치는 스캔이 기록한 **벽 앞면(room-facing surface)** 좌표를 그대로 쓴다. 이 좌표를 중심으로 두께를 좌우 대칭 적용하면 두께의 절반이 항상 벽 앞으로 튀어나온다 — 이게 실제 튀어나옴의 원인이었다. 이를 막기 위해 `createDoorModel()`/`createWindowModel()`은 `wallColliders`를 받아 아래 순서로 두께와 위치를 보정한다.

```text
문/창문 저장 위치(position)
  ↓
nearestWallMesh() — 벽 mesh들의 world bounding box까지의 거리(Box3.distanceToPoint)로
  가장 가까운 벽 mesh 하나를 찾는다
  (문/창문은 벽 개구부 위에 있어 삼각형 자체와는 안 겹치므로 bounding box 거리로 판정한다.
   per-triangle face collider를 기준으로 찾으면 문틀 옆면(reveal)처럼 두께 축과 무관한
   삼각형을 잘못 고를 수 있어서, 벽 mesh 전체를 기준으로 삼는다)
  ↓
localThicknessAxis() — 그 mesh의 로컬 bounding box에서 가장 짧은 축을 두께 방향으로 판정
  (길이/높이보다 두께가 훨씬 얇은 박스 형태이므로 안정적으로 두께 축을 찾는다)
  ↓
geometryProjectionRange(wall.object, normal) — 벽 mesh 전체를 그 축에 투영해 실제 두께
  (min/max)와 두께 방향 중심(centerProjection)을 측정
  ↓
fitReferenceToWallThickness() — targetSize.z를 min(원래 두께, 실측 두께 - margin)으로 clamp,
  position을 벽의 두께 방향 중심(centerProjection)으로 재정렬
```

가까이에 벽을 찾지 못하면(거리 0.5m 초과) 원래 값을 그대로 사용한다. 위치는 `wallColliders.js`, 로직은 `objectFactory.js`에 있다.

---

## 선택, 이동, 회전

### 선택

pointer down에서 pick target을 raycast하고, hit된 mesh의 `userData.editableRoot`를 선택한다. 선택된 오브젝트는 `objectToEditableJson()` 결과로 React state에 반영된다.

선택 시 갱신되는 UI:

- 우측 선택 정보 패널
- 회전 슬라이더 값
- 선택 edge line
- 치수 label
- 충돌 경고

### 이동

이동은 floor plane 위에서 계산된다.

```text
pointer ray
  ↓
floor plane 교차점
  ↓
target position 계산
  ↓
movement vector 계산
  ↓
constrainedMovementBeforeWallCollision()
  ↓
벽을 넘지 않는 movement만 적용
```

이동 가능한 대상은 일반 가구다. 문/창문은 선택 및 교체는 가능하지만 벽 충돌 제약 대상(움직이는 쪽)에서는 제외된다. 다만 가구를 이동/회전시킬 때는 문/창문도 벽과 함께 장애물로 취급되어 통과할 수 없다 — [벽 충돌과 이동 제한](#벽-충돌과-이동-제한) 참고.

### 높이(수직) 이동

포인터 드래그는 바닥 평면(X-Z) 이동만 처리하며 `object.position.y`는 드래그 도중 항상 시작 높이로 고정된다. 수직 이동은 별도의 높이 슬라이더(`setSelectedElevationCm`)로만 가능하다.

| 항목 | 설명 |
| --- | --- |
| 대상 | `sourceType: "object"`인 일반 가구만 (`canTransformObject()`가 true인 오브젝트) |
| 값 정의 | 바닥에서 가구 바닥면까지의 간격(cm). 0이면 바닥에 놓인 상태 |
| 범위 | `0 ~ (천장Y - 바닥Y - 가구높이)`를 cm로 환산한 값. `useRoomSceneEditor`의 `elevationBoundsForObject()`가 매 선택마다 계산 |
| 충돌 처리 | 높이 변경 후 `hasWallCollision()`이 true이면 이전 위치로 되돌림(회전 슬라이더와 동일 패턴) |
| UI | `RoomSceneEditorPage.js`의 `room-scene-editor-elevation-panel` 슬라이더, 최대 이동 범위가 0보다 클 때만 표시 |

가구를 벽에 자동으로 붙이거나 끌어당기는 스냅 로직은 없다. 이 높이 슬라이더도 스냅이 아니라 사용자가 직접 값을 지정하는 방식이다.

### 회전

회전은 두 경로가 있다.

| 경로 | 설명 |
| --- | --- |
| 드래그 회전 | pointer angle delta를 Y축 quaternion에 반영 |
| 슬라이더 회전 | `setSelectedRotationDegrees(degrees)`로 Y축 각도를 직접 지정 |

회전 적용 후 `hasWallCollision()`이 true이면 이전 quaternion으로 되돌린다. 성공하면 마지막 유효 transform을 저장하고 변경 상태를 표시한다.

---

## 벽 충돌과 이동 제한

### 충돌 기준

가구와 벽 충돌은 `Box3` AABB가 아니라 **OBB** 기준이다.

```text
object.userData.localObb
  + object.matrixWorld
  = world OBB
```

UI 치수 표시는 metadata 또는 bounds 기반이지만, 실제 충돌 판정은 `localObb`를 월드 좌표로 변환한 OBB로 수행한다.

### 문/창문도 장애물이다

가구를 이동/회전/높이 조정할 때 충돌 판정에 쓰이는 목록은 벽 콜라이더만이 아니다. `useRoomSceneEditor.js`의 `activeColliders()`가 `wallColliders`에 `referenceCollidersFromRoots(referenceRoots)`(문/창문 오브젝트들의 world OBB)를 합쳐서 전달한다.

```text
activeColliders()
  = wallColliders
  + referenceRoots.map(root => ({ object: root, obb: worldObbForObject(root) }))
```

문/창문 콜라이더는 `spanAxes`/`roomFacingNormal`이 없어서, `wallBlocksObjectObb()`가 boundary 판정 대신 **단순 OBB 교차 판정**으로 처리한다 — 실제 문/창문 박스와 겹치면 그대로 막힌다. `constrainedMovementBeforeWallCollision()`, `hasWallCollision()`, `initializeWallConstraints()`, `refreshCollisionState()`에 전달되는 콜라이더 목록은 모두 이 `activeColliders()` 결과다. 문/창문 자신은 `shouldConstrainToWalls()`에서 여전히 제외되므로(움직이지 않음) 이 목록에 자기 자신이 포함돼도 스스로 막히지는 않는다.

### 핵심 함수

| 함수 | 역할 |
| --- | --- |
| `worldObbForObject(object)` | local OBB를 world OBB로 변환 |
| `shouldConstrainToWalls(object)` | 벽 제약 대상인지 판단 |
| `wallBlocksObjectObb(objectObb, wall)` | 벽이 object OBB를 막는지 판정 |
| `objectOverlapsWallSpan(objectObb, wall)` | object가 벽의 길이/높이 범위와 겹치는지 판정 |
| `constrainedMovementBeforeWallCollision()` | 이동 vector를 벽을 넘지 않는 값으로 제한 |
| `initializeWallConstraints()` | 초기 로딩 시 벽 침범 가구 보정 |
| `refreshCollisionState()` | 충돌 상태와 시각 표시 갱신 |

### 이동 제한 방식

큰 movement를 한 번에 적용하지 않고 작은 step으로 나눠 검사한다.

```text
requested movement
  ↓
sweepStep 기준으로 분할
  ↓
각 step에서 벽 내부로 들어가는 성분 제거
  ↓
허용된 step만 누적
  ↓
최종 constrained movement 반환
```

이 방식은 빠르게 드래그할 때 가구가 벽을 순간적으로 통과하는 문제를 줄인다.

### 충돌 표시

`refreshCollisionState()`는 충돌한 가구에 다음 상태를 기록한다.

```js
object.userData.collisions = ["wall"]
```

이후 `setFurnitureVisualState()`가 edge와 fallback mesh 색상을 충돌 색상으로 바꾼다.

---

## 벽 표시와 측정 표시

### 카메라 기준 벽 투명화

`updateViewFacingWalls(wallColliders, camera, referenceRoots)`는 매 frame 실행된다.

카메라 위치를 기준으로 시야를 가리는 벽 face를 투명하게 만들어 방 내부를 보기 쉽게 한다.

| 상황 | 처리 |
| --- | --- |
| face triangle 정보가 있음 | geometry group material index를 바꿔 해당 face만 투명화 |
| face 정보가 부족함 | wall object material opacity를 낮춤 |
| 문/창문 reference가 시야를 가림 | reference material opacity를 낮춤 |

### 벽 색상 변경

`applyRoomWallColor(wallColliders, color)`는 상위 화면에서 선택한 벽 색상을 모든 wall material에 적용한다. preview 복원 시에도 색상이 유지되도록 original material state에도 반영한다.

### 방 측정

`calculateRoomMeasurements(roomModel)`은 바닥 mesh의 삼각형을 분석해 방 치수를 계산한다.

| 값 | 의미 |
| --- | --- |
| `width` | 방 폭 |
| `depth` | 방 깊이 |
| `height` | 방 높이 |
| `area` | 바닥 면적 |
| `areaSource` | `floor` 또는 `bounds` |
| `outlineSegments` | 바닥 외곽선 |
| `heightSegment` | 높이 측정선 |

`showMeasurements`가 true이면 외곽선, 높이선, 면적 badge, CSS2D label이 표시된다.

---

## 저장과 복원

### 저장 데이터 생성

저장은 `objectToEditableJson()`과 `createReplayableMetadataJson()`이 중심이다.

```text
현재 Three.js object들
  ↓
objectToEditableJson()
  ↓
editedItems
  ↓
createReplayableMetadataJson()
  ↓
metadata.json
  ↓
saveMetadataJson()
  ↓
POST /api/rooms/save
```

### `objectToEditableJson(object)`

가구/문/창문 object 하나를 저장 가능한 JSON으로 변환한다.

포함 정보:

- `id`, `sourceType`, `index`
- `catalogId`, `name`, `category`
- `path`, `modelUrl`
- `dimensions`, `dimensionsCm`
- `position`, `rotation`
- `transform.columns`
- `collision.hasCollision`, `collision.with`

### `_spatiumRoom`

`serializeRoomModelToJson(roomModel, generatedFrom)`은 현재 방 mesh를 JSON으로 직렬화한다.

저장되는 정보:

- 벽 mesh
- 바닥 mesh
- 기타 room mesh
- geometry position / normal / uv / index
- world matrix
- material 정보

`createRoomModelFromJson(roomJson)`은 이 JSON을 다시 Three.js group으로 복원한다. 복원된 mesh에는 벽/바닥 판별용 userData가 다시 설정된다.

### `createReplayableMetadataJson(metadata, editedItems, roomModel)`

기존 metadata를 clone한 뒤 현재 편집 상태로 갱신한다.

| 필드 | 처리 |
| --- | --- |
| `objects` | 현재 일반 가구 편집 결과로 대체 |
| `doors` | 문 편집 결과가 있으면 갱신, 없으면 기존 유지 |
| `windows` | 창문 편집 결과가 있으면 갱신, 없으면 기존 유지 |
| `_spatiumRoom` | 현재 방 mesh 직렬화 결과 저장 |
| `_spatiumExport` | export 버전, 시간, scene config, 모델 URL, editedItems 기록 |

### 실제 저장 API

`saveMetadataJson()`은 `RoomSpringBootApi.saveRoomMetadataJson()`을 호출한다.

```text
FormData
  ├─ projectId
  ├─ roomId
  ├─ area optional
  └─ metadata: metadata.json Blob

POST /api/rooms/save
```

---

## 설정 파일

위치: `spatium-frontend/public/config/room-scene-config.json`

| 키 | 의미 |
| --- | --- |
| `models` | category별 기본 GLB 모델 URL |
| `colors.category` | fallback box category 색상 |
| `colors.collision` | 충돌 edge 색상 |
| `colors.collisionFill` | 충돌 fill 색상 |
| `colors.selectedEdge` | 선택 edge 색상 |
| `colors.defaultEdge` | 기본 edge 색상 |
| `colors.doorReference` | 문 reference 색상 |
| `colors.windowReference` | 창문 reference 색상 |
| `referenceFallbackThickness` | 문/창문 두께 fallback |
| `debug.showReferenceLabels` | 문/창문 방향 디버그 라벨 표시 |
| `debug.showCameraAngle` | 카메라 yaw/pitch badge 표시 |
| `wallConstraints.collisionEpsilon` | OBB 교차 판정 여유값 |
| `wallConstraints.sweepStep` | 이동 sweep step 크기 |
| `wallConstraints.sweepRotationStepDegrees` | 회전 sweep 설정값 |
| `wallConstraints.colliderHalfThickness` | 벽 콜라이더 최소 반두께 |
| `wallConstraints.boundaryEpsilon` | 벽 경계 허용 오차 |
| `wallConstraints.boundarySpanPadding` | 벽 span overlap padding |
| `wallConstraints.logWallDiagnostics` | 벽 이동 차단/충돌 debug 로그 |
| `wallConstraints.showColliderDebug` | 벽 콜라이더 시각화 |

현재 설정에는 `showWallDiagnostics`, `clampIterations`, `sweepMaxSteps`도 남아 있다. 다만 현재 핵심 이동/충돌 흐름에서는 위 표의 값들이 주로 사용된다.

---

## 현재 구현 특징

- 방 씬 데이터는 API의 `roomScene`을 우선 사용한다.
- 저장된 `_spatiumRoom`이 있으면 원본 USD 모델보다 먼저 복원된다.
- 일반 가구는 추가, 이동, 회전, 높이(수직) 조정, 삭제, 교체가 가능하다.
- 문과 창문은 reference object이며, 기존 reference를 같은 계열 모델로 교체하는 방식이다.
- 문/창문 삭제는 개구부로 남기기와 벽으로 메우기 중 선택할 수 있다(`deleteSelectedReference(fillWithWall)`).
- 문/창문 두께는 속한 벽의 실측 두께에 맞춰 clamp되고 위치도 벽 두께 중심으로 재정렬되어, 벽보다 두꺼워서 앞뒤로 튀어나오는 문제를 방지한다.
- 충돌 판정은 object OBB와 wall collider 기준이며, 가구 이동/회전/높이 조정 시에는 문/창문 OBB도 동일하게 장애물로 취급된다(`activeColliders()`).
- 이동은 충돌 후 되돌리는 방식이 아니라, 적용 전 movement vector를 제한하는 방식이다.
- 빠른 드래그에서도 벽을 통과하지 않도록 movement를 step 단위로 나눠 검사한다.
- 선택 정보와 저장 metadata는 `objectToEditableJson()` 결과를 중심으로 동기화된다.
- 저장 결과는 다시 로드 가능한 metadata JSON이며, 방 mesh 자체도 `_spatiumRoom`에 포함된다.

---

## 빠른 참조

| 하고 싶은 일 | 먼저 볼 파일 |
| --- | --- |
| 에디터 UI 수정 | `spatium-frontend/src/pages/3dEditor.js` |
| 선택 패널/회전 슬라이더 수정 | `spatium-frontend/src/pages/roomSceneEditor/RoomSceneEditorPage.js` |
| 포인터 이동/회전 로직 수정 | `spatium-frontend/src/pages/roomSceneEditor/hooks/useRoomSceneEditor.js` |
| 선택/replace 상태 수정 | `spatium-frontend/src/pages/roomSceneEditor/hooks/useSelectionState.js` |
| 씬 config 로딩 상태 수정 | `spatium-frontend/src/pages/roomSceneEditor/hooks/useSceneConfigStatus.js` |
| Skyview 카메라 전환 수정 | `spatium-frontend/src/pages/roomSceneEditor/hooks/useSkyviewMode.js` |
| transform/dimensions/회전 계산 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/editorTransforms.js` |
| 벽 투명화/벽 색상 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/wallVisibility.js` |
| 문/창문 reference 표시 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/referenceVisibility.js` |
| 치수 label/단위 포맷 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/measurementLabels.js` |
| 가구 모델 생성 방식 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/objectFactory.js` |
| 벽 충돌 판정 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/collision.js` |
| 벽 콜라이더 생성 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/wallColliders.js` |
| 저장 JSON 구조 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/roomMetadata.js` |
| 방 면적/치수 계산 수정 | `spatium-frontend/src/pages/roomSceneEditor/scene/roomMeasurements.js` |
| 모델 URL/색상/제약값 수정 | `spatium-frontend/public/config/room-scene-config.json` |
