import React from "react";

function ObjectNameStep({
  objectName,
  onObjectNameChange,
  segmentationProvider,
  onSegmentationProviderChange,
  generationProvider,
  onGenerationProviderChange,
  mcResolution,
  onMcResolutionChange,
  textureResolution,
  onTextureResolutionChange,
  remesh,
  onRemeshChange,
}) {
  return (
    <div className="it3-step">
      <h2 className="it3-step-title">어떤 가구인가요?</h2>
      <p className="it3-step-desc">
        사진에서 분리할 가구 이름을 입력해주세요. 한국어 이름은 배경 제거 과정에서 자동으로
        변환됩니다.
      </p>

      <div className="it3-name-row">
        <input
          className="it3-input"
          type="text"
          value={objectName}
          placeholder="예) 침대 옆 협탁"
          onChange={(event) => onObjectNameChange(event.target.value)}
        />
      </div>

      <p className="it3-hint">
        예: 의자, 책상, 침대 옆 협탁. 입력한 이름과 가장 잘 맞는 가구를 자동으로 분리합니다.
      </p>

      <div className="it3-save-form it3-pipeline-config">
        <section className="it3-config-section">
          <h3 className="it3-config-title">객체 분리 설정</h3>

          <div className="it3-field">
            <label className="it3-field-label" htmlFor="it3-segmentation-provider">
              객체 분리 모델
            </label>
            <select
              id="it3-segmentation-provider"
              className="it3-input"
              value={segmentationProvider}
              onChange={(event) => onSegmentationProviderChange(event.target.value)}
            >
              <option value="grounded_sam2">GroundingDINO + SAM2 (객체명 기반)</option>
              <option value="yolo">YOLO (빠른 기존 방식)</option>
            </select>
          </div>

          {segmentationProvider === "yolo" && (
            <div className="it3-field">
              <span className="it3-field-label">분리할 대상</span>
              <div className="it3-option-readonly">자동 선택 (사진 중앙의 큰 객체)</div>
            </div>
          )}

          <p className="it3-hint">
            {segmentationProvider === "grounded_sam2"
              ? "입력한 가구 이름을 번역해 GroundingDINO 탐지와 SAM2 마스크를 순서대로 실행합니다."
              : "YOLO의 개별 클래스는 선택하지 않고 사진 중앙의 주요 객체를 자동으로 분리합니다."}
          </p>
        </section>

        <section className="it3-config-section">
          <h3 className="it3-config-title">3D 생성 설정</h3>

          <div className="it3-field">
            <label className="it3-field-label" htmlFor="it3-generation-provider">
              3D 생성 모델
            </label>
            <select
              id="it3-generation-provider"
              className="it3-input"
              value={generationProvider}
              onChange={(event) => onGenerationProviderChange(event.target.value)}
            >
              <option value="local_triposr">TripoSR (기존 로컬 모델)</option>
              <option value="local_stable_fast_3d">Stable Fast 3D (무료 로컬 모델)</option>
            </select>
          </div>

          <p className="it3-hint">
            {generationProvider === "local_stable_fast_3d"
              ? "Stability API 과금 없이 서버 GPU에서 로컬로 실행합니다. 최초 1회 설치가 필요합니다."
              : "기존 TripoSR 환경을 그대로 사용합니다."}
          </p>

          {generationProvider === "local_triposr" ? (
            <div className="it3-field">
              <label className="it3-field-label" htmlFor="it3-mc-resolution">
                메시 해상도
              </label>
              <select
                id="it3-mc-resolution"
                className="it3-input"
                value={mcResolution}
                onChange={(event) => onMcResolutionChange(event.target.value)}
              >
                <option value="192">192</option>
                <option value="256">256 (권장)</option>
                <option value="320">320</option>
              </select>
            </div>
          ) : (
            <div className="it3-inline-fields">
              <div className="it3-field">
                <label className="it3-field-label" htmlFor="it3-texture-resolution">
                  텍스처 해상도
                </label>
                <select
                  id="it3-texture-resolution"
                  className="it3-input"
                  value={textureResolution}
                  onChange={(event) => onTextureResolutionChange(event.target.value)}
                >
                  <option value="512">512</option>
                  <option value="1024">1024 (권장)</option>
                  <option value="2048">2048</option>
                </select>
              </div>

              <div className="it3-field">
                <label className="it3-field-label" htmlFor="it3-remesh">
                  리메시
                </label>
                <select
                  id="it3-remesh"
                  className="it3-input"
                  value={remesh}
                  onChange={(event) => onRemeshChange(event.target.value)}
                >
                  <option value="none">없음 (권장)</option>
                  <option value="triangle">Triangle</option>
                  <option value="quad">Quad</option>
                </select>
              </div>
            </div>
          )}

          <p className="it3-config-preview">
            배경 제거 미리보기에서 확인된 투명 PNG로 3D 모델을 생성합니다.
          </p>
        </section>
      </div>
    </div>
  );
}

export default ObjectNameStep;
