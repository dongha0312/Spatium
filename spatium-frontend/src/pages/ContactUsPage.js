import React, { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../styles/ContactUsPage.css";
import Header from "../components/Header";
import Footer from "../components/Footer";
import AccountPanel from "../components/AccountPanel";
import AvatarButton from "../components/AvatarButton";
import useLogout from "../hooks/useLogout";
import useProjectStats from "../hooks/useProjectStats";
import { getLoginSession } from "../utils/authSession";
import { getMyInfo } from "../springApi/MemberSpringBootApi";

const CONTACT_EMAIL = "rsj1001@gmail.com";

function ContactUsPage() {
  const [session, setSession] = useState(() => getLoginSession());
  const [panelOpen, setPanelOpen] = useState(false);
  const [profileImage, setProfileImage] = useState(null);
  const navigate = useNavigate();
  const stats = useProjectStats(Boolean(session));

  useEffect(() => {
    if (!session) return undefined;

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

  const handleGoMypage = () => navigate("/member/mypage");
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };
  const handleLogout = useLogout(() => {
    setSession(null);
    setPanelOpen(false);
  });

  return (
    <div className="app-page cu-root">
      <Header prefix="cu">
        <div className="hp-nav-right">
          {session ? (
            <div className="hp-nav-account">
              <button
                type="button"
                className="hp-mypage-btn"
                onClick={handleGoMypage}
              >
                내 공간
              </button>
              <AvatarButton
                prefix="hp"
                imageUrl={profileImage}
                initial={session.nickname.charAt(0).toUpperCase()}
                name={session.nickname}
                onClick={() => setPanelOpen((prev) => !prev)}
                showCaret={false}
              />
            </div>
          ) : (
            <Link to="/auth/login" className="hp-btn-prim">
              로그인
            </Link>
          )}
        </div>
      </Header>

      <main className="cu-main">
        <section className="ui-card ui-card--raised cu-card" aria-labelledby="contact-title">
          <p className="cu-eyebrow">Contact Us</p>
          <h1 className="cu-title" id="contact-title">
            문의하기
          </h1>
          <p className="cu-description">
            SPATIUM에 궁금한 점이 있으시면 아래 이메일로 문의해 주세요.
          </p>

          <div className="cu-email-box">
            <span className="cu-email-label">Email</span>
            <p className="cu-email">{CONTACT_EMAIL}</p>
          </div>
        </section>
      </main>

      <Footer />

      <AccountPanel
        open={Boolean(session && panelOpen)}
        prefix="hp"
        profile={{
          name: session?.nickname,
          initial: session?.nickname?.charAt(0),
          imageUrl: profileImage,
          subtext: session?.email || "",
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

export default ContactUsPage;
