import React, { useEffect, useState } from "react";
import { GENERATE_STAGES } from "./mockData";

// 5단계: TripoSR GLB 생성 진행 표시 (가짜 프로그레스)
function GenerateStep({ generated, onComplete }) {
  const [progress, setProgress] = useState(generated ? 100 : 0);

  useEffect(() => {
    if (generated) return;
    const id = setInterval(() => {
      setProgress((p) => Math.min(p + Math.random() * 4 + 1, 100));
    }, 120);
    return () => clearInterval(id);
  }, [generated]);

  useEffect(() => {
    if (progress >= 100 && !generated) onComplete();
  }, [progress, generated, onComplete]);

  const stageIdx = Math.min(
    Math.floor((progress / 100) * GENERATE_STAGES.length),
    GENERATE_STAGES.length - 1
  );

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">
        {progress >= 100 ? "3D 모델이 완성됐어요!" : "3D 모델을 만들고 있어요"}
      </h2>
      <p className="it3-step-desc">
        {progress >= 100
          ? "다음 단계에서 모델을 확인하고 보정할 수 있어요."
          : "사진 한 장으로 GLB 모델을 생성하는 중이에요. 잠시만 기다려주세요."}
      </p>

      <div className="it3-progress-track">
        <div className="it3-progress-fill" style={{ width: `${progress}%` }} />
      </div>
      <div className="it3-progress-pct">{Math.floor(progress)}%</div>

      <ul className="it3-stage-list">
        {GENERATE_STAGES.map((label, i) => {
          const state = progress >= 100 || i < stageIdx ? "done" : i === stageIdx ? "active" : "wait";
          return (
            <li key={label} className={`it3-stage is-${state}`}>
              <span className="it3-stage-dot">{state === "done" ? "✓" : i + 1}</span>
              {label}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export default GenerateStep;
