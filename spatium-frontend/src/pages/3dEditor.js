import React, { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import "../styles/3deditor.css";
import TestThreeStagingPage from "./testThree/TestThreeStagingPage";
import { getAccessToken } from "../utils/authSession";

const ROOM_NAME = "우리집 거실 리모델링";
const TEAM_LABEL = "1조";
const FURNITURE_CATALOG_URL = "/data/furniture_catalog.json";

const INITIAL_LAYERS = [
  { id: "living", name: "거실", color: "#C4956A" },
  { id: "kitchen", name: "주방", color: "#D4A96A" },
  { id: "bedroom", name: "침실", color: "#7B9EC2" },
];

const WALL_COLORS = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"];

function normalizeCatalogItem(item) {
  return {
    ...item,
    path: item.path || item.modelUrl || null,
    modelUrl: item.modelUrl || item.path || null,
  };
}

function ThreeDEditor() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const editorRef = useRef(null);
  const [activeLayerId, setActiveLayerId] = useState(INITIAL_LAYERS[0].id);
  const [roomDropdownOpen, setRoomDropdownOpen] = useState(false);
  const [furnitureCatalog, setFurnitureCatalog] = useState([]);
  const [activeCategory, setActiveCategory] = useState(null);
  const [priceBannerVisible, setPriceBannerVisible] = useState(true);
  const [isSkyview, setIsSkyview] = useState(false);
  const [wallColor, setWallColor] = useState(null);
  const [wallColorPickerOpen, setWallColorPickerOpen] = useState(false);
  const [showMeasurements, setShowMeasurements] = useState(false);

  const activeLayer =
    INITIAL_LAYERS.find((layer) => layer.id === activeLayerId) ??
    INITIAL_LAYERS[0];
  const categoryFilters = Array.from(
    new Set(furnitureCatalog.map((item) => item.group).filter(Boolean)),
  );
  const visibleCatalogItems = activeCategory
    ? furnitureCatalog.filter((item) => item.group === activeCategory)
    : furnitureCatalog;

  useEffect(() => {
    let isMounted = true;

    fetch(FURNITURE_CATALOG_URL, { cache: "no-store" })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Failed to load furniture catalog (${response.status})`);
        }
        return response.json();
      })
      .then((data) => {
        if (isMounted) {
          setFurnitureCatalog((Array.isArray(data) ? data : []).map(normalizeCatalogItem));
        }
      })
      .catch((error) => {
        console.error("Failed to load furniture catalog", error);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  const toggleRoomDropdown = () => setRoomDropdownOpen((prev) => !prev);

  const selectRoom = (layer) => {
    setActiveLayerId(layer.id);
    setRoomDropdownOpen(false);
  };

  const selectCategory = (category) => {
    setActiveCategory((prev) => (prev === category ? null : category));
  };

  const showAllCategories = () => {
    setActiveCategory(null);
  };

  const handleAddFurniture = async (item) => {
    await editorRef.current?.addFurniture(item);
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

  const handleSaveRoom = async () => {
    const accessToken = getAccessToken();
    const projectId = searchParams.get("projectId");
    const roomId = searchParams.get("roomId");

    if (!projectId || !roomId) {
      alert("저장할 프로젝트/룸 정보를 찾을 수 없습니다.");
      return;
    }

    if (!accessToken) {
      alert("로그인이 필요합니다.");
      return;
    }

    const saved = await editorRef.current?.saveEditedSceneJson({
      projectId,
      roomId,
    });

    if (saved) {
      alert("저장되었습니다.");
    }
  };

  return (
    <div className="ed-root">
      <div className="ed-nav">
        <Link to="/" className="ed-logo">
          <div className="ed-logo-sq">
            <div className="ed-logo-sq-i" />
          </div>
          SPATIUM
        </Link>
        <div className="ed-nav-center">{ROOM_NAME}</div>
      </div>

      <div className="ed-wrap">
        <div className="ed-toolbar">
          <button className="ed-toolbar-btn ed-proj" type="button">
            {TEAM_LABEL}
          </button>
        </div>

        <div className="ed-main">
          <div className="ed-layers-panel">
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
                  onClick={(event) => event.stopPropagation()}
                >
                  {INITIAL_LAYERS.map((layer) => (
                    <button
                      key={layer.id}
                      type="button"
                      className={`ed-cat-room-option${
                        layer.id === activeLayerId ? " ed-active" : ""
                      }`}
                      onClick={() => selectRoom(layer)}
                    >
                      {layer.name}
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="ed-cat-filters">
              {categoryFilters.map((category) => (
                <button
                  key={category}
                  type="button"
                  className={`ed-cat-filter${activeCategory === category ? " ed-active" : ""}`}
                  onClick={() => selectCategory(category)}
                >
                  {category}
                </button>
              ))}
              <button
                type="button"
                className={`ed-cat-filter ed-cat-filter-more${
                  activeCategory === null ? " ed-active" : ""
                }`}
                onClick={showAllCategories}
              >
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

            <div className="ed-cat-products">
              {visibleCatalogItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="ed-cat-product"
                  onClick={() => handleAddFurniture(item)}
                >
                  <span className="ed-cat-product-thumb" />
                  <span className="ed-cat-product-body">
                    <span className="ed-cat-product-name">{item.name}</span>
                    <span className="ed-cat-product-meta">{item.group}</span>
                  </span>
                </button>
              ))}
            </div>

            {priceBannerVisible && (
              <div className="ed-cat-banner">
                <span className="ed-cat-banner-icon">ⓘ</span>
                <div className="ed-cat-banner-text">
                  <div>최종 가격은 다를 수 있습니다.</div>
                  <div>결제 시 가격 세부 정보를 확인하세요.</div>
                </div>
                <button
                  type="button"
                  className="ed-cat-banner-close"
                  onClick={() => setPriceBannerVisible(false)}
                >
                  ✕
                </button>
              </div>
            )}
          </div>

          <div
            className="ed-canvas"
            id="editor-canvas-mount"
            style={wallColor ? { background: wallColor } : undefined}
          >
            <div className="ed-canvas-placeholder">
              <TestThreeStagingPage ref={editorRef} isSkyview={isSkyview} />
            </div>

            {isSkyview && (
              <div className="ed-canvas-badge ed-canvas-badge-sky">
                Skyview 모드
              </div>
            )}

            {showMeasurements && (
              <div className="ed-canvas-badge ed-canvas-badge-measure">
                측정 모드
              </div>
            )}

            <div className="ed-viewbar">
              <button
                type="button"
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

              <div className="ed-viewbar-divider" />

              <div className="ed-viewbar-icon-wrap">
                <button
                  type="button"
                  className={`ed-viewbar-icon-btn${
                    wallColorPickerOpen ? " ed-viewbar-active" : ""
                  }`}
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
                        type="button"
                        className={`ed-wallcolor-swatch${
                          wallColor === color ? " ed-wallcolor-swatch-active" : ""
                        }`}
                        style={{ background: color }}
                        onClick={() => handleSelectWallColor(color)}
                        aria-label={`벽 색상 ${color}`}
                      />
                    ))}
                  </div>
                )}
              </div>

              <button
                type="button"
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

        <div className="ed-footer">
          <button
            type="button"
            className="ed-footer-btn ed-footer-cancel"
            onClick={handleCancel}
          >
            취소하기
          </button>
          <button
            type="button"
            className="ed-footer-btn ed-footer-preview"
            onClick={handlePreview}
          >
            미리보기
          </button>
          <button
            type="button"
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
