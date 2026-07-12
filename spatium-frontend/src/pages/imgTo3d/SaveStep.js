import React, { useMemo, useState } from "react";
import { createUserFurniture } from "../../springApi/FurnitureSpringBootApi";

const CATEGORIES = [
  { code: "chair", label: "의자" },
  { code: "table", label: "테이블 · 책상" },
  { code: "bed", label: "침대" },
  { code: "storage", label: "수납장" },
  { code: "lamp", label: "조명" },
  { code: "other", label: "기타" },
];

function formatFileSize(bytes) {
  if (!Number.isFinite(bytes)) return "-";
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function SaveStep({ objectName, normalizedName, correctedModel }) {
  const [name, setName] = useState(objectName || "");
  const [category, setCategory] = useState(CATEGORIES[0].code);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(null);
  const [error, setError] = useState("");

  const selectedCategory = useMemo(
    () => CATEGORIES.find((item) => item.code === category) || CATEGORIES[0],
    [category],
  );

  const handleSave = async () => {
    if (!name.trim() || !correctedModel?.file || saving) return;
    setSaving(true);
    setError("");
    try {
      const result = await createUserFurniture({
        file: correctedModel.file,
        metadata: {
          nameKr: name.trim(),
          name: normalizedName || name.trim(),
          category: selectedCategory.code,
          categoryKr: selectedCategory.label,
          dimensions: correctedModel.dimensions,
        },
      });
      setSaved(result);
    } catch (requestError) {
      setError(requestError.message || "가구 저장에 실패했습니다.");
    } finally {
      setSaving(false);
    }
  };

  if (saved) {
    return (
      <div className="it3-step it3-done">
        <div className="it3-done-icon">✓</div>
        <h2 className="it3-step-title">가구를 저장했어요!</h2>
        <p className="it3-step-desc">
          “{name}” 모델이 사용자 가구로 등록되었습니다. ({saved.id})
        </p>
      </div>
    );
  }

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">마지막으로 확인해주세요</h2>
      <p className="it3-step-desc">보정한 GLB와 가구 정보를 내 가구로 저장합니다.</p>

      <div className="it3-save-form">
        <div className="it3-field">
          <label className="it3-field-label" htmlFor="it3-furniture-name">가구 이름</label>
          <input
            id="it3-furniture-name"
            className="it3-input"
            type="text"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </div>

        <div className="it3-field">
          <label className="it3-field-label" htmlFor="it3-furniture-category">카테고리</label>
          <select
            id="it3-furniture-category"
            className="it3-input"
            value={category}
            onChange={(event) => setCategory(event.target.value)}
          >
            {CATEGORIES.map((item) => (
              <option key={item.code} value={item.code}>{item.label}</option>
            ))}
          </select>
        </div>

        <div className="it3-file-card">
          <div className="it3-result-label">보정된 파일</div>
          <div className="it3-file-name">{correctedModel?.file?.name || "GLB 없음"}</div>
          <div className="it3-file-meta">
            glTF Binary · {formatFileSize(correctedModel?.file?.size)}
          </div>
          {correctedModel?.dimensions && (
            <div className="it3-file-meta">
              {correctedModel.dimensions.x.toFixed(2)}m × {correctedModel.dimensions.y.toFixed(2)}m ×{" "}
              {correctedModel.dimensions.z.toFixed(2)}m
            </div>
          )}
        </div>

        {error && (
          <div className="it3-result-card">
            <div className="it3-result-label">저장 실패</div>
            <div className="it3-result-main">{error}</div>
          </div>
        )}

        <button
          type="button"
          className="it3-btn-prim it3-btn-wide"
          disabled={!name.trim() || !correctedModel?.file || saving}
          onClick={handleSave}
        >
          {saving ? "저장 중…" : "내 가구로 저장"}
        </button>
      </div>
    </div>
  );
}

export default SaveStep;
