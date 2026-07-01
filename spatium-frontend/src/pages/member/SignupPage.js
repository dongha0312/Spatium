import React, { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import "../../styles/signuppage.css";

function SignupPage() {
  // 이메일을 저장할 수 있는 상태변수(객체) 정의
  const [email, setEmail] = useState("");

  // 닉네임을 저장할 수 있는 상태변수(객체) 정의
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

  const handleSubmit = (e) => {
    e.preventDefault();

    if (!agree) {
      alert("이용약관 및 개인정보처리방침에 동의해주세요.");
      return;
    }

    alert(
      `회원가입 정보\n이메일 : ${email}\n닉네임 : ${nickname}\n생년월일 : ${birth}\n성별 : ${gender === "male" ? "남성" : "여성"}`,
    );

    // TODO: 추후 백엔드(springApi) 회원가입 API 연동
    navigate("/auth/login");
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
        <span className="su-nav-link">룸 인테리어</span>
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
              이미 계정이 있으신가요? <Link to="/auth/login">로그인 →</Link>
            </div>

            <div className="su-fgrp">
              <label className="su-flabel">이메일</label>
              <input
                className="su-finput"
                type="email"
                value={email}
                required
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

            <div className="su-form-row2">
              <div className="su-fgrp">
                <label className="su-flabel">생년월일</label>
                <input
                  className="su-finput"
                  type="text"
                  value={birth}
                  required
                  placeholder="YY.MM.DD"
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
