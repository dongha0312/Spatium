import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import "../styles/3deditor.css";
import AccountPanel from "../components/AccountPanel";
import AvatarButton from "../components/AvatarButton";
import Logo from "../components/Logo";
import RoomSceneEditorPage from "./roomSceneEditor/RoomSceneEditorPage";
import { getAccessToken, getLoginSession } from "../utils/authSession";
import { getMyInfo } from "../springApi/MemberSpringBootApi";
import { getProjectInfo } from "../springApi/ProjectSpringBootAPi";
import { getRoomList, getRoomSceneData } from "../springApi/RoomSpringBootApi";
import {
  getFurnitureCatalog,
  getUserFurnitureCatalog,
} from "../springApi/FurnitureSpringBootApi";
import useLogout from "../hooks/useLogout";
import useProjectStats from "../hooks/useProjectStats";
import { FLOOR_COLORS } from "./roomSceneEditor/scene/floorColor";

const WALL_COLORS = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"];

// 카테고리 필터에서 "사용자 가구"를 구분하기 위한 값. 실제 가구 group과 겹치지 않게 한다.
const USER_FURNITURE_CATEGORY = "__userFurniture__";

function normalizeCatalogItem(item) {
  return {
    ...item,
    path: item.path || item.modelUrl || null,
    modelUrl: item.modelUrl || item.path || null,
  };
}

function shortId(value, fallback) {
  if (!value) return fallback;
  return String(value).slice(0, 8);
}

function ThreeDEditor() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const editorRef = useRef(null);
  const editorUrlRef = useRef(window.location.href);
  const projectId = searchParams.get("projectId");
  const roomId = searchParams.get("roomId");

  const [roomDropdownOpen, setRoomDropdownOpen] = useState(false);
  const [furnitureCatalog, setFurnitureCatalog] = useState([]);
  const [userFurnitureCatalog, setUserFurnitureCatalog] = useState([]);
  const [catalogSearch, setCatalogSearch] = useState("");
  const [activeCategory, setActiveCategory] = useState(null);
  const [catalogError, setCatalogError] = useState("");
  const [isSkyview, setIsSkyview] = useState(false);
  const [wallColor, setWallColor] = useState(null);
  const [wallColorPickerOpen, setWallColorPickerOpen] = useState(false);
  const [floorColor, setFloorColor] = useState(null);
  const [floorColorPickerOpen, setFloorColorPickerOpen] = useState(false);
  const [showMeasurements, setShowMeasurements] = useState(false);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState("");
  const [saveError, setSaveError] = useState("");
  const [projectLabel, setProjectLabel] = useState(
    shortId(projectId, "Project"),
  );
  const [roomLabel, setRoomLabel] = useState(shortId(roomId, "Room editor"));
  const [roomScene, setRoomScene] = useState(null);
  const [roomSceneLoading, setRoomSceneLoading] = useState(Boolean(roomId));
  const [roomSceneError, setRoomSceneError] = useState("");
  const [projectRooms, setProjectRooms] = useState([]);
  const [projectRoomsLoading, setProjectRoomsLoading] = useState(
    Boolean(projectId),
  );
  const [projectRoomsError, setProjectRoomsError] = useState("");
  const [manualOpen, setManualOpen] = useState(false);
  const [pendingCatalogItem, setPendingCatalogItem] = useState(null);
  const [sizeDraftCm, setSizeDraftCm] = useState({
    width: 0,
    depth: 0,
    height: 0,
  });

  const [session, setSession] = useState(() => getLoginSession());

  // 닉네임 클릭 시 열리는 "내 정보" 우측 패널
  const [panelOpen, setPanelOpen] = useState(false);

  // 패널 이용현황에 표시할 통계 (프로젝트 수 / 룸 수)
  const accountStats = useProjectStats(Boolean(session));

  // 상단바/패널 아바타에 표시할 프로필 사진 (없으면 이니셜)
  const [profileImage, setProfileImage] = useState(null);

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

  const openEditorManual = () => {
    setManualOpen(true);
    setPanelOpen(false);
  };

  const closeEditorManual = () => {
    setManualOpen(false);
  };

  // 마이페이지 버튼 : 대시보드로 이동
  const handleGoMypage = () => navigate("/member/mypage");

  // 계정설정 이동 (패널 닫고 이동)
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  // 로그아웃 : 서버 세션 정리 후 로컬 세션 삭제, 상단바를 로그인 상태에서 되돌림
  const handleLogout = useLogout(() => {
    setSession(null);
    setPanelOpen(false);
    navigate("/");
  });

  // 기본 카탈로그 + 사용자 가구를 합친 목록. 검색/카테고리 필터는 이 목록을 대상으로 한다.
  const mergedCatalog = useMemo(
    () => [...furnitureCatalog, ...userFurnitureCatalog],
    [furnitureCatalog, userFurnitureCatalog],
  );

  const categoryFilters = useMemo(
    () =>
      Array.from(
        new Set(mergedCatalog.map((item) => item.group).filter(Boolean)),
      ),
    [mergedCatalog],
  );

  const visibleCatalogItems = useMemo(() => {
    const query = catalogSearch.trim().toLowerCase();

    return mergedCatalog.filter((item) => {
      const matchesCategory =
        activeCategory === USER_FURNITURE_CATEGORY
          ? Boolean(item.isUserFurniture)
          : activeCategory
            ? item.group === activeCategory
            : true;
      const haystack = [item.name, item.group, item.category]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      const matchesSearch = query ? haystack.includes(query) : true;

      return matchesCategory && matchesSearch;
    });
  }, [activeCategory, catalogSearch, mergedCatalog]);

  useEffect(() => {
    let isMounted = true;

    getFurnitureCatalog()
      .then((data) => {
        if (isMounted) {
          setFurnitureCatalog(
            (Array.isArray(data) ? data : []).map(normalizeCatalogItem),
          );
          setCatalogError("");
        }
      })
      .catch((error) => {
        if (isMounted) {
          setCatalogError(
            error.message || "카탈로그 정보를 불러오는데 실패했습니다",
          );
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

  // 로그인 상태면 내가 만든 사용자 가구 목록도 불러온다.
  useEffect(() => {
    if (!session) {
      setUserFurnitureCatalog([]);
      return undefined;
    }

    let isMounted = true;

    getUserFurnitureCatalog()
      .then((data) => {
        if (!isMounted) return;
        setUserFurnitureCatalog(
          (Array.isArray(data) ? data : []).map((item) => ({
            ...normalizeCatalogItem(item),
            isUserFurniture: true,
          })),
        );
      })
      .catch((error) => {
        console.warn("사용자 가구 목록 조회 실패:", error);
        if (isMounted) setUserFurnitureCatalog([]);
      });

    return () => {
      isMounted = false;
    };
  }, [session]);

  useEffect(() => {
    let isMounted = true;

    if (projectId) {
      getProjectInfo(projectId)
        .then((data) => {
          if (isMounted && data?.projectName) {
            setProjectLabel(data.projectName);
          }
        })
        .catch(() => {
          if (isMounted) setProjectLabel(shortId(projectId, "Project"));
        });
    }

    if (roomId) {
      setRoomScene(null);
      setRoomSceneError("");
      setRoomSceneLoading(true);

      getRoomSceneData(roomId)
        .then((data) => {
          if (!isMounted) return;
          setRoomScene(data);
          if (isMounted && data?.roomName) {
            setRoomLabel(data.roomName);
          }
        })
        .catch((error) => {
          if (!isMounted) return;
          setRoomScene(null);
          setRoomSceneError(
            error.message || "방 데이터를 불러오는데 실패했습니다",
          );
          setRoomLabel(shortId(roomId, "Room editor"));
        })
        .finally(() => {
          if (isMounted) setRoomSceneLoading(false);
        });
    } else {
      setRoomScene(null);
      setRoomSceneError("");
      setRoomSceneLoading(false);
    }

    return () => {
      isMounted = false;
    };
  }, [projectId, roomId]);

  useEffect(() => {
    let isMounted = true;

    if (!projectId) {
      setProjectRooms([]);
      setProjectRoomsError("");
      setProjectRoomsLoading(false);
      return () => {
        isMounted = false;
      };
    }

    setProjectRoomsLoading(true);
    setProjectRoomsError("");

    getRoomList(projectId)
      .then((data) => {
        if (!isMounted) return;
        setProjectRooms(Array.isArray(data?.items) ? data.items : []);
      })
      .catch((error) => {
        if (!isMounted) return;
        setProjectRooms([]);
        setProjectRoomsError(error.message || "방 정보 불러오기 실패");
      })
      .finally(() => {
        if (isMounted) setProjectRoomsLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [projectId]);

  useEffect(() => {
    if (!hasUnsavedChanges) return undefined;

    const handleBeforeUnload = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };

    const handlePopState = () => {
      const confirmed = window.confirm(
        "수정중인 방인 저장되지 않았습니다. 그래도 떠나시겠습니까?",
      );

      if (confirmed) {
        setHasUnsavedChanges(false);
        return;
      }

      window.history.pushState(null, "", editorUrlRef.current);
    };

    window.history.pushState(null, "", editorUrlRef.current);
    window.addEventListener("beforeunload", handleBeforeUnload);
    window.addEventListener("popstate", handlePopState);

    return () => {
      window.removeEventListener("beforeunload", handleBeforeUnload);
      window.removeEventListener("popstate", handlePopState);
    };
  }, [hasUnsavedChanges]);

  useEffect(() => {
    if (!manualOpen) return undefined;

    const handleKeyDown = (event) => {
      if (event.key === "Escape") {
        setManualOpen(false);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [manualOpen]);

  const handleSceneChanged = useCallback(() => {
    setHasUnsavedChanges(true);
    setSaveMessage("");
    setSaveError("");
  }, []);

  const toggleRoomDropdown = () => setRoomDropdownOpen((prev) => !prev);

  const selectProjectRoom = (room) => {
    const nextRoomId = room?.roomId;
    if (!projectId || !nextRoomId || String(nextRoomId) === String(roomId)) {
      setRoomDropdownOpen(false);
      return;
    }

    if (hasUnsavedChanges) {
      const confirmed = window.confirm(
        "수정중인 방이 저장되지 않았습니다. 그래도 새로운 방을 불러오시겠습니까?",
      );
      if (!confirmed) return;
    }

    const params = new URLSearchParams({
      projectId: String(projectId),
      roomId: String(nextRoomId),
    });

    setRoomDropdownOpen(false);
    setHasUnsavedChanges(false);
    navigate(`/member/editor?${params.toString()}`);
  };

  const selectCategory = (category) => {
    setActiveCategory((prev) => (prev === category ? null : category));
  };

  const showAllCategories = () => {
    setActiveCategory(null);
  };

  const handleAddFurniture = (item) => {
    if (editorRef.current?.isReplacingSelected) {
      editorRef.current?.addFurniture(item);
      return;
    }

    const dims = item.dimensions || {};
    setPendingCatalogItem(item);
    setSizeDraftCm({
      width: Math.round((dims.x || 0.8) * 100),
      depth: Math.round((dims.z || 0.8) * 100),
      height: Math.round((dims.y || 0.8) * 100),
    });
  };

  const closeSizeModal = () => {
    setPendingCatalogItem(null);
  };

  const handleSizeFieldChange = (field) => (event) => {
    const { value } = event.target;
    setSizeDraftCm((prev) => ({ ...prev, [field]: value }));
  };

  const handleConfirmAddFurniture = async () => {
    if (!pendingCatalogItem) return;

    const originalDims = pendingCatalogItem.dimensions || {};
    const toMeters = (cm, fallback) => {
      const value = Number(cm);
      return Number.isFinite(value) && value > 0 ? value / 100 : fallback;
    };
    const customDimensions = {
      x: toMeters(sizeDraftCm.width, originalDims.x || 0.8),
      y: toMeters(sizeDraftCm.height, originalDims.y || 0.8),
      z: toMeters(sizeDraftCm.depth, originalDims.z || 0.8),
    };

    await editorRef.current?.addFurniture(pendingCatalogItem, customDimensions);
    setPendingCatalogItem(null);
  };

  const toggleSkyview = () => {
    setIsSkyview((prev) => !prev);
    setWallColorPickerOpen(false);
    setFloorColorPickerOpen(false);
  };

  const toggleWallColorPicker = () => {
    setWallColorPickerOpen((prev) => !prev);
    setFloorColorPickerOpen(false);
  };

  const handleSelectWallColor = (color) => {
    setWallColor(color);
    setWallColorPickerOpen(false);
  };

  const toggleFloorColorPicker = () => {
    setFloorColorPickerOpen((prev) => !prev);
    setWallColorPickerOpen(false);
  };

  const handleSelectFloorColor = (color) => {
    setFloorColor(color);
    setFloorColorPickerOpen(false);
    handleSceneChanged();
  };

  const toggleMeasurements = () => {
    setShowMeasurements((prev) => !prev);
    setWallColorPickerOpen(false);
    setFloorColorPickerOpen(false);
  };

  const handleCancel = () => {
    if (hasUnsavedChanges) {
      const confirmed = window.confirm(
        "수정중인 방이 저장되지 않았습니다. 그래도 떠나시겠습니까?",
      );
      if (!confirmed) return;
    }

    navigate("/member/mypage");
  };

  const handleSaveRoom = async () => {
    const accessToken = getAccessToken();

    setSaveMessage("");
    setSaveError("");

    if (!projectId || !roomId) {
      setSaveError("프로젝트나 방 정보를 찾을 수 없습니다");
      return;
    }

    if (!accessToken) {
      setSaveError("저장하시려면 로그인해주세요");
      return;
    }

    setIsSaving(true);

    try {
      const saved = await editorRef.current?.saveEditedSceneJson({
        projectId,
        roomId,
      });

      if (!saved) {
        setSaveError("저장실패. 메시지를 확인후 다시 시도해주세요");
        return;
      }

      setHasUnsavedChanges(false);
      setSaveMessage("저장됨");
      window.setTimeout(() => setSaveMessage(""), 1800);
    } catch (error) {
      setSaveError(error.message || "저장 실패");
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="ed-root">
      <div className="ed-nav">
        <Logo prefix="ed" />
        <div className="ed-nav-center">{roomLabel}</div>
        <div className="ed-nav-status">
          {isSaving && <span className="ed-save-state">저장중...</span>}
          {!isSaving && saveMessage && (
            <span className="ed-save-state ed-save-ok">{saveMessage}</span>
          )}
          {!isSaving && saveError && (
            <span className="ed-save-state ed-save-error">{saveError}</span>
          )}
          {!isSaving && hasUnsavedChanges && !saveMessage && !saveError && (
            <span className="ed-save-state">저장되지 않은 변경사항</span>
          )}
        </div>
        <button
          type="button"
          className="ed-help-btn"
          onClick={openEditorManual}
          aria-label="Open 3D editor guide"
          title="3D editor guide"
        >
          ?
        </button>
        {session ? (
          <div className="ed-nav-account">
            {/* 닉네임 왼쪽 : 마이페이지로 바로 이동하는 외곽선 버튼 */}
            <button
              type="button"
              className="ed-mypage-btn"
              onClick={handleGoMypage}
            >
              마이페이지
            </button>
            {/* 닉네임 클릭 : 우측 "내 정보" 패널 열기 */}
            <AvatarButton
              prefix="ed"
              imageUrl={profileImage}
              initial={session.nickname.charAt(0).toUpperCase()}
              name={session.nickname}
              onClick={toggleAccountPanel}
              showCaret={false}
            />
          </div>
        ) : (
          <Link to="/member/mypage" className="ed-av-btn">
            <div className="ed-av-circ">S</div>
            <span className="ed-av-name">마이페이지</span>
          </Link>
        )}
      </div>

      <div className="ed-wrap">
        <div className="ed-toolbar">
          <button className="ed-toolbar-btn ed-proj" type="button">
            {projectLabel}
          </button>
        </div>

        <div className="ed-main">
          <div className="ed-layers-panel">
            <div
              className={`ed-cat-header${roomDropdownOpen ? " ed-cat-open" : ""}`}
              onClick={toggleRoomDropdown}
            >
              <span className="ed-cat-room-name">{roomLabel}</span>
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
                  {projectRoomsLoading ? (
                    <div className="ed-cat-empty">Loading rooms...</div>
                  ) : projectRoomsError ? (
                    <div className="ed-cat-empty">{projectRoomsError}</div>
                  ) : projectRooms.length === 0 ? (
                    <div className="ed-cat-empty">
                      이 프로젝트에 저장된 방이 없습니다
                    </div>
                  ) : (
                    projectRooms.map((room) => (
                      <button
                        key={room.roomId}
                        type="button"
                        className={`ed-cat-room-option${
                          String(room.roomId) === String(roomId)
                            ? " ed-active"
                            : ""
                        }`}
                        onClick={() => selectProjectRoom(room)}
                      >
                        {room.roomName || "Untitled room"}
                      </button>
                    ))
                  )}
                </div>
              )}
            </div>

            <div className="ed-cat-search-wrap">
              <input
                className="ed-cat-search"
                type="search"
                placeholder="가구 검색하기"
                value={catalogSearch}
                onChange={(event) => setCatalogSearch(event.target.value)}
              />
            </div>

            <div className="ed-cat-filters">
              <button
                type="button"
                className={`ed-cat-filter ed-cat-filter-more${
                  activeCategory === null ? " ed-active" : ""
                }`}
                onClick={showAllCategories}
              >
                All
              </button>
              {session && (
                <button
                  type="button"
                  className={`ed-cat-filter${
                    activeCategory === USER_FURNITURE_CATEGORY
                      ? " ed-active"
                      : ""
                  }`}
                  onClick={() => selectCategory(USER_FURNITURE_CATEGORY)}
                >
                  사용자 가구
                </button>
              )}
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
            </div>

            <div className="ed-cat-products">
              {catalogError && (
                <div className="ed-cat-empty">{catalogError}</div>
              )}
              {!catalogError && visibleCatalogItems.length === 0 && (
                <div className="ed-cat-empty">
                  {activeCategory === USER_FURNITURE_CATEGORY
                    ? "등록된 사용자 가구가 없습니다"
                    : "가구정보를 불러오지 못했습니다"}
                </div>
              )}
              {visibleCatalogItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="ed-cat-product"
                  onClick={() => handleAddFurniture(item)}
                >
                  <span className="ed-cat-product-body">
                    <span className="ed-cat-product-name">{item.name}</span>
                    <span className="ed-cat-product-meta">
                      {item.group || item.category}
                    </span>
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div
            className="ed-canvas"
            id="editor-canvas-mount"
            style={wallColor ? { background: wallColor } : undefined}
          >
            <div className="ed-canvas-placeholder">
              {roomSceneLoading ? (
                <div className="ed-cat-empty">방 정보 불러오는 중...</div>
              ) : roomSceneError ? (
                <div className="ed-cat-empty">{roomSceneError}</div>
              ) : (
                <RoomSceneEditorPage
                  ref={editorRef}
                  isSkyview={isSkyview}
                  showMeasurements={showMeasurements}
                  wallColor={wallColor}
                  floorColor={floorColor}
                  roomScene={roomScene}
                  onSceneChanged={handleSceneChanged}
                  onFloorColorLoaded={setFloorColor}
                />
              )}
            </div>

            {isSkyview && (
              <div className="ed-canvas-badge ed-canvas-badge-sky">Skyview</div>
            )}

            {showMeasurements && (
              <div className="ed-canvas-badge ed-canvas-badge-measure">
                측정모드 On
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
                  className={`ed-viewbar-btn${
                    wallColorPickerOpen ? " ed-viewbar-active" : ""
                  }`}
                  onClick={toggleWallColorPicker}
                  aria-label="벽 색상 변경"
                  title="벽 색상 변경"
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
                  벽 색상
                </button>

                {wallColorPickerOpen && (
                  <div className="ed-wallcolor-popover">
                    {WALL_COLORS.map((color) => (
                      <button
                        key={color}
                        type="button"
                        className={`ed-wallcolor-swatch${
                          wallColor === color
                            ? " ed-wallcolor-swatch-active"
                            : ""
                        }`}
                        style={{ background: color }}
                        onClick={() => handleSelectWallColor(color)}
                        aria-label={`Wall color ${color}`}
                      />
                    ))}
                  </div>
                )}
              </div>

              <div className="ed-viewbar-icon-wrap">
                <button
                  type="button"
                  className={`ed-viewbar-btn${
                    floorColorPickerOpen ? " ed-viewbar-active" : ""
                  }`}
                  onClick={toggleFloorColorPicker}
                  aria-label="바닥 색상 변경"
                >
                  <svg
                    viewBox="0 0 24 24"
                    width="18"
                    height="18"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.8"
                  >
                    <rect x="3" y="3" width="8" height="8" rx="1.2" />
                    <rect x="13" y="3" width="8" height="8" rx="1.2" />
                    <rect x="3" y="13" width="8" height="8" rx="1.2" />
                    <rect x="13" y="13" width="8" height="8" rx="1.2" />
                  </svg>
                  바닥 색상
                </button>

                {floorColorPickerOpen && (
                  <div className="ed-wallcolor-popover">
                    {FLOOR_COLORS.map((color) => (
                      <button
                        key={color}
                        type="button"
                        className={`ed-wallcolor-swatch${
                          floorColor === color
                            ? " ed-wallcolor-swatch-active"
                            : ""
                        }`}
                        style={{ background: color }}
                        onClick={() => handleSelectFloorColor(color)}
                        aria-label={`Floor color ${color}`}
                      />
                    ))}
                  </div>
                )}
              </div>

              <button
                type="button"
                className={`ed-viewbar-btn${showMeasurements ? " ed-viewbar-active" : ""}`}
                onClick={toggleMeasurements}
                aria-label="측정 모드"
                title="측정 모드"
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
                측정 모드
              </button>
            </div>
          </div>
        </div>

        <div className="ed-footer">
          <button
            type="button"
            className="ed-footer-btn ed-footer-cancel"
            onClick={handleCancel}
            disabled={isSaving}
          >
            마이페이지로 돌아가기
          </button>
          <button
            type="button"
            className="ed-footer-btn ed-footer-save"
            onClick={handleSaveRoom}
            disabled={isSaving}
          >
            {isSaving ? "저장중..." : "저장하기"}
          </button>
        </div>
      </div>

      {/* 닉네임 클릭 시 열리는 "내 정보" 우측 패널 */}
      <AccountPanel
        open={Boolean(session && panelOpen)}
        prefix="ed"
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

      {pendingCatalogItem && (
        <div className="ed-size-modal-backdrop" onClick={closeSizeModal}>
          <section
            className="ed-size-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="ed-size-modal-title"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="ed-size-modal-head">
              <h2 id="ed-size-modal-title">
                {pendingCatalogItem.name || "가구"} 크기 설정
              </h2>
              <button
                type="button"
                className="ed-size-modal-close"
                onClick={closeSizeModal}
                aria-label="닫기"
              >
                ×
              </button>
            </div>

            <div className="ed-size-modal-body">
              <label className="ed-size-modal-field">
                <span>가로 (cm)</span>
                <input
                  type="number"
                  min="1"
                  max="1000"
                  step="1"
                  value={sizeDraftCm.width}
                  onChange={handleSizeFieldChange("width")}
                />
              </label>
              <label className="ed-size-modal-field">
                <span>세로 (cm)</span>
                <input
                  type="number"
                  min="1"
                  max="1000"
                  step="1"
                  value={sizeDraftCm.depth}
                  onChange={handleSizeFieldChange("depth")}
                />
              </label>
              <label className="ed-size-modal-field">
                <span>높이 (cm)</span>
                <input
                  type="number"
                  min="1"
                  max="1000"
                  step="1"
                  value={sizeDraftCm.height}
                  onChange={handleSizeFieldChange("height")}
                />
              </label>
            </div>

            <div className="ed-size-modal-actions">
              <button
                type="button"
                className="ed-footer-btn ed-footer-cancel"
                onClick={closeSizeModal}
              >
                취소
              </button>
              <button
                type="button"
                className="ed-footer-btn ed-footer-save"
                onClick={handleConfirmAddFurniture}
              >
                추가
              </button>
            </div>
          </section>
        </div>
      )}

      {manualOpen && (
        <div className="ed-manual-backdrop" onClick={closeEditorManual}>
          <section
            className="ed-manual-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="ed-manual-title"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="ed-manual-head">
              <div>
                <div className="ed-manual-kicker">3D Editor Guide</div>
                <h2 id="ed-manual-title">3D 에디터 설명서</h2>
              </div>
              <button
                type="button"
                className="ed-manual-close"
                onClick={closeEditorManual}
                aria-label="Close editor guide"
              >
                ×
              </button>
            </div>

            <div className="ed-manual-body">
              <section className="ed-manual-section">
                <h3>기본 흐름</h3>
                <ol>
                  <li>
                    왼쪽 목록에서 가구를 클릭하면 가로/세로/높이를 입력하는 창이
                    뜹니다. 크기를 정하고 추가를 누르면 배치 모드가 시작되며,
                    바닥에서 원하는 위치를 클릭하면 그 자리에 놓입니다. ESC 또는
                    취소 버튼으로 배치를 취소할 수 있습니다.
                  </li>
                  <li>
                    배치된 가구를 클릭한 뒤 드래그해서 바닥 위 위치를 다시
                    조정할 수 있습니다.
                  </li>
                  <li>선택 패널의 회전 슬라이더로 각도를 조정합니다.</li>
                  <li>
                    일반 가구는 높이 슬라이더로 바닥에서 띄운 높이를 조정할 수
                    있습니다.
                  </li>
                  <li>
                    작업이 끝나면 오른쪽 아래 저장 버튼으로 현재 방을
                    저장합니다.
                  </li>
                </ol>
              </section>

              <section className="ed-manual-section">
                <h3>선택한 오브젝트</h3>
                <ul>
                  <li>가구를 선택하면 크기, 회전값, 충돌 상태가 표시됩니다.</li>
                  <li>
                    일반 가구를 선택하면 바닥에서 띄운 높이(Elevation)도 함께
                    표시되며, 높이 슬라이더로 값을 직접 지정할 수 있습니다.
                    선반이나 액자처럼 벽 중간 높이에 배치하고 싶을 때
                    사용하세요.
                  </li>
                  <li>
                    교체버튼을 누른 뒤 왼쪽 목록에서 다른 가구를 선택하면
                    교체됩니다.
                  </li>
                  <li>
                    가구의 삭제버튼은 가구만 지웁니다. 문과 창문은 벽에 고정되어
                    있어 높이 조정은 지원하지 않습니다.
                  </li>
                  <li>
                    문이나 창문을 선택하면 "개구부로 삭제"와 "벽으로 메우기" 두
                    가지 삭제 방법이 나타납니다. 개구부로 삭제하면 벽에 뚫린
                    구멍은 그대로 남고, 벽으로 메우면 그 자리가 막힌 벽이
                    됩니다.
                  </li>
                  <li>
                    개구부로 남겨둔 자리를 클릭하면 다시 선택할 수 있고,
                    "채우기" 버튼을 누른 뒤 왼쪽 목록에서 문이나 창문을 고르면
                    그 자리에 채워집니다.
                  </li>
                </ul>
              </section>

              <section className="ed-manual-section">
                <h3>하단 보기 도구</h3>
                <ul>
                  <li>Skyview는 방을 위에서 내려다보는 시점으로 전환합니다.</li>
                  <li>색상 버튼은 벽 색상을 변경합니다.</li>
                  <li>자 아이콘은 방 치수와 면적 표시를 켜거나 끕니다.</li>
                </ul>
              </section>

              <section className="ed-manual-section">
                <h3>충돌과 저장</h3>
                <ul>
                  <li>
                    가구는 벽이나 방 경계를 통과하지 않도록 이동이 제한됩니다.
                  </li>
                  <li>
                    겹침 경고가 보이면 선택한 가구의 위치나 회전을 조정하세요.
                  </li>
                  <li>
                    방을 바꾸거나 나가기 전에 저장하지 않은 변경 사항이 있으면
                    확인 메시지가 표시됩니다.
                  </li>
                </ul>
              </section>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}

export default ThreeDEditor;
