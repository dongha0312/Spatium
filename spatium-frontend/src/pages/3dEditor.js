import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import "../styles/3deditor.css";
import TestThreeStagingPage from "./testThree/TestThreeStagingPage";
import { getAccessToken, getLoginSession } from "../utils/authSession";
import { getProjectInfo } from "../springApi/ProjectSpringBootAPi";
import { getRoomJsonData } from "../springApi/RoomSpringBootApi";

const FURNITURE_CATALOG_URL = "/data/furniture_catalog.json";

const INITIAL_LAYERS = [
  { id: "room", name: "Room", color: "#C4956A" },
  { id: "furniture", name: "Furniture", color: "#7B9EC2" },
  { id: "openings", name: "Doors & windows", color: "#D4A96A" },
];

const WALL_COLORS = ["#F5F0EA", "#E8DCC8", "#C4956A", "#3A3A3A"];

function normalizeCatalogItem(item) {
  return {
    ...item,
    path: item.path || item.modelUrl || null,
    modelUrl: item.modelUrl || item.path || null,
    thumbnailUrl: item.thumbnailUrl || item.imageUrl || null,
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

  const [activeLayerId, setActiveLayerId] = useState(INITIAL_LAYERS[0].id);
  const [roomDropdownOpen, setRoomDropdownOpen] = useState(false);
  const [furnitureCatalog, setFurnitureCatalog] = useState([]);
  const [catalogSearch, setCatalogSearch] = useState("");
  const [activeCategory, setActiveCategory] = useState(null);
  const [catalogError, setCatalogError] = useState("");
  const [isSkyview, setIsSkyview] = useState(false);
  const [wallColor, setWallColor] = useState(null);
  const [wallColorPickerOpen, setWallColorPickerOpen] = useState(false);
  const [showMeasurements, setShowMeasurements] = useState(false);
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState("");
  const [saveError, setSaveError] = useState("");
  const [projectLabel, setProjectLabel] = useState(
    shortId(projectId, "Project"),
  );
  const [roomLabel, setRoomLabel] = useState(shortId(roomId, "Room editor"));

  const [session] = useState(() => getLoginSession());

  const activeLayer =
    INITIAL_LAYERS.find((layer) => layer.id === activeLayerId) ??
    INITIAL_LAYERS[0];

  const categoryFilters = useMemo(
    () =>
      Array.from(
        new Set(furnitureCatalog.map((item) => item.group).filter(Boolean)),
      ),
    [furnitureCatalog],
  );

  const visibleCatalogItems = useMemo(() => {
    const query = catalogSearch.trim().toLowerCase();

    return furnitureCatalog.filter((item) => {
      const matchesCategory = activeCategory
        ? item.group === activeCategory
        : true;
      const haystack = [item.name, item.group, item.category]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      const matchesSearch = query ? haystack.includes(query) : true;

      return matchesCategory && matchesSearch;
    });
  }, [activeCategory, catalogSearch, furnitureCatalog]);

  useEffect(() => {
    let isMounted = true;

    fetch(FURNITURE_CATALOG_URL, { cache: "no-store" })
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            `Failed to load furniture catalog (${response.status})`,
          );
        }
        return response.json();
      })
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
          setCatalogError(error.message || "Failed to load catalog.");
        }
      });

    return () => {
      isMounted = false;
    };
  }, []);

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
      getRoomJsonData(roomId)
        .then((data) => {
          if (isMounted && data?.roomName) {
            setRoomLabel(data.roomName);
          }
        })
        .catch(() => {
          if (isMounted) setRoomLabel(shortId(roomId, "Room editor"));
        });
    }

    return () => {
      isMounted = false;
    };
  }, [projectId, roomId]);

  useEffect(() => {
    if (!hasUnsavedChanges) return undefined;

    const handleBeforeUnload = (event) => {
      event.preventDefault();
      event.returnValue = "";
    };

    const handlePopState = () => {
      const confirmed = window.confirm(
        "You have unsaved changes. Leave the editor anyway?",
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

  const handleSceneChanged = useCallback(() => {
    setHasUnsavedChanges(true);
    setSaveMessage("");
    setSaveError("");
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
    if (hasUnsavedChanges) {
      const confirmed = window.confirm(
        "You have unsaved changes. Leave the editor anyway?",
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
      setSaveError("Missing project or room information.");
      return;
    }

    if (!accessToken) {
      setSaveError("Please log in before saving.");
      return;
    }

    setIsSaving(true);

    try {
      const saved = await editorRef.current?.saveEditedSceneJson({
        projectId,
        roomId,
      });

      if (!saved) {
        setSaveError("Save failed. Check the editor message and try again.");
        return;
      }

      setHasUnsavedChanges(false);
      setSaveMessage("Saved.");
      window.setTimeout(() => setSaveMessage(""), 1800);
    } catch (error) {
      setSaveError(error.message || "Save failed.");
    } finally {
      setIsSaving(false);
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
        <div className="ed-nav-center">{roomLabel}</div>
        <div className="ed-nav-status">
          {isSaving && <span className="ed-save-state">Saving...</span>}
          {!isSaving && saveMessage && (
            <span className="ed-save-state ed-save-ok">{saveMessage}</span>
          )}
          {!isSaving && saveError && (
            <span className="ed-save-state ed-save-error">{saveError}</span>
          )}
          {!isSaving && hasUnsavedChanges && !saveMessage && !saveError && (
            <span className="ed-save-state">Unsaved changes</span>
          )}
        </div>
        <Link to="/member/mypage" className="ed-av-btn">
          <div className="ed-av-circ">
            {(session?.nickname || "S").charAt(0).toUpperCase()}
          </div>
          <span className="ed-av-name">
            {session?.nickname || "마이페이지"}
          </span>
        </Link>
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

            <div className="ed-cat-search-wrap">
              <input
                className="ed-cat-search"
                type="search"
                placeholder="Search furniture"
                value={catalogSearch}
                onChange={(event) => setCatalogSearch(event.target.value)}
              />
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
                All
              </button>
            </div>

            <div className="ed-cat-products">
              {catalogError && (
                <div className="ed-cat-empty">{catalogError}</div>
              )}
              {!catalogError && visibleCatalogItems.length === 0 && (
                <div className="ed-cat-empty">No furniture found.</div>
              )}
              {visibleCatalogItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  className="ed-cat-product"
                  onClick={() => handleAddFurniture(item)}
                >
                  <span className="ed-cat-product-thumb">
                    {item.thumbnailUrl ? (
                      <img src={item.thumbnailUrl} alt="" />
                    ) : (
                      <span>
                        {String(item.category || item.name || "?").slice(0, 2)}
                      </span>
                    )}
                  </span>
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
              <TestThreeStagingPage
                ref={editorRef}
                isSkyview={isSkyview}
                showMeasurements={showMeasurements}
                wallColor={wallColor}
                onSceneChanged={handleSceneChanged}
              />
            </div>

            {isSkyview && (
              <div className="ed-canvas-badge ed-canvas-badge-sky">Skyview</div>
            )}

            {showMeasurements && (
              <div className="ed-canvas-badge ed-canvas-badge-measure">
                Measurements on
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
                  aria-label="Change wall color"
                  title="Change wall color"
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

              <button
                type="button"
                className={`ed-viewbar-icon-btn${showMeasurements ? " ed-viewbar-active" : ""}`}
                onClick={toggleMeasurements}
                aria-label="Toggle measurements"
                title="Toggle measurements"
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
            disabled={isSaving}
          >
            Cancel
          </button>
          <button
            type="button"
            className="ed-footer-btn ed-footer-save"
            onClick={handleSaveRoom}
            disabled={isSaving}
          >
            {isSaving ? "Saving..." : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default ThreeDEditor;
