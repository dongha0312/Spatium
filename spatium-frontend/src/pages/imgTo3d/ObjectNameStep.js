import React from "react";

function ObjectNameStep({
  objectName,
  onObjectNameChange,
  segmentationProvider,
  onSegmentationProviderChange,
  generationProvider,
  onGenerationProviderChange,
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

      <div className="it3-save-form">
        <div className="it3-field">
          <label className="it3-field-label" htmlFor="it3-segmentation-provider">
            배경 제거 모델
          </label>
          <select
            id="it3-segmentation-provider"
            className="it3-input"
            value={segmentationProvider}
            onChange={(event) => onSegmentationProviderChange(event.target.value)}
          >
            <option value="grounded_sam2">GroundingDINO + SAM2 (객체명 기반)</option>
            <option value="yolo">YOLO segmentation (자동 선택)</option>
          </select>
          <p className="it3-hint">
            {segmentationProvider === "grounded_sam2"
              ? "한국어 객체명을 번역해 사진에서 해당 가구를 찾아 분리합니다."
              : "지원 클래스가 제한적이며, 한국어 입력일 때는 사진 중앙의 주요 객체를 자동 선택합니다."}
          </p>
        </div>

        <div className="it3-field">
          <label className="it3-field-label" htmlFor="it3-generation-provider">
            3D GLB 생성 모델
          </label>
          <select
            id="it3-generation-provider"
            className="it3-input"
            value={generationProvider}
            onChange={(event) => onGenerationProviderChange(event.target.value)}
          >
            <option value="local_triposr">Local TripoSR (GPU)</option>
            <option value="local_stable_fast_3d">Local Stable Fast 3D (GPU)</option>
          </select>
        </div>
      </div>
    </div>
  );
}

export default ObjectNameStep;
