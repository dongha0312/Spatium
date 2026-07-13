import { useEffect, useRef } from "react";
import * as THREE from "three";
import {
  applyCameraState,
  captureCameraView,
  startCameraTransition,
  updateCameraTransition,
} from "../scene/cameraTransitions";

// 전환 애니메이션 헬퍼는 scene/cameraTransitions.js로 분리됐다. 기존 호출부
// (useRoomSceneEditor 등)가 계속 이 모듈에서 import할 수 있게 re-export한다.
export { captureCameraView, updateCameraTransition };

// 카메라를 방 전체가 내려다보이는 위치(정통 위에서 아래로)로 옮긴다.
// 방의 bounding box 크기와 FOV로 적당한 높이를 계산해서 전체가 화면에 들어오게 한다.
function applySkyviewCamera(viewController) {
  const { camera, worldGroup, roomYawOffsetDegrees } = viewController;
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
    const skyState = applySkyviewCamera(viewController);
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
