import React, { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import "../styles/3deditor_detail.css";

const ROOM_NAME = "우리집 거실 리모델링";

// 레이어(공간) 목록
const INITIAL_LAYERS = [
  { id: "living", name: "거실", color: "#C4956A" },
  { id: "kitchen", name: "주방", color: "#D4A96A" },
  { id: "bedroom", name: "침실", color: "#7B9EC2" },
  { id: "bathroom", name: "욕실", color: "#B08080" },
];

// 배치된 가구 목록
const FURNITURE = [
  { id: "sofa", name: "소파 L형" },
  { id: "diningtable", name: "다이닝 테이블" },
  { id: "bed", name: "침대 킹" },
];

// 벽 색상 스와치 목록
const WALL_COLORS = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"];

// Skyview 모드에서 레이어별 평면도 구역 위치/스타일
const SKY_ZONES = {
  living: {
    left: "10%",
    top: "12%",
    width: "46%",
    height: "58%",
    border: "rgba(196,149,106,.58)",
    bg: "rgba(196,149,106,.05)",
    labelColor: "rgba(196,149,106,.85)",
    label: "거실 · 19.76㎡",
    fontSize: 8,
    fontWeight: 700,
  },
  kitchen: {
    left: "58%",
    top: "12%",
    width: "30%",
    height: "32%",
    border: "rgba(212,169,106,.48)",
    bg: "rgba(212,169,106,.04)",
    labelColor: "rgba(212,169,106,.7)",
    label: "주방",
    fontSize: 8,
    fontWeight: 400,
  },
  bedroom: {
    left: "58%",
    top: "46%",
    width: "30%",
    height: "30%",
    border: "rgba(123,158,194,.42)",
    bg: "rgba(123,158,194,.04)",
    labelColor: "rgba(123,158,194,.62)",
    label: "침실",
    fontSize: 8,
    fontWeight: 400,
  },
  bathroom: {
    left: "10%",
    top: "72%",
    width: "22%",
    height: "22%",
    border: "rgba(176,128,128,.38)",
    bg: "rgba(176,128,128,.04)",
    labelColor: "rgba(176,128,128,.55)",
    label: "욕실",
    fontSize: 7,
    fontWeight: 400,
  },
};

function ThreeDEditorDetail() {
  const navigate = useNavigate();
  const location = useLocation();

  // 3dEditor.js(⑥ 3D 에디터)에서 레이어를 클릭하고 넘어온 경우, 그 레이어를 그대로 이어받음
  const requestedLayerId = location.state?.layerId;
  const initialLayer =
    INITIAL_LAYERS.find((layer) => layer.id === requestedLayerId) ||
    INITIAL_LAYERS[0];

  // 3D 보기 / Skyview 모드 전환
  const [viewMode, setViewMode] = useState("3d");

  // 현재 선택된 레이어(공간)
  const [activeLayerId, setActiveLayerId] = useState(initialLayer.id);

  // 속성 패널 표시 여부 : 선택된 레이어를 한 번 더 누르면 닫힘
  const [propsOpen, setPropsOpen] = useState(true);

  // 속성 패널 입력값
  const [spaceName, setSpaceName] = useState(initialLayer.name);
  const [area, setArea] = useState("19.76 ㎡");
  const [ceilingHeight, setCeilingHeight] = useState("2.4 m");
  const [wallColor, setWallColor] = useState(WALL_COLORS[2]);

  // 레이어(공간) 클릭 : 같은 레이어를 다시 누르면 속성 패널을 닫고,
  //  다른 레이어를 누르면 그 레이어를 선택하며 속성 패널을 엶
  const handleSelectLayer = (layer) => {
    if (activeLayerId === layer.id && propsOpen) {
      setPropsOpen(false);
    } else {
      setActiveLayerId(layer.id);
      setSpaceName(layer.name);
      setPropsOpen(true);
    }
  };

  const handleAddFurniture = () => {
    alert("가구 추가 기능은 준비 중입니다.");
  };

  const handleCancel = () => {
    navigate("/member/mypage");
  };

  const handlePreview = () => {
    alert("미리보기 기능은 준비 중입니다.");
  };

  const handleSaveRoom = () => {
    alert("저장되었습니다. (추후 백엔드 연동 예정)");
  };

  return (
    <div className="ed2-root">
      {/* 상단 네비게이션 */}
      <div className="ed2-nav">
        <Link to="/" className="ed2-logo">
          <div className="ed2-logo-sq">
            <div className="ed2-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <div className="ed2-nav-center">{ROOM_NAME}</div>
        <div className="ed2-nav-right">
          <button className="ed2-nav-save-btn" onClick={handleSaveRoom}>
            저장
          </button>
        </div>
      </div>

      <div className="ed2-wrap">
        {/* 툴바 : 3D 보기 / Skyview 전환 */}
        <div className="ed2-toolbar">
          <div className="ed2-toolbar-group">
            <button
              className={`ed2-toolbar-btn${viewMode === "3d" ? " ed2-active" : ""}`}
              onClick={() => setViewMode("3d")}
            >
              3D 보기
            </button>
            <button
              className={`ed2-toolbar-btn ed2-sky${viewMode === "sky" ? " ed2-active" : ""}`}
              onClick={() => setViewMode("sky")}
            >
              Skyview
            </button>
          </div>
          <span className="ed2-toolbar-status">
            {ROOM_NAME.split(" ").slice(0, 2).join(" ")} · 자동저장됨
          </span>
        </div>

        {/* 본문 : 레이어 패널 + 3D 캔버스 + 속성 패널 */}
        <div className="ed2-main">
          {/* 좌측 레이어/가구 패널 */}
          <div className="ed2-layers-panel">
            <div className="ed2-layers-scroll">
              <div className="ed2-panel-heading">레이어</div>
              {INITIAL_LAYERS.map((layer) => (
                <button
                  key={layer.id}
                  className={`ed2-layer-item${activeLayerId === layer.id && propsOpen ? " ed2-active" : ""}`}
                  onClick={() => handleSelectLayer(layer)}
                >
                  <div
                    className="ed2-layer-dot"
                    style={{ background: layer.color }}
                  ></div>
                  <span className="ed2-layer-name">{layer.name}</span>
                </button>
              ))}

              <div className="ed2-separator"></div>

              <div className="ed2-panel-heading">가구</div>
              {FURNITURE.map((item) => (
                <div key={item.id} className="ed2-layer-item">
                  <div
                    className="ed2-layer-dot"
                    style={{ background: "#666" }}
                  ></div>
                  <span className="ed2-layer-name">{item.name}</span>
                </div>
              ))}
            </div>
            <div className="ed2-layer-btns">
              <button className="ed2-btn-add" onClick={handleAddFurniture}>
                ＋ 가구 추가하기
              </button>
            </div>
          </div>

          {/* 3D / Skyview 캔버스 영역 : 추후 Three.js 렌더러로 교체될 자리. 지금은 시안(찐찐찐찐.html ⑦ 에디터 상세)과
                        동일한 모습을 레이어 선택에 반응하도록 구현해둠 */}
          <div className="ed2-canvas" id="editor-detail-canvas-mount">
            {viewMode === "3d" ? (
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  background: "linear-gradient(160deg,#2A2520,#1A1612)",
                }}
              >
                <div
                  style={{
                    position: "absolute",
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: "45%",
                    background: "#2E2720",
                    clipPath: "polygon(0 30%,100% 5%,100% 100%,0 100%)",
                  }}
                ></div>
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    right: 0,
                    width: "52%",
                    height: "58%",
                    background: "#272220",
                  }}
                ></div>
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    width: "50%",
                    height: "62%",
                    background: "#2E2822",
                    clipPath: "polygon(0 0,100% 22%,100% 100%,0 100%)",
                  }}
                ></div>
                <div
                  style={{
                    position: "absolute",
                    top: "6%",
                    left: "35%",
                    width: 100,
                    height: 60,
                    background:
                      "radial-gradient(ellipse,rgba(196,149,106,.2),transparent 70%)",
                    borderRadius: "50%",
                  }}
                ></div>
                <div
                  style={{
                    position: "absolute",
                    bottom: "28%",
                    left: "14%",
                    width: "48%",
                  }}
                >
                  <div
                    style={{
                      height: 22,
                      background: "#7A6045",
                      borderRadius: "3px 3px 1px 1px",
                      position: "relative",
                    }}
                  >
                    <div
                      style={{
                        position: "absolute",
                        top: "-65%",
                        left: 0,
                        right: 0,
                        height: "68%",
                        background: "#8C7050",
                        borderRadius: 3,
                      }}
                    ></div>
                    <div
                      style={{
                        display: "flex",
                        gap: 5,
                        position: "absolute",
                        top: "-48%",
                        left: "4%",
                        right: "4%",
                      }}
                    >
                      <div
                        style={{
                          flex: 1,
                          height: 11,
                          background: "#C4956A",
                          borderRadius: 2,
                          opacity: 0.6,
                        }}
                      ></div>
                      <div
                        style={{
                          flex: 1,
                          height: 11,
                          background: "#C4956A",
                          borderRadius: 2,
                          opacity: 0.6,
                        }}
                      ></div>
                    </div>
                  </div>
                </div>
                <div
                  style={{
                    position: "absolute",
                    bottom: "13%",
                    left: "22%",
                    width: "52%",
                    height: "11%",
                    background: "#3A3028",
                    borderRadius: 2,
                    opacity: 0.7,
                  }}
                ></div>
                <div
                  style={{
                    position: "absolute",
                    top: 10,
                    left: 10,
                    background: "rgba(0,0,0,.32)",
                    backdropFilter: "blur(6px)",
                    border: "1px solid rgba(255,255,255,.06)",
                    borderRadius: 6,
                    padding: "4px 9px",
                    fontSize: 9,
                    color: "rgba(255,255,255,.7)",
                  }}
                >
                  3D 보기 모드
                </div>
                <div
                  style={{
                    position: "absolute",
                    top: 10,
                    right: 10,
                    background: "rgba(196,149,106,.2)",
                    border: "1px solid rgba(196,149,106,.35)",
                    borderRadius: 6,
                    padding: "4px 9px",
                    fontSize: 9,
                    color: "#C4956A",
                    fontWeight: 600,
                  }}
                >
                  실시간
                </div>
              </div>
            ) : (
              <div style={{ position: "absolute", inset: 0 }}>
                {INITIAL_LAYERS.map((layer) => {
                  const zone = SKY_ZONES[layer.id];
                  const isActive = activeLayerId === layer.id && propsOpen;
                  return (
                    <button
                      key={layer.id}
                      onClick={() => handleSelectLayer(layer)}
                      style={{
                        position: "absolute",
                        left: zone.left,
                        top: zone.top,
                        width: zone.width,
                        height: zone.height,
                        border: `${isActive ? 2.5 : 1.5}px solid ${zone.border}`,
                        background: zone.bg,
                        borderRadius: 2,
                        cursor: "pointer",
                        padding: 0,
                      }}
                    >
                      <span
                        style={{
                          position: "absolute",
                          left: 8,
                          top: 6,
                          fontSize: zone.fontSize,
                          fontWeight: zone.fontWeight,
                          color: zone.labelColor,
                        }}
                      >
                        {zone.label}
                      </span>
                    </button>
                  );
                })}
                <div
                  style={{
                    position: "absolute",
                    top: 10,
                    left: 10,
                    background: "rgba(100,140,200,.18)",
                    border: "1px solid rgba(100,140,200,.3)",
                    borderRadius: 6,
                    padding: "4px 9px",
                    fontSize: 9,
                    color: "#7EB0F0",
                    fontWeight: 600,
                  }}
                >
                  ☁ Skyview 모드
                </div>
                <div
                  style={{
                    position: "absolute",
                    bottom: "8%",
                    left: "50%",
                    transform: "translateX(-50%)",
                    background: "rgba(17,24,39,.8)",
                    borderRadius: 6,
                    padding: "4px 11px",
                    fontSize: 9,
                    color: "#fff",
                    whiteSpace: "nowrap",
                  }}
                >
                  {spaceName} 선택됨 — 드래그하여 이동
                </div>
              </div>
            )}
          </div>

          {/* 우측 속성 패널 : 선택된 레이어를 다시 누르면 닫힘 */}
          {propsOpen && (
            <div className="ed2-props-panel">
              <div className="ed2-props-heading">속성</div>
              <div className="ed2-props-row">
                <div className="ed2-props-label">공간 이름</div>
                <input
                  className="ed2-props-input"
                  value={spaceName}
                  onChange={(e) => setSpaceName(e.target.value)}
                />
              </div>
              <div className="ed2-props-row">
                <div className="ed2-props-label">면적</div>
                <input
                  className="ed2-props-input"
                  value={area}
                  onChange={(e) => setArea(e.target.value)}
                />
              </div>
              <div className="ed2-props-row">
                <div className="ed2-props-label">층고</div>
                <input
                  className="ed2-props-input"
                  value={ceilingHeight}
                  onChange={(e) => setCeilingHeight(e.target.value)}
                />
              </div>
              <div className="ed2-props-row">
                <div className="ed2-props-label">벽 색상</div>
                <div className="ed2-props-swatches">
                  {WALL_COLORS.map((color) => (
                    <button
                      key={color}
                      className={`ed2-swatch${wallColor === color ? " ed2-swatch-active" : ""}`}
                      style={{ background: color }}
                      onClick={() => setWallColor(color)}
                    ></button>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>

        {/* 하단 액션바 */}
        <div className="ed2-footer">
          <button
            className="ed2-footer-btn ed2-footer-cancel"
            onClick={handleCancel}
          >
            취소하기
          </button>
          <button
            className="ed2-footer-btn ed2-footer-preview"
            onClick={handlePreview}
          >
            미리보기
          </button>
          <button
            className="ed2-footer-btn ed2-footer-save"
            onClick={handleSaveRoom}
          >
            저장하기
          </button>
        </div>
      </div>
    </div>
  );
}

export default ThreeDEditorDetail;
