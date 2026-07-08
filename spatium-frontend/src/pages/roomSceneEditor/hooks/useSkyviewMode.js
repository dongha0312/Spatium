import { useEffect, useRef } from "react";
import * as THREE from "three";

export function captureCameraView(camera, controls) {
  return {
    position: camera.position.clone(),
    target: controls.target.clone(),
    up: camera.up.clone(),
    near: camera.near,
    far: camera.far,
  };
}

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

export function useSkyviewMode(viewControllerRef, isSkyview) {
  const isSkyviewRef = useRef(isSkyview);

  useEffect(() => {
    isSkyviewRef.current = isSkyview;
    applySkyviewMode(viewControllerRef.current, isSkyview);
  }, [isSkyview, viewControllerRef]);

  return isSkyviewRef;
}
