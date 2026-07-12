import React, { useCallback, useEffect, useState } from "react";
import "../../styles/imgto3d.css";
import UploadStep from "./UploadStep";
import ObjectNameStep from "./ObjectNameStep";
import DetectionSelectStep from "./DetectionSelectStep";
import SegmentationStep from "./SegmentationStep";
import GenerateStep from "./GenerateStep";
import ViewerStep from "./ViewerStep";
import SaveStep from "./SaveStep";

// 이미지 → 3D 가구 생성 위저드
// 아직 라우터 · 백엔드와 연결하지 않은 독립 페이지 (UI 목업)
// 흐름: 업로드 → 객체명 → 객체 선택 → 배경 제거 → 3D 생성 → 보정 → 저장

const STEP_LABELS = [
  "사진 업로드",
  "객체명 입력",
  "객체 선택",
  "배경 제거",
  "3D 생성",
  "모델 보정",
  "저장",
];

function ImgTo3dPage() {
  const [step, setStep] = useState(0);

  // 단계 간 공유 상태
  const [image, setImage] = useState(null); // { file, url }
  const [objectName, setObjectName] = useState("");
  const [normalized, setNormalized] = useState(null); // { input, en, tags }
  const [detections, setDetections] = useState(null); // 바운딩박스 목록
  const [selectedId, setSelectedId] = useState(null);
  const [generated, setGenerated] = useState(false);

  // 사진을 교체하면 이전 objectURL 해제 + 이후 단계 결과 초기화
  const handleImageChange = useCallback((next) => {
    setImage((prev) => {
      if (prev?.url) URL.revokeObjectURL(prev.url);
      return next;
    });
    setDetections(null);
    setSelectedId(null);
    setGenerated(false);
  }, []);

  // 페이지를 떠날 때 objectURL 해제
  useEffect(() => {
    return () => {
      setImage((prev) => {
        if (prev?.url) URL.revokeObjectURL(prev.url);
        return null;
      });
    };
  }, []);

  const handleNormalized = useCallback((result) => {
    setNormalized(result);
    setDetections(null); // 객체명이 바뀌면 detection도 다시
    setSelectedId(null);
  }, []);

  const handleGenerated = useCallback(() => setGenerated(true), []);

  // 단계별 "다음" 버튼 활성 조건
  const canNext = [
    Boolean(image),
    Boolean(normalized),
    Boolean(selectedId),
    true,
    generated,
    true,
    false, // 마지막 단계는 저장 버튼으로 종료
  ][step];

  const stepViews = [
    <UploadStep image={image} onImageChange={handleImageChange} />,
    <ObjectNameStep
      objectName={objectName}
      onObjectNameChange={setObjectName}
      normalized={normalized}
      onNormalized={handleNormalized}
    />,
    <DetectionSelectStep
      image={image}
      normalized={normalized}
      detections={detections}
      onDetections={setDetections}
      selectedId={selectedId}
      onSelect={setSelectedId}
    />,
    <SegmentationStep image={image} detections={detections} selectedId={selectedId} />,
    <GenerateStep generated={generated} onComplete={handleGenerated} />,
    <ViewerStep objectLabel={normalized?.en} />,
    <SaveStep objectName={objectName} normalized={normalized} />,
  ];

  return (
    <div className="it3-root">
      <header className="it3-header">
        <div className="it3-header-logo">
          <span className="it3-logo-sq">
            <span className="it3-logo-sq-i" />
          </span>
          SPATIUM
        </div>
        <div className="it3-header-title">이미지로 3D 가구 만들기</div>
      </header>

      {/* 단계 표시기 */}
      <ol className="it3-steps">
        {STEP_LABELS.map((label, i) => {
          const state = i < step ? "done" : i === step ? "active" : "wait";
          return (
            <li key={label} className={`it3-steps-item is-${state}`}>
              <span className="it3-steps-dot">{i < step ? "✓" : i + 1}</span>
              <span className="it3-steps-label">{label}</span>
            </li>
          );
        })}
      </ol>

      <main className="it3-body">
        <div className="it3-card">{stepViews[step]}</div>
      </main>

      <footer className="it3-footer">
        <button
          type="button"
          className="it3-btn-ghost"
          disabled={step === 0}
          onClick={() => setStep((s) => Math.max(s - 1, 0))}
        >
          ← 이전
        </button>
        {step < STEP_LABELS.length - 1 && (
          <button
            type="button"
            className="it3-btn-prim"
            disabled={!canNext}
            onClick={() => setStep((s) => s + 1)}
          >
            다음 →
          </button>
        )}
      </footer>
    </div>
  );
}

export default ImgTo3dPage;
