import * as THREE from "three";

export const SCENE_CONFIG_URL = "/config/test-three-scene-config.json";
let sceneConfig = null;

export function hasSceneConfig() {
  return Boolean(sceneConfig);
}

export async function loadSceneConfig() {
  const response = await fetch(`${SCENE_CONFIG_URL}?t=${Date.now()}`, {
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(`Failed to load scene config (${response.status})`);
  }

  sceneConfig = await response.json();
  return sceneConfig;
}

export function requiredConfigValue(path) {
  if (!sceneConfig) {
    throw new Error("Scene config has not been loaded.");
  }

  const value = path.reduce((current, key) => current?.[key], sceneConfig);
  if (value == null) {
    throw new Error(`Missing scene config value: ${path.join(".")}`);
  }
  return value;
}

export function configNumber(path) {
  const value = Number(requiredConfigValue(path));
  if (!Number.isFinite(value)) {
    throw new Error(`Scene config value must be a number: ${path.join(".")}`);
  }
  return value;
}

export function configBoolean(path) {
  return Boolean(requiredConfigValue(path));
}

export function configString(path) {
  return String(requiredConfigValue(path));
}

export function getRoomModelUrl() {
  return configString(["room", "modelUrl"]);
}

export function getRoomMetadataUrl() {
  return configString(["room", "metadataUrl"]);
}

export function getMetadataSaveApiUrl() {
  return configString(["save", "metadataApiUrl"]);
}

export function getModelUrls() {
  return { ...requiredConfigValue(["models"]) };
}

export function sceneColor(name) {
  return configString(["colors", name]);
}

export function referenceFallbackThickness(category) {
  return configNumber(["referenceFallbackThickness", category]);
}

export function wallConfigNumber(name) {
  return configNumber(["wallConstraints", name]);
}

export function wallConfigBoolean(name) {
  return configBoolean(["wallConstraints", name]);
}

export function wallSweepRotationStep() {
  return THREE.MathUtils.degToRad(wallConfigNumber("sweepRotationStepDegrees"));
}

export function normalizeModelKey(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

export function categoryColor(category) {
  const categoryColors = requiredConfigValue(["colors", "category"]);
  const normalizedCategory = normalizeModelKey(category);
  const matchedEntry = Object.entries(categoryColors).find(
    ([key]) => normalizeModelKey(key) === normalizedCategory,
  );
  return matchedEntry?.[1] || configString(["colors", "category", "object"]);
}
