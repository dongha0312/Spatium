import * as THREE from "three";

// 모델링 설정 파일
export const SCENE_CONFIG_URL = "/config/room-scene-config.json";
let sceneConfig = null;

export function hasSceneConfig() {
  return Boolean(sceneConfig);
}

// room-scene-config.json을 fetch해서 모듈 내부 캐시(sceneConfig)에 저장한다.
// 이후 configXxx/sceneColor 등은 이 캐시에서 값을 읽는다.
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

// path(예: ["colors","collision"])로 설정값을 찾는다. 값이 없으면 예외를 던진다
// (필수 설정 누락을 조기에 발견하기 위함).
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

// requiredConfigValue와 달리 값이 없어도 예외를 던지지 않고 defaultValue를 반환한다.
// 디버그/토글성 설정(showXxx 등)에 주로 쓰인다.
export function optionalConfigBoolean(path, defaultValue = false) {
  if (!sceneConfig) return defaultValue;

  const value = path.reduce((current, key) => current?.[key], sceneConfig);
  return value == null ? defaultValue : Boolean(value);
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

// 모델 카테고리 키를 비교 가능한 형태로 정규화한다(소문자, 영문/숫자만 남김).
// "washerDryer"와 "washer-dryer" 같은 표기 차이를 흡수하기 위함.
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
