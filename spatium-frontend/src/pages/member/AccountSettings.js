import React, { useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../../styles/accountsettings.css";

// 데모용 사용자 정보 (추후 백엔드 연동 시 API 응답으로 대체)
const USER = {
  initial: "김",
  name: "김스파티",
  email: "spatium@example.com",
  birth: "1998. 06. 07",
};

function AccountSettings() {
  const navigate = useNavigate();

  // 계정설정 폼 상태
  const [nickname, setNickname] = useState(USER.name);
  const [birth, setBirth] = useState(USER.birth);
  const [password, setPassword] = useState("");

  // 프로필 사진 : 컴퓨터에서 선택한 이미지의 미리보기 URL (선택 안 하면 이니셜 표시)
  const [avatarUrl, setAvatarUrl] = useState(null);
  // "사진 삭제"를 눌렀는지 여부 : true면 이니셜 대신 빈 이미지를 보여줌
  const [avatarRemoved, setAvatarRemoved] = useState(false);
  const fileInputRef = useRef(null);

  const dangerRef = useRef(null);

  // "사진 변경" 클릭 → 숨겨진 파일 입력창을 대신 열어줌
  const handleAvatarEditClick = () => {
    fileInputRef.current?.click();
  };

  // 파일 선택 완료 → 로컬 미리보기 URL 생성해서 아바타에 반영
  //  - 추후 백엔드 연동 시에는 이 file 객체를 FormData에 담아 업로드 API로 보내면 됨
  const handleAvatarFileChange = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      alert("이미지 파일만 선택할 수 있습니다.");
      return;
    }

    if (avatarUrl) {
      URL.revokeObjectURL(avatarUrl);
    }
    setAvatarUrl(URL.createObjectURL(file));
    setAvatarRemoved(false);

    // 같은 파일을 다시 선택해도 onChange가 발생하도록 초기화
    e.target.value = "";
  };

  const handleAvatarDelete = () => {
    if (avatarUrl) {
      URL.revokeObjectURL(avatarUrl);
    }
    setAvatarUrl(null);
    setAvatarRemoved(true);
  };

  const handleSave = (e) => {
    e.preventDefault();
    alert(`저장되었습니다.\n닉네임 : ${nickname}\n생년월일 : ${birth}`);
  };

  const handleCancel = () => {
    setNickname(USER.name);
    setBirth(USER.birth);
    setPassword("");
  };

  const handleWithdraw = () => {
    if (
      window.confirm(
        "정말 탈퇴하시겠습니까? 모든 프로젝트와 데이터가 삭제됩니다.",
      )
    ) {
      alert("탈퇴되었습니다.");
      navigate("/");
    }
  };

  const scrollToWithdraw = () => {
    dangerRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  };

  return (
    <div className="as-root">
      {/* 상단 네비게이션 */}
      <div className="as-nav">
        <Link to="/" className="as-logo">
          <div className="as-logo-sq">
            <div className="as-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <span className="as-nav-link">룸 인테리어</span>
        <div className="as-nav-right">
          <div className="as-av-btn">
            <div className="as-av-circ">{USER.initial}</div>
            <span className="as-av-name">{USER.name}</span>
          </div>
        </div>
      </div>

      {/* 본문 */}
      <div className="as-body">
        {/* 좌측 사이드바 */}
        <div className="as-sidebar">
          <div className="as-sidebar-label">설정</div>
          <button className="as-sb-item as-active">계정 설정</button>
          <div className="as-sb-divider"></div>
          <button className="as-sb-item as-danger" onClick={scrollToWithdraw}>
            회원 탈퇴
          </button>
        </div>

        {/* 메인 영역 */}
        <div className="as-main">
          <div className="as-section">
            <div className="as-section-title">프로필</div>
            <div className="as-profile-row">
              <div className={`as-avatar${avatarUrl ? "" : avatarRemoved ? " as-avatar-empty" : ""}`}>
                {avatarUrl ? (
                  <img className="as-avatar-img" src={avatarUrl} alt="프로필 사진" />
                ) : avatarRemoved ? (
                  null
                ) : (
                  USER.initial
                )}
              </div>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={handleAvatarFileChange}
                style={{ display: "none" }}
              />
              <div className="as-avatar-actions">
                <button
                  type="button"
                  className="as-avatar-btn as-avatar-edit"
                  onClick={handleAvatarEditClick}
                >
                  사진 변경
                </button>
                <button
                  type="button"
                  className="as-avatar-btn as-avatar-del"
                  onClick={handleAvatarDelete}
                >
                  사진 삭제
                </button>
              </div>
            </div>
          </div>

          <form className="as-section" onSubmit={handleSave}>
            <div className="as-section-title">기본 정보</div>
            <div className="as-field">
              <label className="as-field-label">이메일</label>
              <input className="as-field-input" value={USER.email} readOnly />
            </div>
            <div className="as-field">
              <label className="as-field-label">닉네임</label>
              <input
                className="as-field-input"
                value={nickname}
                onChange={(e) => setNickname(e.target.value)}
              />
            </div>
            <div className="as-field">
              <label className="as-field-label">생년월일</label>
              <input
                className="as-field-input"
                value={birth}
                onChange={(e) => setBirth(e.target.value)}
              />
            </div>
            <div className="as-field">
              <label className="as-field-label">비밀번호</label>
              <input
                className="as-field-input"
                type="password"
                value={password}
                placeholder="변경 시에만 입력하세요"
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <div className="as-save-row">
              <button type="submit" className="as-save-btn">
                저장
              </button>
              <button
                type="button"
                className="as-cancel-btn"
                onClick={handleCancel}
              >
                취소
              </button>
            </div>
          </form>

          <div className="as-section" ref={dangerRef}>
            <div className="as-section-title">회원 탈퇴</div>
            <div className="as-danger-box">
              <div>
                <div className="as-danger-title">회원 탈퇴</div>
                <div className="as-danger-desc">
                  탈퇴 시 모든 프로젝트와 데이터가 삭제됩니다
                </div>
              </div>
              <button className="as-danger-btn" onClick={handleWithdraw}>
                회원 탈퇴
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default AccountSettings;
