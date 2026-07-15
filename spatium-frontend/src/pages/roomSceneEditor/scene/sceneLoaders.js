import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { USDLoader } from "three/examples/jsm/loaders/USDLoader.js";
import {
  SCENE_CONFIG_URL,
  getModelUrls,
  normalizeModelKey,
} from "./sceneConfig";
import { saveRoomMetadataJson } from "../../../springApi/RoomSpringBootApi";

// Keep parsed GLTF promises at module scope so a scene rebuild (for example
// structural undo/redo) reuses the already downloaded and parsed asset.
// Callers always clone the returned scene before attaching it to the editor.
const gltfPromiseCache = new Map();

// USD/USDZ 방 모델을 로드한다. blob: URL은 그대로, 일반 URL은 캐시 무효화용 timestamp를
// 붙여서 로드한다. 로드에 실패해도 예외를 던지지 않고 null을 반환한다(呼출부가 fallback 처리).
export function loadUsdRoomModel(url) {
  if (!url) return Promise.resolve(null);

  const separator = url.includes("?") ? "&" : "?";
  const cacheSafeUrl = url.startsWith("blob:")
    ? url
    : `${url}${separator}t=${Date.now()}`;
  return new Promise((resolve) => {
    new USDLoader().load(cacheSafeUrl, resolve, undefined, () =>
      resolve(null),
    );
  });
}

// 가구/문/창문용 GLB 모델을 로드한다.
export function loadGltfModel(url, label) {
  if (!url) {
    return Promise.reject(new Error(`Missing model URL for ${label}.`));
  }

  const cachedPromise = gltfPromiseCache.get(url);
  if (cachedPromise) return cachedPromise;

  const request = new Promise((resolve, reject) => {
    new GLTFLoader().load(url, resolve, undefined, reject);
  });
  const cachedRequest = request.catch((error) => {
    if (gltfPromiseCache.get(url) === cachedRequest) {
      gltfPromiseCache.delete(url);
    }
    throw error;
  });
  gltfPromiseCache.set(url, cachedRequest);
  return cachedRequest;
}

// 설정 파일의 models 목록 중, 주어진 category들과 이름이 매칭되는 항목만 골라낸다.
// categories가 없으면 전체를 반환한다.
export function modelEntriesForCategories(categories) {
  const entries = Object.entries(getModelUrls()).filter(([, url]) => url);
  if (!categories) return entries;

  const selectedEntries = new Map();
  categories.forEach((category) => {
    const normalizedCategory = normalizeModelKey(category);
    const matchedEntry = entries.find(
      ([key]) => normalizeModelKey(key) === normalizedCategory,
    );
    if (matchedEntry) {
      selectedEntries.set(normalizeModelKey(matchedEntry[0]), matchedEntry);
    }
  });

  return Array.from(selectedEntries.values());
}

// 방 metadata(objects/doors/windows)에 실제로 등장하는 category 목록을 뽑는다.
// 필요한 모델 템플릿만 미리 로드하기 위한 목록으로 쓰인다.
export function modelCategoriesFromMetadata(metadata) {
  const categories = new Set(
    (metadata.objects || []).map((item) => item.category).filter(Boolean),
  );

  if ((metadata.doors || []).length) categories.add("door");
  if ((metadata.windows || []).length) categories.add("window");

  return Array.from(categories);
}

// category별 기본 GLB 모델들을 한 번에 로드해서 Map(lookupKey -> {key, gltf})으로 반환한다.
// 이후 findModelTemplate()으로 category 이름으로 조회해서 재사용(clone)한다.
export async function loadModelTemplates(categories) {
  const entries = modelEntriesForCategories(categories);
  const loadedTemplates = await Promise.all(
    entries.map(async ([key, url]) => ({
      key,
      lookupKey: normalizeModelKey(key),
      gltf: await loadGltfModel(url, key),
    })),
  );

  return new Map(
    loadedTemplates.map((template) => [template.lookupKey, template]),
  );
}

export function findModelTemplate(modelTemplates, category) {
  return modelTemplates.get(normalizeModelKey(category)) || null;
}

export function requireModelTemplate(modelTemplates, category) {
  const template = findModelTemplate(modelTemplates, category);
  if (!template) {
    throw new Error(
      `Missing model mapping for "${category}" in ${SCENE_CONFIG_URL}.`,
    );
  }
  return template;
}

// JSON을 fetch한다 (캐시 무효화 timestamp 포함, no-store).
export function fetchJson(url, label) {
  if (!url) {
    return Promise.reject(new Error(`Missing JSON URL for ${label}.`));
  }

  const separator = url.includes("?") ? "&" : "?";
  return fetch(`${url}${separator}t=${Date.now()}`, {
    cache: "no-store",
  }).then((response) => {
    if (!response.ok) {
      throw new Error(`Failed to load ${label} (${response.status})`);
    }
    return response.json();
  });
}

// 편집된 metadata JSON을 백엔드에 저장한다 (POST /api/rooms/save).
export function saveMetadataJson(metadata, saveContext = {}) {
  return saveRoomMetadataJson({
    projectId: saveContext.projectId,
    roomId: saveContext.roomId,
    area: saveContext.area,
    metadata,
  });
}
