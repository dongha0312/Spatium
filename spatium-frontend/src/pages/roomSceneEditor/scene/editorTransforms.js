import * as THREE from "three";
import { canTransformObject } from "./collision";
import { referenceFallbackThickness, sceneColor } from "./sceneConfig";
import { columnsFromMatrix } from "./threeUtils";

export const DEFAULT_FURNITURE_DIMENSIONS = { x: 0.8, y: 0.8, z: 0.8 };
export const REFERENCE_CATEGORIES = new Set(["door", "window"]);

export function base64ToObjectUrl(
  base64,
  contentType = "application/octet-stream",
) {
  const binary = window.atob(base64);
  const bytes = [];

  for (let offset = 0; offset < binary.length; offset += 1024) {
    const slice = binary.slice(offset, offset + 1024);
    const chunk = new Uint8Array(slice.length);

    for (let index = 0; index < slice.length; index += 1) {
      chunk[index] = slice.charCodeAt(index);
    }

    bytes.push(chunk);
  }

  return URL.createObjectURL(new Blob(bytes, { type: contentType }));
}

export function normalizedDimensions(dimensions = {}) {
  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z: Math.max(Number(dimensions.z) || DEFAULT_FURNITURE_DIMENSIONS.z, 0.04),
  };
}

export function normalizedReferenceDimensions(category, dimensions = {}) {
  const fallbackThickness = referenceFallbackThickness(category);
  const thickness = Number(dimensions.z);

  return {
    x: Math.max(Number(dimensions.x) || DEFAULT_FURNITURE_DIMENSIONS.x, 0.04),
    y: Math.max(Number(dimensions.y) || DEFAULT_FURNITURE_DIMENSIONS.y, 0.04),
    z:
      Number.isFinite(thickness) &&
      thickness > 0 &&
      thickness <= fallbackThickness * 1.5
        ? thickness
        : fallbackThickness,
  };
}

export function roundedTransform(
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const matrix = new THREE.Matrix4().compose(position, quaternion, scale);

  return {
    columns: columnsFromMatrix(matrix).map((column) =>
      column.map((value) => Number(value.toFixed(6))),
    ),
  };
}

export function createFurnitureItemFromCatalog(
  catalogItem,
  position,
  quaternion = new THREE.Quaternion(),
  scale = new THREE.Vector3(1, 1, 1),
) {
  const dimensions = normalizedDimensions(catalogItem.dimensions);

  return {
    catalogId: catalogItem.id,
    name: catalogItem.name,
    category: catalogItem.category,
    path: catalogItem.path || catalogItem.modelUrl,
    modelUrl: catalogItem.modelUrl,
    dimensions,
    transform: roundedTransform(position, quaternion, scale),
  };
}

export function estimateFloorY(metadataObjects, roomModel) {
  const objectFloorYs = (metadataObjects || [])
    .map((item) => {
      const y = Number(item.transform?.columns?.[3]?.[1]);
      const height = Number(item.dimensions?.y);
      return Number.isFinite(y) && Number.isFinite(height)
        ? y - height / 2
        : null;
    })
    .filter((value) => value != null);

  if (objectFloorYs.length) {
    return Math.min(...objectFloorYs);
  }

  const bounds = new THREE.Box3().setFromObject(roomModel);
  return bounds.isEmpty() ? 0 : bounds.min.y;
}

export function normalizeRotationDegrees(degrees) {
  const normalized = THREE.MathUtils.euclideanModulo(degrees + 180, 360) - 180;
  return Math.round(normalized);
}

export function rotationDegreesFromObject(object) {
  if (!object) return 0;

  const euler = new THREE.Euler().setFromQuaternion(object.quaternion, "YXZ");
  return normalizeRotationDegrees(THREE.MathUtils.radToDeg(euler.y));
}

export function yawDegreesFromDirection(direction) {
  return normalizeRotationDegrees(
    THREE.MathUtils.radToDeg(Math.atan2(direction.x, direction.z)),
  );
}

export function formatCameraViewAngle(camera) {
  const direction = camera.getWorldDirection(new THREE.Vector3());
  const yaw = yawDegreesFromDirection(direction);
  const pitch = Math.round(
    THREE.MathUtils.radToDeg(
      Math.asin(THREE.MathUtils.clamp(direction.y, -1, 1)),
    ),
  );

  return `View Yaw ${yaw}째 / Pitch ${pitch}째`;
}

export function isReplaceableObject(object) {
  if (!object) return false;

  return (
    canTransformObject(object) ||
    object.userData.sourceType === "door" ||
    object.userData.sourceType === "window"
  );
}

export function createFallbackReferenceTemplate(sourceType) {
  const geometry = new THREE.BoxGeometry(1, 1, 1);
  const material = new THREE.MeshStandardMaterial({
    color: sceneColor(
      sourceType === "door" ? "doorReference" : "windowReference",
    ),
    roughness: 0.72,
  });
  const mesh = new THREE.Mesh(geometry, material);
  const group = new THREE.Group();

  group.add(mesh);
  return group;
}
