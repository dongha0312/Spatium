import React, { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../../styles/mypage.css";
import { clearLoginSession } from "../../utils/authSession";

// 데모용 사용자 정보 (추후 백엔드 연동 시 API 응답으로 대체)
const USER = {
  initial: "김",
  name: "김스파티",
  fullName: "김스파티움",
  handle: "@spatium_kim",
  email: "spatium@example.com",
  birth: "1998. 06. 07",
};

// 데모용 프로젝트 목록 (프로젝트 하나 = 카드 하나, 그 안에 룸이 여러 개 들어감)
const INITIAL_PROJECTS = [
  {
    id: "default",
    name: "내 프로젝트",
    rooms: [
      {
        id: 1,
        thumb: "🛋️",
        name: "1조 — 우리집 거실 리모델링",
        updatedAt: "2026.06.28",
        furnitureCount: 8,
      },
      {
        id: 2,
        thumb: "🛏️",
        name: "2조 — 침실 인테리어",
        updatedAt: "2026.06.20",
        furnitureCount: 5,
      },
      {
        id: 3,
        thumb: "🍳",
        name: "3조 — 주방 리모델링",
        updatedAt: "2026.06.15",
        furnitureCount: 3,
      },
    ],
  },
];

function formatToday() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}.${m}.${d}`;
}

function MyPage() {
  const navigate = useNavigate();

  // 우측 슬라이드 패널(내 정보) 열림 여부
  const [panelOpen, setPanelOpen] = useState(false);

  // 프로젝트 목록 (프로젝트 각각이 카드 하나 = "칸")
  const [projects, setProjects] = useState(INITIAL_PROJECTS);

  useEffect(()=>{
    
  }, [])

  // 프로젝트 이름 인라인 수정 (더블클릭) 상태
  const [editingProjectId, setEditingProjectId] = useState(null);
  const [editingName, setEditingName] = useState("");

  // 룸 이름 인라인 수정 (더블클릭) 상태 : { projectId, roomId }
  const [editingRoomKey, setEditingRoomKey] = useState(null);
  const [editingRoomName, setEditingRoomName] = useState("");

  // 새 프로젝트 / 새 룸 모달 상태
  const [modalOpen, setModalOpen] = useState(false);
  // 모달을 연 방식 : 'room'(특정 프로젝트에 ＋ 새 룸 만들기) | 'project'(사이드바 ＋ 새 프로젝트 = 새 칸 생성)
  const [modalMode, setModalMode] = useState("project");
  // 'room' 모드일 때, 어느 프로젝트(칸)에 룸을 추가할지
  const [modalTargetProjectId, setModalTargetProjectId] = useState(null);
  const [nameInput, setNameInput] = useState("");
  const [modalError, setModalError] = useState("");

  const totalRoomCount = projects.reduce((sum, p) => sum + p.rooms.length, 0);
  const totalFurnitureCount = projects.reduce(
    (sum, p) => sum + p.rooms.reduce((rSum, r) => rSum + r.furnitureCount, 0),
    0,
  );

  const togglePanel = () => setPanelOpen((prev) => !prev);

  // 계정설정 페이지(AccountSettings.js)로 이동
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  const handleLogout = () => {
    alert("로그아웃 되었습니다.");
    clearLoginSession();
    navigate("/");
  };

  // 프로젝트(룸) 클릭 → 3D 에디터로 이동
  const handleOpenRoom = () => {
    navigate("/member/editor");
  };

  // 프로젝트 이름 더블클릭 → 인라인 수정 시작
  const startRenameProject = (project) => {
    setEditingProjectId(project.id);
    setEditingName(project.name);
  };

  const cancelRenameProject = () => {
    setEditingProjectId(null);
    setEditingName("");
  };

  const saveRenameProject = () => {
    const name = editingName.trim();
    if (name) {
      setProjects((prev) =>
        prev.map((p) => (p.id === editingProjectId ? { ...p, name } : p)),
      );
    }
    setEditingProjectId(null);
    setEditingName("");
  };

  // 룸 이름 더블클릭 → 인라인 수정 시작
  const startRenameRoom = (project, room) => {
    setEditingRoomKey({ projectId: project.id, roomId: room.id });
    setEditingRoomName(room.name);
  };

  const cancelRenameRoom = () => {
    setEditingRoomKey(null);
    setEditingRoomName("");
  };

  const saveRenameRoom = () => {
    const name = editingRoomName.trim();
    if (name && editingRoomKey) {
      setProjects((prev) =>
        prev.map((p) =>
          p.id !== editingRoomKey.projectId
            ? p
            : {
                ...p,
                rooms: p.rooms.map((r) =>
                  r.id === editingRoomKey.roomId ? { ...r, name } : r,
                ),
              },
        ),
      );
    }
    setEditingRoomKey(null);
    setEditingRoomName("");
  };

  // 모달 열기 : mode='project'면 새 프로젝트(새 칸), mode='room'이면 해당 프로젝트에 룸 추가
  const openProjectModal = (mode = "project", projectId = null) => {
    setModalMode(mode);
    setModalTargetProjectId(projectId);
    setNameInput("");
    setModalError("");
    setModalOpen(true);
  };

  const closeProjectModal = () => {
    setModalOpen(false);
  };

  // 모달 배경(백드롭) 클릭 시 닫기 — 다이얼로그 내부 클릭은 무시
  const handleBackdropClick = (e) => {
    if (e.target === e.currentTarget) {
      closeProjectModal();
    }
  };

  // 새 프로젝트(새 칸) 또는 새 룸 생성
  const submitProjectModal = (e) => {
    e.preventDefault();

    const name = nameInput.trim();
    if (!name) {
      setModalError(
        modalMode === "room"
          ? "룸명을 입력해주세요."
          : "프로젝트 명을 입력해주세요.",
      );
      return;
    }

    if (modalMode === "room") {
      // 특정 프로젝트(칸) 안에 룸 한 줄 추가
      const newRoom = {
        id: Date.now(),
        thumb: "🏠",
        name,
        updatedAt: formatToday(),
        furnitureCount: 0,
      };
      setProjects((prev) =>
        prev.map((p) =>
          p.id === modalTargetProjectId
            ? { ...p, rooms: [newRoom, ...p.rooms] }
            : p,
        ),
      );
    } else {
      // 완전히 새로운 프로젝트 칸(카드) 생성
      const newProject = {
        id: Date.now(),
        name,
        rooms: [],
      };
      setProjects((prev) => [newProject, ...prev]);
    }

    setModalOpen(false);
  };

  return (
    <div className="mp-root">
      {/* 상단 네비게이션 */}
      <div className="mp-nav">
        <Link to="/" className="mp-logo">
          <div className="mp-logo-sq">
            <div className="mp-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <span className="mp-nav-link">룸 인테리어</span>
        <div className="mp-nav-right">
          <button className="mp-av-btn" onClick={togglePanel}>
            <div className="mp-av-circ">{USER.initial}</div>
            <span className="mp-av-name">{USER.name}</span>
            <span className="mp-av-caret">▾</span>
          </button>
        </div>
      </div>

      {/* 본문 */}
      <div className="mp-body">
        {/* 좌측 사이드바 */}
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
            ＋ 새 프로젝트
          </button>
        </div>

        {/* 메인 영역 */}
        <div className="mp-main">
          {/* 프로젝트 뷰 */}
          <div>
            <div style={{ marginBottom: 22 }}>
              <div className="mp-main-title">최근 룸</div>
              <div className="mp-main-sub">
                총 {totalRoomCount}개의 룸이 있습니다
              </div>
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
                        ＋ 새 룸 만들기
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
                          if (!isEditingRoom) handleOpenRoom(room);
                        }}
                      >
                        <div className="mp-room-thumb">{room.thumb}</div>
                        <div className="mp-room-info">
                          {isEditingRoom ? (
                            <input
                              className="mp-room-name-input"
                              value={editingRoomName}
                              onClick={(e) => e.stopPropagation()}
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
                              onDoubleClick={(e) => {
                                e.stopPropagation();
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
                        <div className="mp-room-arrow">›</div>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>

          {/* 우측 슬라이드 패널 (내 정보) */}
          <div className={`mp-panel${panelOpen ? " mp-panel-open" : ""}`}>
            <div className="mp-panel-head">
              <div className="mp-panel-title">내 정보</div>
              <button className="mp-panel-close" onClick={togglePanel}>
                ✕
              </button>
            </div>
            <div className="mp-panel-body">
              <span className="mp-panel-label">기본정보</span>
              <button className="mp-panel-profile" onClick={handleGoAccount}>
                <div className="mp-panel-avatar">{USER.initial}</div>
                <div>
                  <div className="mp-panel-pname">{USER.fullName}</div>
                  <div className="mp-panel-pnick">{USER.handle}</div>
                </div>
                <span className="mp-panel-arrow">›</span>
              </button>

              <span className="mp-panel-label">이용현황</span>
              <div className="mp-panel-stats">
                <div className="mp-panel-stat">
                  <span className="mp-panel-stat-num">{projects.length}</span>
                  <span className="mp-panel-stat-label">프로젝트</span>
                </div>
                <div className="mp-panel-stat">
                  <span className="mp-panel-stat-num">
                    {totalFurnitureCount}
                  </span>
                  <span className="mp-panel-stat-label">저장 가구</span>
                </div>
              </div>
            </div>
            <div className="mp-panel-foot">
              <button
                className="mp-panel-foot-btn mp-panel-sub"
                onClick={handleLogout}
              >
                로그아웃
              </button>
              <button
                className="mp-panel-foot-btn mp-panel-main"
                onClick={handleGoAccount}
              >
                → 계정설정
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* 새 프로젝트 / 새 룸 모달 */}
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
                ✕
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
              <div className="mp-modal-help">{modalError}</div>
            </div>
            <div className="mp-dialog-actions">
              <button
                type="button"
                className="mp-dialog-btn mp-dialog-btn-sub"
                onClick={closeProjectModal}
              >
                취소
              </button>
              <button
                type="submit"
                className="mp-dialog-btn mp-dialog-btn-main"
              >
                생성
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}

export default MyPage;
