import React, { useEffect } from "react";

function GenerateStep({ result, status, error, onStart, onRetry, provider }) {
  useEffect(() => {
    if (status === "idle" && !result) onStart();
  }, [onStart, result, status]);

  const completed = status === "success" && result;
  const providerLabel =
    provider === "local_stable_fast_3d" ? "Stable Fast 3D" : "TripoSR";

  return (
    <div className="it3-step">
      <h2 className="it3-step-title">
        {completed ? "3D 모델이 완성됐어요!" : "3D 모델을 만들고 있어요"}
      </h2>
      <p className="it3-step-desc">
        {completed
          ? "다음 단계에서 생성된 모델을 확인하고 보정할 수 있어요."
          : "배경이 제거된 이미지로 GLB 모델을 생성합니다. 작업이 끝날 때까지 기다려주세요."}
      </p>

      {(status === "idle" || status === "loading") && (
        <div className="it3-loading-note">
          <span className="it3-spinner" />
          {providerLabel}가 메시와 텍스처를 생성하고 있어요…
        </div>
      )}

      {status === "error" && (
        <div className="it3-result-card">
          <div className="it3-result-label">3D 생성 실패</div>
          <div className="it3-result-main">{error}</div>
          <button type="button" className="it3-btn-ghost" onClick={onRetry}>
            다시 시도
          </button>
        </div>
      )}

      {completed && (
        <div className="it3-result-card">
          <div className="it3-result-label">생성 완료</div>
          <div className="it3-result-main">GLB 모델이 준비되었습니다.</div>
          <p className="it3-hint">Provider: {result.provider}</p>
        </div>
      )}
    </div>
  );
}

export default GenerateStep;
