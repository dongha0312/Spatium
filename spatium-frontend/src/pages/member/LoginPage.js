import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../../styles/loginpage.css";
import { saveLoginSession } from "../../utils/authSession";
import { GoogleLogin } from "@react-oauth/google";
import {
  postLogin,
  postSocialLogin,
} from "../../springApi/MemberSpringBootApi";

// 이메일 형식 검증용 정규식
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// ID Token(JWT)의 payload를 디코딩 (화면 표시용 - 실제 검증은 백엔드가 수행)
const decodeJwtPayload = (token) => {
  try {
    const base64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return {};
  }
};

function LoginPage({ onLoginSuccess }) {
  // 이메일을 저장할 수 있는 상태변수(객체) 정의
  const [email, setEmail] = useState("");

  // 패스워드를 저장할 수 있는 상태변수(객체) 정의
  const [pw, setPw] = useState("");

  // 로그인 상태 유지 체크 여부
  const [keep, setKeep] = useState(false);

  // 이메일 형식 오류 메시지
  const [emailError, setEmailError] = useState("");

  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();

    // 이메일 형식이 아니면 로그인을 진행하지 않음
    if (!EMAIL_REGEX.test(email)) {
      setEmailError("올바른 이메일 형식이 아닙니다. (예: name@example.com)");
      return;
    }
    setEmailError("");

    try {
      // 백엔드 로그인 API 호출 (POST /api/auth/sessions)
      const data = await postLogin({ email, password: pw });

      // 로그인 세션 저장 (백엔드가 내려준 닉네임 + JWT 토큰)
      saveLoginSession(email, data.user?.nickname, "LOCAL", {
        accessToken: data.accessToken,
        refreshToken: data.refreshToken,
      });

      if (onLoginSuccess) {
        onLoginSuccess();
      } else {
        // 로그인 성공 시 메인 페이지로 이동 (메인 페이지 우측 상단에 닉네임 표시)
        navigate("/");
      }
    } catch (err) {
      // 401(INVALID_CREDENTIALS) : 이메일 또는 비밀번호 불일치
      if (err.status === 401) {
        setEmailError(
          err.message || "이메일 또는 비밀번호가 일치하지 않습니다.",
        );
      } else {
        console.error("로그인 처리 중 오류:", err);
        alert("로그인 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.");
      }
    }
  };

  //---------------------------------------------------------------------------

  // 소셜 로그인 : 아직 백엔드 연동 전이라, 우선 회원가입 페이지로 안내
  const handleAppleLogin = () => {
    navigate("/auth/signup", { state: { socialProvider: "apple" } });
  };

  // 구글 인증 성공 시 credential(ID Token)을 백엔드로 보내 로그인 시도
  //  - 백엔드가 ID Token의 서명/발급자/대상(aud)을 직접 검증함 (프론트 값은 신뢰하지 않음)
  //  - 이미 가입된 회원이면 로그인 처리, 미가입(404)이면 회원가입 페이지로 안내
  const handleGoogleCredential = async (credentialResponse) => {
    const idToken = credentialResponse?.credential;
    if (!idToken) {
      alert("구글 로그인에 실패했습니다. 다시 시도해주세요.");
      return;
    }

    // 화면 표시/회원가입 폼 미리 채우기용 프로필 (검증은 백엔드가 수행)
    const profile = decodeJwtPayload(idToken);

    try {
      const data = await postSocialLogin({ provider: "GOOGLE", idToken });

      // 기존 가입된 구글 계정 : 로그인 처리 (백엔드가 발급한 JWT 토큰도 함께 저장)
      saveLoginSession(profile.email, data.user?.nickname, "GOOGLE", {
        accessToken: data.accessToken,
        refreshToken: data.refreshToken,
      });

      if (onLoginSuccess) {
        onLoginSuccess();
      } else {
        navigate("/");
      }
    } catch (loginErr) {
      if (loginErr.status === 404) {
        // 가입되지 않은 구글 계정 : 회원가입 페이지로 안내 (idToken을 함께 전달)
        navigate("/auth/signup", {
          state: {
            socialProvider: "google",
            provider: "GOOGLE",
            idToken,
            email: profile.email,
          },
        });
      } else {
        console.error("구글 로그인 처리 중 오류:", loginErr);
        alert(
          loginErr.message ||
            "구글 로그인 중 문제가 발생했습니다. 다시 시도해주세요.",
        );
      }
    }
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
                className={`lg-finput${emailError ? " lg-finput-error" : ""}`}
                type="email"
                value={email}
                required
                placeholder="name@example.com"
                onChange={(e) => {
                  setEmail(e.target.value);
                  if (emailError) setEmailError("");
                }}
              />
              {emailError && <div className="lg-field-error">{emailError}</div>}
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
                {/* 애플 로고 이미지 */}
                <svg viewBox="0 0 384 512" xmlns="http://www.w3.org/2000/svg">
                  <path
                    fill="#000"
                    d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"
                  />
                </svg>
              </button>

              {/* 구글 공식 로그인 버튼 : credential(ID Token) 발급 방식
                  - ID Token 서버 검증을 위해 커스텀 버튼(access_token 방식)에서 교체함 */}
              {/* 구글 버튼은 존재만 함 뒤에 lg-google-mark */}
              <div className="lg-google-btn">
                <GoogleLogin
                  onSuccess={handleGoogleCredential}
                  onError={() => {
                    console.error("구글 로그인에 실패했습니다.");
                    alert("구글 로그인에 실패했습니다. 다시 시도해주세요.");
                  }}
                  type="icon"
                  theme="outline"
                  shape="circle"
                  size="large"
                  width="44"
                  containerProps={{
                    style: {
                      width: "44px",
                      height: "44px",
                    },
                  }}
                />

                <div className="lg-google-mark" aria-hidden="true">
                  <svg viewBox="0 0 48 48">
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
                      d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24s.92 7.54 2.56 10.78l7.97-6.19z"
                    />
                    <path
                      fill="#34A853"
                      d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
                    />
                  </svg>
                </div>
              </div>
            </div>
          </form>
        </div>
      </div>

      {/* 하단 푸터 : 쿠키 정책 / 개인정보처리방침 */}
      <div className="lg-footer">
        <span className="lg-footer-brand">SPATIUM</span>
        <span className="lg-footer-sep">·</span>
        <Link to="/cookie-policy">쿠키 정책</Link>
        <span className="lg-footer-sep">·</span>
        <Link to="/privacy-consent">개인정보처리방침</Link>
        <div className="lg-footer-copy">© SPATIUM 2026</div>
      </div>
    </div>
  );
}

export default LoginPage;
