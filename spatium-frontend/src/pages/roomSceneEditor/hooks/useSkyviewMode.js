import { useEffect, useRef } from "react";
import * as THREE from "three";

const TRANSITION_DURATION_MS = 1300;

// 현재 카메라/컨트롤 상태를 스냅샷으로 저장한다 (Skyview 진입 전 원래 시점을 기억해뒀다가
// 복귀할 때 그대로 되돌리기 위함 + 전환 애니메이션의 시작 상태로도 쓰인다).
export function captureCameraView(camera, controls) {
  return {
    position: camera.position.clone(),
    target: controls.target.clone(),
    up: camera.up.clone(),
    near: camera.near,
    far: camera.far,
  };
}

// 저장해둔 카메라 스냅샷으로 되돌린다.
function applyCameraView(camera, controls, view) {
  camera.position.copy(view.position);
  camera.up.copy(view.up);
  camera.near = view.near;
  camera.far = view.far;
  camera.updateProjectionMatrix();
  controls.target.copy(view.target);
  controls.enableRotate = true;
  controls.update();
}

// 카메라를 방 전체가 내려다보이는 위치(정통 위에서 아래로)로 옮긴다.
// 방의 bounding box 크기와 FOV로 적당한 높이를 계산해서 전체가 화면에 들어오게 한다.
function applySkyviewCamera(viewController) {
  const { camera, controls, worldGroup } = viewController;
  const bounds = new THREE.Box3().setFromObject(worldGroup);
  if (bounds.isEmpty()) return null;

  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxFloorSpan = Math.max(size.x, size.z, 1);
  const height =
    (maxFloorSpan / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.1;
  const baseUp = new THREE.Vector3(0, 0, -1).applyAxisAngle(
    new THREE.Vector3(0, 1, 0),
    THREE.MathUtils.degToRad(roomYawOffsetDegrees || 0),
  );

  const camDirFromCenter = new THREE.Vector3(
    camera.position.x - center.x,
    0,
    camera.position.z - center.z,
  );
  const up =
    camDirFromCenter.lengthSq() > 1e-6 &&
    baseUp.dot(camDirFromCenter.normalize()) > 0
      ? baseUp.clone().negate()
      : baseUp;

  return {
    position: new THREE.Vector3(
      center.x,
      center.y + Math.max(height, size.y + 2),
      center.z,
    ),
    target: center.clone(),
    up,
    near: Math.max(height / 1000, 0.01),
    far: Math.max(height * 100, size.y + height + 100),
  };
}

// 카메라 상태를 보간 없이 즉시 적용한다(초기 로딩 시 사용 — 애니메이션이 필요 없음).
function applyCameraState(camera, controls, state, maxDistance) {
  camera.position.copy(state.position);
  camera.up.copy(state.up);
  camera.near = state.near;
  camera.far = state.far;
  camera.updateProjectionMatrix();
  controls.target.copy(state.target);
  if (Number.isFinite(maxDistance)) {
    controls.maxDistance = maxDistance;
  }
  controls.update();
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
}

// Skyview 진입/해제 애니메이션을 시작한다. 진행 상태는 viewController.transition에
// 저장해두고, updateCameraTransition()이 매 프레임 이어서 진행시킨다. 전환 중에는
// OrbitControls 입력을 막는다(마우스 드래그가 애니메이션과 충돌하지 않도록).
function startCameraTransition(viewController, toState, finalMaxDistance) {
  const { camera, controls } = viewController;
  viewController.transition = {
    from: captureCameraView(camera, controls),
    to: toState,
    startTime: performance.now(),
    finalMaxDistance,
  };
  controls.enabled = false;
}

// 렌더 루프(animate())에서 매 프레임 호출한다. 진행 중인 transition이 있으면 카메라를
// 보간된 위치/방향으로 옮기고, true를 반환해서 이번 프레임엔 일반 controls.update()를
// 건너뛰게 한다(전환 도중엔 OrbitControls의 내부 spherical 계산이 우리가 매 프레임 직접
// 설정하는 camera.position/up과 충돌하기 때문). 전환이 끝나면 정확한 최종 값으로 스냅한
// 뒤 OrbitControls를 다시 활성화하고 false를 반환한다.
export function updateCameraTransition(viewController) {
  const transition = viewController?.transition;
  if (!transition) return false;

  const { camera, controls } = viewController;
  const elapsed = performance.now() - transition.startTime;
  const t = Math.min(1, elapsed / TRANSITION_DURATION_MS);
  const eased = easeInOutCubic(t);

  camera.position.lerpVectors(
    transition.from.position,
    transition.to.position,
    eased,
  );
  controls.target.lerpVectors(
    transition.from.target,
    transition.to.target,
    eased,
  );
  camera.up.copy(transition.from.up).lerp(transition.to.up, eased).normalize();
  camera.near = THREE.MathUtils.lerp(
    transition.from.near,
    transition.to.near,
    eased,
  );
  camera.far = THREE.MathUtils.lerp(
    transition.from.far,
    transition.to.far,
    eased,
  );
  camera.updateProjectionMatrix();
  camera.lookAt(controls.target);

  if (t >= 1) {
    if (Number.isFinite(transition.finalMaxDistance)) {
      controls.maxDistance = transition.finalMaxDistance;
    }
    controls.enabled = true;
    controls.update();
    viewController.transition = null;
  }

  return true;
}

// Skyview on/off를 전환한다. 켤 때는 현재 시점을 저장해두고 위에서 내려다보는 카메라로
// 바꾸고, 끌 때는 저장해둔 원래 시점으로 복귀한다. instant가 true면(초기 로딩 시) 애니
// 메이션 없이 바로 적용하고, 아니면(사용자가 버튼을 눌렀을 때) 부드럽게 전환한다.
export function applySkyviewMode(viewController, isSkyview, options = {}) {
  const { instant = false } = options;
  if (!viewController) return;

  const { camera, controls } = viewController;

  if (isSkyview) {
    // 이미 Skyview로 전환 중/완료 상태면 defaultView를 다시 캡처하지 않는다 — 안 그러면
    // 애니메이션 도중 빠르게 두 번 토글했을 때 "돌아갈 원래 시점"이 전환 중간의 어중간한
    // 자세로 덮어써진다.
    if (!viewController.isInSkyview) {
      viewController.defaultView = captureCameraView(camera, controls);
    }
    viewController.isInSkyview = true;
    const skyState = computeSkyviewCameraState(viewController);
    if (!skyState) return;

    // Skyview 높이가 휠 줌아웃 한도(maxDistance, 초기 프레이밍 거리)보다 멀면 카메라가
    // 그 한도 안으로 당겨져서 방 전체가 안 보일 수 있으므로, 필요한 만큼만 넓혀준다.
    const requiredDistance = skyState.position.distanceTo(skyState.target);
    const finalMaxDistance = Math.max(controls.maxDistance, requiredDistance);
    controls.enableRotate = false;

    if (instant) {
      applyCameraState(camera, controls, skyState, finalMaxDistance);
    } else {
      startCameraTransition(viewController, skyState, finalMaxDistance);
    }
    return;
  }

  if (viewController.defaultView) {
    viewController.isInSkyview = false;
    controls.enableRotate = true;

    if (instant) {
      applyCameraState(
        camera,
        controls,
        viewController.defaultView,
        viewController.baseMaxDistance,
      );
    } else {
      startCameraTransition(
        viewController,
        viewController.defaultView,
        viewController.baseMaxDistance,
      );
    }
  }
}

// isSkyview prop이 바뀔 때마다 카메라를 전환하고, 최신 값을 ref로도 들고 있어서
// 렌더 루프(requestAnimationFrame) 안에서도 최신 상태를 즉시 참조할 수 있게 한다.
export function useSkyviewMode(viewControllerRef, isSkyview) {
  const isSkyviewRef = useRef(isSkyview);

  useEffect(() => {
    isSkyviewRef.current = isSkyview;
    applySkyviewMode(viewControllerRef.current, isSkyview);
  }, [isSkyview, viewControllerRef]);

  return isSkyviewRef;
}
