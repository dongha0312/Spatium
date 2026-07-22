import React, { useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import {
  generateModel,
  getImgTo3dErrorMessage,
  isCanceledImgTo3dRequest,
  removeBackground,
} from "../../api/imgTo3dApi";
import "../../styles/imgto3d.css";

import AccountPanel from "../../components/AccountPanel";
import AvatarButton from "../../components/AvatarButton";
import Header from "../../components/Header";
import { getLoginSession } from "../../utils/authSession";
import { checkGpuRateLimit, recordGpuUsage } from "../../utils/gpuRateLimit";
import { getMyInfo } from "../../springApi/MemberSpringBootApi";
import useLogout from "../../hooks/useLogout";
import useProjectStats from "../../hooks/useProjectStats";

import UploadStep from "./UploadStep";
import ObjectNameStep from "./ObjectNameStep";
import SegmentationStep from "./SegmentationStep";
import GenerateStep from "./GenerateStep";
import ViewerStep from "./ViewerStep";
import SaveStep from "./SaveStep";

const STEP_LABELS = [
  "사진 업로드",
  "객체명 입력",
  "배경 제거",
  "3D 생성",
  "모델 보정",
  "저장",
];

const revokeObjectUrl = (url) => {
  if (typeof url === "string" && url.startsWith("blob:")) {
    URL.revokeObjectURL(url);
  }
};

function ImgTo3dPage() {
  const navigate = useNavigate();

  // 상단바 계정 영역 : 로그인 세션 / 내 정보 패널
  const [session, setSession] = useState(() => getLoginSession());
  const [panelOpen, setPanelOpen] = useState(false);
  const [profileImage, setProfileImage] = useState(null);
  const accountStats = useProjectStats(Boolean(session));

  const [step, setStep] = useState(0);
  const [image, setImage] = useState(null);
  const [objectName, setObjectName] = useState("");
  const [segmentationProvider, setSegmentationProvider] =
    useState("grounded_sam2");
  const [generationProvider, setGenerationProvider] = useState("local_triposr");
  const [mcResolution, setMcResolution] = useState("256");
  const [textureResolution, setTextureResolution] = useState("1024");
  const [remesh, setRemesh] = useState("none");
  const [segmentationResult, setSegmentationResult] = useState(null);
  const [segmentationStatus, setSegmentationStatus] = useState("idle");
  const [segmentationError, setSegmentationError] = useState("");
  const [generatedAsset, setGeneratedAsset] = useState(null);
  const [generationStatus, setGenerationStatus] = useState("idle");
  const [generationError, setGenerationError] = useState("");
  const [correctedModel, setCorrectedModel] = useState(null);

  const imageRef = useRef(null);
  const segmentationResultRef = useRef(null);
  const generatedAssetRef = useRef(null);
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
    revokeObjectUrl(generatedAssetRef.current?.modelUrl);
    generatedAssetRef.current = null;
    setGeneratedAsset(null);
    setGenerationStatus("idle");
    setGenerationError("");
    setCorrectedModel(null);
  }, [cancelGeneration]);

  const resetPipelineResults = useCallback(() => {
    cancelSegmentation();
    revokeObjectUrl(segmentationResultRef.current?.imageUrl);
    segmentationResultRef.current = null;
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

  const handleMcResolutionChange = useCallback(
    (next) => {
      setMcResolution(next);
      resetGenerationResult();
    },
    [resetGenerationResult],
  );

  const handleTextureResolutionChange = useCallback(
    (next) => {
      setTextureResolution(next);
      resetGenerationResult();
    },
    [resetGenerationResult],
  );

  const handleRemeshChange = useCallback(
    (next) => {
      setRemesh(next);
      resetGenerationResult();
    },
    [resetGenerationResult],
  );

  useEffect(() => {
    return () => {
      cancelSegmentation();
      cancelGeneration();
      if (imageRef.current?.url) URL.revokeObjectURL(imageRef.current.url);
      revokeObjectUrl(segmentationResultRef.current?.imageUrl);
      revokeObjectUrl(generatedAssetRef.current?.modelUrl);
    };
  }, [cancelGeneration, cancelSegmentation]);

  // 로그인 상태면 내 정보(프로필 사진)를 불러옴
  useEffect(() => {
    if (!session) return;
    let active = true;

    getMyInfo()
      .then((me) => {
        if (active) setProfileImage(me?.profileImageUrl || null);
      })
      .catch((err) => {
        console.warn("내 정보 조회 실패:", err);
      });

    return () => {
      active = false;
    };
  }, [session]);

  const toggleAccountPanel = () => setPanelOpen((prev) => !prev);

  // 마이페이지 버튼 : 대시보드로 이동
  const handleGoMypage = () => navigate("/member/mypage");

  // 계정설정 이동 (패널 닫고 이동)
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  // 로그아웃 : 서버 세션 정리 후 로컬 세션 삭제
  const handleLogout = useLogout(() => {
    setSession(null);
    setPanelOpen(false);
    navigate("/");
  });

  const runSegmentation = useCallback(async () => {
    const query = objectName.trim();
    if (
      !image?.file ||
      !query ||
      segmentationResult ||
      segmentationRequestRef.current
    )
      return;

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
      if (segmentationRequestRef.current !== controller) {
        revokeObjectUrl(result.imageUrl);
        return;
      }
      revokeObjectUrl(segmentationResultRef.current?.imageUrl);
      segmentationResultRef.current = result;
      setSegmentationResult(result);
      setSegmentationStatus("success");
    } catch (error) {
      if (
        segmentationRequestRef.current !== controller ||
        isCanceledImgTo3dRequest(error)
      )
        return;
      setSegmentationStatus("error");
      setSegmentationError(getImgTo3dErrorMessage(error));
    } finally {
      if (segmentationRequestRef.current === controller)
        segmentationRequestRef.current = null;
    }
  }, [image, objectName, segmentationProvider, segmentationResult]);

  const runGeneration = useCallback(async () => {
    if (
      !segmentationResult?.file ||
      generatedAsset ||
      generationRequestRef.current
    )
      return;

    // 사용자별 생성 횟수 제한 (3분 1회 / 하루 5회) : 초과 시 요청을 보내지 않고 안내
    const limit = checkGpuRateLimit();
    if (!limit.allowed) {
      setGenerationStatus("error");
      setGenerationError(limit.reason);
      return;
    }

    const controller = new AbortController();
    generationRequestRef.current = controller;
    setGenerationStatus("loading");
    setGenerationError("");

    // 실제 생성 요청을 보내는 시점에 사용 1회 기록
    recordGpuUsage();

    try {
      const result = await generateModel({
        image: segmentationResult.file,
        provider: generationProvider,
        mcResolution,
        textureResolution,
        remesh,
        signal: controller.signal,
      });
      if (generationRequestRef.current !== controller) {
        revokeObjectUrl(result.modelUrl);
        return;
      }
      revokeObjectUrl(generatedAssetRef.current?.modelUrl);
      generatedAssetRef.current = result;
      setGeneratedAsset(result);
      setGenerationStatus("success");
    } catch (error) {
      if (
        generationRequestRef.current !== controller ||
        isCanceledImgTo3dRequest(error)
      )
        return;
      setGenerationStatus("error");
      setGenerationError(getImgTo3dErrorMessage(error));
    } finally {
      if (generationRequestRef.current === controller)
        generationRequestRef.current = null;
    }
  }, [
    generatedAsset,
    generationProvider,
    mcResolution,
    remesh,
    segmentationResult,
    textureResolution,
  ]);

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
      mcResolution={mcResolution}
      onMcResolutionChange={handleMcResolutionChange}
      textureResolution={textureResolution}
      onTextureResolutionChange={handleTextureResolutionChange}
      remesh={remesh}
      onRemeshChange={handleRemeshChange}
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
      normalizedName={
        segmentationResult?.translatedQuery ||
        segmentationResult?.segmentedObject
      }
      correctedModel={correctedModel}
    />,
  ];

  return (
    <div className="app-page it3-root">
      <Header prefix="it3">
        {session ? (
          <div className="it3-nav-account">
            {/* 닉네임 왼쪽 : 마이페이지로 바로 이동하는 외곽선 버튼 */}
            <button
              type="button"
              className="it3-mypage-btn"
              onClick={handleGoMypage}
            >
              내 공간
            </button>
            {/* 닉네임 클릭 : 우측 "내 정보" 패널 열기 */}
            <AvatarButton
              prefix="it3"
              imageUrl={profileImage}
              initial={session.nickname.charAt(0).toUpperCase()}
              name={session.nickname}
              onClick={toggleAccountPanel}
              showCaret={false}
            />
          </div>
        ) : (
          <Link to="/member/mypage" className="it3-av-btn">
            <div className="it3-av-circ">S</div>
            <span className="it3-av-name">마이페이지</span>
          </Link>
        )}
      </Header>

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

      {/* 닉네임 클릭 시 열리는 "내 정보" 우측 패널 */}
      <AccountPanel
        open={Boolean(session && panelOpen)}
        prefix="it3"
        profile={{
          name: session?.nickname,
          initial: session?.nickname?.charAt(0).toUpperCase(),
          imageUrl: profileImage,
          subtext: session?.email ? `${session.email}` : "",
        }}
        statItems={[
          { label: "프로젝트", value: accountStats.projectCount },
          { label: "룸 개수", value: accountStats.roomCount },
        ]}
        onClose={() => setPanelOpen(false)}
        onProfileClick={handleGoAccount}
        onLogout={handleLogout}
        onAccountClick={handleGoAccount}
      />
    </div>
  );
}

export default ImgTo3dPage;
