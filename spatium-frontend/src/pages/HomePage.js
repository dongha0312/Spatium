import React, { useState } from "react";
import { Link } from "react-router-dom";
import "../styles/homepage.css";
import { getLoginSession } from "../utils/authSession";

// HomePage 정의 하기
function HomePage() {
  // 로그인 세션 (있으면 우측 상단에 닉네임 표시, 없으면 로그인 버튼 표시)
  const [session] = useState(() => getLoginSession());

  return (
    <div className="hp-root">
      {/* 상단 네비게이션 */}
      <div className="hp-nav">
        <Link to="/" className="hp-logo">
          <div className="hp-logo-sq">
            <div className="hp-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <Link to="/member/editor" className="hp-nav-link">
          룸 인테리어
        </Link>
        <div className="hp-nav-right">
          {session ? (
            <Link to="/member/mypage" className="hp-av-btn">
              <div className="hp-av-circ">{session.nickname.charAt(0)}</div>
              <span className="hp-av-name">{session.nickname}</span>
            </Link>
          ) : (
            <Link to="/auth/login" className="hp-btn-prim">
              로그인
            </Link>
          )}
        </div>
      </div>

      {/* 히어로 영역 */}
      <div className="hp-hero">
        <div className="hp-hero-inner">
          <div className="hp-hero-eyebrow">✦ 3D 인테리어 시뮬레이터</div>
          <h1 className="hp-hero-h1">
            나만의 공간을
            <br />
            <span className="hp-grad">직접 디자인하세요</span>
          </h1>
          <p className="hp-hero-desc">
            가구를 배치하고, 색상을 바꾸고, 완성된 공간을 3D로 확인하세요.
            <br />
            전문가 없이도 완벽한 인테리어를 만들 수 있습니다.
          </p>
          <button
            type="button"
            className="hp-hero-btn-main"
            onClick={() => alert("준비 중인 기능입니다.")}
          >
            지금 무료로 시작하기 →
          </button>
          <div className="hp-hero-stats">
            <div className="hp-hero-stat">
              <div className="hp-hero-stat-num">10,000+</div>
              <div className="hp-hero-stat-label">가구 라이브러리</div>
            </div>
            <div className="hp-hero-stat">
              <div className="hp-hero-stat-num">무료</div>
              <div className="hp-hero-stat-label">기본 플랜 제공</div>
            </div>
            <div className="hp-hero-stat">
              <div className="hp-hero-stat-num">3D</div>
              <div className="hp-hero-stat-label">실시간 렌더링</div>
            </div>
            <div className="hp-hero-stat">
              <div className="hp-hero-stat-num">5만+</div>
              <div className="hp-hero-stat-label">활성 사용자</div>
            </div>
          </div>
        </div>
      </div>

      {/* 개발용 바로가기 (배포 전 제거 예정) */}
      <div
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
          <a href="/test">[test 페이지 바로가기]</a>
        </p>
        <p>
          <a href="/test/three">[3d 모델링 편집 페이지 바로가기]</a>
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
      </div>
    </div>
  );
}

export default HomePage;
