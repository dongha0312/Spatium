import React, { useState } from "react";
import { mockNormalizeName } from "./mockData";

// 2단계: 객체명 입력 → LLM 영어 번역 · 정규화 (지금은 목업 사전으로 흉내)
function ObjectNameStep({ objectName, onObjectNameChange, normalized, onNormalized }) {
  const [loading, setLoading] = useState(false);

  const runNormalize = async () => {
    if (!objectName.trim() || loading) return;
    setLoading(true);
    onNormalized(null);
    const result = await mockNormalizeName(objectName.trim());
    onNormalized(result);
    setLoading(false);
  };

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">어떤 가구인가요?</h2>
      <p className="it3-step-desc">
        사진 속에서 찾을 가구의 이름을 알려주세요. 예: 의자, 책상, 침대 옆 협탁
      </p>

      <div className="it3-name-row">
        <input
          className="it3-input"
          type="text"
          value={objectName}
          placeholder="예) 침대 옆 협탁"
          onChange={(e) => {
            onObjectNameChange(e.target.value);
            onNormalized(null); // 이름을 고치면 이전 정규화 결과는 무효
          }}
          onKeyDown={(e) => e.key === "Enter" && runNormalize()}
        />
        <button
          type="button"
          className="it3-btn-prim"
          disabled={!objectName.trim() || loading}
          onClick={runNormalize}
        >
          {loading ? "변환 중…" : "번역 · 정규화"}
        </button>
      </div>

      {loading && (
        <div className="it3-loading-note">
          <span className="it3-spinner" />
          LLM이 객체명을 영어로 정규화하고 있어요…
        </div>
      )}

      {normalized && (
        <div className="it3-result-card">
          <div className="it3-result-label">정규화 결과</div>
          <div className="it3-result-main">
            “{normalized.input}” → <strong>{normalized.en}</strong>
          </div>
          <div className="it3-tag-row">
            {normalized.tags.map((t) => (
              <span key={t} className="it3-tag">
                {t}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default ObjectNameStep;
