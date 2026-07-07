# Spatium 3D 모델링 로직 정리

이 문서는 `spatium-frontend/src/pages/testThree` 기준으로 방, 벽, 가구, 이동/회전, 충돌, 저장 로직이 어떤 함수로 구현되어 있고 어떤 역할을 하는지 정리한다.

## 전체 구조

3D 에디터의 중심은 `useTestThreeEditor.js` 훅이다. 이 훅이 Three.js 씬, 카메라, 컨트롤, 방 모델, 벽 콜라이더, 가구 오브젝트, 선택 오버레이, 포인터 이벤트, 저장 상태를 연결한다.

주요 파일은 다음과 같다.

| 파일                          | 역할                                                                |
| ----------------------------- | ------------------------------------------------------------------- |
| `hooks/useTestThreeEditor.js` | 3D 에디터 전체 orchestration, 입력 이벤트, 선택/이동/회전/저장 처리 |
| `scene/objectFactory.js`      | 가구, 문, 창문 3D 오브젝트 생성 및 OBB 생성                         |
| `scene/wallColliders.js`      | USD 방 모델에서 벽/바닥을 판별하고 벽 충돌체 생성                   |
| `scene/collision.js`          | 가구 OBB와 벽 충돌/경계 판정, 이동 제한, 충돌 시각 상태             |
| `scene/roomMetadata.js`       | 편집된 오브젝트와 방 모델을 JSON으로 직렬화/복원                    |
| `scene/roomMeasurements.js`   | 방 바닥 면적, 외곽선, 폭/깊이/높이 측정                             |
| `scene/sceneLoaders.js`       | USD/GLB/JSON 로딩 및 메타데이터 저장 API 호출                       |
| `scene/sceneConfig.js`        | 설정값, 색상, 모델 URL, 벽 제약 파라미터 조회                       |
| `scene/threeUtils.js`         | 행렬 변환, 라벨 생성, 리소스 dispose, 카메라 framing 유틸           |

## 방 모델 로딩 및 준비

### `loadUsdRoomModel(url)`

위치: `scene/sceneLoaders.js`

USDZ/USD 방 모델을 `USDLoader`로 로드한다. 캐시 방지를 위해 URL에 timestamp query를 붙인다. 로딩 실패 시 에러를 던지지 않고 `null`을 반환하도록 처리한다.

### `fetchJson(url, label)`

위치: `scene/sceneLoaders.js`

RoomPlan 메타데이터 JSON 또는 저장된 편집 JSON을 가져온다. `cache: "no-store"`와 timestamp query를 사용해 최신 데이터를 가져오도록 한다.

### `prepareRoomModel(model)`

위치: `scene/wallColliders.js`

로드된 방 모델을 traverse하면서 벽, 바닥, 교체된 오브젝트 여부를 userData로 표시한다. 이후 벽 콜라이더 생성, 벽 숨김 처리, 바닥 측정에서 같은 판별 정보를 재사용한다.

### `isUsdWallMesh(object)`

위치: `scene/wallColliders.js`

USD 방 모델에서 벽 mesh인지 판별한다. `Wall_#_grp`, `Wall#` 계층 이름을 기준으로 탐색하고, 문/창문 이름을 가진 노드는 벽에서 제외한다.

### `isUsdFloorMesh(object)`

위치: `scene/wallColliders.js`

바닥 mesh인지 판별한다. 이름에 `Floor`, `Ground`, `Slab` 등이 포함된 계층을 바닥으로 본다. 문/창문 계층은 제외한다.

## 벽 콜라이더 생성

### `createWallColliders(roomModel)`

위치: `scene/wallColliders.js`

방 모델 전체에서 벽 충돌체 배열을 만든다.

구현 흐름:

1. `roomModel.updateWorldMatrix(true, true)`로 월드 행렬 갱신
2. `Box3().setFromObject(roomModel)`로 방 중심 계산
3. `collectFloorTriangles(roomModel)`로 바닥 삼각형 수집
4. 각 벽 mesh를 순회
5. 우선 `worldWallFaceCollidersFromGeometry()`로 벽의 실제 면 단위 콜라이더 생성 시도
6. 실패하면 geometry boundingBox 기반으로 `worldObbFromLocalBox()` fallback 콜라이더 생성
7. 각 벽 콜라이더에 `obb`, `spanAxes`, `roomFacingNormal`, `roomFacingProjection` 등을 저장

### `worldWallFaceCollidersFromGeometry(object, roomCenter, floorTriangles)`

위치: `scene/wallColliders.js`

벽 mesh의 triangle들을 분석해 실제 벽면 단위 OBB 콜라이더를 만든다. 수직에 가까운 면만 벽 후보로 보고, normal/projection 기준으로 같은 평면의 삼각형들을 묶는다.

### `createWallColliderFromFaceGroup(object, group, roomCenter, floorTriangles)`

위치: `scene/wallColliders.js`

동일 평면으로 묶인 벽 face group 하나를 OBB 콜라이더로 변환한다.

핵심 구현:

- `group.normal`을 벽 normal로 사용
- `roomSideFromFloorSamples()`로 벽의 어느 쪽이 방 내부인지 샘플링
- 내부 방향을 `roomFacingNormal`로 저장
- 벽의 길이/높이 축을 계산해 `OBB(center, halfSize, rotation)` 생성
- 벽 span 검사용 `spanAxes`, `spanPolygon` 저장

### `roomSideFromFloorSamples(points, normal, floorTriangles)`

위치: `scene/wallColliders.js`

벽 중심에서 normal 양쪽으로 작은 offset을 두고 바닥 polygon 위에 있는지 검사한다. 한쪽만 바닥 위라면 그 방향을 방 내부 방향으로 판단한다. 양쪽 모두 내부이거나 둘 다 외부면 방향을 확정하지 않는다.

### `worldObbFromLocalBox(box, matrixWorld)`

위치: `scene/wallColliders.js`

geometry의 local `Box3`를 월드 OBB로 변환한다. local AABB의 중심/크기를 가져온 뒤 월드 행렬의 rotation/scale을 반영해 `OBB`를 만든다.

### `createWallColliderVisuals(wallColliders)`

위치: `scene/wallColliders.js`

디버그용 벽 콜라이더 시각화 mesh/line group을 생성한다. 각 벽 OBB edge, 내부 경계 outline, baseline 등을 만든다.

## 가구, 문, 창문 생성

### `createEditableFurniture(item, index)`

위치: `scene/objectFactory.js`

메타데이터 dimensions만으로 기본 box 가구를 만든다. 실제 GLB 모델이 없을 때 fallback처럼 사용할 수 있다.

구현 내용:

- `item.dimensions`를 기준으로 `BoxGeometry` 생성
- `createCenteredLocalObb()`로 centered OBB 생성
- root group에 위치/회전/스케일 적용
- `root.userData.localObb`, `lastValidPosition`, 색상, 충돌 상태 등을 저장

### `createEditableFurnitureModel(modelTemplate, item, index)`

위치: `scene/objectFactory.js`

GLB 템플릿을 복제해 실제 가구 모델을 생성한다.

구현 흐름:

1. catalog/metadata dimensions를 target size로 계산
2. GLB scene clone
3. mesh shadow, picking root userData 설정
4. `fitModelToTargetSize(model, targetSize)`로 모델 크기를 목표 dimensions에 맞춤
5. `getBaseGeometryBounds(model)`로 모델 bounds 계산
6. `createLocalObbFromBounds()`로 가구 충돌 기준 `localObb` 생성
7. 보이지 않는 pick hit box와 충돌 edge line 생성
8. root group에 모델, hitBox, edge를 추가

### `createDoorModel(doorTemplate, item, index)`

위치: `scene/objectFactory.js`

문 reference object를 생성한다. 가구와 비슷하게 GLB template을 target size에 맞추고 `localObb`를 만든다. userData에는 `sourceType: "door"`와 reference 색상, 충돌 edge 등을 저장한다.

### `createWindowModel(windowTemplate, item, index)`

위치: `scene/objectFactory.js`

창문 reference object를 생성한다. 문과 같은 방식으로 모델 크기 보정, OBB 생성, hit box/edge 생성, userData 설정을 수행한다.

### `getBaseGeometryBounds(object)`

위치: `scene/objectFactory.js`

모델의 모든 mesh vertex를 월드 좌표로 변환해 `Box3` bounds를 만든다. 이 bounds는 모델 크기 보정과 `localObb` 생성에 사용된다.

### `fitModelToTargetSize(model, targetSize)`

위치: `scene/objectFactory.js`

모델의 현재 bounds size를 target size와 비교해 x/y/z 축별 scale을 곱한다. 이후 모델 중심을 원점 쪽으로 보정해 root group 기준 배치가 자연스럽게 되도록 한다.

### `createLocalObbFromBounds(bounds, fallbackSize)`

위치: `scene/objectFactory.js`

`Box3` bounds의 center와 size를 사용해 local OBB를 만든다. bounds가 비어 있거나 size가 유효하지 않으면 fallback size 기준 centered OBB를 만든다.

## 가구 이동 및 회전

### `beginMoveInteraction(event, object)`

위치: `hooks/useTestThreeEditor.js`

가구 이동 드래그를 시작한다. pointer ray와 가구 y 위치의 floor plane 교차점을 구하고, object position과 hit point의 offset을 저장한다.

### `beginRotateInteraction(event, object)`

위치: `hooks/useTestThreeEditor.js`

회전 드래그를 시작한다. 현재 object position을 회전 중심으로 잡고, floor plane 위에서 pointer가 만드는 시작 각도와 시작 quaternion을 저장한다.

### `updateActiveInteraction(event)`

위치: `hooks/useTestThreeEditor.js`

드래그 중 매 pointer move마다 이동 또는 회전을 적용한다.

이동 구현:

1. pointer ray와 floor plane의 교차점 계산
2. target position 계산
3. 현재 position에서 target까지의 movement vector 계산
4. `constrainedMovementBeforeWallCollision()`로 벽을 넘지 않는 movement로 보정
5. 보정된 movement를 object position에 더함
6. y 위치는 기존 activeInteraction y로 유지

회전 구현:

1. 현재 pointer angle 계산
2. 시작 angle과의 delta 계산
3. 시작 quaternion에 Y축 회전 quaternion을 premultiply

### `rotateSelectedObject()`

위치: `hooks/useTestThreeEditor.js`

선택된 오브젝트를 Y축 기준 90도 회전한다.

### `setSelectedRotationDegrees(degrees)`

위치: `hooks/useTestThreeEditor.js`

선택된 오브젝트의 Y축 회전각을 직접 지정한다. `normalizeRotationDegrees()`로 0~360도 범위로 정규화한 뒤 quaternion을 새로 설정한다. 벽 충돌 체크 없이 적용한다.

## 이동 제한 및 충돌 로직

### `worldObbForObject(object)`

위치: `scene/collision.js`

가구 root의 `userData.localObb`를 clone한 뒤 object의 `matrixWorld`를 적용해 월드 OBB를 만든다. 실제 충돌 판정의 기준이 된다.

### `objectIntersectsWalls(object, wallColliders)`

위치: `scene/collision.js`

가구의 월드 OBB가 벽 콜라이더 중 하나라도 막는지 검사한다. 내부적으로 `wallBlocksObjectObb()`를 사용한다.

### `wallBlocksObjectObb(objectObb, wall)`

위치: `scene/collision.js`

벽이 가구 OBB를 막는지 판정한다.

구현 기준:

- `roomFacingNormal`과 `roomFacingProjection`이 있으면 `objectObbViolatesWallBoundary()`로 벽 내부 경계 침범 여부 확인
- 그렇지 않거나 fallback 상황이면 `objectObb.intersectsOBB(wall.obb, collisionEpsilon)`로 OBB 교차 확인
- 벽 span과 겹치는 경우만 충돌로 인정

### `objectOverlapsWallSpan(objectObb, wall)`

위치: `scene/collision.js`

가구 OBB가 벽의 길이/높이 범위와 겹치는지 검사한다. 벽에 `spanPolygon`이 있으면 OBB를 2D polygon으로 투영해 polygon overlap을 검사하고, 없으면 span axis projection 범위로 검사한다.

### `projectionRadiusForObb(obb, axis)`

위치: `scene/collision.js`

임의 축에 대한 OBB의 projection radius를 계산한다. OBB 각 basis axis와 halfSize를 dot product로 조합한다. 벽 경계까지 남은 거리 계산에 사용된다.

### `objectWallBoundaryClearance(objectObb, wall)`

위치: `scene/collision.js`

가구 OBB가 벽 내부 경계로부터 얼마나 떨어져 있는지 계산한다. 값이 작거나 음수이면 벽 경계를 침범했거나 거의 닿은 상태다.

### `constrainedMovementBeforeWallCollision(object, movement, wallColliders)`

위치: `scene/collision.js`

현재 이동 제한의 핵심 함수다. 한 번의 큰 이동 벡터를 그대로 적용하지 않고, `wallConstraints.sweepStep` 기준으로 작은 step으로 나눈다. 각 step마다 `adjustedMovementForObbBeforeWallCollision()`을 호출해 벽을 넘지 않는 이동량만 누적한다.

이 방식은 빠르게 드래그했을 때 가구가 벽을 순간적으로 건너뛰는 문제를 줄인다. 충돌 후 되돌리는 방식이 아니라, 적용 전에 이동량을 제한한다.

### `adjustedMovementForObbBeforeWallCollision(objectObb, movement, wallColliders)`

위치: `scene/collision.js`

단일 step movement에서 벽 방향으로 파고드는 성분을 제거한다.

처리 방식:

- 이동 후 OBB가 벽 span과 겹치는지 검사
- `roomFacingNormal`이 있는 벽은 내부 경계 기준 clearance를 계산
- 벽 안쪽 방향 이동량이 clearance보다 크면 초과분 제거
- `roomFacingNormal`이 애매한 벽을 위해 `wallSolidClearance()`로 벽 OBB의 가장 얇은 축 기준 제한도 적용
- 벽과 평행한 이동 성분은 유지

### `wallSolidClearance(objectObb, wall)`

위치: `scene/collision.js`

벽 OBB의 가장 얇은 축을 벽 두께 방향으로 보고, 가구 OBB가 벽 실체까지 얼마나 떨어져 있는지 계산한다. 방 내부 방향 normal 판정이 불안정한 벽, 방 안쪽으로 튀어나온 벽을 보완하기 위해 사용한다.

### `initializeWallConstraints(editableObjects, wallColliders)`

위치: `scene/collision.js`

초기 로딩된 가구가 벽과 겹쳐 있으면 `pushObjectOutOfWalls()`로 벽 밖으로 밀어낸다. 이후 `lastValidPosition`, `lastValidQuaternion`, `lastValidScale`을 저장한다.

### `refreshCollisionState(editableObjects, selectedObject, wallColliders)`

위치: `scene/collision.js`

모든 editable object의 충돌 상태를 갱신한다. 벽과 충돌하면 `object.userData.collisions`에 `"wall"`을 넣고, `setFurnitureVisualState()`로 색상/edge 표시를 업데이트한다.

## 선택 오버레이 및 측정 표시

### `updateSelectionOverlay(object)`

위치: `hooks/useTestThreeEditor.js`

선택된 오브젝트 주변의 링, 치수 라벨 위치를 갱신한다.

주의할 점:

- 선택 링 크기와 라벨 위치는 `new THREE.Box3().setFromObject(object)` AABB 기반이다.
- 충돌 판정은 OBB 기반이지만, UI 측정 표시는 AABB를 사용한다.
- 링 반지름은 `Math.max(0.35, Math.max(size.x, size.z) * 0.58 + 0.18)`로 계산한다.

### `stableDimensionsForObject(object, fallbackSize)`

위치: `hooks/useTestThreeEditor.js`

표시용 치수를 안정적으로 가져온다. metadata의 dimensions가 있으면 그 값을 우선하고, 없으면 현재 bounds size를 fallback으로 사용한다.

## 방 치수 및 면적 계산

### `calculateRoomMeasurements(roomModel)`

위치: `scene/roomMeasurements.js`

방의 바닥 면적, 외곽선, width/depth/height를 계산한다.

구현 흐름:

1. `collectFloorAreaGroups()`로 바닥 mesh의 triangle들을 평면별 그룹으로 수집
2. 가장 큰 floor group을 선택
3. triangle edge 중 한 번만 등장하는 edge를 외곽선으로 추출
4. floor bounds로 width/depth 계산
5. 전체 room `Box3`로 height 계산
6. floor group이 없으면 room bounds 기반 fallback 면적 사용

### `addRoomMeasurements(measurements)`

위치: `hooks/useTestThreeEditor.js`

`calculateRoomMeasurements()` 결과를 바탕으로 방 외곽선, 치수 line, 면적 badge, pyung 표시를 생성한다.

## 벽 표시 및 카메라 기반 숨김

### `updateViewFacingWalls(wallColliders, camera, referenceRoots)`

위치: `hooks/useTestThreeEditor.js`

카메라 방향에 따라 시야를 가리는 벽이나 reference object를 숨기거나 흐리게 표시한다. 벽 내부를 보기 쉽게 하기 위한 preview 로직이다.

### `isWallHiddenFromCamera(wall, camera)`

위치: `hooks/useTestThreeEditor.js`

벽 normal과 카메라 방향을 비교해 현재 카메라에서 숨길 벽인지 판단한다.

### `applyWallFacePreview(wall, hidden)`

위치: `hooks/useTestThreeEditor.js`

벽 mesh의 특정 face group만 투명하게 만들거나 복원한다. face group 상태를 저장해 원래 material group을 복구할 수 있게 한다.

### `applyReferencePreviewVisibility(reference, hidden)`

위치: `hooks/useTestThreeEditor.js`

문/창문 reference object가 시야를 가릴 때 투명도를 낮추거나 숨김 상태로 표시한다.

## 메타데이터 직렬화 및 저장

### `objectToEditableJson(object)`

위치: `scene/roomMetadata.js`

가구/문/창문 object를 저장 가능한 JSON으로 변환한다.

포함 정보:

- id, sourceType, index
- catalogId, name, category, modelUrl/path
- dimensions, dimensionsCm
- position, rotation
- transform matrix columns
- collision 상태

### `serializeRoomModelToJson(roomModel, generatedFrom)`

위치: `scene/roomMetadata.js`

현재 방 모델 mesh들을 JSON으로 직렬화한다. geometry position/index, matrix, material 정보를 저장한다.

### `createRoomModelFromJson(roomJson)`

위치: `scene/roomMetadata.js`

저장된 room JSON에서 Three.js group과 mesh들을 복원한다.

### `createReplayableMetadataJson(metadata, editedItems, roomModel)`

위치: `scene/roomMetadata.js`

현재 편집 상태를 다시 로드 가능한 JSON 형태로 만든다. 기존 metadata를 clone하고, 편집된 objects/doors/windows와 직렬화된 room model을 합친다.

### `saveEditedSceneJson(saveContext)`

위치: `hooks/useTestThreeEditor.js`

현재 editedItems와 roomModel을 `createReplayableMetadataJson()`으로 묶은 뒤 `saveMetadataJson()`을 호출해 백엔드로 저장한다.

### `saveMetadataJson(metadata, saveContext)`

위치: `scene/sceneLoaders.js`

`RoomSpringBootApi.saveRoomMetadataJson()`을 호출해 백엔드에 편집 결과를 저장한다.

## 설정값

### `loadSceneConfig()`

위치: `scene/sceneConfig.js`

`/config/test-three-scene-config.json` 설정을 로드한다. 모델 URL, 색상, 벽 충돌 파라미터, 디버그 표시 여부 등을 제공한다.

### 주요 설정

위치: `public/config/test-three-scene-config.json`

| 키                                      | 의미                             |
| --------------------------------------- | -------------------------------- |
| `models`                                | category별 기본 GLB 모델 URL     |
| `colors.category`                       | category별 fallback box 색상     |
| `colors.collision`                      | 충돌 edge 색상                   |
| `colors.collisionFill`                  | 충돌 fill 색상                   |
| `wallConstraints.collisionEpsilon`      | OBB 교차 판정 여유값             |
| `wallConstraints.sweepStep`             | 이동 제한 step 크기              |
| `wallConstraints.sweepMaxSteps`         | 한 번 이동에서 나눌 최대 step 수 |
| `wallConstraints.colliderHalfThickness` | 벽 콜라이더 최소 반두께          |
| `wallConstraints.boundaryEpsilon`       | 벽 경계 허용 오차                |
| `wallConstraints.boundarySpanPadding`   | 벽 span 판정 padding             |
| `wallConstraints.showColliderDebug`     | 벽 콜라이더 디버그 표시 여부     |

## 현재 구현상 중요한 특징

- 가구와 벽 충돌은 OBB 중심이다.
- 가구 `localObb`는 모델 bounds를 기반으로 생성되고, 이동/회전 시 object matrix를 적용해 world OBB로 변환한다.
- UI 선택 링과 치수 라벨은 `Box3` AABB 기반이다.
- 이동은 충돌 후 되돌리는 방식이 아니라, 이동 적용 전에 movement vector를 제한한다.
- 빠른 이동에서 벽을 건너뛰지 않도록 movement를 작은 step으로 분할한다.
- 문/창문은 reference object로 관리되며 일반 가구와 충돌 제한 대상에서 제외된다.
- 충돌 상태 표시는 유지되며, 충돌한 editable furniture에는 `"wall"` collision이 기록된다.
