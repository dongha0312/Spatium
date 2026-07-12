import React, { useEffect, useState } from "react";

function SegmentationStep({ image, result, status, error, onStart, onRetry, provider }) {
  const [showOriginal, setShowOriginal] = useState(false);

  useEffect(() => {
    if (status === "idle" && !result) onStart();
  }, [onStart, result, status]);

  useEffect(() => {
    setShowOriginal(false);
  }, [result?.id]);

  const confidence = Number(result?.confidence);
  const providerLabel =
    provider === "yolo" ? "YOLO segmentation" : "GroundingDINO + SAM2";

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">
        {status === "success" ? "배경을 제거했어요" : "가구를 분리하고 있어요"}
      </h2>
      <p className="it3-step-desc">
        입력한 가구 이름을 기준으로 사진에서 대상을 찾아 투명 배경 PNG로 만듭니다.
      </p>

      {(status === "idle" || status === "loading") && (
        <div className="it3-loading-note">
          <span className="it3-spinner" />
          {providerLabel} 모델이 가구를 분리하고 있어요…
        </div>
      )}

      {status === "error" && (
        <div className="it3-result-card">
          <div className="it3-result-label">배경 제거 실패</div>
          <div className="it3-result-main">{error}</div>
          <button type="button" className="it3-btn-ghost" onClick={onRetry}>
            다시 시도
          </button>
        </div>
      )}

      {status === "success" && result && (
        <>
          <div className="it3-seg-wrap it3-checker">
            <img
              className="it3-seg-img"
              src={showOriginal ? image?.url : result.imageUrl}
              alt={showOriginal ? "업로드한 원본" : "배경이 제거된 가구"}
            />
          </div>

          <div className="it3-seg-actions">
            <label className="it3-toggle">
              <input
                type="checkbox"
                checked={showOriginal}
                onChange={(event) => setShowOriginal(event.target.checked)}
              />
              원본 사진 보기
            </label>
          </div>

          <div className="it3-result-card">
            <div className="it3-result-label">분리 결과</div>
            <div className="it3-result-main">
              {result.segmentedObject || result.translatedQuery || "가구"}
            </div>
            <p className="it3-hint">사용 모델: {providerLabel}</p>
            {result.translatedQuery && (
              <p className="it3-hint">변환된 검색어: {result.translatedQuery}</p>
            )}
            {Number.isFinite(confidence) && (
              <p className="it3-hint">탐지 신뢰도: {(confidence * 100).toFixed(1)}%</p>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default SegmentationStep;
