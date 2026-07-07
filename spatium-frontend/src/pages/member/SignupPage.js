import React, { useState } from "react";
import { Link, useNavigate, useLocation } from "react-router-dom";
import "../../styles/signuppage.css";
import { saveLoginSession } from "../../utils/authSession";
import {
  postUserSignup,
  postSocialSignup,
  postLogin,
  postSocialLogin,
} from "../../springApi/MemberSpringBootApi";

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

  // 이용약관 및 개인정보처리방침 동의 여부
  const [agree, setAgree] = useState(false);

  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!agree) {
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
          termsAgreed: agree,
          privacyAgreed: agree,
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
          termsAgreed: agree,
          privacyAgreed: agree,
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
          accessToken: loginData.accessToken,
          refreshToken: loginData.refreshToken,
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
    <div className="su-root">
      {/* 상단 네비게이션 */}
      <div className="su-nav">
        <Link to="/" className="su-logo">
          <div className="su-logo-sq">
            <div className="su-logo-sq-i"></div>
          </div>
          SPATIUM
        </Link>
        <div className="su-nav-right">
          <Link to="/auth/login" className="su-btn-out">
            로그인
          </Link>
        </div>
      </div>

      {/* 회원가입 폼 (화면 정중앙 배치) */}
      <div className="su-auth-wrap">
        <div className="su-auth-card">
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
                checked={agree}
                onChange={(e) => setAgree(e.target.checked)}
              />
              <label htmlFor="terms">
                <a>이용약관</a> 및 <a>개인정보처리방침</a>에 동의합니다 (필수)
              </label>
            </div>

            <button type="submit" className="su-btn-full">
              회원가입 완료
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default SignupPage;
