import React, { useCallback, useEffect, useState } from "react";
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
import AccountPanel from "../../components/AccountPanel";
import AvatarButton from "../../components/AvatarButton";
import Footer from "../../components/Footer";
import useLogout from "../../hooks/useLogout";

const DEFAULT_USER = {
  initial: "",

  name: "",
  fullName: "",
  handle: "",
  email: "",
  profileImage: null,
};

// 데모용 사용자 정보 (추후 백엔드 연동 시 API 응답으로 대체)
// const USER = {
//   initial: "김",
//   name: "김스파티",
//   fullName: "김스파티움",
//   handle: "@spatium_kim",
//   email: "spatium@example.com",
//   birth: "1998. 06. 07",
// };

function normalizeUser(data) {
  const nickname = data?.nickname || data?.email?.split("@")[0] || "SPATIUM";

  return {
    initial: nickname.charAt(0).toUpperCase(),
    name: nickname,
    fullName: nickname,
    handle: data?.email ? `@${data.email}` : "",
    email: data?.email || "",
    profileImage: data?.profileImageUrl || null,
  };
}

function normalizeRoom(room) {
  return {
    id: room.roomId,
    thumb: "3D",
    name: room.roomName || "Untitled room",
    updatedAt: room.updatedAt || "-",
    furnitureCount: 0,
  };
}

function normalizeProject(project, rooms = []) {
  return {
    id: project.projectId,
    name: project.projectName || "Untitled project",
    furnitureCount: project.furnitureCount || 0,
    rooms: rooms.map(normalizeRoom),
  };
}

function MyPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const [panelOpen, setPanelOpen] = useState(false);
  const [user, setUser] = useState(DEFAULT_USER);
  const [projects, setProjects] = useState([]);
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

  // 홈에서 "시작하기"로 진입한 경우 새 프로젝트 모달 자동 오픈
  useEffect(() => {
    if (location.state?.openNewProject) {
      openProjectModal("project");
      // 새로고침/뒤로가기 시 모달이 다시 열리지 않도록 state 제거
      navigate(location.pathname, { replace: true, state: {} });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const totalRoomCount = projects.reduce((sum, p) => sum + p.rooms.length, 0);
  const totalFurnitureCount = projects.reduce(
    (sum, p) => sum + (p.furnitureCount || 0),
    0,
  );

  const togglePanel = () => setPanelOpen((prev) => !prev);

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

  // 모달 열기 : mode='project'면 새 프로젝트(새 칸), mode='room'이면 해당 프로젝트에 룸 추가
  const openProjectModal = (mode = "project", projectId = null) => {
    setModalMode(mode);
    setModalTargetProjectId(projectId);
    setNameInput("");
    setMetadataFile(null);
    setRoomFile(null);
    setModalError("");
    setModalOpen(true);
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
        <Link to="/" className="mp-logo">
          <div className="mp-logo-sq">
            <div className="mp-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <div className="mp-nav-right">
          <AvatarButton
            prefix="mp"
            imageUrl={user.profileImage}
            initial={user.initial}
            name={user.name}
            onClick={togglePanel}
            showCaret={false}
          />
        </div>
      </div>

      <div className="mp-body">
        <div className="mp-sidebar">
          <div className="mp-sb-sec">
            <span className="mp-sb-label">내 공간</span>
            {projects.map((project) => (
              <div key={project.id} className="mp-sb-item mp-active">
                <div className="mp-sb-dot"></div>
                <span>{project.name}</span>
              </div>
            ))}
          </div>
          <div className="mp-sb-divider"></div>
          <button
            className="mp-sb-btn"
            onClick={() => openProjectModal("project")}
          >
            + 새 프로젝트
          </button>
        </div>

        <div className="mp-main">
          <div>
            <div style={{ marginBottom: 22 }}>
              <div className="mp-main-title">최근 룸</div>
              <div className="mp-main-sub">
                {loading
                  ? "불러오는 중..."
                  : `총 ${totalRoomCount}개의 룸이 있습니다`}
              </div>
              {apiError && <div className="mp-modal-help">{apiError}</div>}
            </div>

            <div className="mp-projects-list">
              {projects.map((project) => (
                <div className="mp-room-card" key={project.id}>
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
                        className="mp-new-btn"
                        onClick={() => openProjectModal("room", project.id)}
                      >
                        + 룸 만들기
                      </button>
                      <button
                        type="button"
                        className="mp-project-delete-btn"
                        disabled={deletingProjectId === project.id}
                        onClick={(event) => handleDeleteProject(event, project)}
                      >
                        {deletingProjectId === project.id
                          ? "삭제 중..."
                          : "삭제"}
                      </button>
                      <div className="mp-room-card-count">
                        총 {project.rooms.length}개
                      </div>
                    </div>
                  </div>

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
                          if (!isEditingRoom) handleOpenRoom(project, room);
                        }}
                      >
                        <div className="mp-room-thumb">{room.thumb}</div>
                        <div className="mp-room-info">
                          {isEditingRoom ? (
                            <input
                              className="mp-room-name-input"
                              value={editingRoomName}
                              onClick={(event) => event.stopPropagation()}
                              onChange={(e) =>
                                setEditingRoomName(e.target.value)
                              }
                              onBlur={saveRenameRoom}
                              onKeyDown={(e) => {
                                if (e.key === "Enter") saveRenameRoom();
                                if (e.key === "Escape") cancelRenameRoom();
                              }}
                              autoFocus
                            />
                          ) : (
                            <div
                              className="mp-room-name"
                              onClick={(event) => event.stopPropagation()}
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
                            최근 수정 {room.updatedAt} · 가구{" "}
                            {room.furnitureCount}개
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
              ))}
            </div>
          </div>

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
              { label: "배치 가구", value: totalFurnitureCount },
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

      {modalOpen && (
        <div className="mp-modal-backdrop" onClick={handleBackdropClick}>
          <form
            className="mp-dialog"
            role="dialog"
            aria-modal="true"
            onSubmit={submitProjectModal}
          >
            <div className="mp-dialog-head">
              <div className="mp-dialog-title">
                {modalMode === "room" ? "New room" : "새 프로젝트"}
              </div>
              <button
                type="button"
                className="mp-dialog-close"
                onClick={closeProjectModal}
              >
                ×
              </button>
            </div>
            <div className="mp-modal-field">
              <label htmlFor="mp-name-input">
                {modalMode === "room" ? "Room name" : "프로젝트명"}
              </label>
              <input
                id="mp-name-input"
                type="text"
                placeholder={
                  modalMode === "room"
                    ? "룸명을 입력하세요"
                    : "프로젝트명을 입력하세요"
                }
                autoComplete="off"
                value={nameInput}
                onChange={(e) => {
                  setNameInput(e.target.value);
                  if (modalError) setModalError("");
                }}
                autoFocus
              />
              {modalMode === "room" && (
                <>
                  <label htmlFor="mp-metadata-input">Metadata JSON</label>
                  <input
                    id="mp-metadata-input"
                    type="file"
                    accept="application/json,.json"
                    onChange={(event) =>
                      setMetadataFile(event.target.files?.[0] || null)
                    }
                  />
                  <label htmlFor="mp-room-file-input">Room file</label>
                  <input
                    id="mp-room-file-input"
                    type="file"
                    accept=".usdz,model/vnd.usdz+zip,application/octet-stream"
                    onChange={(event) =>
                      setRoomFile(event.target.files?.[0] || null)
                    }
                  />
                </>
              )}
              <div className="mp-modal-help">{modalError}</div>
            </div>
            <div className="mp-dialog-actions">
              <button
                type="button"
                className="mp-dialog-btn mp-dialog-btn-sub"
                onClick={closeProjectModal}
                disabled={submitting}
              >
                취소
              </button>
              <button
                type="submit"
                className="mp-dialog-btn mp-dialog-btn-main"
                disabled={submitting}
              >
                {submitting ? "생성 중..." : "생성"}
              </button>
            </div>
          </form>
        </div>
      )}
      <Footer />
    </div>
  );
}

export default MyPage;
