import React, { useRef, useState } from "react";

const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

// 1단계: 가구 사진 업로드 (드래그앤드롭 + 파일 선택)
function UploadStep({ image, onImageChange }) {
  const inputRef = useRef(null);
  const [dragOver, setDragOver] = useState(false);
  const [validationError, setValidationError] = useState("");

  const handleFile = (file) => {
    if (!file) return;
    if (!ALLOWED_IMAGE_TYPES.has(file.type)) {
      setValidationError("PNG, JPG, WEBP 이미지만 사용할 수 있어요.");
      return;
    }
    if (file.size > MAX_UPLOAD_BYTES) {
      setValidationError("이미지 크기는 10MB 이하여야 해요.");
      return;
    }
    setValidationError("");
    onImageChange({ file, url: URL.createObjectURL(file) });
  };

  const handleDrop = (e) => {
    e.preventDefault();
    setDragOver(false);
    handleFile(e.dataTransfer.files?.[0]);
  };

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">가구 사진을 올려주세요</h2>
      <p className="it3-step-desc">
        3D로 만들고 싶은 가구가 잘 보이는 사진 한 장이면 충분해요.
      </p>

      {image ? (
        <div className="it3-preview-wrap">
          <img className="it3-preview-img" src={image.url} alt="업로드한 가구 사진" />
          <button
            type="button"
            className="it3-btn-ghost"
          onClick={() => {
            onImageChange(null);
            setValidationError("");
            if (inputRef.current) inputRef.current.value = "";
          }}
          >
            다른 사진 선택
          </button>
        </div>
      ) : (
        <div
          className={`it3-dropzone${dragOver ? " is-over" : ""}`}
          onClick={() => inputRef.current?.click()}
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={handleDrop}
        >
          <div className="it3-dropzone-icon">🖼️</div>
          <div className="it3-dropzone-main">사진을 끌어다 놓거나 클릭해서 선택</div>
          <div className="it3-dropzone-sub">JPG · PNG · WEBP</div>
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        style={{ display: "none" }}
        onChange={(e) => handleFile(e.target.files?.[0])}
      />

      {validationError && (
        <div className="it3-result-card">
          <div className="it3-result-label">파일을 확인해주세요</div>
          <div className="it3-result-main">{validationError}</div>
        </div>
      )}
    </div>
  );
}

export default UploadStep;
