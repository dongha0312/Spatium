import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../../styles/loginpage.css";

function LoginPage({ onLoginSuccess }) {
  // 이메일을 저장할 수 있는 상태변수(객체) 정의
  const [email, setEmail] = useState("");

  // 패스워드를 저장할 수 있는 상태변수(객체) 정의
  const [pw, setPw] = useState("");

  // 로그인 상태 유지 체크 여부
  const [keep, setKeep] = useState(false);

  const navigate = useNavigate();

  const handleSubmit = (e) => {
    e.preventDefault();

    alert(`이메일 : ${email} / 비밀번호 : ${pw}`);

    if (onLoginSuccess) {
      onLoginSuccess();
    } else {
      navigate("/");
    }
  };

  // 소셜 로그인 : 아직 백엔드 연동 전이라, 우선 회원가입 페이지로 안내
  const handleAppleLogin = () => {
    navigate("/auth/signup", { state: { socialProvider: "apple" } });
  };

  const handleGoogleLogin = () => {
    navigate("/auth/signup", { state: { socialProvider: "google" } });
  };

  return (
    <div className="lg-root">
      {/* 상단 네비게이션 */}
      <div className="lg-nav">
        <Link to="/" className="lg-logo">
          <div className="lg-logo-sq">
            <div className="lg-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <span className="lg-nav-link">룸 인테리어</span>
        <div className="lg-nav-right">
          <Link to="/auth/signup" className="lg-btn-out">
            회원가입
          </Link>
        </div>
      </div>

      {/* 로그인 폼 (화면 정중앙 배치) */}
      <div className="lg-auth-wrap">
        <div className="lg-auth-card">
          <form className="lg-auth-form" onSubmit={handleSubmit}>
            <div className="lg-auth-form-title">로그인</div>
            <div className="lg-auth-form-sub">
              처음이신가요? <Link to="/auth/signup">회원가입 →</Link>
            </div>

            <div className="lg-fgrp">
              <label className="lg-flabel">이메일</label>
              <input
                className="lg-finput"
                type="email"
                value={email}
                required
                placeholder="name@example.com"
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>

            <div className="lg-fgrp">
              <label className="lg-flabel">비밀번호</label>
              <input
                className="lg-finput"
                type="password"
                value={pw}
                required
                placeholder="비밀번호 입력"
                onChange={(e) => setPw(e.target.value)}
              />
              <div className="lg-form-hint">
                <button type="button">비밀번호를 잊으셨나요?</button>
              </div>
            </div>

            <div className="lg-check-row">
              <input
                type="checkbox"
                id="keep"
                checked={keep}
                onChange={(e) => setKeep(e.target.checked)}
              />
              <label htmlFor="keep">로그인 상태 유지</label>
            </div>

            <button type="submit" className="lg-btn-full">
              로그인
            </button>

            <div className="lg-social-divider">
              <span>SNS계정으로 간편 로그인/회원가입</span>
            </div>

            <div className="lg-social-row">
              <button
                type="button"
                className="lg-social-btn"
                onClick={handleAppleLogin}
                aria-label="Apple로 로그인"
              >
                <svg viewBox="0 0 384 512" xmlns="http://www.w3.org/2000/svg">
                  <path
                    fill="#000"
                    d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"
                  />
                </svg>
              </button>

              <button
                type="button"
                className="lg-social-btn"
                onClick={handleGoogleLogin}
                aria-label="Google로 로그인"
              >
                <svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
                  <path
                    fill="#EA4335"
                    d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
                  />
                  <path
                    fill="#4285F4"
                    d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
                  />
                  <path
                    fill="#FBBC05"
                    d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
                  />
                  <path
                    fill="#34A853"
                    d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
                  />
                </svg>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}

export default LoginPage;
