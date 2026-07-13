import React, { useCallback, useEffect, useRef, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import "../../styles/mypage.css";
import { getAccessToken } from "../../utils/authSession";
import { getMyInfo } from "../../springApi/MemberSpringBootApi";
import {
  deleteProject,
  getProjectList,
  patchProject,
  postProject,
} from "../../springApi/ProjectSpringBootAPi";
import {
  getRoomList,
  patchRoom,
  postRoom,
} from "../../springApi/RoomSpringBootApi";
import { deleteRoom } from "../../springApi/RoomSpringBootApi";
import {
  deleteUserFurniture,
  getUserFurnitureCatalog,
} from "../../springApi/FurnitureSpringBootApi";
import AccountPanel from "../../components/AccountPanel";
import AvatarButton from "../../components/AvatarButton";
import Footer from "../../components/Footer";
import Logo from "../../components/Logo";
import MakeRoom from "../../components/MakeRoom";
import useLogout from "../../hooks/useLogout";

const DEFAULT_USER = {
  initial: "S",

  name: "SPATIUM",
  fullName: "SPATIUM",
  handle: "",
  email: "",
  profileImage: null,
};

function normalizeUser(data) {
  const nickname = data?.nickname || data?.email?.split("@")[0] || "SPATIUM";

  return {
    initial: nickname.charAt(0).toUpperCase(),
    name: nickname,
    fullName: nickname,
    handle: data?.email ? `${data.email}` : "",
    email: data?.email || "",
    profileImage: data?.profileImageUrl || null,
  };
}

function normalizeRoom(room) {
  return {
    id: room.roomId,
    thumb: "3D",
    name: room.roomName || "Untitled room",
    // 정렬용 원본(ISO) — ISO 문자열은 사전순 비교가 시간순과 일치한다.
    updatedAtRaw: room.updatedAt || null,
    // 표시용 (마지막 수정일, 수정된 적 없으면 백엔드가 생성일을 내려준다)
    updatedAt: room.updatedAt
      ? new Date(room.updatedAt).toLocaleDateString("ko-KR")
      : "-",
    furnitureCount: 0,
  };
}

function normalizeProject(project, rooms = []) {
  const normalizedRooms = rooms.map(normalizeRoom);
  // 프로젝트의 "최근 활동" = 프로젝트 생성일과 소속 룸 수정일 중 가장 최근 값
  const lastActivity =
    [project.createdAt, ...normalizedRooms.map((room) => room.updatedAtRaw)]
      .filter(Boolean)
      .sort()
      .pop() || null;

  return {
    id: project.projectId,
    name: project.projectName || "Untitled project",
    furnitureCount: project.furnitureCount || 0,
    rooms: normalizedRooms,
    lastActivity,
  };
}

function MyPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const [panelOpen, setPanelOpen] = useState(false);
  const [activeTab, setActiveTab] = useState("project");
  const [user, setUser] = useState(DEFAULT_USER);
  const [projects, setProjects] = useState([]);
  const [expandedProjectIds, setExpandedProjectIds] = useState(() => new Set());
  const [loading, setLoading] = useState(true);
  const [apiError, setApiError] = useState("");
  const [editingProjectId, setEditingProjectId] = useState(null);
  const [editingName, setEditingName] = useState("");
  const [editingRoomKey, setEditingRoomKey] = useState(null);
  const [editingRoomName, setEditingRoomName] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [modalMode, setModalMode] = useState("project");
  const [modalTargetProjectId, setModalTargetProjectId] = useState(null);
  const [nameInput, setNameInput] = useState("");
  const [metadataFile, setMetadataFile] = useState(null);
  const [roomFile, setRoomFile] = useState(null);
  const [modalError, setModalError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [deletingProjectId, setDeletingProjectId] = useState(null);
  const [myFurniture, setMyFurniture] = useState([]);
  const [furnitureLoading, setFurnitureLoading] = useState(false);
  const [furnitureError, setFurnitureError] = useState("");
  const [deletingFurnitureId, setDeletingFurnitureId] = useState(null);
  const [expandedFurnitureIds, setExpandedFurnitureIds] = useState(
    () => new Set(),
  );
  const autoModalHandled = useRef(false);
  const metadataFileInputRef = useRef(null);
  const roomFileInputRef = useRef(null);

  const loadDashboard = useCallback(async () => {
    if (!getAccessToken()) {
      navigate("/auth/login");
      return;
    }

    setLoading(true);
    setApiError("");

    try {
      const [me, projectPage] = await Promise.all([
        getMyInfo(),
        getProjectList(),
      ]);
      const projectItems = projectPage?.items || [];
      const projectsWithRooms = await Promise.all(
        projectItems.map(async (project) => {
          const roomPage = await getRoomList(project.projectId);
          return normalizeProject(project, roomPage?.items || []);
        }),
      );

      // 최근에 수정/생성된 프로젝트부터 보여준다
      projectsWithRooms.sort((a, b) =>
        (b.lastActivity || "").localeCompare(a.lastActivity || ""),
      );

      setUser(normalizeUser(me));
      setProjects(projectsWithRooms);
    } catch (err) {
      setApiError(err.message || "데이터를 불러오지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }, [navigate]);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  // 내가 만든 사용자 가구 목록을 불러온다 (내 가구관리 탭).
  const loadMyFurniture = useCallback(async () => {
    if (!getAccessToken()) return;

    setFurnitureLoading(true);
    setFurnitureError("");

    try {
      const data = await getUserFurnitureCatalog();
      setMyFurniture(Array.isArray(data) ? data : []);
    } catch (err) {
      setFurnitureError(err.message || "가구 목록을 불러오지 못했습니다.");
    } finally {
      setFurnitureLoading(false);
    }
  }, []);

  // 내 가구관리 탭을 열 때마다 최신 목록으로 갱신한다.
  useEffect(() => {
    if (activeTab === "furniture") {
      loadMyFurniture();
    }
  }, [activeTab, loadMyFurniture]);

  // 홈에서 "시작하기"로 진입한 경우, 새로고침/뒤로가기 시 모달이 다시 열리지 않도록 state 제거
  useEffect(() => {
    if (location.state?.openNewProject) {
      navigate(location.pathname, { replace: true, state: {} });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 마이페이지 진입 시 프로젝트가 하나도 없으면 새 프로젝트 모달 자동 오픈 (있으면 열지 않음)
  useEffect(() => {
    if (loading || autoModalHandled.current) return;

    autoModalHandled.current = true;
    if (projects.length === 0) {
      openProjectModal("project");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading, projects]);

  const totalRoomCount = projects.reduce((sum, p) => sum + p.rooms.length, 0);
  const modalTargetProject = projects.find(
    (p) => p.id === modalTargetProjectId,
  );
  const togglePanel = () => setPanelOpen((prev) => !prev);

  const toggleProjectRooms = (projectId) => {
    setExpandedProjectIds((previous) => {
      const next = new Set(previous);

      if (next.has(projectId)) {
        next.delete(projectId);
      } else {
        next.add(projectId);
      }

      return next;
    });
  };

  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  const handleLogout = useLogout(() => {
    navigate("/");
  });

  const handleOpenRoom = (project, room) => {
    const params = new URLSearchParams({
      projectId: String(project.id),
      roomId: String(room.id),
    });

    navigate(`/member/editor?${params.toString()}`);
  };

  const startRenameProject = (project) => {
    setEditingProjectId(project.id);
    setEditingName(project.name);
  };

  const cancelRenameProject = () => {
    setEditingProjectId(null);
    setEditingName("");
  };

  const saveRenameProject = async () => {
    const name = editingName.trim();
    const projectId = editingProjectId;
    setEditingProjectId(null);
    setEditingName("");

    if (!name || !projectId) return;

    const project = projects.find((p) => p.id === projectId);
    if (project && project.name === name) return;

    setProjects((prev) =>
      prev.map((p) => (p.id === projectId ? { ...p, name } : p)),
    );

    try {
      await patchProject({ projectId, projectName: name });
    } catch (err) {
      alert(err.message || "프로젝트 이름 변경에 실패했습니다.");
      await loadDashboard();
    }
  };

  const startRenameRoom = (project, room) => {
    setEditingRoomKey({ projectId: project.id, roomId: room.id });
    setEditingRoomName(room.name);
  };

  const cancelRenameRoom = () => {
    setEditingRoomKey(null);
    setEditingRoomName("");
  };

  const saveRenameRoom = async () => {
    const name = editingRoomName.trim();
    const roomKey = editingRoomKey;
    setEditingRoomKey(null);
    setEditingRoomName("");

    if (!name || !roomKey) return;

    const project = projects.find((p) => p.id === roomKey.projectId);
    const room = project?.rooms.find((r) => r.id === roomKey.roomId);
    if (room && room.name === name) return;

    setProjects((prev) =>
      prev.map((p) =>
        p.id !== roomKey.projectId
          ? p
          : {
              ...p,
              rooms: p.rooms.map((r) =>
                r.id === roomKey.roomId ? { ...r, name } : r,
              ),
            },
      ),
    );

    try {
      await patchRoom({ roomId: roomKey.roomId, roomName: name });
    } catch (err) {
      alert(err.message || "룸 이름 변경에 실패했습니다.");
      await loadDashboard();
    }
  };

  const handleDeleteRoom = async (event, project, room) => {
    event.stopPropagation();

    const confirmed = window.confirm(`"${room.name}" 룸을 삭제하시겠습니까?`);
    if (!confirmed) return;

    const accessToken = getAccessToken();
    if (!accessToken) {
      alert("로그인이 필요합니다.");
      return;
    }

    try {
      await deleteRoom({
        projectId: project.id,
        roomId: room.id,
        accessToken,
      });

      setProjects((prev) =>
        prev.map((p) =>
          p.id !== project.id
            ? p
            : {
                ...p,
                rooms: p.rooms.filter((r) => r.id !== room.id),
              },
        ),
      );

      alert("룸이 삭제되었습니다.");
    } catch (err) {
      alert(err.message || "룸 삭제에 실패했습니다.");
    }
  };

  const handleDeleteProject = async (event, project) => {
    event.stopPropagation();

    const confirmed = window.confirm(
      `"${project.name}" 프로젝트를 삭제하시겠습니까?\n프로젝트 안의 룸도 함께 삭제됩니다.`,
    );
    if (!confirmed) return;

    if (!getAccessToken()) {
      alert("로그인이 필요합니다.");
      return;
    }

    setDeletingProjectId(project.id);

    try {
      await deleteProject({
        projectId: project.id,
      });

      setProjects((prev) => prev.filter((p) => p.id !== project.id));

      if (editingProjectId === project.id) {
        cancelRenameProject();
      }

      if (editingRoomKey?.projectId === project.id) {
        cancelRenameRoom();
      }

      alert("프로젝트가 삭제되었습니다.");
    } catch (err) {
      alert(err.message || "프로젝트 삭제에 실패했습니다.");
    } finally {
      setDeletingProjectId(null);
    }
  };

  const toggleFurnitureDetails = (furnitureId) => {
    setExpandedFurnitureIds((previous) => {
      const next = new Set(previous);

      if (next.has(furnitureId)) {
        next.delete(furnitureId);
      } else {
        next.add(furnitureId);
      }

      return next;
    });
  };

  const handleDeleteFurniture = async (item) => {
    const confirmed = window.confirm(`"${item.name}" 가구를 삭제하시겠습니까?`);
    if (!confirmed) return;

    if (!getAccessToken()) {
      alert("로그인이 필요합니다.");
      return;
    }

    setDeletingFurnitureId(item.id);

    try {
      await deleteUserFurniture(item.id);
      setMyFurniture((prev) => prev.filter((f) => f.id !== item.id));
      alert("가구가 삭제되었습니다.");
    } catch (err) {
      alert(err.message || "가구 삭제에 실패했습니다.");
    } finally {
      setDeletingFurnitureId(null);
    }
  };

  // 모달 열기 : mode='project'면 새 프로젝트(새 칸), mode='room'이면 해당 프로젝트에 룸 추가
  const openProjectModal = (mode = "project", projectId = null) => {
    setModalMode(mode);
    setModalTargetProjectId(projectId);
    setNameInput("");
    setMetadataFile(null);
    setRoomFile(null);
    setModalError("");
    setModalOpen(true);
    if (metadataFileInputRef.current) metadataFileInputRef.current.value = "";
    if (roomFileInputRef.current) roomFileInputRef.current.value = "";
  };

  const handleRemoveMetadataFile = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setMetadataFile(null);
    if (metadataFileInputRef.current) metadataFileInputRef.current.value = "";
  };

  const handleRemoveRoomFile = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setRoomFile(null);
    if (roomFileInputRef.current) roomFileInputRef.current.value = "";
  };

  const closeProjectModal = () => {
    if (!submitting) {
      setModalOpen(false);
    }
  };

  const handleBackdropClick = (e) => {
    if (e.target === e.currentTarget) {
      closeProjectModal();
    }
  };

  const submitProjectModal = async (e) => {
    e.preventDefault();

    const name = nameInput.trim();
    if (!name) {
      setModalError(
        modalMode === "room"
          ? "룸 이름을 입력해주세요."
          : "프로젝트 이름을 입력해주세요.",
      );
      return;
    }

    if (modalMode === "room" && (!metadataFile || !roomFile)) {
      setModalError("metadata JSON 파일과 룸 파일을 모두 선택해주세요.");
      return;
    }

    setSubmitting(true);
    setModalError("");

    try {
      if (modalMode === "room") {
        await postRoom({
          projectId: modalTargetProjectId,
          roomName: name,
          metadata: metadataFile,
          file: roomFile,
        });
      } else {
        await postProject(name);
      }

      setModalOpen(false);
      await loadDashboard();
    } catch (err) {
      setModalError(err.message || "생성에 실패했습니다.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="mp-root">
      <div className="mp-nav">
        <Logo prefix="mp" />
        <div className="mp-nav-right">
          <AvatarButton
            prefix="mp"
            imageUrl={user.profileImage}
            initial={user.initial.toUpperCase()}
            name={user.name}
            onClick={togglePanel}
            showCaret={false}
          />
        </div>
      </div>

      <div className="mp-body">
        <div className="mp-sidebar">
          <div className="mp-sb-divider"></div>
          <button
            type="button"
            className={`mp-tab-btn ${
              activeTab === "project" ? "mp-tab-active" : ""
            }`}
            onClick={() => setActiveTab("project")}
          >
            내 프로젝트
          </button>
          <button
            type="button"
            className={`mp-tab-btn ${
              activeTab === "furniture" ? "mp-tab-active" : ""
            }`}
            onClick={() => setActiveTab("furniture")}
          >
            내 가구관리
          </button>
        </div>

        <div className="mp-main">
          {activeTab === "furniture" ? (
            <div>
              <div className="mp-main-head" style={{ marginBottom: 22 }}>
                <div className="mp-main-title">내 가구관리</div>
                <div className="mp-main-head-row">
                  <div className="mp-main-sub">
                    {furnitureLoading
                      ? "불러오는 중..."
                      : `총 ${myFurniture.length}개의 가구가 있습니다`}
                  </div>
                  <button
                    type="button"
                    className="mp-new-project-btn"
                    onClick={() => navigate("/member/imgto3d")}
                  >
                    + 가구 만들기
                  </button>
                </div>
                {furnitureError && (
                  <div className="mp-modal-help">{furnitureError}</div>
                )}
              </div>

              <div className="mp-projects-list">
                {myFurniture.map((item) => {
                  const isExpanded = expandedFurnitureIds.has(item.id);
                  const sizeText = item.dimensions
                    ? `${(item.dimensions.x || 0).toFixed(2)}m × ${(
                        item.dimensions.y || 0
                      ).toFixed(2)}m × ${(item.dimensions.z || 0).toFixed(2)}m`
                    : "-";

                  return (
                    <div
                      className={`mp-room-card ${
                        isExpanded ? "is-expanded" : "is-collapsed"
                      }`}
                      key={item.id}
                    >
                      <div className="mp-room-card-header">
                        <div className="mp-room-card-title">🪑 {item.name}</div>
                        <div className="mp-room-card-actions">
                          <button
                            type="button"
                            className="mp-project-collapse-btn"
                            onClick={() => toggleFurnitureDetails(item.id)}
                            aria-expanded={isExpanded}
                            aria-controls={`furniture-details-${item.id}`}
                            title={isExpanded ? "정보 접기" : "정보 보기"}
                          >
                            <span className="mp-project-collapse-label">
                              정보
                            </span>
                            <svg
                              className="mp-project-collapse-icon"
                              aria-hidden="true"
                              viewBox="0 0 16 16"
                              fill="none"
                            >
                              <path
                                d={
                                  isExpanded
                                    ? "M4 10L8 6L12 10"
                                    : "M4 6L8 10L12 6"
                                }
                                stroke="currentColor"
                                strokeWidth="1.75"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                              />
                            </svg>
                          </button>
                          <button
                            type="button"
                            className="mp-project-delete-btn"
                            disabled={deletingFurnitureId === item.id}
                            onClick={() => handleDeleteFurniture(item)}
                          >
                            {deletingFurnitureId === item.id
                              ? "삭제 중..."
                              : "삭제"}
                          </button>
                        </div>
                      </div>

                      <div
                        id={`furniture-details-${item.id}`}
                        className={`mp-project-rooms ${
                          isExpanded ? "is-expanded" : ""
                        }`}
                        aria-hidden={!isExpanded}
                        inert={!isExpanded ? "" : undefined}
                      >
                        <div className="mp-project-rooms-inner">
                          <div className="mp-fur-details">
                            <div className="mp-fur-detail-row">
                              <span className="mp-fur-detail-label">
                                카테고리
                              </span>
                              <span className="mp-fur-detail-value">
                                {item.group || item.category || "-"}
                              </span>
                            </div>
                            <div className="mp-fur-detail-row">
                              <span className="mp-fur-detail-label">
                                크기 (가로 × 높이 × 깊이)
                              </span>
                              <span className="mp-fur-detail-value">
                                {sizeText}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ) : (
            <div>
              <div className="mp-main-head" style={{ marginBottom: 22 }}>
                <div className="mp-main-title">최근 룸</div>
                <div className="mp-main-head-row">
                  <div className="mp-main-sub">
                    {loading
                      ? "불러오는 중..."
                      : `총 ${totalRoomCount}개의 룸이 있습니다`}
                  </div>
                  <button
                    type="button"
                    className="mp-new-project-btn"
                    onClick={() => openProjectModal("project")}
                  >
                    + 새 프로젝트
                  </button>
                </div>
                {apiError && <div className="mp-modal-help">{apiError}</div>}
              </div>

              <div className="mp-projects-list">
                {projects.map((project) => {
                  const isExpanded = expandedProjectIds.has(project.id);

                  return (
                    <div
                      className={`mp-room-card ${
                        isExpanded ? "is-expanded" : "is-collapsed"
                      }`}
                      key={project.id}
                    >
                      <div className="mp-room-card-header">
                        {editingProjectId === project.id ? (
                          <input
                            className="mp-room-card-title-input"
                            value={editingName}
                            onChange={(e) => setEditingName(e.target.value)}
                            onBlur={saveRenameProject}
                            onKeyDown={(e) => {
                              if (e.key === "Enter") saveRenameProject();
                              if (e.key === "Escape") cancelRenameProject();
                            }}
                            autoFocus
                          />
                        ) : (
                          <div
                            className="mp-room-card-title"
                            onDoubleClick={() => startRenameProject(project)}
                            title="더블클릭하여 이름 변경"
                          >
                            {project.name}
                          </div>
                        )}
                        <div className="mp-room-card-actions">
                          <button
                            type="button"
                            className="mp-project-collapse-btn"
                            onClick={() => toggleProjectRooms(project.id)}
                            aria-expanded={isExpanded}
                            aria-controls={`project-rooms-${project.id}`}
                            title={isExpanded ? "룸 목록 접기" : "룸 목록 보기"}
                          >
                            <span className="mp-project-collapse-label">
                              룸
                            </span>
                            <span className="mp-project-collapse-count">
                              {project.rooms.length}
                            </span>
                            <svg
                              className="mp-project-collapse-icon"
                              aria-hidden="true"
                              viewBox="0 0 16 16"
                              fill="none"
                            >
                              <path
                                d={
                                  isExpanded
                                    ? "M4 10L8 6L12 10"
                                    : "M4 6L8 10L12 6"
                                }
                                stroke="currentColor"
                                strokeWidth="1.75"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                              />
                            </svg>
                          </button>
                          <button
                            className="mp-new-btn"
                            onClick={() => openProjectModal("room", project.id)}
                          >
                            + 룸 만들기
                          </button>
                          <button
                            type="button"
                            className="mp-project-delete-btn"
                            disabled={deletingProjectId === project.id}
                            onClick={(event) =>
                              handleDeleteProject(event, project)
                            }
                          >
                            {deletingProjectId === project.id
                              ? "삭제 중..."
                              : "삭제"}
                          </button>
                        </div>
                      </div>

                      <div
                        id={`project-rooms-${project.id}`}
                        className={`mp-project-rooms ${
                          isExpanded ? "is-expanded" : ""
                        }`}
                        aria-hidden={!isExpanded}
                        inert={!isExpanded ? "" : undefined}
                      >
                        <div className="mp-project-rooms-inner">
                          {project.rooms.length === 0 && (
                            <div className="mp-empty-rooms">
                              아직 생성된 룸이 없습니다.
                            </div>
                          )}
                          {project.rooms.map((room) => {
                            const isEditingRoom =
                              editingRoomKey &&
                              editingRoomKey.projectId === project.id &&
                              editingRoomKey.roomId === room.id;

                            return (
                              <div
                                key={room.id}
                                className="mp-room-row"
                                onClick={() => {
                                  if (!isEditingRoom)
                                    handleOpenRoom(project, room);
                                }}
                              >
                                <div className="mp-room-thumb">
                                  {room.thumb}
                                </div>
                                <div className="mp-room-info">
                                  {isEditingRoom ? (
                                    <input
                                      className="mp-room-name-input"
                                      value={editingRoomName}
                                      onClick={(event) =>
                                        event.stopPropagation()
                                      }
                                      onChange={(e) =>
                                        setEditingRoomName(e.target.value)
                                      }
                                      onBlur={saveRenameRoom}
                                      onKeyDown={(e) => {
                                        if (e.key === "Enter") saveRenameRoom();
                                        if (e.key === "Escape")
                                          cancelRenameRoom();
                                      }}
                                      autoFocus
                                    />
                                  ) : (
                                    <div
                                      className="mp-room-name"
                                      onClick={(event) =>
                                        event.stopPropagation()
                                      }
                                      onDoubleClick={(event) => {
                                        event.stopPropagation();
                                        startRenameRoom(project, room);
                                      }}
                                      title="더블클릭하여 이름 변경"
                                    >
                                      {room.name}
                                    </div>
                                  )}
                                  <div className="mp-room-meta">
                                    최근 수정 {room.updatedAt}
                                  </div>
                                </div>
                                <button
                                  type="button"
                                  className="mp-room-delete-btn"
                                  onClick={(event) =>
                                    handleDeleteRoom(event, project, room)
                                  }
                                >
                                  삭제
                                </button>
                                <div className="mp-room-arrow">›</div>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* 내 정보 오른쪽 모달*/}
          <AccountPanel
            open={panelOpen}
            prefix="mp"
            profile={{
              name: user.fullName,
              initial: user.initial,
              imageUrl: user.profileImage,
              subtext: user.handle,
            }}
            statItems={[
              { label: "프로젝트", value: projects.length },
              { label: "룸 개수", value: totalRoomCount },
            ]}
            onClose={() => setPanelOpen(false)}
            onProfileClick={handleGoAccount}
            onLogout={handleLogout}
            onAccountClick={handleGoAccount}
            showScrim={false}
            panelExtraClass="mp-panel-open"
          />
        </div>
      </div>

      <MakeRoom
        open={modalOpen}
        mode={modalMode}
        targetProject={modalTargetProject}
        nameInput={nameInput}
        onNameChange={(e) => {
          setNameInput(e.target.value);
          if (modalError) setModalError("");
        }}
        metadataFile={metadataFile}
        metadataFileInputRef={metadataFileInputRef}
        onMetadataFileChange={(event) =>
          setMetadataFile(event.target.files?.[0] || null)
        }
        onRemoveMetadataFile={handleRemoveMetadataFile}
        roomFile={roomFile}
        roomFileInputRef={roomFileInputRef}
        onRoomFileChange={(event) =>
          setRoomFile(event.target.files?.[0] || null)
        }
        onRemoveRoomFile={handleRemoveRoomFile}
        error={modalError}
        submitting={submitting}
        onClose={closeProjectModal}
        onBackdropClick={handleBackdropClick}
        onSubmit={submitProjectModal}
      />
      <Footer />
    </div>
  );
}

export default MyPage;
