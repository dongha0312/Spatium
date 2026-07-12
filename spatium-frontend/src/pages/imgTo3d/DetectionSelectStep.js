import React, { useEffect, useState } from "react";
import { mockDetect } from "./mockData";

// 3단계: GroundingDINO detection 결과(목업) 중 사용자가 원하는 객체 하나를 선택
function DetectionSelectStep({ image, normalized, detections, onDetections, selectedId, onSelect }) {
  const [loading, setLoading] = useState(false);

  // 스텝 진입 시 detection이 아직 없으면 목업 detection 실행
  useEffect(() => {
    if (detections || !normalized) return;
    let active = true;
    setLoading(true);
    mockDetect(normalized.en.split("/")[0].trim()).then((boxes) => {
      if (!active) return;
      onDetections(boxes);
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [detections, normalized, onDetections]);

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">가구를 선택해주세요</h2>
      <p className="it3-step-desc">
        사진에서 후보를 찾았어요. 3D로 만들 가구 하나를 골라주세요.
      </p>

      {loading && (
        <div className="it3-loading-note">
          <span className="it3-spinner" />
          GroundingDINO가 “{normalized?.en}” 객체를 찾고 있어요…
        </div>
      )}

      {!loading && detections && (
        <>
          <div className="it3-detect-wrap">
            <img className="it3-detect-img" src={image.url} alt="객체 후보가 표시된 사진" />
            {detections.map((box) => (
              <button
                key={box.id}
                type="button"
                className={`it3-detect-box${selectedId === box.id ? " is-selected" : ""}`}
                style={{
                  left: `${box.x}%`,
                  top: `${box.y}%`,
                  width: `${box.w}%`,
                  height: `${box.h}%`,
                }}
                onClick={() => onSelect(box.id)}
              >
                <span className="it3-detect-chip">
                  {box.label} {Math.round(box.score * 100)}%
                </span>
              </button>
            ))}
          </div>
          <p className="it3-hint">
            {selectedId
              ? "선택 완료! 다음 단계에서 배경을 제거해요."
              : `후보 ${detections.length}개 중 하나를 클릭하세요.`}
          </p>
        </>
      )}
    </div>
  );
}

export default DetectionSelectStep;
