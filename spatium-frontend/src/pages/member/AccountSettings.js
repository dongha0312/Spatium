import React, { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { GoogleLogin } from "@react-oauth/google";
import "../../styles/accountsettings.css";
import AccountPanel from "../../components/AccountPanel";
import AvatarButton from "../../components/AvatarButton";
import Footer from "../../components/Footer";
import {
  clearLoginSession,
  getLoginSession,
  saveLoginSession,
} from "../../utils/authSession";
import {
  deleteMyAvatar,
  deleteMyInfo,
  getMyInfo,
  patchMyInfo,
  putMyAvatar,
} from "../../springApi/MemberSpringBootApi";
import useLogout from "../../hooks/useLogout";
import useProjectStats from "../../hooks/useProjectStats";

function AccountSettings() {
  const navigate = useNavigate();

  // 소셜(구글) 가입 회원 여부 : 회원가입 때 비밀번호를 입력한 적이 없음 -> 바로 계정설정 페이지로
  const session = getLoginSession();
  const isSocialMember = session?.provider && session.provider !== "LOCAL";

  // 백엔드에서 불러온 내 정보 (GET /api/users/me)
  const [me, setMe] = useState(null);

  // 상단 우측 프로필에 표시할 이름/이니셜 (내 정보 로드 전에는 세션 닉네임 사용)
  const displayName = me?.nickname || session?.nickname || "회원";
  const displayInitial = displayName.charAt(0).toUpperCase();
  const email = me?.email || session?.email || "";

  // 계정설정 화면 진입 전 비밀번호 재확인 게이트
  //  - true가 되기 전까지는 아래 실제 설정 화면 대신 비밀번호 입력 화면을 보여줌
  //  - 소셜 가입 회원은 비밀번호가 없으므로 처음부터 통과 상태로 시작함

  //  - TODO: 일반 회원 쪽도 지금은 프론트 UI만 먼저 만든 상태라 실제 검증 없이 통과시킴.
  //          추후 백엔드 비밀번호 검증 API 연동 예정.
  const [verified, setVerified] = useState(isSocialMember);
  const [verifyPassword, setVerifyPassword] = useState("");
  const [verifyError, setVerifyError] = useState("");

  // 계정설정 폼 상태 (내 정보 로드 후 채워짐)
  const [nickname, setNickname] = useState("");
  const [birth, setBirth] = useState("");
  const [password, setPassword] = useState("");

  // 계정설정 페이지 진입 시 내 정보 조회 → 폼/프로필에 반영
  useEffect(() => {
    let active = true;
    getMyInfo()
      .then((data) => {
        if (!active) return;
        setMe(data);
        setNickname(data.nickname || "");
        setBirth(data.birthDate || "");
        // 서버에 저장된 프로필 사진이 있으면 아바타에 반영
        if (data.profileImageUrl) {
          setAvatarUrl(data.profileImageUrl);
        }
      })
      .catch((err) => {
        console.error("내 정보 조회 실패:", err);
      });
    return () => {
      active = false;
    };
  }, []);

  // 닉네임 클릭 시 열리는 "내 정보" 우측 패널
  const [panelOpen, setPanelOpen] = useState(false);

  // 패널 이용현황에 표시할 통계 (프로젝트 수 / 룸 수)
  const stats = useProjectStats(Boolean(session));

  const togglePanel = () => setPanelOpen((prev) => !prev);

  // 마이페이지 버튼 : 대시보드로 이동
  const handleGoMypage = () => navigate("/member/mypage");

  // "내 정보" 패널의 프로필/계정설정 : 패널 닫고 계정설정으로 (현재 페이지)
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  // 로그아웃 : 서버 세션 정리 후 로컬 세션 삭제하고 메인으로
  const handleLogout = useLogout(() => {
    setPanelOpen(false);
    navigate("/");
  });

  // 프로필 사진 : 서버에 저장된 이미지 URL(data URL) (없으면 기본 이니셜 표시)
  const [avatarUrl, setAvatarUrl] = useState(null);
  const fileInputRef = useRef(null);

  // 아바타에 표시할 내용 : 프로필 사진이 있으면 이미지, 없으면 기본 이니셜
  const avatarNode = avatarUrl ? (
    <img className="as-av-img" src={avatarUrl} alt="" />
  ) : (
    displayInitial
  );

  const dangerRef = useRef(null);

  // "사진 변경" 클릭 → 숨겨진 파일 입력창을 대신 열어줌
  const handleAvatarEditClick = () => {
    fileInputRef.current?.click();
  };

  // 프로필 사진 업로드 중 여부 (중복 클릭 방지 + 버튼 표시)
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

  // 파일 선택 완료 → 서버에 업로드하고, 저장된 이미지로 아바타를 갱신
  const handleAvatarFileChange = async (e) => {
    const file = e.target.files?.[0];
    // 같은 파일을 다시 선택해도 onChange가 발생하도록 초기화
    e.target.value = "";
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      alert("이미지 파일만 선택할 수 있습니다.");
      return;
    }

    setUploadingAvatar(true);
    try {
      const data = await putMyAvatar(file);
      setAvatarUrl(data.profileImageUrl || null);
      setMe((prev) =>
        prev ? { ...prev, profileImageUrl: data.profileImageUrl } : prev,
      );
    } catch (err) {
      alert(
        err.message || "프로필 사진 변경에 실패했습니다. 다시 시도해주세요.",
      );
    } finally {
      setUploadingAvatar(false);
    }
  };

  // "사진 삭제" : 서버에서 프로필 사진을 삭제하고 기본(이니셜) 상태로 되돌림
  const handleAvatarDelete = async () => {
    // 이미 사진이 없으면 아무 것도 하지 않음
    if (!avatarUrl) return;

    setUploadingAvatar(true);
    try {
      await deleteMyAvatar();
      setAvatarUrl(null);
      setMe((prev) => (prev ? { ...prev, profileImageUrl: null } : prev));
    } catch (err) {
      alert(
        err.message || "프로필 사진 삭제에 실패했습니다. 다시 시도해주세요.",
      );
    } finally {
      setUploadingAvatar(false);
    }
  };

  // 저장 중복 클릭 방지
  const [saving, setSaving] = useState(false);

  const handleSave = async (e) => {
    e.preventDefault();
    if (saving) return;

    setSaving(true);
    try {
      const updated = await patchMyInfo({
        nickname,
        birthDate: birth,
        // 비밀번호는 입력했을 때만 변경 (비우면 유지)
        password: password.trim() ? password : undefined,
      });

      setMe(updated);
      setNickname(updated.nickname || "");
      setBirth(updated.birthDate || "");
      setPassword("");

      // 상단 우측 닉네임 등 다른 화면에 반영되도록 세션도 갱신
      if (session) {
        saveLoginSession(session.email, updated.nickname, session.provider, {
          accessToken: session.accessToken,
        });
      }

      alert("저장되었습니다.");
    } catch (err) {
      alert(
        err.message ||
          "저장 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.",
      );
    } finally {
      setSaving(false);
    }
  };

  const handleCancel = () => {
    setNickname(me?.nickname || "");
    setBirth(me?.birthDate || "");
    setPassword("");
  };

  // 소셜 회원 탈퇴 시 : 구글 재인증 버튼을 노출할지 여부
  const [socialWithdrawPending, setSocialWithdrawPending] = useState(false);

  // 탈퇴 API 호출 공통 처리 (성공 시 세션 정리 후 메인으로)
  const requestWithdraw = async (payload) => {
    try {
      await deleteMyInfo(payload);
      clearLoginSession();
      alert("탈퇴되었습니다.");
      navigate("/");
    } catch (err) {
      alert(err.message || "탈퇴 처리 중 문제가 발생했습니다.");
    }
  };

  const handleWithdraw = () => {
    if (
      !window.confirm(
        "정말 탈퇴하시겠습니까? 모든 프로젝트와 데이터가 삭제됩니다.",
      )
    ) {
      return;
    }

    if (isSocialMember) {
      // 소셜 회원 : 비밀번호가 없으므로 구글 재인증(idToken)으로 본인 확인
      setSocialWithdrawPending(true);
      return;
    }

    // 일반 회원 : 현재 비밀번호 재확인
    const currentPassword = window.prompt(
      "본인 확인을 위해 현재 비밀번호를 입력해주세요.",
    );
    if (!currentPassword) return;

    requestWithdraw({ password: currentPassword });
  };

  // 소셜 회원 탈퇴 : 구글 재인증 성공 시 받은 idToken으로 탈퇴 진행
  const handleWithdrawGoogleCredential = (credentialResponse) => {
    const idToken = credentialResponse?.credential;
    if (!idToken) {
      alert("구글 본인 확인에 실패했습니다. 다시 시도해주세요.");
      return;
    }
    setSocialWithdrawPending(false);
    requestWithdraw({ idToken });
  };

  const scrollToWithdraw = () => {
    dangerRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  };

  // 비밀번호 재확인 제출
  const handleVerifySubmit = (e) => {
    e.preventDefault();

    if (!verifyPassword.trim()) {
      setVerifyError("비밀번호를 입력해주세요.");
      return;
    }

    // TODO: 백엔드 비밀번호 검증 API 연동 전이라, 지금은 입력만 있으면 통과시킴
    setVerifyError("");
    setVerified(true);
  };

  // 계정설정 화면 진입 전, 비밀번호 재확인 화면부터 보여줌
  if (!verified) {
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
          <div className="as-nav-right">
            <div className="as-av-btn">
              <div className="as-av-circ">{avatarNode}</div>
              <span className="as-av-name">{displayName}</span>
            </div>
          </div>
        </div>

        <div className="as-body">
          <div
            className="as-main"
            style={{ maxWidth: 420, margin: "60px auto" }}
          >
            <form className="as-section" onSubmit={handleVerifySubmit}>
              <div className="as-section-title">비밀번호 확인</div>
              <div style={{ marginBottom: 16, color: "#8a8a8a", fontSize: 14 }}>
                계정설정 화면으로 이동하려면 비밀번호를 다시 입력해주세요.
              </div>
              <div className="as-field">
                <label className="as-field-label">비밀번호</label>
                <input
                  className="as-field-input"
                  type="password"
                  value={verifyPassword}
                  autoFocus
                  placeholder="비밀번호 입력"
                  onChange={(e) => {
                    setVerifyPassword(e.target.value);
                    if (verifyError) setVerifyError("");
                  }}
                />
                {verifyError && (
                  <div style={{ color: "#d33", fontSize: 13, marginTop: 6 }}>
                    {verifyError}
                  </div>
                )}
              </div>
              <div className="as-save-row">
                <button type="submit" className="as-save-btn">
                  확인
                </button>
                <button
                  type="button"
                  className="as-cancel-btn"
                  onClick={() => navigate(-1)}
                >
                  취소
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    );
  }

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
        <div className="as-nav-right">
          <div className="as-nav-account">
            {/* 닉네임 왼쪽 : 마이페이지로 바로 이동하는 외곽선 버튼 */}
            <button
              type="button"
              className="as-mypage-btn"
              onClick={handleGoMypage}
            >
              마이페이지
            </button>
            {/* 닉네임 클릭 : 우측 "내 정보" 패널 열기 */}
            <AvatarButton
              prefix="as"
              imageUrl={avatarUrl}
              initial={displayInitial}
              name={displayName}
              onClick={togglePanel}
            />
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
              <div className="as-avatar">
                {avatarUrl ? (
                  <img
                    className="as-avatar-img"
                    src={avatarUrl}
                    alt="프로필 사진"
                  />
                ) : (
                  displayInitial
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
                  disabled={uploadingAvatar}
                >
                  {uploadingAvatar ? "업로드 중..." : "사진 변경"}
                </button>
                <button
                  type="button"
                  className="as-avatar-btn as-avatar-del"
                  onClick={handleAvatarDelete}
                  disabled={uploadingAvatar}
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
              <input className="as-field-input" value={email} readOnly />
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
              <button type="submit" className="as-save-btn" disabled={saving}>
                {saving ? "저장 중..." : "저장"}
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
            {socialWithdrawPending && (
              <div style={{ marginTop: 12 }}>
                <div
                  style={{ marginBottom: 8, color: "#8a8a8a", fontSize: 13 }}
                >
                  본인 확인을 위해 구글 로그인을 한 번 더 진행해주세요.
                </div>
                <GoogleLogin
                  onSuccess={handleWithdrawGoogleCredential}
                  onError={() => {
                    alert("구글 본인 확인에 실패했습니다. 다시 시도해주세요.");
                  }}
                  text="continue_with"
                  size="medium"
                />
              </div>
            )}
          </div>
        </div>
      </div>
      <Footer />

      {/* 닉네임 클릭 시 열리는 "내 정보" 우측 패널 */}
      <AccountPanel
        open={panelOpen}
        prefix="as"
        profile={{
          name: displayName,
          initial: displayInitial,
          imageUrl: avatarUrl,
          subtext: email ? `@${email}` : "",
        }}
        statItems={[
          { label: "프로젝트", value: stats.projectCount },
          { label: "룸 개수", value: stats.roomCount },
        ]}
        onClose={() => setPanelOpen(false)}
        onProfileClick={handleGoAccount}
        onLogout={handleLogout}
        onAccountClick={handleGoAccount}
      />
    </div>
  );
}

export default AccountSettings;
