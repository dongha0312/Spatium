import React, { useState, useEffect, useRef } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../styles/homepage.css";
import { getLoginSession } from "../utils/authSession";
import { getMyInfo } from "../springApi/MemberSpringBootApi";
import Footer from "../components/Footer";
import AccountPanel from "../components/AccountPanel";
import AvatarButton from "../components/AvatarButton";
import Logo from "../components/Logo";
import useLogout from "../hooks/useLogout";
import useProjectStats from "../hooks/useProjectStats";

// 이용 순서 소개 (4단계)
const STEPS = [
  {
    img: "/images/steps/step1.gif",
    title: "새 프로젝트 생성",
    desc: "프로젝트를 만들어 공간 작업을 시작해요",
  },
  {
    img: "/images/steps/step2.gif",
    title: "새 룸 만들기",
    desc: "프로젝트 안에 방(룸)을 추가해요",
  },
  {
    img: "/images/steps/step3.gif",
    title: "스캔한 3D 업로드",
    desc: "LiDAR로 스캔한 내 방 3D 파일을 업로드해요",
  },
  {
    img: "/images/steps/step4.gif",
    title: "가구 배치 · 교체",
    desc: "가구를 옮기고 다른 가구로 바꿔봐요",
  },
];

// HomePage 정의 하기
function HomePage() {
  // 로그인 세션 (있으면 우측 상단에 닉네임 표시, 없으면 로그인 버튼 표시)
  const [session, setSession] = useState(() => getLoginSession());
  const navigate = useNavigate();
  const stepsGridRef = useRef(null);

  // 닉네임 클릭 시 열리는 "내 정보" 우측 패널
  const [panelOpen, setPanelOpen] = useState(false);

  // 패널 이용현황에 표시할 통계 (프로젝트 수 / 룸 수)
  const stats = useProjectStats(Boolean(session));

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

  const togglePanel = () => setPanelOpen((prev) => !prev);

  // 마이페이지 버튼 : 대시보드로 이동
  const handleGoMypage = () => navigate("/member/mypage");

  // 계정설정 이동 (패널 닫고 이동)
  const handleGoAccount = () => {
    setPanelOpen(false);
    navigate("/member/account");
  };

  // 로그아웃 : 서버 세션 정리 후 로컬 세션 삭제, 상단바를 로그인 버튼 상태로 되돌림
  const handleLogout = useLogout(() => {
    setSession(null);
    setPanelOpen(false);
  });

  // 이용 순서 카드가 스크롤로 화면에 들어오면 순차적으로 페이드인 + 슬라이드업
  useEffect(() => {
    const cards = stepsGridRef.current
      ? stepsGridRef.current.querySelectorAll(".hp-step-card")
      : [];
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("hp-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.2 },
    );
    cards.forEach((card, i) => {
      card.style.transitionDelay = `${i * 0.12}s`;
      observer.observe(card);
    });
    return () => observer.disconnect();
  }, []);

  // 시작하기 : 로그인 상태면 마이페이지로 이동하며 새 프로젝트 모달 자동 오픈, 아니면 로그인 페이지로
  const handleStart = () => {
    if (session) {
      navigate("/member/mypage", { state: { openNewProject: true } });
    } else {
      navigate("/auth/login");
    }
  };

  return (
    <div className="hp-root">
      {/* 상단 네비게이션 */}
      <div className="hp-nav">
        <Logo prefix="hp" />
        <div className="hp-nav-right">
          {session ? (
            <div className="hp-nav-account">
              {/* 닉네임 왼쪽 : 마이페이지로 바로 이동하는 외곽선 버튼 */}
              <button
                type="button"
                className="hp-mypage-btn"
                onClick={handleGoMypage}
              >
                내 공간
              </button>
              {/* 닉네임 클릭 : 우측 "내 정보" 패널 열기 */}
              <AvatarButton
                prefix="hp"
                imageUrl={profileImage}
                initial={session.nickname.charAt(0).toUpperCase()}
                name={session.nickname}
                onClick={togglePanel}
                showCaret={false}
              />
            </div>
          ) : (
            <Link to="/auth/login" className="hp-btn-prim">
              로그인
            </Link>
          )}
        </div>
      </div>

      {/* 히어로 영역 : 좌측 텍스트 + 우측 룸 일러스트 */}
      <div className="hp-hero">
        <div className="hp-hero-inner">
          <div className="hp-hero-left">
            <div className="hp-hero-eyebrow">✦ 3D 인테리어 시뮬레이터</div>
            <h1 className="hp-hero-h1">
              "내 방 그대로" 옮긴 3D 공간에서
              <br />
              <span className="hp-grad">가구를 배치해보세요</span>
            </h1>
            <p className="hp-hero-desc">
              아이폰 LiDAR로 스캔한 내 방을 3D로 불러와 가구를 원하는 위치에
              놓아보고, 다른 가구로 바꿔볼 수 있어요. 직접 가구를 옮기지 않아도
              배치 결과를 미리 확인해 시행착오를 줄입니다.
            </p>
            <button
              type="button"
              className="hp-hero-btn-main"
              onClick={handleStart}
            >
              시작하기 →
            </button>
          </div>
        </div>
      </div>

      {/* 이용 순서 소개 */}
      <div className="hp-steps">
        <div className="hp-steps-label">이용 순서</div>
        <div className="hp-steps-title">4단계로 완성하는 우리 집 가구 배치</div>
        <div className="hp-steps-grid" ref={stepsGridRef}>
          {STEPS.map((step, i) => (
            <div className="hp-step-card" key={step.title}>
              <div className="hp-step-shot">
                <img src={step.img} alt={step.title} />
              </div>
              <div className="hp-step-meta">
                <div className="hp-step-badge">{i + 1}</div>
                <span className="hp-step-eyebrow">STEP</span>
              </div>
              <div className="hp-step-name">{step.title}</div>
              <div className="hp-step-desc">{step.desc}</div>
            </div>
          ))}
        </div>
      </div>
      <Footer />

      {/* 개발용 바로가기 (배포 전 제거 예정) 일단 주석만 해놓겠습니다~*/}
      {/* <div
        style={{
          padding: "24px 32px",
          background: "var(--bg)",
          borderTop: "1px solid var(--bd)",
        }}
      >
        <p>
          <a href="/">[Home 바로가기]</a>
        </p>
        <p>
          <a href="/auth/login">[Login page 바로가기]</a>
        </p>
        <p>
          <a href="/auth/signup">[회원가입 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/member/mypage">[마이 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/member/account">[계정설정 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/member/editor">[3D 에디터 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/cookie-policy">[쿠키 정책 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/privacy-consent">
            [개인정보 수집·이용 동의 페이지 바로가기]
          </a>
        </p>
      </div> */}

      {/* 닉네임 클릭 시 열리는 "내 정보" 우측 패널 */}
      <AccountPanel
        open={Boolean(session && panelOpen)}
        prefix="hp"
        profile={{
          name: session?.nickname,
          initial: session?.nickname?.charAt(0),
          imageUrl: profileImage,
          subtext: session?.email ? `${session.email}` : "",
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

export default HomePage;
