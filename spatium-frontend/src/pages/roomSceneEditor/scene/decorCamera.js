import * as THREE from "three";
import { projectionRadiusForObb, worldObbForObject } from "./collision";

// 정면 시점에서 서랍장이 화면에 꽉 차지 않게 주는 여유 배율.
const DECOR_VIEW_FIT_MARGIN = 1.2;
// 카메라가 서랍장에 지나치게 붙지 않도록 하는 최소 거리(m).
const DECOR_VIEW_MIN_DISTANCE = 0.8;
// 꾸미기 모드 중 허용하는 orbit 범위 — 정면 기준 좌우/상하로 이만큼만 돌 수 있다.
const DECOR_AZIMUTH_RANGE = THREE.MathUtils.degToRad(50);
const DECOR_POLAR_RANGE = THREE.MathUtils.degToRad(30);
// 정면 시점을 수평이 아니라 이 각도만큼 위에서 내려다보게 한다 — 선반 안쪽 바닥이
// 보여야 피규어를 어느 층에 놓을지 판단하기 쉽다.
const DECOR_VIEW_PITCH = THREE.MathUtils.degToRad(25);

const UP = new THREE.Vector3(0, 1, 0);

// 서랍장의 "정면" 방향(수평 단위 벡터)을 구한다. 모델 로컬 +Z축을 월드로 변환한 뒤,
// 방 중심을 향하는 쪽을 정면으로 고른다 — 서랍장은 보통 벽에 붙어 있고 정면이 방 안쪽을
// 향하므로, GLB의 앞뒤 축이 뒤집혀 있어도 안전하게 동작한다.
export function decorFrontDirection(targetRoot, roomCenter) {
  const front = new THREE.Vector3(0, 0, 1)
    .applyQuaternion(targetRoot.getWorldQuaternion(new THREE.Quaternion()))
    .setY(0);

  if (front.lengthSq() < 1e-8) front.set(0, 0, 1);
  front.normalize();

  if (roomCenter) {
    const toCenter = new THREE.Vector3(
      roomCenter.x - targetRoot.position.x,
      0,
      roomCenter.z - targetRoot.position.z,
    );
    if (toCenter.lengthSq() > 1e-6 && front.dot(toCenter) < 0) {
      front.negate();
    }
  }

  return front;
}

// 서랍장을 정면으로 바라보는 카메라 시점(cameraTransitions의 state 형식)을 계산한다.
// OBB를 카메라 기준 가로/세로/깊이로 투영해서, FOV와 종횡비에 서랍장 전체가 들어오는
// 거리를 구한다.
export function computeDecorView(targetRoot, camera, roomCenter) {
  const obb = worldObbForObject(targetRoot);
  const front = decorFrontDirection(targetRoot, roomCenter);
  const right = new THREE.Vector3().crossVectors(front, UP).normalize();

  const halfWidth = projectionRadiusForObb(obb, right);
  const halfHeight = projectionRadiusForObb(obb, UP);
  const halfDepth = projectionRadiusForObb(obb, front);

  const halfFovTan = Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2);
  const fitDistance = Math.max(
    halfHeight / halfFovTan,
    halfWidth / (halfFovTan * Math.max(camera.aspect, 0.5)),
  );
  const distance = Math.max(
    fitDistance * DECOR_VIEW_FIT_MARGIN + halfDepth,
    DECOR_VIEW_MIN_DISTANCE,
  );

  const target = obb.center.clone();
  // 정면 방향에서 DECOR_VIEW_PITCH만큼 들어 올린 위치 — 거리(distance)는 유지한 채
  // 수평 성분과 수직 성분으로 나눠서 위에서 내려다보는 각도를 만든다.
  const position = target
    .clone()
    .addScaledVector(front, distance * Math.cos(DECOR_VIEW_PITCH))
    .addScaledVector(UP, distance * Math.sin(DECOR_VIEW_PITCH));

  return {
    position,
    target,
    up: UP.clone(),
    near: Math.max(distance / 1000, 0.01),
    far: camera.far,
    distance,
  };
}

// 꾸미기 모드에서 잠글 OrbitControls 설정을 통째로 스냅샷한다(복귀용).
export function captureControlLimits(controls) {
  return {
    minDistance: controls.minDistance,
    maxDistance: controls.maxDistance,
    minPolarAngle: controls.minPolarAngle,
    maxPolarAngle: controls.maxPolarAngle,
    minAzimuthAngle: controls.minAzimuthAngle,
    maxAzimuthAngle: controls.maxAzimuthAngle,
    enablePan: controls.enablePan,
    enableRotate: controls.enableRotate,
  };
}

export function restoreControlLimits(controls, limits) {
  if (!limits) return;
  Object.assign(controls, limits);
  controls.update();
}

// 꾸미기 모드 진입 후의 카메라 제한 — 정면 시점을 중심으로 좌우/상하 약간만 돌 수 있고,
// 줌도 서랍장 근처 범위로 제한한다. 전환 애니메이션이 끝난 뒤(onComplete) 적용해야
// 전환 도중 OrbitControls 클램핑과 충돌하지 않는다.
export function applyDecorControlLimits(controls, view) {
  const offset = view.position.clone().sub(view.target);
  const spherical = new THREE.Spherical().setFromVector3(offset);

  controls.minDistance = view.distance * 0.35;
  controls.maxDistance = view.distance * 1.8;
  controls.minAzimuthAngle = spherical.theta - DECOR_AZIMUTH_RANGE;
  controls.maxAzimuthAngle = spherical.theta + DECOR_AZIMUTH_RANGE;
  controls.minPolarAngle = Math.max(spherical.phi - DECOR_POLAR_RANGE, 0.05);
  controls.maxPolarAngle = Math.min(
    spherical.phi + DECOR_POLAR_RANGE,
    Math.PI / 2,
  );
  controls.enablePan = false;
  controls.enableRotate = true;
  controls.update();
}
