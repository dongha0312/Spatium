import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { USDLoader } from "three/examples/jsm/loaders/USDLoader.js";
import {
  SCENE_CONFIG_URL,
  getModelUrls,
  normalizeModelKey,
} from "./sceneConfig";
import { saveRoomMetadataJson } from "../../../springApi/RoomSpringBootApi";

export function loadUsdRoomModel(url) {
  if (!url) return Promise.resolve(null);

  const separator = url.includes("?") ? "&" : "?";
  const cacheSafeUrl = `${url}${separator}t=${Date.now()}`;
  return new Promise((resolve) => {
    new USDLoader().load(cacheSafeUrl, resolve, undefined, () =>
      resolve(null),
    );
  });
}

export function loadGltfModel(url, label) {
  if (!url) {
    return Promise.reject(new Error(`Missing model URL for ${label}.`));
  }

  return new Promise((resolve, reject) => {
    new GLTFLoader().load(url, resolve, undefined, reject);
  });
}

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

export function modelCategoriesFromMetadata(metadata) {
  const categories = new Set(
    (metadata.objects || []).map((item) => item.category).filter(Boolean),
  );

  if ((metadata.doors || []).length) categories.add("door");
  if ((metadata.windows || []).length) categories.add("window");

  return Array.from(categories);
}

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

export function saveMetadataJson(metadata, saveContext = {}) {
  return saveRoomMetadataJson({
    projectId: saveContext.projectId,
    roomId: saveContext.roomId,
    metadata,
    accessToken: saveContext.accessToken,
  });
}
