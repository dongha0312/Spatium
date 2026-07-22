// 3D 생성(GPU 작업) 사용자별 횟수 제한 (프론트엔드 UX 제한)
//  - 사용자(email)별로 최근 생성 시각들을 localStorage에 기록해두고,
//    "짧은 창(기본 3분)에 N회" + "하루 N회"를 넘었는지 검사한다.
//  - (주의) localStorage 기반이라 개발자도구/시크릿창으로 우회 가능하다.
//    실수 연타/과도한 사용 방지용 UX 장치이며, 실질적 남용 차단은 백엔드 몫이다.

import { getLoginSession } from "./authSession";

const STORAGE_KEY = "spatium_gpu_usage";

// .env(REACT_APP_*) 값을 숫자로 읽되, 없거나 이상하면 기본값 사용
function readNumber(rawValue, fallback) {
  const parsed = Number(rawValue);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

// "3분에 1회" / "하루 5회" 기본값 (환경변수로 덮어쓸 수 있음)
const WINDOW_MS =
  readNumber(process.env.REACT_APP_GPU_LIMIT_WINDOW_MIN, 3) * 60 * 1000;
const PER_WINDOW = readNumber(process.env.REACT_APP_GPU_LIMIT_PER_WINDOW, 1);
const PER_DAY = readNumber(process.env.REACT_APP_GPU_LIMIT_PER_DAY, 5);
const DAY_MS = 24 * 60 * 60 * 1000;

// 현재 로그인 사용자 식별 키 (세션의 email 사용, 없으면 게스트 공용 키)
function currentUserKey() {
  const session = getLoginSession();
  return session?.email || "guest";
}

// 저장 구조 : { [userKey]: [timestamp, timestamp, ...] }
function readStore() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function writeStore(store) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
  } catch {
    // 저장 실패(용량 초과 등)는 제한을 못 걸 뿐이라 조용히 무시
  }
}

// 하루가 지난 오래된 기록은 버려서 무한정 쌓이지 않게 한다.
function pruneOldTimestamps(timestamps, now) {
  return timestamps.filter((t) => now - t < DAY_MS);
}

function minutesLabel(ms) {
  const minutes = Math.ceil(ms / 60000);
  return `${minutes}분`;
}

// 생성 요청 직전에 호출 : 제한을 넘었으면 { allowed:false, reason } 반환
//  - allowed:true 인 경우에만 실제 생성 요청을 진행한다.
export function checkGpuRateLimit() {
  const now = Date.now();
  const userKey = currentUserKey();
  const store = readStore();
  const timestamps = pruneOldTimestamps(store[userKey] || [], now);

  // 하루 총 횟수 검사
  if (timestamps.length >= PER_DAY) {
    const oldest = Math.min(...timestamps);
    const resetInMs = DAY_MS - (now - oldest);
    return {
      allowed: false,
      reason:
        `오늘 생성 가능 횟수(${PER_DAY}회)를 모두 사용했습니다. ` +
        `약 ${minutesLabel(resetInMs)} 후에 다시 시도할 수 있습니다.`,
    };
  }

  // 짧은 창(기본 3분) 내 횟수 검사
  const inWindow = timestamps.filter((t) => now - t < WINDOW_MS);
  if (inWindow.length >= PER_WINDOW) {
    const newestInWindow = Math.max(...inWindow);
    const waitMs = WINDOW_MS - (now - newestInWindow);
    return {
      allowed: false,
      reason:
        `너무 자주 요청했습니다. ` +
        `약 ${minutesLabel(waitMs)} 후에 다시 시도해주세요.`,
    };
  }

  return { allowed: true };
}

// 생성 요청을 실제로 보낸 시점에 호출 : 사용 1회 기록
export function recordGpuUsage() {
  const now = Date.now();
  const userKey = currentUserKey();
  const store = readStore();
  const timestamps = pruneOldTimestamps(store[userKey] || [], now);
  timestamps.push(now);
  store[userKey] = timestamps;
  writeStore(store);
}
