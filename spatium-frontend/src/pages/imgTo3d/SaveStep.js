import React, { useState } from "react";
import { MOCK_RESULT_FILE } from "./mockData";

const CATEGORIES = ["의자", "테이블 · 책상", "침대", "수납장", "조명", "기타"];

// 7단계: 메타데이터 확인 후 저장 → 가구 목록에 추가 (목업)
// 실제 연동 시: GLB는 S3 등 object storage, 메타데이터는 DB에 저장된다.
function SaveStep({ objectName, normalized }) {
  const [name, setName] = useState(objectName || "");
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  const handleSave = () => {
    setSaving(true);
    setTimeout(() => {
      setSaving(false);
      setSaved(true);
    }, 1000);
  };

  if (saved) {
    return (
      <div className="it3-step it3-done">
        <div className="it3-done-icon">✓</div>
        <h2 className="it3-step-title">가구 목록에 추가했어요!</h2>
        <p className="it3-step-desc">
          이제 3D 에디터에서 “{name}”을(를) 방에 배치할 수 있어요.
        </p>
      </div>
    );
  }

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">마지막으로 확인해주세요</h2>
      <p className="it3-step-desc">저장하면 내 가구 목록에서 바로 사용할 수 있어요.</p>

      <div className="it3-save-form">
        <div className="it3-field">
          <label className="it3-field-label">가구 이름</label>
          <input
            className="it3-input"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>

        <div className="it3-field">
          <label className="it3-field-label">카테고리</label>
          <select
            className="it3-input"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
          >
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>

        <div className="it3-file-card">
          <div className="it3-result-label">생성된 파일</div>
          <div className="it3-file-name">{MOCK_RESULT_FILE.name}</div>
          <div className="it3-file-meta">
            {MOCK_RESULT_FILE.format} · {MOCK_RESULT_FILE.size}
            {normalized ? ` · ${normalized.en}` : ""}
          </div>
        </div>

        <p className="it3-hint">
          파일은 object storage(S3), 메타데이터는 DB에 저장돼요. — 백엔드 연동 시 활성화
        </p>

        <button
          type="button"
          className="it3-btn-prim it3-btn-wide"
          disabled={!name.trim() || saving}
          onClick={handleSave}
        >
          {saving ? "저장 중…" : "가구 목록에 추가"}
        </button>
      </div>
    </div>
  );
}

export default SaveStep;
