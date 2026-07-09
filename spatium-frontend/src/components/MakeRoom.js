import { useState } from "react";

function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// Metadata JSON / 룸 파일(3D 스캔) 드롭존 : 아이콘·확장자만 다르고 구조가 같아 공용으로 뺌
function FileDropzone({
  id,
  label,
  accept,
  icon,
  file,
  inputRef,
  onChange,
  onRemove,
  placeholder,
  extHint,
}) {
  const [isDragOver, setIsDragOver] = useState(false);

  const handleDragOver = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  };

  const handleDragLeave = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);

    const droppedFiles = e.dataTransfer.files;
    if (!droppedFiles || droppedFiles.length === 0) return;

    if (inputRef?.current) {
      inputRef.current.files = droppedFiles;
    }

    onChange({ target: { files: droppedFiles } });
  };

  return (
    <>
      <label>{label}</label>
      <input
        ref={inputRef}
        id={id}
        type="file"
        accept={accept}
        className="mp-dz-input"
        onChange={onChange}
      />
      <label
        htmlFor={id}
        className={`mp-dropzone${file ? " is-filled" : ""}${isDragOver ? " is-dragover" : ""}`}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        <span className="mp-dz-icon">{icon}</span>
        <span className="mp-dz-text">
          <span className="mp-dz-title">{file ? file.name : placeholder}</span>
          <span className="mp-dz-ext">
            {file ? formatFileSize(file.size) : extHint}
          </span>
        </span>
        <span className="mp-dz-check">✓</span>
        {file && (
          <button type="button" className="mp-dz-remove" onClick={onRemove}>
            ×
          </button>
        )}
      </label>
    </>
  );
}

// 마이페이지의 "새 프로젝트 / 새 룸 만들기" 모달
function MakeRoom({
  open,
  mode,
  targetProject,
  nameInput,
  onNameChange,
  metadataFile,
  metadataFileInputRef,
  onMetadataFileChange,
  onRemoveMetadataFile,
  roomFile,
  roomFileInputRef,
  onRoomFileChange,
  onRemoveRoomFile,
  error,
  submitting,
  onClose,
  onBackdropClick,
  onSubmit,
}) {
  if (!open) return null;

  return (
    <div className="mp-modal-backdrop" onClick={onBackdropClick}>
      <form
        className="mp-dialog"
        role="dialog"
        aria-modal="true"
        onSubmit={onSubmit}
      >
        <div className="mp-dialog-head">
          <div className="mp-dialog-title-group">
            <div className="mp-dialog-title">
              {mode === "room" ? "새 룸 만들기" : "새 프로젝트"}
            </div>
            {mode === "room" && targetProject && (
              <div className="mp-dialog-sub">
                {targetProject.name} 프로젝트에 추가됩니다
              </div>
            )}
          </div>
          <button type="button" className="mp-dialog-close" onClick={onClose}>
            ×
          </button>
        </div>
        <div className="mp-modal-field">
          <label htmlFor="mp-name-input">
            {mode === "room" ? "룸 이름" : "프로젝트명"}
          </label>
          <input
            id="mp-name-input"
            type="text"
            placeholder={
              mode === "room" ? "룸명을 입력하세요" : "프로젝트명을 입력하세요"
            }
            autoComplete="off"
            value={nameInput}
            onChange={onNameChange}
            autoFocus
          />
          {mode === "room" && (
            <>
              <FileDropzone
                id="mp-metadata-input"
                label="Metadata JSON"
                accept="application/json,.json"
                icon={
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Z"
                      stroke="currentColor"
                      strokeWidth="1.6"
                    />
                  </svg>
                }
                file={metadataFile}
                inputRef={metadataFileInputRef}
                onChange={onMetadataFileChange}
                onRemove={onRemoveMetadataFile}
                placeholder="클릭하거나 파일을 끌어다 놓으세요"
                extHint=".json파일"
              />

              <FileDropzone
                id="mp-room-file-input"
                label="룸 파일 (3D 스캔)"
                accept=".usdz,model/vnd.usdz+zip,application/octet-stream"
                icon={
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M12 2 3 7v10l9 5 9-5V7l-9-5Z"
                      stroke="currentColor"
                      strokeWidth="1.6"
                      strokeLinejoin="round"
                    />
                  </svg>
                }
                file={roomFile}
                inputRef={roomFileInputRef}
                onChange={onRoomFileChange}
                onRemove={onRemoveRoomFile}
                placeholder="클릭하거나 파일을 끌어다놓으세요"
                extHint=".usdz"
              />
            </>
          )}
          <div className="mp-modal-help">{error}</div>
        </div>
        <div className="mp-dialog-actions">
          <button
            type="button"
            className="mp-dialog-btn mp-dialog-btn-sub"
            onClick={onClose}
            disabled={submitting}
          >
            취소
          </button>
          <button
            type="submit"
            className="mp-dialog-btn mp-dialog-btn-main"
            disabled={submitting}
          >
            {submitting ? "생성 중..." : mode === "room" ? "룸 만들기" : "생성"}
          </button>
        </div>
      </form>
    </div>
  );
}

export default MakeRoom;
