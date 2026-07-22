import React, { useRef, useState } from "react";

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_GLB_BYTES = 100 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

// 1단계: 사진과 GLB를 구분해서 업로드한다.
function UploadStep({ selectedFile, onFileChange }) {
  const imageInputRef = useRef(null);
  const glbInputRef = useRef(null);
  const [dragOver, setDragOver] = useState(null);
  const [validationError, setValidationError] = useState("");

  const handleFile = (file, expectedKind) => {
    if (!file) return;

    if (selectedFile && selectedFile.kind !== expectedKind) {
      setValidationError("사진과 GLB 파일은 동시에 업로드할 수 없어요. 선택한 파일을 먼저 제거해주세요.");
      return;
    }

    const isGlb = file.name.toLowerCase().endsWith(".glb");
    const isImage = ALLOWED_IMAGE_TYPES.has(file.type);

    if (expectedKind === "image" && !isImage) {
      setValidationError("사진 업로드에는 JPG, PNG, WEBP 이미지만 선택할 수 있어요.");
      return;
    }

    if (expectedKind === "glb" && !isGlb) {
      setValidationError("GLB 파일 업로드에는 .glb 파일만 선택할 수 있어요.");
      return;
    }

    if (isImage && file.size > MAX_IMAGE_BYTES) {
      setValidationError("이미지 크기는 10MB 이하여야 해요.");
      return;
    }

    if (isGlb && file.size > MAX_GLB_BYTES) {
      setValidationError("GLB 파일 크기는 100MB 이하여야 해요.");
      return;
    }

    setValidationError("");
    onFileChange({
      kind: expectedKind,
      file,
      url: URL.createObjectURL(file),
    });
  };

  const handleDrop = (event, kind) => {
    event.preventDefault();
    setDragOver(null);
    handleFile(event.dataTransfer.files?.[0], kind);
  };

  const clearSelectedFile = () => {
    onFileChange(null);
    setValidationError("");
    if (imageInputRef.current) imageInputRef.current.value = "";
    if (glbInputRef.current) glbInputRef.current.value = "";
  };

  const renderDropzone = ({ kind, icon, main, sub, inputRef, disabled }) => (
    <div
      className={`it3-dropzone${dragOver === kind ? " is-over" : ""}${disabled ? " is-disabled" : ""}`}
      role="button"
      aria-disabled={disabled}
      tabIndex={disabled ? -1 : 0}
      onClick={() => {
        if (!disabled) inputRef.current?.click();
      }}
      onKeyDown={(event) => {
        if (!disabled && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          inputRef.current?.click();
        }
      }}
      onDragOver={(event) => {
        event.preventDefault();
        if (!disabled) setDragOver(kind);
      }}
      onDragLeave={() => setDragOver(null)}
      onDrop={(event) => {
        event.preventDefault();
        if (!disabled) handleDrop(event, kind);
      }}
    >
      <div className="it3-dropzone-icon">{icon}</div>
      <div className="it3-dropzone-main">{main}</div>
      <div className="it3-dropzone-sub">{sub}</div>
    </div>
  );

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">업로드할 파일 종류를 선택해주세요</h2>
      <p className="it3-step-desc">
        사진으로 새 모델을 만들거나, 가지고 있는 GLB 모델을 바로 보정할 수 있어요.
      </p>

      <div className="it3-upload-options">
        <section className="it3-upload-option">
          <div className="it3-upload-option-head">
            <span className="it3-upload-option-badge">사진</span>
            <div>
              <h3>사진으로 3D 만들기</h3>
              <p>배경 제거와 3D 생성 과정을 진행해요.</p>
            </div>
          </div>

          {selectedFile?.kind === "image" ? (
            <div className="it3-preview-wrap">
              <img
                className="it3-preview-img"
                src={selectedFile.url}
                alt="업로드한 가구 사진"
              />
              <button
                type="button"
                className="it3-btn-ghost"
                onClick={clearSelectedFile}
              >
                다른 사진 선택
              </button>
            </div>
          ) : (
            renderDropzone({
              kind: "image",
              icon: "🖼️",
              main: selectedFile?.kind === "glb" ? "GLB가 선택되어 있어요" : "사진 선택",
              sub: selectedFile?.kind === "glb"
                ? "GLB를 제거한 후 사진을 선택할 수 있어요."
                : "JPG · PNG · WEBP / 최대 10MB",
              inputRef: imageInputRef,
              disabled: selectedFile?.kind === "glb",
            })
          )}
        </section>

        <section className="it3-upload-option">
          <div className="it3-upload-option-head">
            <span className="it3-upload-option-badge is-glb">GLB</span>
            <div>
              <h3>GLB 파일 보정하기</h3>
              <p>3D 생성 없이 모델 보정으로 바로 이동해요.</p>
            </div>
          </div>

          {selectedFile?.kind === "glb" ? (
            <div className="it3-selected-glb">
              <div className="it3-dropzone-icon">🧊</div>
              <div className="it3-result-label">선택한 GLB 파일</div>
              <div className="it3-result-main">{selectedFile.file.name}</div>
              <div className="it3-file-meta">
                {(selectedFile.file.size / 1024 / 1024).toFixed(2)} MB
              </div>
              <button
                type="button"
                className="it3-btn-ghost"
                onClick={clearSelectedFile}
              >
                다른 GLB 선택
              </button>
            </div>
          ) : (
            renderDropzone({
              kind: "glb",
              icon: "🧊",
              main: selectedFile?.kind === "image" ? "사진이 선택되어 있어요" : "GLB 파일 선택",
              sub: selectedFile?.kind === "image"
                ? "사진을 제거한 후 GLB를 선택할 수 있어요."
                : ".GLB / 최대 100MB",
              inputRef: glbInputRef,
              disabled: selectedFile?.kind === "image",
            })
          )}
        </section>
      </div>

      <input
        ref={imageInputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        style={{ display: "none" }}
        onChange={(event) => {
          handleFile(event.target.files?.[0], "image");
          event.target.value = "";
        }}
      />
      <input
        ref={glbInputRef}
        type="file"
        accept=".glb,model/gltf-binary"
        style={{ display: "none" }}
        onChange={(event) => {
          handleFile(event.target.files?.[0], "glb");
          event.target.value = "";
        }}
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
