import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../styles/3deditor.css";

const ROOM_NAME = "우리집 거실 리모델링";
const TEAM_LABEL = "1조";

// 레이어(공간) 목록
const INITIAL_LAYERS = [
  { id: "living", name: "거실", color: "#C4956A" },
  { id: "kitchen", name: "주방", color: "#D4A96A" },
  { id: "bedroom", name: "침실", color: "#7B9EC2" },
];

// 가구 카테고리 필터 목록 (이케아 3D 플래너 참고, 지금은 실제 가구 데이터가 없어 형식만 구현)
const CATEGORY_FILTERS = ["침대", "옷장/시스템행거", "서랍장"];

// 벽 색상 스와치 목록 (하단 뷰 툴바의 "벽 색깔 바꾸기"에서 사용)
const WALL_COLORS = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"];

function ThreeDEditor() {
  const navigate = useNavigate();

  // 현재 선택된 레이어(공간) : 가구 카탈로그 패널 상단의 룸 이름으로 표시됨
  const [activeLayerId, setActiveLayerId] = useState(INITIAL_LAYERS[0].id);
  const activeLayer =
    INITIAL_LAYERS.find((layer) => layer.id === activeLayerId) ??
    INITIAL_LAYERS[0];

  // 룸 선택 드롭다운 열림 여부
  const [roomDropdownOpen, setRoomDropdownOpen] = useState(false);

  // 가구 카테고리 필터 (실제 가구 데이터가 없어 선택만 가능, 목록은 비어있음)
  const [activeCategory, setActiveCategory] = useState(null);

  // 가격 안내 배너 표시 여부
  const [priceBannerVisible, setPriceBannerVisible] = useState(true);

  // 캔버스 하단 뷰 툴바 상태 (IKEA 3D 플래너 참고 : Skyview / 벽 색깔 바꾸기 / 측정 옵션 표시)
  const [isSkyview, setIsSkyview] = useState(false);
  const [wallColor, setWallColor] = useState(null);
  const [wallColorPickerOpen, setWallColorPickerOpen] = useState(false);
  const [showMeasurements, setShowMeasurements] = useState(false);

  const toggleRoomDropdown = () => setRoomDropdownOpen((prev) => !prev);

  const selectRoom = (layer) => {
    setActiveLayerId(layer.id);
    setRoomDropdownOpen(false);
  };

  const selectCategory = (category) => {
    setActiveCategory((prev) => (prev === category ? null : category));
  };

  const toggleSkyview = () => {
    setIsSkyview((prev) => !prev);
    setWallColorPickerOpen(false);
  };

  const toggleWallColorPicker = () => {
    setWallColorPickerOpen((prev) => !prev);
  };

  const handleSelectWallColor = (color) => {
    setWallColor(color);
    setWallColorPickerOpen(false);
  };

  const toggleMeasurements = () => {
    setShowMeasurements((prev) => !prev);
    setWallColorPickerOpen(false);
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
    <div className="ed-root">
      {/* 상단 네비게이션 */}
      <div className="ed-nav">
        <Link to="/" className="ed-logo">
          <div className="ed-logo-sq">
            <div className="ed-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <div className="ed-nav-center">{ROOM_NAME}</div>
      </div>

      <div className="ed-wrap">
        {/* 툴바 */}
        <div className="ed-toolbar">
          <button className="ed-toolbar-btn ed-proj">{TEAM_LABEL}</button>
        </div>

        {/* 본문 : 레이어 패널 + 3D 캔버스 */}
        <div className="ed-main">
          {/* 좌측 가구 카탈로그 패널 (이케아 3D 플래너 참고) : 지금은 가구 데이터가 없어 형식만 구현 */}
          <div className="ed-layers-panel">
            {/* 룸 선택 드롭다운 : 현재 룸 이름이 표시됨 */}
            <div
              className={`ed-cat-header${roomDropdownOpen ? " ed-cat-open" : ""}`}
              onClick={toggleRoomDropdown}
            >
              <span className="ed-cat-room-name">{activeLayer.name}</span>
              <svg
                viewBox="0 0 24 24"
                width="16"
                height="16"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M6 9l6 6 6-6" />
              </svg>

              {roomDropdownOpen && (
                <div
                  className="ed-cat-room-dropdown"
                  onClick={(e) => e.stopPropagation()}
                >
                  {INITIAL_LAYERS.map((layer) => (
                    <button
                      key={layer.id}
                      className={`ed-cat-room-option${layer.id === activeLayerId ? " ed-active" : ""}`}
                      onClick={() => selectRoom(layer)}
                    >
                      {layer.name}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* 가구 카테고리 필터 */}
            <div className="ed-cat-filters">
              {CATEGORY_FILTERS.map((category) => (
                <button
                  key={category}
                  className={`ed-cat-filter${activeCategory === category ? " ed-active" : ""}`}
                  onClick={() => selectCategory(category)}
                >
                  {category}
                </button>
              ))}
              <button className="ed-cat-filter ed-cat-filter-more">
                모든 카테고리
                <svg
                  viewBox="0 0 24 24"
                  width="13"
                  height="13"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M6 9l6 6 6-6" />
                </svg>
              </button>
            </div>

            {/* 가구 상품 목록 : 실제 데이터 연동 전이라 비워둠 */}
            <div className="ed-cat-products"></div>

            {/* 가격 안내 배너 */}
            {priceBannerVisible && (
              <div className="ed-cat-banner">
                <span className="ed-cat-banner-icon">ⓘ</span>
                <div className="ed-cat-banner-text">
                  <div>최종 가격은 다를 수 있습니다.</div>
                  <div>결제 시 가격 세부 정보를 확인하세요.</div>
                </div>
                <button
                  className="ed-cat-banner-close"
                  onClick={() => setPriceBannerVisible(false)}
                >
                  ✕
                </button>
              </div>
            )}
          </div>

          {/* 3D 캔버스 영역 : 추후 Three.js 렌더러가 이 자리에 마운트될 예정이라 지금은 비워둠.
              벽 색깔을 고르면 미리보기로 배경색만 바뀜 */}
          <div
            className="ed-canvas"
            id="editor-canvas-mount"
            style={wallColor ? { background: wallColor } : undefined}
          >
            <div className="ed-canvas-placeholder"></div>

            {isSkyview && (
              <div className="ed-canvas-badge ed-canvas-badge-sky">
                ☁ Skyview 모드
              </div>
            )}

            {showMeasurements && (
              <div className="ed-canvas-badge ed-canvas-badge-measure">
                📏 측정 모드 · 가로 3.2m × 세로 4.1m
              </div>
            )}

            {/* 하단 뷰 툴바 (IKEA 3D 플래너 참고) : Skyview / 벽 색깔 바꾸기 / 측정 옵션 표시 */}
            <div className="ed-viewbar">
              <button
                className={`ed-viewbar-btn${isSkyview ? " ed-viewbar-active" : ""}`}
                onClick={toggleSkyview}
              >
                <svg
                  viewBox="0 0 24 24"
                  width="16"
                  height="16"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinejoin="round"
                >
                  <path d="M12 3l9 5-9 5-9-5 9-5z" />
                  <path d="M3 8v8l9 5 9-5V8" />
                </svg>
                Skyview
              </button>

              <div className="ed-viewbar-divider"></div>

              <div className="ed-viewbar-icon-wrap">
                <button
                  className={`ed-viewbar-icon-btn${wallColorPickerOpen ? " ed-viewbar-active" : ""}`}
                  onClick={toggleWallColorPicker}
                  aria-label="벽 색깔 바꾸기"
                  title="벽 색깔 바꾸기"
                >
                  <svg
                    viewBox="0 0 24 24"
                    width="18"
                    height="18"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.8"
                  >
                    <rect x="3" y="3" width="18" height="18" rx="4" />
                    <path
                      d="M3 12a9 9 0 0 1 9-9v18a9 9 0 0 1-9-9z"
                      fill="currentColor"
                      opacity=".3"
                      stroke="none"
                    />
                  </svg>
                </button>

                {wallColorPickerOpen && (
                  <div className="ed-wallcolor-popover">
                    {WALL_COLORS.map((color) => (
                      <button
                        key={color}
                        className={`ed-wallcolor-swatch${wallColor === color ? " ed-wallcolor-swatch-active" : ""}`}
                        style={{ background: color }}
                        onClick={() => handleSelectWallColor(color)}
                        aria-label={`벽 색상 ${color}`}
                      ></button>
                    ))}
                  </div>
                )}
              </div>

              <button
                className={`ed-viewbar-icon-btn${showMeasurements ? " ed-viewbar-active" : ""}`}
                onClick={toggleMeasurements}
                aria-label="측정 옵션 표시"
                title="측정 옵션 표시"
              >
                <svg
                  viewBox="0 0 24 24"
                  width="18"
                  height="18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <rect
                    x="2.5"
                    y="8.5"
                    width="19"
                    height="7"
                    rx="1.5"
                    transform="rotate(-15 12 12)"
                  />
                  <path
                    d="M6 9l1 2M9 8l1 2M12 7l1 2M15 6l1 2M18 5l1 2"
                    transform="rotate(-15 12 12)"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>

        {/* 하단 액션바 */}
        <div className="ed-footer">
          <button
            className="ed-footer-btn ed-footer-cancel"
            onClick={handleCancel}
          >
            취소하기
          </button>
          <button
            className="ed-footer-btn ed-footer-preview"
            onClick={handlePreview}
          >
            미리보기
          </button>
          <button
            className="ed-footer-btn ed-footer-save"
            onClick={handleSaveRoom}
          >
            저장하기
          </button>
        </div>
      </div>
    </div>
  );
}

export default ThreeDEditor;
