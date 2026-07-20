import * as THREE from "three";

// 꾸미기(피규어 올려놓기)를 지원하는 가구 판정 — 모델 GLB가
// public/data/3d_models/editable_furniture/ 폴더에 있는 가구만 대상이다.
// (일반 카탈로그 GLB는 통짜 형태라 선반 안쪽 표면이 없어서, 꾸미기 전용으로 만든
// 모델만 폴더로 구분해 허용한다.)
const DECORATABLE_MODEL_PATH = /\/editable_furniture\//i;

export function isDecoratableModelPath(path) {
  return DECORATABLE_MODEL_PATH.test(path || "");
}

// 피규어를 올려놓을 수 있는 표면으로 인정하는 법선의 최소 Y 성분(위쪽 방향과의 코사인).
// 0.7이면 약 45도 이내로 기울어진 면(상판, 선반 바닥)만 허용하고, 옆면/앞면은 걸러진다.
const SUPPORT_NORMAL_MIN_Y = 0.7;

const worldNormal = new THREE.Vector3();

// 서랍장 root에서 "피규어가 실제로 닿을 수 있는" 렌더링 mesh들만 모은다.
// 클릭 판정용 투명 hitBox(userData.isCollisionHitBox)와, 이미 올려둔 피규어의
// mesh(피규어 subtree 전체)는 제외한다 — 표면 스냅은 서랍장 지오메트리 기준이어야 한다.
export function collectSupportMeshes(furnitureRoot) {
  const meshes = [];

  function visit(object) {
    if (object.userData?.isDecorFigure) return;
    if (object.isMesh && !object.userData?.isCollisionHitBox) {
      meshes.push(object);
    }
    object.children.forEach(visit);
  }

  visit(furnitureRoot);
  return meshes;
}

// raycast hit의 face normal(오브젝트 로컬)을 월드 방향으로 변환해 "위를 향하는 면"인지
// 판정한다. transformDirection은 matrixWorld의 회전/스케일만 적용하고 정규화까지 해준다.
function isUpFacingHit(hit) {
  if (!hit.face) return false;

  worldNormal
    .copy(hit.face.normal)
    .transformDirection(hit.object.matrixWorld);
  return worldNormal.y >= SUPPORT_NORMAL_MIN_Y;
}

// 이미 세팅된 raycaster(포인터 방향)로 서랍장 표면 중 "피규어를 놓을 수 있는" 지점을
// 찾는다. 거리순 히트 중 첫 번째 위쪽 면을 고르므로, 서랍장 앞면을 가로질러 드래그하면
// 그 안쪽 선반 바닥에 자연스럽게 놓인다. 없으면 null.
export function findSupportPointOnRay(raycaster, supportMeshes) {
  const hits = raycaster.intersectObjects(supportMeshes, false);
  const supportHit = hits.find(isUpFacingHit);
  if (!supportHit) return null;

  return {
    point: supportHit.point.clone(),
    normalY: worldNormal.y,
  };
}

// 지지 판정 down-raycast를 현재 바닥보다 얼마나 위에서 시작할지(m).
const SUPPORT_PROBE_HEIGHT = 0.1;
// 같은 층으로 인정하는 표면 높이 차(m) — 이보다 낮은 표면은 "가장자리를 벗어났다"로 본다.
const SUPPORT_LEVEL_TOLERANCE = 0.06;
// 가장자리 제한 이동의 sweep step 크기(m)와 스텝 수 상한. 벽 충돌 이동 제한
// (collision.js의 constrainedMovementBeforeWallCollision)과 같은 방식이다.
const SLIDE_STEP = 0.02;
const SLIDE_MAX_STEPS = 64;

const probeRaycaster = new THREE.Raycaster();
const probeOrigin = new THREE.Vector3();
const DOWN = new THREE.Vector3(0, -1, 0);

// 월드 (x, z)에서 기준 높이(nearY) 근처의 지지 표면 Y를 찾는다. 현재 층에서
// SUPPORT_LEVEL_TOLERANCE 이상 낮은 표면은 무시하므로, 선반 가장자리를 넘어가면
// null이 반환된다.
function supportHeightAt(supportMeshes, x, z, nearY) {
  probeOrigin.set(x, nearY + SUPPORT_PROBE_HEIGHT, z);
  probeRaycaster.set(probeOrigin, DOWN);
  probeRaycaster.far = SUPPORT_PROBE_HEIGHT + SUPPORT_LEVEL_TOLERANCE;

  const hits = probeRaycaster.intersectObjects(supportMeshes, false);
  const supportHit = hits.find(isUpFacingHit);

  probeRaycaster.far = Infinity;
  return supportHit ? supportHit.point.y : null;
}

// 피규어 바닥 중심의 월드 좌표(현재 놓여 있는 지지점).
export function figureWorldSupportPoint(figureRoot, target = new THREE.Vector3()) {
  figureRoot.getWorldPosition(target);
  target.y += figureBottomOffset(figureRoot);
  return target;
}

// 피규어의 지지점을 requestedPoint(월드, 현재 층 평면 위의 목표)로 옮기되, 지지 표면을
// 벗어나기 직전까지만 허용한다. 벽 충돌 이동 제한과 같은 sweep 방식이다:
// 이동을 작은 step으로 나눠 각 step마다 지지 여부를 검사하고, step이 통째로 막히면
// X/Z 축 성분별로 나눠 시도해서 가장자리를 따라 미끄러지게 한다.
// 반환값은 실제로 허용된 지지점(월드)이며, 전혀 못 움직이면 현재 지지점 그대로다.
export function constrainedSupportPoint(figureRoot, supportMeshes, requestedPoint) {
  const current = figureWorldSupportPoint(figureRoot);
  let x = current.x;
  let z = current.z;
  let y = current.y;

  const totalX = requestedPoint.x - x;
  const totalZ = requestedPoint.z - z;
  const distance = Math.hypot(totalX, totalZ);
  if (distance < 1e-6) return current;

  const stepCount = Math.min(
    Math.max(1, Math.ceil(distance / SLIDE_STEP)),
    SLIDE_MAX_STEPS,
  );
  const stepX = totalX / stepCount;
  const stepZ = totalZ / stepCount;

  for (let step = 0; step < stepCount; step += 1) {
    const fullY = supportHeightAt(supportMeshes, x + stepX, z + stepZ, y);
    if (fullY != null) {
      x += stepX;
      z += stepZ;
      y = fullY;
      continue;
    }

    // 대각선 이동이 막혔으면 축별로 나눠 시도한다 — 가장자리에 붙어 미끄러지는 효과.
    const xOnlyY = supportHeightAt(supportMeshes, x + stepX, z, y);
    if (xOnlyY != null) {
      x += stepX;
      y = xOnlyY;
      continue;
    }

    const zOnlyY = supportHeightAt(supportMeshes, x, z + stepZ, y);
    if (zOnlyY != null) {
      z += stepZ;
      y = zOnlyY;
      continue;
    }

    break;
  }

  return current.set(x, y, z);
}

// 피규어 root의 부모(서랍장) 좌표계에서 "바닥면"의 Y 오프셋. 피규어 position.y를
// (표면 Y - 이 값)으로 두면 바닥면이 표면에 정확히 닿는다. localObb는 scale 1 기준이므로
// 크기 슬라이더로 조절된 현재 scale을 곱해서 계산한다.
export function figureBottomOffset(figureRoot) {
  const localObb = figureRoot.userData.localObb;
  if (!localObb) return 0;
  return (localObb.center.y - localObb.halfSize.y) * figureRoot.scale.y;
}

// 월드 좌표의 지지점(supportPoint)에 피규어의 바닥 중심이 오도록, 부모(서랍장 root)
// 로컬 좌표계 기준 position을 계산해 적용한다. 피규어는 서랍장의 자식이므로 서랍장이
// 나중에 이동/회전해도 상대 위치가 유지된다.
export function placeFigureAtSupportPoint(figureRoot, supportPoint) {
  const parent = figureRoot.parent;
  if (!parent) return;

  parent.updateWorldMatrix(true, false);
  const localPoint = parent.worldToLocal(supportPoint.clone());
  figureRoot.position.set(
    localPoint.x,
    localPoint.y - figureBottomOffset(figureRoot),
    localPoint.z,
  );
  figureRoot.updateWorldMatrix(true, false);
}
