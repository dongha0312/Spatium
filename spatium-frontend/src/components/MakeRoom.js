function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
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
              {/* htmlFor 없음: 파일 선택은 아래 드롭존 영역에서만 열리도록 함 */}
              <label>Metadata JSON</label>
              <input
                ref={metadataFileInputRef}
                id="mp-metadata-input"
                type="file"
                accept="application/json,.json"
                className="mp-dz-input"
                onChange={onMetadataFileChange}
              />
              <label
                htmlFor="mp-metadata-input"
                className={`mp-dropzone${metadataFile ? " is-filled" : ""}`}
              >
                <span className="mp-dz-icon">
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M6 2h9l5 5v15a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Z"
                      stroke="currentColor"
                      strokeWidth="1.6"
                    />
                  </svg>
                </span>
                <span className="mp-dz-text">
                  <span className="mp-dz-title">
                    {metadataFile
                      ? metadataFile.name
                      : "클릭하거나 파일을 끌어다 놓으세요"}
                  </span>
                  <span className="mp-dz-ext">
                    {metadataFile
                      ? formatFileSize(metadataFile.size)
                      : ".json파일"}
                  </span>
                </span>
                <span className="mp-dz-check">✓</span>
                {metadataFile && (
                  <button
                    type="button"
                    className="mp-dz-remove"
                    onClick={onRemoveMetadataFile}
                  >
                    ×
                  </button>
                )}
              </label>

              <label>룸 파일 (3D 스캔)</label>
              <input
                ref={roomFileInputRef}
                id="mp-room-file-input"
                type="file"
                accept=".usdz,model/vnd.usdz+zip,application/octet-stream"
                className="mp-dz-input"
                onChange={onRoomFileChange}
              />
              <label
                htmlFor="mp-room-file-input"
                className={`mp-dropzone${roomFile ? " is-filled" : ""}`}
              >
                <span className="mp-dz-icon">
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M12 2 3 7v10l9 5 9-5V7l-9-5Z"
                      stroke="currentColor"
                      strokeWidth="1.6"
                      strokeLinejoin="round"
                    />
                  </svg>
                </span>
                <span className="mp-dz-text">
                  <span className="mp-dz-title">
                    {roomFile
                      ? roomFile.name
                      : "클릭하거나 파일을 끌어다놓으세요"}
                  </span>
                  <span className="mp-dz-ext">
                    {roomFile ? formatFileSize(roomFile.size) : ".usdz"}
                  </span>
                </span>
                <span className="mp-dz-check">✓</span>
                {roomFile && (
                  <button
                    type="button"
                    className="mp-dz-remove"
                    onClick={onRemoveRoomFile}
                  >
                    ×
                  </button>
                )}
              </label>
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
