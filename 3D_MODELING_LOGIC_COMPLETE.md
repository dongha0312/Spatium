# Spatium 3D 공간 편집 전체 로직

> 기준 문서: `3D_MODELING_LOGIC.md`와 현재 웹·iOS 구현 코드
>
> 범위: RoomPlan으로 생성된 공간을 불러온 뒤, 가구를 편집하고 저장·복원하는 전체 흐름

## 1. 문서 목적

Spatium의 3D 공간 편집은 단순히 3D 모델을 화면에 보여주는 기능이 아니다. 실제 공간의 벽·바닥·문·창문과 가구의 실측 치수를 하나의 편집 가능한 공간 모델로 만들고, 사용자의 이동·회전·크기 조정을 공간 제약 안에서 처리한 뒤, 그 결과를 다시 열 수 있는 데이터로 저장한다.

웹과 앱은 서로 다른 렌더러를 사용하지만, 편집 대상과 핵심 동작은 다음 공통 모델을 따른다.

```text
공간(Room) + 객체(Object) + 변환값(Transform) + 제약조건(Constraint)
```

웹에서는 React와 Three.js를 기준으로 동작하며, iOS 앱에서는 동일한 의미의 데이터를 SwiftUI·SceneKit·GLTFKit2 환경에 맞게 연결한다.

---

## 2. 핵심 설계 원칙

### 2.1 렌더러와 편집 상태의 분리

렌더러가 관리하는 것은 화면에 표시되는 Mesh·Node이고, 편집 상태가 관리하는 것은 객체의 의미와 변환값이다.

```text
편집 상태
  ├─ 객체 종류와 모델 경로
  ├─ 위치(position)
  ├─ 회전(rotation)
  ├─ 크기(scale / dimensions)
  └─ 객체별 편집 속성

렌더러
  ├─ Three.js Object3D / Scene
  └─ iOS SCNNode / SCNScene
```

따라서 가구를 이동할 때 화면의 모델을 먼저 바꾸고, 이동이 끝나면 같은 결과를 편집 상태에 반영한다. UI는 편집 상태 중 선택된 객체, 회전값, 높이, 저장 상태처럼 사용자에게 필요한 값만 구독한다.

### 2.2 단위와 좌표 규약의 통일

- 내부 공간 단위는 미터(m)를 사용한다.
- UI에는 필요에 따라 센티미터(cm), 제곱미터(㎡), 평으로 변환해 표시한다.
- 가구 위치는 바닥 기준의 중심 좌표를 사용한다.
- 가구의 회전은 주로 Y축 회전으로 처리한다.
- GLB 모델은 원본 pivot에 의존하지 않고, 실제 bounds를 계산해 바닥이 `position.y`에 닿도록 보정한다.

이 규약을 통일해야 RoomPlan 좌표, GLB 모델 좌표, 웹·앱의 입력 좌표가 서로 어긋나지 않는다.

---

## 3. 전체 아키텍처

### 3.1 웹 구조

```text
3dEditor.js
  ├─ 프로젝트·방 정보 로딩
  ├─ 가구 카탈로그 로딩
  ├─ 저장·취소·방 전환 UI
  └─ RoomSceneEditorPage
       └─ useRoomSceneEditor
            ├─ Three.js scene / camera / renderer / OrbitControls
            ├─ 방 모델과 metadata 로딩
            ├─ 가구·문·창문 Object3D 생성
            ├─ pointer 기반 선택·이동·회전
            ├─ 벽 면 Collider와 OBB 충돌 판정
            ├─ 카메라·벽 투명화·측정 표시
            └─ metadata JSON 저장
```

### 3.2 iOS 구조

```text
RoomEditorView
  └─ RoomEditorSceneView (UIViewRepresentable)
       └─ Coordinator
            ├─ SceneKit scene / camera / gesture
            ├─ USDZ 방 shell 로딩
            ├─ FurnitureModelLoader (GLTFKit2로 GLB 로딩)
            ├─ hitTest 기반 선택·이동
            ├─ WallCollider와 FurnitureFootprint 충돌 판정
            └─ RoomEditorViewModel
                 ├─ RoomLayout
                 ├─ transform·선택 상태
                 ├─ undo/redo·임시 draft
                 └─ metadata JSON 저장
```

### 3.3 공통 로직과 플랫폼별 구현

| 편집 단계 | 웹 기준 구현 | iOS 구현 | 공통 의미 |
| --- | --- | --- | --- |
| 공간 렌더링 | Three.js Scene | SceneKit SCNScene | 방 shell과 객체를 3D로 표시 |
| 모델 로딩 | USDLoader / GLTFLoader | USDZ + GLTFKit2 | 공간·가구 모델 로드 |
| 객체 선택 | Raycaster | `SCNView.hitTest` | 사용자가 편집할 객체 식별 |
| 바닥 이동 | Ray와 바닥 Plane 교차 | 바닥 Node hitTest | 손가락 위치를 월드 좌표로 변환 |
| 변환 편집 | `Object3D.position/quaternion/scale` | `SCNNode.position/eulerAngles/scale` | 위치·회전·크기 변경 |
| 충돌 | OBB + wall collider | FurnitureFootprint + WallCollider | 벽을 통과하지 않도록 이동 제한 |
| 상태 저장 | `_spatiumRoom` 포함 metadata JSON | `editedObjects` metadata + `RoomLayout` | 편집 결과를 재현 가능한 데이터로 저장 |

---

## 4. 데이터 흐름

```text
1. RoomPlan 스캔
      ↓
2. USDZ 공간 모델 + metadata JSON 생성
      ↓
3. 프로젝트/룸 조회
      ↓
4. 방 shell 로딩 및 벽·바닥·개구부 분류
      ↓
5. metadata의 객체 목록으로 가구·문·창문 복원
      ↓
6. 사용자의 선택·이동·회전·크기 조정
      ↓
7. 충돌·벽 제약을 적용한 유효 transform 반영
      ↓
8. 객체 transform과 방 변경 사항을 metadata JSON으로 직렬화
      ↓
9. 서버 저장
      ↓
10. 다음 진입 시 저장 metadata를 우선 복원
```

### 4.1 웹 진입 데이터

웹 에디터는 URL의 `projectId`, `roomId`를 기준으로 편집 대상을 결정한다.

```text
/member/editor?projectId=...&roomId=...
```

필요한 데이터는 다음과 같다.

| 데이터 | 용도 |
| --- | --- |
| 프로젝트 정보 | 상단 프로젝트명·방 목록 표시 |
| 방 씬 데이터 | 방 모델과 metadata 로딩 |
| 가구 카탈로그 | 새 가구 추가·교체 |
| scene config | 기본 모델 URL, 색상, 벽 제약 파라미터 |

### 4.2 방 모델 선택 우선순위

웹 렌더링 시 방 모델은 다음 순서로 선택한다.

1. API 응답의 `roomScene.model.dataBase64`
2. scene config의 `room.modelUrl`
3. 저장 metadata 안의 `_spatiumRoom` JSON으로 복원한 방 모델

단, metadata에 `_spatiumRoom`이 있으면 저장된 편집 결과를 원본 USD보다 우선한다. 이 정책으로 벽을 메우거나 색상을 바꾼 결과도 원본 USDZ 없이 다시 표시할 수 있다.

### 4.3 앱의 두 가지 진입 모드

- **서버 룸 모드**: 서버 layout을 조회하고 저장 가능한 방을 편집한다.
- **스캔 직후 모드**: 아직 서버에 올리지 않은 USDZ와 `EditableScanItem`으로 로컬 편집을 시작한 뒤, 저장 시 프로젝트에 업로드한다.

앱의 `RoomEditorViewModel`은 두 모드를 구분해 원격 layout 조회 여부, 오프라인 상태, 저장 대상 room ID를 관리한다.

---

## 5. 씬 초기화

### 5.1 웹 초기화 순서

```text
loadSceneConfig()
  ↓
renderer / CSS2DRenderer / scene / camera / OrbitControls 생성
  ↓
방 모델과 metadata 병렬 로딩
  ↓
저장된 _spatiumRoom이 있으면 JSON 방 모델 복원
  ↓
prepareRoomModel()
  ↓
createWallColliders()
  ↓
가구·문·창문 Object3D 생성
  ↓
initializeWallConstraints()
  ↓
카메라 framing 및 첫 상태 동기화
```

`useRoomSceneEditor`는 위 과정을 하나의 편집 세션으로 묶고, 실제 기능은 `scene/` 유틸리티로 분리한다.

### 5.2 씬 레이어

웹에서는 다음 레이어를 나누어 관리한다.

- `worldGroup`: 방 shell과 바닥
- `furnitureLayer`: 일반 가구
- `referenceLayer`: 문·창문·개구부 marker
- `selectionLayer`: 선택 링·transform 표시
- `wallDiagnosticLayer`: 충돌 진단용 시각화
- `roomMeasurementLayer`: 치수선·면적·외곽선

레이어를 분리하면 선택 표시, 충돌 디버깅, 측정 표시를 본체 Mesh와 독립적으로 켜고 끌 수 있다.

### 5.3 iOS 씬 구성

iOS는 `SCNScene`을 생성한 뒤 스캔 방이면 USDZ shell만 남기고, 방이 없는 서버 layout이면 면적·천장 높이로 단순 박스 방을 만든다.

- 스캔 방: 벽·바닥 Mesh를 배경으로 사용하고, 감지된 가구는 별도 GLB로 렌더링한다.
- 박스 방: 면적에서 한 변을 추정해 바닥과 벽을 생성한다.
- 가구 추가·삭제·교체 시에는 필요한 노드만 재생성하고, 위치·회전만 바뀌는 경우 기존 노드를 재사용한다.

---

## 6. 방 모델과 벽 Collider

### 6.1 Mesh 분류

방 Mesh를 순회하면서 이름 패턴과 `userData`를 이용해 다음을 구분한다.

- 벽 Mesh
- 바닥 Mesh
- 저장 대상에서 제외할 교체 Mesh
- 문·창문과 같은 reference Mesh

이 분류 결과는 충돌, 측정, 색상 변경, metadata 직렬화에서 공통으로 사용한다.

### 6.2 벽 면 단위 Collider

스캔된 벽은 하나의 반듯한 박스가 아니라 삼각형 Mesh의 집합이다. 벽 전체를 하나의 bounding box로 처리하면 문·창문 개구부까지 막히거나 ㄱ자 벽 주변이 과도하게 차단된다.

따라서 벽 Mesh의 삼각형을 분석해 실제 벽 면에 가까운 face마다 Collider를 만든다.

각 Collider는 다음 정보를 가진다.

| 필드 | 의미 |
| --- | --- |
| `obb` 또는 footprint 범위 | 벽의 실제 충돌 영역 |
| `roomFacingNormal` | 방 안쪽을 향하는 방향 |
| `spanAxes` / `lengthAxis` | 벽 길이 방향 |
| `spanPolygon` | 벽 면을 2D로 투영한 경계 |
| `object` / `node` | 원본 벽 Mesh 참조 |

face 분석이 불가능한 특수 Mesh는 전체 bounds 기반 OBB로 fallback한다. 이중 경로가 있어 일반적인 USD Mesh와 예외적인 Mesh를 함께 처리할 수 있다.

### 6.3 방 안쪽 기준 충돌

단순한 박스 교차만 확인하지 않고, 가구의 footprint가 방 안쪽 경계선을 침범했는지를 확인한다.

```text
가구 중심과 벽 normal 비교
  ↓
가구 footprint를 normal 방향으로 투영
  ↓
벽의 방 안쪽 projection을 넘었는지 확인
  ↓
침범한 경우 normal 방향 이동을 제한
```

이 방식은 벽 바깥쪽이나 개구부 주변에서 불필요한 차단이 발생하는 것을 줄인다.

---

## 7. 가구·문·창문 모델 생성

### 7.1 가구 생성

가구 추가 시 카탈로그 항목을 편집용 객체로 변환한다.

1. 카탈로그에서 모델 URL 또는 GLB 경로를 찾는다.
2. GLB scene을 clone한다.
3. 전체 hierarchy의 geometry bounds를 계산한다.
4. metadata 치수에 맞춰 모델을 스케일한다.
5. pivot을 바닥 중심으로 이동한다.
6. 충돌용 local OBB와 선택용 invisible pick box를 만든다.
7. `userData`에 source type, room item, local OBB, 원본 transform을 기록한다.

모델을 찾지 못하면 입력 치수 기반 fallback box를 생성해 편집을 계속할 수 있도록 한다.

### 7.2 GLB 아티팩트와 재질 보정

일부 GLB에는 모델 본체 외에 제작 툴의 UI 잔여 Mesh가 포함될 수 있다. 모델 이름·재질 이름 패턴을 검사해 해당 아티팩트를 제거한다.

문·창문의 유리 재질이 `alphaMode: OPAQUE`로 저장된 경우에는 재질 이름을 기준으로 투명도를 보정한다. 인스턴스별 재질을 clone해 한 모델의 투명도 변경이 다른 인스턴스에 전파되지 않도록 한다.

### 7.3 문·창문 reference object

문·창문은 일반 가구와 달리 방 구조의 일부로 취급한다.

- 이동·높이 조정 대상이 아니다.
- 같은 reference 계열 모델로 교체할 수 있다.
- 삭제 시 개구부를 유지하거나 벽으로 메울 수 있다.
- 벽으로 메운 결과는 새 벽 Mesh와 Collider로 관리한다.

### 7.4 문·창문 두께 fitting

RoomPlan metadata는 문·창문을 두께가 거의 없는 평면으로 기록할 수 있다. 실제 모델을 임의의 두께로 넣으면 벽 앞·뒤로 튀어나오기 때문에 다음 과정을 적용한다.

```text
문·창문 위치에서 가장 가까운 벽 탐색
  ↓
벽 Mesh의 가장 짧은 축을 두께 방향으로 결정
  ↓
벽 정점을 해당 축에 투영해 실측 두께·중심 계산
  ↓
reference 모델의 두께를 벽 두께에 맞춰 clamp
  ↓
벽 중심으로 위치 재정렬
```

벽으로 메우는 infill Mesh도 동일한 벽 두께 측정 결과를 사용한다. 매칭된 벽의 재질을 clone해 색상, roughness, texture를 유지한다.

---

## 8. 객체 선택과 transform 편집

### 8.1 선택

웹은 `THREE.Raycaster`로 pick target을 검사하고, 실제 선택 대상의 상위 editable root를 찾는다. 앱은 `SCNView.hitTest`로 노드와 floor hit를 조회한다.

선택 시 다음 상태를 함께 갱신한다.

- 선택된 객체 ID
- 객체 종류
- 현재 치수
- 회전값
- 높이 조정 가능 여부
- 교체·삭제·꾸미기 가능 여부
- 현재 충돌 상태

### 8.2 이동

드래그 위치를 바닥 Plane과 교차시켜 월드 좌표로 바꾼다. 드래그 시작 시 손가락과 객체 중심의 offset을 저장해, 잡은 위치가 객체 중심으로 튀지 않도록 한다.

```text
pointer/touch 시작
  ↓
선택 객체와 grab offset 저장
  ↓
현재 입력점을 바닥 좌표로 변환
  ↓
목표 위치 계산
  ↓
벽 제약 적용
  ↓
허용된 위치를 렌더러와 편집 상태에 반영
```

### 8.3 회전과 높이

- 회전은 Y축을 기준으로 처리한다.
- 웹은 회전 제어와 슬라이더 입력을 통해 각도를 조정한다.
- 앱은 회전 스톱 값 근처에서 `-180, -90, 0, 90, 180`도로 스냅한다.
- 높이는 바닥 높이와 천장 높이 사이로 clamp한다.
- 문·창문과 벽 infill은 일반 가구와 달리 높이·크기 편집 대상에서 제외한다.

### 8.4 크기 조정

웹과 앱 모두 배치 후 선택된 일반 가구의 가장 긴 변을 기준으로 크기 슬라이더를 적용한다. 세 축을 같은 비율로 조정해 비율이 찌그러지지 않도록 하고, 하단 높이를 유지한 채 새 footprint가 벽을 침범했는지 다시 검사한다. 웹의 추가 모달은 초기 치수를 정하는 입력이고, 선택 후 슬라이더는 배치된 객체의 후속 크기 조정이다.

---

## 9. OBB 충돌과 Sweep 이동

### 9.1 AABB의 한계

축에 맞춰진 AABB는 회전된 가구의 실제 폭·깊이를 정확하게 표현하지 못한다. 회전 후에도 고정된 축의 큰 박스를 사용하면 벽에 닿기 전에 막히거나, 반대로 모서리가 벽을 통과할 수 있다.

### 9.2 가구 footprint

가구의 실제 가로·깊이와 Y축 회전값으로 회전된 footprint를 계산한다.

```text
halfWidth, halfDepth + rotationY
  ↓
벽 normal 방향으로 projection radius 계산
  ↓
벽과 가구의 수평 overlap 판정
```

웹은 Three.js OBB를 사용하고, 앱은 같은 계산을 `FurnitureFootprint` 구조체로 구현한다.

### 9.3 Sweep 방식

한 번에 큰 이동을 적용하면 한 프레임 사이에 벽을 건너뛰는 tunneling이 발생할 수 있다. 따라서 이동 벡터를 작은 step으로 분할한다.

```text
요청된 이동 벡터
  ↓
작은 step으로 분할
  ↓
각 step마다 벽 overlap 확인
  ↓
벽을 향하는 inward 성분만 제거
  ↓
접선 방향 이동은 유지
  ↓
허용된 step 누적
```

이 방식은 충돌 시 객체를 통째로 되돌리는 것이 아니라 벽에 닿을 때까지 이동시키고, 벽에 붙은 상태에서 평행 방향으로 미끄러지게 한다.

### 9.4 이동 후 penetration resolve

새 가구 추가·교체·크기 확대 직후에는 이미 벽을 침범한 상태로 시작할 수 있다. 이때 벽의 방 안쪽 normal 방향으로 침투량만큼 반복 이동시켜 유효한 위치로 되돌린다.

```text
새 footprint 계산
  ↓
침범한 벽 탐색
  ↓
침투량 × roomFacingNormal만큼 밀어내기
  ↓
모든 벽을 다시 검사
  ↓
침투가 없어질 때까지 반복
```

### 9.5 충돌 대상

일반 벽뿐 아니라 벽으로 메운 infill도 Collider 목록에 포함한다. 문·창문 reference는 벽 위에 배치되는 객체이므로 일반 가구의 벽 이동 제한에서는 제외하되, 교체·삭제 결과가 다시 Collider와 metadata에 반영되도록 한다.

---

## 10. 문·창문 편집과 벽 infill

### 10.1 교체

선택된 reference object의 모델, 치수, 재질을 새 카탈로그 항목으로 교체한다. 기존 위치와 방향은 유지하되, 새 모델의 bounds에 맞춰 fitting을 다시 수행한다.

### 10.2 개구부 유지

reference object만 제거하고 방 Mesh의 개구부는 그대로 둔다. 저장 시에도 문·창문 목록과 개구부 상태를 metadata에 반영한다.

### 10.3 벽으로 메우기

1. 선택된 문·창문의 bounds를 읽는다.
2. 소속 벽의 두께·중심을 측정한다.
3. 동일한 재질의 infill box를 생성한다.
4. infill에 벽 Mesh임을 나타내는 metadata를 기록한다.
5. 기존 reference를 제거한다.
6. 벽 Collider를 다시 생성한다.
7. 기존 가구가 새 벽을 침범했는지 재검사한다.

이 과정을 통해 단순히 화면에서 문을 숨기는 것이 아니라, 방 구조 자체가 바뀐 것처럼 이동·충돌·저장·복원이 일관되게 동작한다.

---

## 11. 카메라와 표시 로직

### 11.1 카메라

- 일반 3D 모드: OrbitControls 또는 SceneKit 기본 카메라 컨트롤
- Skyview: 방 전체를 위에서 내려다보는 위치로 전환
- 1인칭 시점: 웹과 앱 모두 방 안의 눈높이 카메라를 제공한다. 웹은 WASD/방향키 이동과 캔버스 드래그 시야 회전, 앱은 Swift 제스처 기반 이동·시야 회전을 사용한다.

Skyview 전환 전에는 카메라 위치·target·제어 제한을 저장하고, 일반 3D로 돌아올 때 복원한다.

### 11.2 카메라 기준 벽 투명화

카메라 방향과 각 벽 면의 normal을 비교해 시야를 가리는 벽만 투명하게 만든다. 벽 전체를 숨기지 않고 geometry group 또는 surface 단위로 material을 변경해 방 내부가 자연스럽게 보이도록 한다.

### 11.3 측정 표시

방의 벽 길이, 폭·깊이·높이, 바닥 면적과 선택 가구의 크기를 계산한다. 웹은 CSS2DRenderer 라벨, 앱은 SceneKit의 선·텍스트 노드로 표시한다.

측정값은 원본 Mesh bounds만 사용하지 않고, 방 바닥 외곽과 벽 segment를 기준으로 안정적인 치수를 계산한다.

---

## 12. 꾸미기 객체(피규어) 로직

책장처럼 꾸미기를 지원하는 가구는 별도의 decor mode를 가진다.

1. 꾸미기 대상 가구 선택
2. 카메라를 대상 가구 중심으로 전환
3. 피규어 모델을 부모 가구의 로컬 좌표계에 배치
4. 선반 표면의 support point를 계산
5. 피규어 위치·회전·균일 크기를 저장
6. 부모 가구를 이동·회전하면 피규어도 함께 이동

웹은 피규어를 가구 root의 자식으로 구성하고, 앱은 비균일 스케일에 의한 찌그러짐을 피하기 위해 별도 decor container를 가구와 동기화한다.

---

## 13. 저장과 복원

### 13.1 공통 저장 단위

편집 결과는 다음 정보를 포함한다.

```json
{
  "name": "bed",
  "modelUrl": ".../bed.glb",
  "dimensions": { "x": 1.24, "y": 0.70, "z": 1.97 },
  "position": { "x": 0.4, "y": 0.0, "z": -0.6 },
  "rotation": { "x": 0, "y": 1.57, "z": 0 },
  "scale": { "x": 1, "y": 1, "z": 1 }
}
```

객체 목록뿐 아니라 벽 infill, 색상, 문·창문 변경, 방 Mesh 복원 정보까지 포함해야 저장된 편집 세션을 재현할 수 있다.

### 13.2 웹 저장

웹의 `createReplayableMetadataJson()`은 현재 씬을 순회해 객체 transform을 JSON으로 만들고, 방 Mesh의 geometry·material·transform도 `_spatiumRoom`에 포함한다.

저장 흐름은 다음과 같다.

```text
현재 씬 순회
  ↓
가구·reference·decor 직렬화
  ↓
방 Mesh 직렬화
  ↓
FormData 생성
  ↓
POST /api/rooms/save
```

웹도 앱과 동일하게 편집 중 snapshot을 이력으로 보관한다. Undo/Redo는 현재 가구·reference·decor·방 Mesh·색상을 포함한 replayable metadata snapshot을 이전/다음 상태로 적용해 씬을 복원한다. 객체 수·모델·방 구조가 그대로인 transform 변경은 기존 Three.js 노드에 transform만 적용하고, 추가·삭제·교체·벽 구조 변경일 때만 전체 씬을 재생성한다. 웹의 미저장 상태는 기존 `저장되지 않은 변경사항` 경고로 안내하고, 별도 로컬 Draft는 사용하지 않는다.

### 13.3 앱 저장

iOS는 화면 편집 상태를 `RoomLayout`으로 관리하고, 서버 metadata에는 `editedObjects` 형식으로 내보낸다. 서버 룸이 아닌 스캔 직후 상태는 USDZ와 metadata를 함께 업로드해 새 룸을 만든다.

편집 중에는 다음 안전장치가 있다.

- 저장 전 변경 여부 fingerprint 비교
- 최대 30개 수준의 undo/redo history
- 임시 draft 파일 저장
- 앱 재진입 시 복구 가능한 draft 탐지
- 서버 저장 성공 후 draft 제거

### 13.4 복원 우선순위

```text
저장 metadata의 방·객체 정보
  ↓ 없으면
원본 USDZ + 원본 metadata
  ↓ 없으면
기본 박스 방 또는 fallback object
```

저장본을 우선 사용해야 벽을 메운 결과, 가구 삭제, 사용자 모델 교체와 같은 편집 내용이 사라지지 않는다.

---

## 14. 상태 관리와 이벤트 흐름

### 14.1 웹

Three.js 객체는 React state에 매 프레임 넣지 않는다. 렌더링 중에는 ref로 객체를 직접 관리하고, 선택 객체 정보·충돌 요약·저장 가능 여부처럼 UI에 필요한 값만 React state로 동기화한다.

```text
pointer event
  ↓
scene action ref
  ↓
Object3D transform 변경
  ↓
collision / measurement 갱신
  ↓
UI state 최소 동기화
```

### 14.2 iOS

`RoomEditorViewModel`이 `@Published` 상태를 소유한다. SceneKit Coordinator는 실제 노드와 제스처를 관리하고, transform 변경이 끝나면 ViewModel의 `commitTransform()`을 호출한다.

슬라이더처럼 하나의 조작이 여러 번 호출되는 경우에는 history transaction을 사용해 하나의 undo step으로 묶는다.

---

## 15. 성능과 견고성

### 15.1 모델 캐시

같은 GLB를 여러 번 파싱하지 않도록 모델 template을 캐시하고 clone해 사용한다. iOS는 메모리 경고 시 GLB template cache를 비워 메모리 피크를 낮춘다.

### 15.2 증분 갱신

위치·회전만 바뀌는 경우 Mesh를 새로 만들지 않고 transform만 갱신한다. 추가·삭제·교체·색상 변경처럼 geometry가 바뀌는 경우에만 필요한 노드를 재생성한다.

### 15.3 충돌 계산 최적화

- 드래그 중에는 필요한 벽과 선택 객체만 경량 검사
- 문·창문 reference의 정적 Collider는 캐시
- 벽 face 분석 실패 시 bounds fallback
- 벽으로 메운 뒤에만 Collider 전체를 재생성

### 15.4 리소스 정리

씬 전환 또는 객체 삭제 시 geometry, material, texture와 같은 GPU 리소스를 dispose한다. Pointer capture, CADisplayLink, gesture recognizer도 화면 종료 시 해제한다.

---

## 16. 주요 예외 상황과 해결 방식

| 상황 | 원인 | 처리 |
| --- | --- | --- |
| 빠른 드래그로 벽 통과 | 프레임 사이 이동량이 벽 두께보다 큼 | 이동을 작은 step으로 분할하는 Sweep 적용 |
| 회전 후 가구가 벽에 파묻힘 | AABB가 회전 상태를 반영하지 못함 | OBB/회전 footprint로 projection 계산 |
| 문·창문이 벽 앞뒤로 돌출 | RoomPlan reference가 평면·앞면 좌표로 저장됨 | 실제 벽 두께 측정 후 clamp·중심 보정 |
| 일부 GLB에 검은 판이 표시됨 | 제작 툴 UI 잔여 Mesh가 함께 export됨 | 이름·재질 패턴 기반 아티팩트 제거 |
| 유리가 불투명하게 표시됨 | alphaMode가 OPAQUE로 저장됨 | 유리 재질 투명도 강제 적용 |
| 벽으로 메운 자리가 색이 다름 | 새 Mesh가 기본 재질로 생성됨 | 매칭 벽 material clone 사용 |
| 벽으로 메운 뒤 가구가 파묻힘 | 새 벽 Collider 생성 후 기존 가구를 재검사하지 않음 | Collider 재생성 후 전체 가구 penetration resolve |
| 앱 재진입 시 편집이 사라짐 | 서버 저장 전 앱 종료 | 앱의 local draft와 복구 가능한 draft 제공 |

---

## 17. 코드 책임 맵

### 웹

| 역할 | 파일 |
| --- | --- |
| 화면·프로젝트·저장 UI | `spatium-frontend/src/pages/3dEditor.js` |
| Three.js 뷰와 액션 ref | `spatium-frontend/src/pages/roomSceneEditor/RoomSceneEditorPage.js` |
| 편집 세션 orchestration | `spatium-frontend/src/pages/roomSceneEditor/hooks/useRoomSceneEditor.js` |
| 방·모델 로딩 | `scene/sceneLoaders.js` |
| 가구·문·창문 생성 | `scene/objectFactory.js` |
| 벽 Collider | `scene/wallColliders.js` |
| OBB 충돌·이동 제한 | `scene/collision.js` |
| 저장·복원 직렬화 | `scene/roomMetadata.js` |
| 벽 투명화·색상 | `scene/wallVisibility.js`, `scene/floorColor.js` |
| 치수·면적 계산 | `scene/roomMeasurements.js`, `scene/measurementLabels.js` |

### iOS

| 역할 | 파일 |
| --- | --- |
| 편집 상태·저장·undo/redo | `Features/Editor/RoomEditorViewModel.swift` |
| SceneKit 씬·제스처·카메라 | `Features/Editor/RoomEditorSceneView.swift` |
| SwiftUI 편집 화면 | `Features/Editor/RoomEditorView.swift` |
| GLB 로딩·bounds·pivot 보정 | `Core/Services/FurnitureModelLoader.swift` |
| 공통 layout·transform 모델 | `Core/Models/RoomLayout.swift` |
| 스캔 객체 metadata | `Core/Models/EditableScanItem.swift` |
| 저장 요청 추상화 | `Core/Services/RoomEditorService.swift` |

---

## 18. 전체 로직 의사코드

```text
openRoom(roomId)
  roomData = fetchRoomScene(roomId)
  metadata = fetchMetadata(roomId)

  scene = createRendererScene()
  roomModel = restoreSavedRoom(metadata._spatiumRoom) ?? loadUsdRoom(roomData)
  prepareRoomModel(roomModel)

  wallColliders = createWallColliders(roomModel)
  objects = restoreObjects(metadata)

  for object in objects:
      model = loadOrFallbackModel(object)
      fitModelToDimensions(model, object.dimensions)
      createPickTargetAndOBB(model)
      addToScene(model)

  onPointerMove(pointer):
      target = raycastOrHitTest(pointer)
      proposed = projectToFloor(target)
      allowed = constrainedMovementBeforeWallCollision(
          object, proposed - current, wallColliders
      )
      object.position += allowed
      syncEditorState(object)

  onRotateOrResize(value):
      applyTransform(value)
      if intersectsWall(object):
          rollbackToLastValidTransform()

  save():
      metadata = serializeRoomAndObjects(scene)
      upload(metadata)

  reopen():
      restoreSavedRoom(metadata)
```

---

## 19. 발표에서 강조할 핵심

1. 웹과 앱의 차이는 렌더러, 입력 방식, Draft 정책이다. 1인칭 시점·크기 조정·Undo/Redo 편집 로직은 동일하고, Draft 복구는 앱에서만 제공한다.
2. 핵심 기술은 실측 치수 기반 모델 fitting, 회전 대응 OBB, 벽 면 단위 Collider, Sweep 이동이다.
3. 편집 결과는 단순한 가구 위치 목록이 아니라 방 구조 변경까지 포함하는 재생 가능한 metadata로 저장한다.
4. 따라서 사용자는 실제 공간을 단순히 보는 것이 아니라, 제약 조건이 반영된 3D 공간 안에서 직접 인테리어를 편집할 수 있다.
