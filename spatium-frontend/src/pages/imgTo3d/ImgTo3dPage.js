import React, { useCallback, useEffect, useRef, useState } from "react";
import { generateModel, getImgTo3dErrorMessage, isCanceledImgTo3dRequest, removeBackground } from "../../api/imgTo3dApi";
import "../../styles/imgto3d.css";
import UploadStep from "./UploadStep";
import ObjectNameStep from "./ObjectNameStep";
import SegmentationStep from "./SegmentationStep";
import GenerateStep from "./GenerateStep";
import ViewerStep from "./ViewerStep";
import SaveStep from "./SaveStep";

const STEP_LABELS = ["사진 업로드", "객체명 입력", "배경 제거", "3D 생성", "모델 보정", "저장"];

function ImgTo3dPage() {
  const [step, setStep] = useState(0);
  const [image, setImage] = useState(null);
  const [objectName, setObjectName] = useState("");
  const [segmentationProvider, setSegmentationProvider] = useState("grounded_sam2");
  const [generationProvider, setGenerationProvider] = useState("local_triposr");
  const [segmentationResult, setSegmentationResult] = useState(null);
  const [segmentationStatus, setSegmentationStatus] = useState("idle");
  const [segmentationError, setSegmentationError] = useState("");
  const [generatedAsset, setGeneratedAsset] = useState(null);
  const [generationStatus, setGenerationStatus] = useState("idle");
  const [generationError, setGenerationError] = useState("");
  const [correctedModel, setCorrectedModel] = useState(null);

  const imageRef = useRef(null);
  const segmentationRequestRef = useRef(null);
  const generationRequestRef = useRef(null);

  const cancelSegmentation = useCallback(() => {
    const request = segmentationRequestRef.current;
    segmentationRequestRef.current = null;
    request?.abort();
  }, []);

  const cancelGeneration = useCallback(() => {
    const request = generationRequestRef.current;
    generationRequestRef.current = null;
    request?.abort();
  }, []);

  const resetGenerationResult = useCallback(() => {
    cancelGeneration();
    setGeneratedAsset(null);
    setGenerationStatus("idle");
    setGenerationError("");
    setCorrectedModel(null);
  }, [cancelGeneration]);

  const resetPipelineResults = useCallback(() => {
    cancelSegmentation();
    setSegmentationResult(null);
    setSegmentationStatus("idle");
    setSegmentationError("");
    resetGenerationResult();
  }, [cancelSegmentation, resetGenerationResult]);

  const handleImageChange = useCallback(
    (next) => {
      if (imageRef.current?.url) URL.revokeObjectURL(imageRef.current.url);
      imageRef.current = next;
      setImage(next);
      resetPipelineResults();
    },
    [resetPipelineResults],
  );

  const handleObjectNameChange = useCallback(
    (next) => {
      setObjectName(next);
      resetPipelineResults();
    },
    [resetPipelineResults],
  );

  const handleSegmentationProviderChange = useCallback(
    (next) => {
      setSegmentationProvider(next);
      resetPipelineResults();
    },
    [resetPipelineResults],
  );

  const handleGenerationProviderChange = useCallback(
    (next) => {
      setGenerationProvider(next);
      resetGenerationResult();
    },
    [resetGenerationResult],
  );

  useEffect(() => {
    return () => {
      cancelSegmentation();
      cancelGeneration();
      if (imageRef.current?.url) URL.revokeObjectURL(imageRef.current.url);
    };
  }, [cancelGeneration, cancelSegmentation]);

  const runSegmentation = useCallback(async () => {
    const query = objectName.trim();
    if (!image?.file || !query || segmentationResult || segmentationRequestRef.current) return;

    const controller = new AbortController();
    segmentationRequestRef.current = controller;
    setSegmentationStatus("loading");
    setSegmentationError("");

    try {
      const result = await removeBackground({
        image: image.file,
        objectQuery: query,
        segmentationProvider,
        signal: controller.signal,
      });
      if (segmentationRequestRef.current !== controller) return;
      setSegmentationResult(result);
      setSegmentationStatus("success");
    } catch (error) {
      if (segmentationRequestRef.current !== controller || isCanceledImgTo3dRequest(error)) return;
      setSegmentationStatus("error");
      setSegmentationError(getImgTo3dErrorMessage(error));
    } finally {
      if (segmentationRequestRef.current === controller) segmentationRequestRef.current = null;
    }
  }, [image, objectName, segmentationProvider, segmentationResult]);

  const runGeneration = useCallback(async () => {
    if (!segmentationResult?.file || generatedAsset || generationRequestRef.current) return;

    const controller = new AbortController();
    generationRequestRef.current = controller;
    setGenerationStatus("loading");
    setGenerationError("");

    try {
      const result = await generateModel({
        image: segmentationResult.file,
        provider: generationProvider,
        signal: controller.signal,
      });
      if (generationRequestRef.current !== controller) return;
      setGeneratedAsset(result);
      setGenerationStatus("success");
    } catch (error) {
      if (generationRequestRef.current !== controller || isCanceledImgTo3dRequest(error)) return;
      setGenerationStatus("error");
      setGenerationError(getImgTo3dErrorMessage(error));
    } finally {
      if (generationRequestRef.current === controller) generationRequestRef.current = null;
    }
  }, [generatedAsset, generationProvider, segmentationResult]);

  const handleModelComplete = useCallback((result) => {
    setCorrectedModel(result);
    setStep(5);
  }, []);

  const canNext = [
    Boolean(image),
    Boolean(objectName.trim()),
    segmentationStatus === "success",
    generationStatus === "success",
    false,
    false,
  ][step];

  const stepViews = [
    <UploadStep image={image} onImageChange={handleImageChange} />,
    <ObjectNameStep
      objectName={objectName}
      onObjectNameChange={handleObjectNameChange}
      segmentationProvider={segmentationProvider}
      onSegmentationProviderChange={handleSegmentationProviderChange}
      generationProvider={generationProvider}
      onGenerationProviderChange={handleGenerationProviderChange}
    />,
    <SegmentationStep
      image={image}
      result={segmentationResult}
      status={segmentationStatus}
      error={segmentationError}
      onStart={runSegmentation}
      onRetry={runSegmentation}
      provider={segmentationProvider}
    />,
    <GenerateStep
      result={generatedAsset}
      status={generationStatus}
      error={generationError}
      onStart={runGeneration}
      onRetry={runGeneration}
      provider={generationProvider}
    />,
    <ViewerStep
      modelUrl={generatedAsset?.modelUrl}
      objectLabel={objectName.trim()}
      onComplete={handleModelComplete}
    />,
    <SaveStep
      objectName={objectName.trim()}
      normalizedName={segmentationResult?.translatedQuery || segmentationResult?.segmentedObject}
      correctedModel={correctedModel}
    />,
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
        <div className="it3-card">
          {stepViews[step]}

          <footer className="it3-footer">
        <button
          type="button"
          className="it3-btn-ghost"
          disabled={step === 0}
          onClick={() => setStep((current) => Math.max(current - 1, 0))}
        >
          ← 이전
        </button>
        {step < STEP_LABELS.length - 1 && step !== 4 && (
          <button
            type="button"
            className="it3-btn-prim"
            disabled={!canNext}
            onClick={() => setStep((current) => current + 1)}
          >
            다음 →
          </button>
        )}
          </footer>
        </div>
      </main>
    </div>
  );
}

export default ImgTo3dPage;
