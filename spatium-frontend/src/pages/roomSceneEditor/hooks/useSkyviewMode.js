import { useEffect, useRef } from "react";
import * as THREE from "three";

// 현재 카메라/컨트롤 상태를 스냅샷으로 저장한다 (Skyview 진입 전 원래 시점을 기억해뒀다가
// 복귀할 때 그대로 되돌리기 위함).
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
  if (bounds.isEmpty()) return;

  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const maxFloorSpan = Math.max(size.x, size.z, 1);
  const height =
    (maxFloorSpan / (2 * Math.tan(THREE.MathUtils.degToRad(camera.fov) / 2))) *
    1.5;

  camera.up.set(0, 0, -1);
  camera.position.set(
    center.x,
    center.y + Math.max(height, size.y + 2),
    center.z,
  );
  camera.near = Math.max(height / 1000, 0.01);
  camera.far = Math.max(height * 100, size.y + height + 100);
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.enableRotate = false;
  controls.update();
}

// Skyview on/off를 전환한다. 켤 때는 현재 시점을 저장해두고 위에서 내려다보는 카메라로
// 바꾸고, 끌 때는 저장해둔 원래 시점으로 복귀한다.
export function applySkyviewMode(viewController, isSkyview) {
  if (!viewController) return;

  const { camera, controls } = viewController;
  if (isSkyview) {
    viewController.defaultView = captureCameraView(camera, controls);
    applySkyviewCamera(viewController);
    return;
  }

  if (viewController.defaultView) {
    applyCameraView(camera, controls, viewController.defaultView);
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
