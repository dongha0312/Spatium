import React, { useEffect, useState } from "react";
import { MOCK_DELAY } from "./mockData";

// 4단계: SAM2 segmentation → 배경 제거 결과 확인 (목업)
// 선택한 바운딩박스 바깥 영역을 체커보드로 덮어 "배경이 제거된" 것처럼 보여준다.
function SegmentationStep({ image, detections, selectedId }) {
  const [processing, setProcessing] = useState(true);
  const [showOriginal, setShowOriginal] = useState(false);

  const box = detections?.find((b) => b.id === selectedId);

  useEffect(() => {
    setProcessing(true);
    const id = setTimeout(() => setProcessing(false), MOCK_DELAY.segment);
    return () => clearTimeout(id);
  }, [selectedId]);

  if (!box) return null;

  // 바운딩박스 바깥 4면(상/하/좌/우)을 체커보드 오버레이로 가린다
  const covers = [
    { left: 0, top: 0, width: "100%", height: `${box.y}%` },
    { left: 0, top: `${box.y + box.h}%`, width: "100%", bottom: 0 },
    { left: 0, top: `${box.y}%`, width: `${box.x}%`, height: `${box.h}%` },
    { left: `${box.x + box.w}%`, top: `${box.y}%`, right: 0, height: `${box.h}%` },
  ];

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">배경을 제거했어요</h2>
      <p className="it3-step-desc">
        결과가 마음에 들지 않으면 이전 단계에서 다른 후보를 선택할 수 있어요.
      </p>

      {processing ? (
        <div className="it3-loading-note">
          <span className="it3-spinner" />
          SAM2가 선택한 가구를 분리하고 있어요…
        </div>
      ) : (
        <>
          <div className="it3-seg-wrap it3-checker">
            <img className="it3-seg-img" src={image.url} alt="배경이 제거된 가구" />
            {!showOriginal &&
              covers.map((style, i) => (
                <div key={i} className="it3-seg-cover it3-checker" style={style} />
              ))}
          </div>

          <div className="it3-seg-actions">
            <label className="it3-toggle">
              <input
                type="checkbox"
                checked={showOriginal}
                onChange={(e) => setShowOriginal(e.target.checked)}
              />
              원본 사진 보기
            </label>
            <button
              type="button"
              className="it3-btn-ghost"
              onClick={() => alert("마스크 브러시 편집은 백엔드 연동 후 지원 예정이에요.")}
            >
              마스크 수정
            </button>
          </div>
        </>
      )}
    </div>
  );
}

export default SegmentationStep;
