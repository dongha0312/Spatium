import * as THREE from "three";

const TRANSITION_DURATION_MS = 1300;

// 현재 카메라/컨트롤 상태를 스냅샷으로 저장한다. Skyview/꾸미기 모드 진입 전 원래 시점을
// 기억해뒀다가 복귀할 때 그대로 되돌리기 위함 + 전환 애니메이션의 시작 상태로도 쓰인다.
export function captureCameraView(camera, controls) {
  return {
    position: camera.position.clone(),
    target: controls.target.clone(),
    up: camera.up.clone(),
    near: camera.near,
    far: camera.far,
  };
}

// 카메라 상태를 보간 없이 즉시 적용한다(초기 로딩 시 사용 — 애니메이션이 필요 없음).
export function applyCameraState(camera, controls, state, maxDistance) {
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

// 카메라 전환 애니메이션을 시작한다. 진행 상태는 viewController.transition에 저장해두고,
// updateCameraTransition()이 매 프레임 이어서 진행시킨다. 전환 중에는 OrbitControls
// 입력을 막는다(마우스 드래그가 애니메이션과 충돌하지 않도록). onComplete를 주면 전환이
// 끝난 프레임에 한 번 호출된다(꾸미기 모드의 컨트롤 제한 적용 등).
export function startCameraTransition(
  viewController,
  toState,
  finalMaxDistance,
  onComplete = null,
) {
  const { camera, controls } = viewController;
  viewController.transition = {
    from: captureCameraView(camera, controls),
    to: toState,
    startTime: performance.now(),
    finalMaxDistance,
    onComplete,
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
    transition.onComplete?.();
  }

  return true;
}
