import React, { useRef, useState } from "react";

// 1단계: 가구 사진 업로드 (드래그앤드롭 + 파일 선택)
function UploadStep({ image, onImageChange }) {
  const inputRef = useRef(null);
  const [dragOver, setDragOver] = useState(false);

  const handleFile = (file) => {
    if (!file || !file.type.startsWith("image/")) return;
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
        accept="image/*"
        style={{ display: "none" }}
        onChange={(e) => handleFile(e.target.files?.[0])}
      />
    </div>
  );
}

export default UploadStep;
