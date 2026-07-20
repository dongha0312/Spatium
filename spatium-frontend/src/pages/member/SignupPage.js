import React, { useEffect, useState } from "react";
import { Link, useNavigate, useLocation } from "react-router-dom";
import "../../styles/signuppage.css";
import { saveLoginSession } from "../../utils/authSession";
import {
  postUserSignup,
  postSocialSignup,
  postLogin,
  postSocialLogin,
} from "../../springApi/MemberSpringBootApi";
import Footer from "../../components/Footer";
import Header from "../../components/Header";
import {
  LegalDocumentContent,
  PRIVACY_SECTIONS,
  TERMS_SECTIONS,
} from "../../components/legal/LegalDocumentContent";

function SignupPage() {
  // 로그인 페이지의 구글 소셜 로그인에서 넘어온 경우, 구글 인증 결과(이메일)가 담겨있음
  const location = useLocation();
  const socialState = location.state || {};
  const isGoogleSignup = socialState.socialProvider === "google";

  // 이메일을 저장할 수 있는 상태변수(객체) 정의 (구글 가입인 경우 구글 이메일로 미리 채움)
  const [email, setEmail] = useState(socialState.email || "");

  // 닉네임을 저장할 수 있는 상태변수(객체) 정의 (구글 가입이어도 직접 입력)
  const [nickname, setNickname] = useState("");

  // 비밀번호를 저장할 수 있는 상태변수(객체) 정의
  const [pw, setPw] = useState("");

  // 생년월일을 저장할 수 있는 상태변수(객체) 정의
  const [birth, setBirth] = useState("");

  // 성별 : "male" | "female"
  const [gender, setGender] = useState("male");

  // 이용약관과 개인정보 수집·이용 동의는 각각 구분해서 받는다.
  const [termsAgreed, setTermsAgreed] = useState(false);
  const [privacyAgreed, setPrivacyAgreed] = useState(false);
  const [openPolicy, setOpenPolicy] = useState(null);

  const navigate = useNavigate();

  useEffect(() => {
    if (!openPolicy) return undefined;

    const handleKeyDown = (event) => {
      if (event.key === "Escape") setOpenPolicy(null);
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [openPolicy]);

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!termsAgreed || !privacyAgreed) {
      alert("이용약관 및 개인정보처리방침에 동의해주세요.");
      return;
    }

    // 백엔드는 성별을 0(남성) / 1(여성)로 받음
    const genderCode = gender === "male" ? "0" : "1";

    try {
      let loginData;

      if (isGoogleSignup) {
        // 소셜 회원가입 : LoginPage에서 넘겨받은 ID Token으로 가입
        //  - 이메일/고유ID는 백엔드가 ID Token을 직접 검증해서 얻음 (프론트 값은 표시용)
        await postSocialSignup({
          provider: socialState.provider,
          idToken: socialState.idToken,
          nickname,
          birthDate: birth,
          gender: genderCode,
          termsAgreed,
          privacyAgreed,
        });

        // 회원가입 API는 JWT 토큰을 내려주지 않으므로, 가입 직후 소셜 로그인을 한 번 더 호출해 토큰을 발급받음
        loginData = await postSocialLogin({
          provider: socialState.provider,
          idToken: socialState.idToken,
        });
      } else {
        // 일반 회원가입
        await postUserSignup({
          email,
          nickname,
          password: pw,
          birthDate: birth,
          gender: genderCode,
          termsAgreed,
          privacyAgreed,
        });

        // 회원가입 API는 JWT 토큰을 내려주지 않으므로, 가입 직후 로그인을 한 번 더 호출해 토큰을 발급받음
        loginData = await postLogin({ email, password: pw });
      }

      // 로그인 세션 저장 (실제 발급받은 토큰을 함께 저장해야 로그인 상태가 유효함)
      //  - 소셜(구글) 가입 회원은 provider를 "GOOGLE"로 저장 -> 계정설정 진입 시 비밀번호 게이트 생략용
      saveLoginSession(
        email,
        loginData.user?.nickname || nickname,
        isGoogleSignup ? "GOOGLE" : "LOCAL",
        {
          // refreshToken은 httpOnly 쿠키로 관리되므로 저장하지 않음
          accessToken: loginData.accessToken,
        },
      );
      navigate("/");
    } catch (err) {
      console.error("회원가입 중 오류:", err);
      alert(
        err.message || "회원가입 중 문제가 발생했습니다. 다시 시도해주세요.",
      );
    }
  };

  return (
    <div className="app-page su-root">
      {/* 상단 네비게이션 */}
      <Header prefix="su">
        <div className="su-nav-right">
          <Link to="/auth/login" className="su-btn-out">
            로그인
          </Link>
        </div>
      </Header>

      {/* 회원가입 폼 (화면 정중앙 배치) */}
      <div className="su-auth-wrap">
        <div className="ui-card su-auth-card">
          <form className="su-auth-form" onSubmit={handleSubmit}>
            <div className="su-auth-form-title">회원가입</div>
            <div className="su-auth-form-sub">
              {isGoogleSignup ? (
                <>구글 계정으로 회원가입을 진행합니다.</>
              ) : (
                <>
                  이미 계정이 있으신가요? <Link to="/auth/login">로그인 →</Link>
                </>
              )}
            </div>

            <div className="su-fgrp">
              <label className="su-flabel">이메일</label>
              <input
                className="su-finput"
                type="email"
                value={email}
                required
                readOnly={isGoogleSignup}
                placeholder="name@example.com"
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>

            <div className="su-fgrp">
              <label className="su-flabel">닉네임</label>
              <input
                className="su-finput"
                type="text"
                value={nickname}
                required
                minLength={2}
                maxLength={12}
                placeholder="사용할 닉네임 (2–12자)"
                onChange={(e) => setNickname(e.target.value)}
              />
            </div>

            {/* 소셜(구글) 회원가입인 경우, 이미 구글 인증으로 신원이 확인됐으므로 비밀번호 입력 생략 */}
            {!isGoogleSignup && (
              <div className="su-fgrp">
                <label className="su-flabel">비밀번호</label>
                <input
                  className="su-finput"
                  type="password"
                  value={pw}
                  required
                  placeholder="8자 이상, 영문+숫자 포함"
                  onChange={(e) => setPw(e.target.value)}
                />
              </div>
            )}

            <div className="su-form-row2">
              <div className="su-fgrp">
                <label className="su-flabel">생년월일</label>
                {/* DB 컬럼(mem_bir)이 VARCHAR2(10)이라 YYYY-MM-DD(10자리) 형식만 허용됨 */}
                {/* type="date"를 쓰면 브라우저가 항상 YYYY-MM-DD 형식의 값을 만들어줌 */}
                <input
                  className="su-finput"
                  type="date"
                  value={birth}
                  required
                  max={new Date().toISOString().slice(0, 10)}
                  onChange={(e) => setBirth(e.target.value)}
                />
              </div>
              <div className="su-fgrp">
                <label className="su-flabel">성별</label>
                <div className="su-gender-wrap">
                  <div
                    className={`su-gender-opt${gender === "male" ? " su-sel" : ""}`}
                    onClick={() => setGender("male")}
                  >
                    남성
                  </div>
                  <div
                    className={`su-gender-opt${gender === "female" ? " su-sel" : ""}`}
                    onClick={() => setGender("female")}
                  >
                    여성
                  </div>
                </div>
              </div>
            </div>

            <div className="su-check-row">
              <input
                type="checkbox"
                id="terms"
                checked={termsAgreed}
                onChange={(e) => setTermsAgreed(e.target.checked)}
                aria-label="이용약관 필수 동의"
                aria-describedby="terms-description"
              />
              <div id="terms-description" className="su-agreement-text">
                <button type="button" onClick={() => setOpenPolicy("terms")}>
                  이용약관
                </button>
                <span>에 동의합니다 (필수)</span>
              </div>
            </div>
            <div className="su-check-row">
              <input
                type="checkbox"
                id="privacy"
                checked={privacyAgreed}
                onChange={(e) => setPrivacyAgreed(e.target.checked)}
                aria-label="개인정보 수집·이용 필수 동의"
                aria-describedby="privacy-description"
              />
              <div id="privacy-description" className="su-agreement-text">
                <button type="button" onClick={() => setOpenPolicy("privacy")}>
                  개인정보 수집·이용 및 처리방침
                </button>
                <span>에 동의합니다 (필수)</span>
              </div>
            </div>

            <button type="submit" className="su-btn-full">
              회원가입 완료
            </button>
          </form>
        </div>
      </div>
      {openPolicy && (
        <div
          className="su-modal-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setOpenPolicy(null);
          }}
        >
          <section
            className="su-policy-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="su-policy-title"
          >
            <div className="su-policy-modal-header">
              <h2 id="su-policy-title">
                {openPolicy === "terms"
                  ? "이용약관"
                  : "개인정보 수집·이용 및 처리방침"}
              </h2>
              <button
                type="button"
                className="su-policy-close"
                onClick={() => setOpenPolicy(null)}
                aria-label="약관 창 닫기"
              >
                ×
              </button>
            </div>

            <div className="su-policy-modal-body">
              <LegalDocumentContent
                sections={
                  openPolicy === "terms" ? TERMS_SECTIONS : PRIVACY_SECTIONS
                }
                compact
              />
            </div>

            <div className="su-policy-modal-footer">
              <button type="button" onClick={() => setOpenPolicy(null)}>
                확인
              </button>
            </div>
          </section>
        </div>
      )}
      <Footer />
    </div>
  );
}

export default SignupPage;
