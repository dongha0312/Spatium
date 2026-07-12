// 이미지 → 3D 파이프라인(LLM 번역 / GroundingDINO / SAM2 / TripoSR)이 아직 연동 전이므로,
// 각 단계가 반환할 법한 응답을 흉내내는 목업 데이터 모음.
// 백엔드 연동 시 이 파일의 함수들만 springApi 실제 호출로 갈아끼우면 된다.

// 단계별 가짜 지연 시간 (ms)
export const MOCK_DELAY = {
  translate: 900,
  detect: 1100,
  segment: 1400,
};

// LLM 객체명 번역 · 정규화 목업 사전
const NAME_DICT = [
  { match: ["협탁", "침대 옆"], en: "nightstand / bedside table", tags: ["nightstand", "bedside table", "side table"] },
  { match: ["의자"], en: "chair", tags: ["chair", "armchair"] },
  { match: ["책상"], en: "desk", tags: ["desk", "table"] },
  { match: ["침대"], en: "bed", tags: ["bed", "bed frame"] },
  { match: ["소파"], en: "sofa / couch", tags: ["sofa", "couch"] },
  { match: ["옷장"], en: "wardrobe", tags: ["wardrobe", "closet"] },
  { match: ["선반"], en: "shelf", tags: ["shelf", "bookshelf"] },
  { match: ["조명", "스탠드"], en: "lamp", tags: ["lamp", "floor lamp"] },
];

// "침대 옆 협탁" → { en: "nightstand / bedside table", tags: [...] }
export function mockNormalizeName(koreanName) {
  const hit = NAME_DICT.find((d) => d.match.some((m) => koreanName.includes(m)));
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(
        hit
          ? { input: koreanName, en: hit.en, tags: hit.tags }
          : { input: koreanName, en: "furniture object", tags: ["furniture", "object"] }
      );
    }, MOCK_DELAY.translate);
  });
}

// GroundingDINO detection 목업 — 이미지 크기와 무관하게 % 좌표로 반환
export function mockDetect(label) {
  const boxes = [
    { id: 1, label, score: 0.94, x: 12, y: 18, w: 36, h: 62 },
    { id: 2, label, score: 0.81, x: 55, y: 30, w: 30, h: 48 },
    { id: 3, label, score: 0.63, x: 40, y: 8, w: 22, h: 26 },
  ];
  return new Promise((resolve) => {
    setTimeout(() => resolve(boxes), MOCK_DELAY.detect);
  });
}

// 3D 생성(TripoSR) 진행 단계 표시용 라벨
export const GENERATE_STAGES = [
  "이미지 전처리",
  "TripoSR 메시 생성",
  "텍스처 베이킹",
  "GLB 내보내기",
];

// 저장 단계에 표시할 가짜 결과 파일 정보
export const MOCK_RESULT_FILE = {
  name: "spatium_furniture.glb",
  size: "2.4 MB",
  format: "glTF Binary (.glb)",
};
